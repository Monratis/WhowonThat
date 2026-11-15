-- Who Won That
-- Shows loot rolls and results in a chat window of your choice: one readable block per item once
-- the roll is finished (winner with a crown, then everyone else's roll).
-- "raw" format keeps Blizzard's original lines (filtered by roll type). Other chat windows are untouched.
-- Settings: Esc > Options > AddOns > Who Won That, or /wwt

local ADDON = "WhoWonThat"

local DEFAULTS = {
    frame = 1,          -- chat window number that receives rolls and results
    format = "summary", -- "summary" = readable block per item, "raw" = Blizzard's original lines
    rolls = true,       -- master switch: show other players' rolls
    need = true,        -- show Need rolls
    greed = true,       -- show Greed rolls
    de = true,          -- (raw mode only) Disenchant rolls, if the game has them
    pass = true,        -- show passes
    wins = true,        -- show who won / that everyone passed
    hideOthers = true,  -- hide other loot messages in that window (picked up items etc.)
    classColors = true, -- color names by class (EllesmereUI colors if installed)
}

local TYPE_LABEL = { need = "Need", greed = "Greed", de = "Disenchant", pass = "Pass" }
local PRIORITY = { win = 1, de = 2, greed = 3, need = 4, pass = 5, other = 6 }
-- Forever (Midnight engine) has a loot history with structured roll data (C_LootHistory) - the main data source.
-- Chat text parsing is only used to hide the raw lines and as a fallback.
local HAS_HISTORY = (C_LootHistory ~= nil and C_LootHistory.GetSortedInfoForDrop ~= nil)
local STALE_SECONDS = 180

local db
local entries = {}  -- {pattern, kinds, kind, wonType, self, prio}
local items = {}    -- [itemLink] = { time = t, players = { [name] = { type, roll } } }

-- Prints to a chat frame the way Blizzard does: AddMessage(text, r, g, b, id).
-- The full argument list matters - addons hooking AddMessage (e.g. EllesmereUIChat)
-- read the 5th argument (chatTypeID) and raise "bad argument #5" without it.
local function Emit(frame, text, chatType)
    local info = ChatTypeInfo and (ChatTypeInfo[chatType] or ChatTypeInfo.SYSTEM)
    if info then
        frame:AddMessage(text, info.r, info.g, info.b, info.id)
    else
        frame:AddMessage(text, 1, 1, 1, 0)
    end
end

local function Print(msg)
    Emit(DEFAULT_CHAT_FRAME, "|cff58c6faWho Won That:|r " .. msg, "SYSTEM")
end

-- Turns a Blizzard format string (e.g. "%s won: %s") into a language-independent Lua pattern
-- with captures. Returns the pattern and the list of captured field types ("s" or "d").
local function Compile(fmt)
    local kinds = {}
    local p = fmt:gsub("%%%%", "\3")
    p = p:gsub("%%(%d*)%$?([sd])", function(_, t)
        kinds[#kinds + 1] = t
        return t == "s" and "\1" or "\2"
    end)
    p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("\1", "(.+)")
    p = p:gsub("\2", "(%%d+)")
    p = p:gsub("\3", "%%%%")
    return "^" .. p .. "$", kinds
end

-- Classifies a message by the name of its global string (e.g. LOOT_ROLL_ROLLED_NEED).
local function ClassifyName(name)
    if name:find("WON") or name:find("ALL_PASSED") then
        return "win"
    end
    if name:find("TRANSMOG") then
        return "other" -- Transmog rolls are intentionally not supported
    end
    if name:find("DISENCHANT") or name:find("_DE$") or name:find("_DE_") then
        return "de"
    end
    if name:find("GREED") then
        return "greed"
    end
    if name:find("NEED") then
        return "need"
    end
    if name:find("PASS") then
        return "pass"
    end
    return "other"
end

local function WonType(name)
    if name:find("DISENCHANT") or name:find("_DE$") or name:find("_DE_") then return "de" end
    if name:find("GREED") then return "greed" end
    if name:find("NEED") then return "need" end
    return nil
end

local function BuildEntries()
    wipe(entries)
    for name, text in pairs(_G) do
        if type(name) == "string" and type(text) == "string" and name:find("^LOOT_ROLL_") then
            local pattern, kinds = Compile(text)
            -- skip patterns that would match every message
            if pattern ~= "^(.+)$" and pattern ~= "^$" then
                local kind = ClassifyName(name)
                local literal = #(text:gsub("%%%d*%$?[sd]", ""))
                entries[#entries + 1] = {
                    literal = literal,
                    pattern = pattern,
                    kinds = kinds,
                    kind = kind,
                    name = name,
                    wonType = (kind == "win") and WonType(name) or nil,
                    allPassed = name:find("ALL_PASSED") ~= nil,
                    self = (name:find("_SELF") or name:find("YOU_")) and true or false,
                    prio = PRIORITY[kind],
                }
            end
        end
    end
    -- wins before rolls ("everyone passed" also matches the "X passed" pattern),
    -- and within a group the patterns with the most literal text first, because the generic
    -- "%s won: %s" would also match "You won: %s" and "%s won: %s (Need - 74)"
    table.sort(entries, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        if a.literal ~= b.literal then return a.literal > b.literal end
        return a.name < b.name
    end)
end

-- Returns the full player name ("Name-Realm", if the client provides it) and the short name.
-- Blizzard messages contain a link |Hplayer:Name-Realm:...|h[Name]|h; the full name comes from it.
local function PlayerInfo(raw)
    if not raw then return nil end
    local full = raw:match("|Hplayer:([^:|]+)")
    local short = raw:match("|h%[(.-)%]|h")
    if full then
        return full, short or (full:match("^([^%-]+)") or full)
    end
    return raw, (raw:match("^([^%-]+)") or raw)
end

local function SelfInfo()
    local name = UnitName("player")
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    if realm and realm ~= "" then
        realm = realm:gsub("%s", "")
        return name .. "-" .. realm, name
    end
    return name, name
end

-- Returns a table {kind, item, player, roll, wonType, allPassed}, or nil if the message is not a roll.
local function Parse(msg)
    for i = 1, #entries do
        local e = entries[i]
        local caps = { msg:match(e.pattern) }
        if caps[1] then
            local r = { kind = e.kind, wonType = e.wonType, allPassed = e.allPassed }
            for j = 1, #e.kinds do
                local c = caps[j]
                if c then
                    if e.kinds[j] == "d" then
                        r.roll = tonumber(c)
                    elseif c:find("|Hitem:") then
                        r.item = r.item or c
                    elseif not r.player then
                        r.player, r.short = PlayerInfo(c)
                    end
                end
            end
            if e.self then
                r.player, r.short = SelfInfo()
            end
            return r
        end
    end
    return nil
end

local function TargetFrame()
    return db and _G["ChatFrame" .. db.frame]
end

-- Returning true = hide the message in this chat window.
local function Filter(self, event, msg, ...)
    if not db or self ~= TargetFrame() then
        return false
    end
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then
        return false
    end
    local p = Parse(msg)
    if p then
        if db.format == "summary" then
            return true -- replaced by the summary block
        end
        if p.kind == "win" then
            return not db.wins
        end
        if not db.rolls then
            return true
        end
        if p.kind == "other" then
            return false
        end
        return not db[p.kind]
    end
    return db.hideOthers
end

-- Player as a clickable link with the FULL name (Name-Realm), so chat addons
-- (name coloring etc.) recognize the player like in a regular message.
-- Class color: EllesmereUI palette first (user's custom colors), then Blizzard's default.
local function ClassColor(classFile)
    if not classFile then
        return nil
    end
    if type(EllesmereUI) == "table" and EllesmereUI.GetRawClassColor then
        local c = EllesmereUI.GetRawClassColor(classFile)
        if c then
            return c
        end
    end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
end

local function PlayerLink(full, short, classFile)
    -- short name in the text, full name (Name-Realm) in the link
    local link = "|Hplayer:" .. full .. "|h[" .. (short or full) .. "]|h"
    if db.classColors then
        local class = classFile
        if not class then
            _, class = UnitClass(full)
        end
        if not class and short then
            _, class = UnitClass(short)
        end
        local c = ClassColor(class)
        if c then
            return string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), link)
        end
    end
    return link
end

-- ===== Main data source: Blizzard loot history (LOOT_HISTORY_UPDATE_DROP event) =====
local ROLL_STATE = (Enum and Enum.EncounterLootDropRollState)
    or { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
local STATE_INFO = {
    [ROLL_STATE.NeedMainSpec] = { kind = "need", label = "Need" },
    [ROLL_STATE.NeedOffSpec] = { kind = "need", label = "Need OS" },
    [ROLL_STATE.Greed] = { kind = "greed", label = "Greed" },
    [ROLL_STATE.Pass] = { kind = "pass", label = "Pass" },
    -- NoRoll: the player has not chosen yet - skipped
}
local printedDrops = {}
local printedCount = 0

local function ShortName(full)
    return (full:match("^([^%-]+)") or full)
end

-- player name usable for display (plain text, not a "secret" value)
local function UsableName(v)
    return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v))
end

-- Client icons
local ICON_CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:16:16:0:0|t"
local KIND_ICON = {
    need = "|TInterface\\Buttons\\UI-GroupLoot-Dice-Up:14:14:0:0|t",
    greed = "|TInterface\\Buttons\\UI-GroupLoot-Coin-Up:14:14:0:0|t",
    pass = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14:0:0|t",
}

-- e.g. "[dice] Need 74"
local function RollLabel(r, st)
    local icon = KIND_ICON[st.kind]
    return (icon and (icon .. " ") or "")
        .. "|cffaaaaaa" .. st.label .. "|r"
        .. (r.roll and (" |cffffffff" .. r.roll .. "|r") or "")
        .. (r.isSelf and "  |cffffd100(You)|r" or "")
end

-- Prints the summary of one item (data from C_LootHistory) on several lines:
--   [Item]
--      [crown] Winner  WON  [dice] Need 74
--          Player2  [coin] Greed 55
--          Player3  [dice] Need OS 31
local function RenderDrop(info)
    local frame = TargetFrame()
    if not frame or type(info) ~= "table" then
        return
    end
    local item = info.itemHyperlink
    if type(item) ~= "string" or (issecretvalue and issecretvalue(item)) then
        return
    end
    if info.allPassed then
        if db.wins then
            Emit(frame, item, "LOOT")
            Emit(frame, "     |cffaaaaaaNobody wanted it (everyone passed)|r", "LOOT")
        end
        return
    end

    local winner = info.winner
    local list = {}
    if db.rolls then
        for _, r in ipairs(info.rollInfos or {}) do
            local st = STATE_INFO[r.state]
            -- the winner is printed separately, unless winners are turned off
            if st and UsableName(r.playerName) and db[st.kind] and not (r.isWinner and db.wins) then
                list[#list + 1] = { r = r, st = st }
            end
        end
        table.sort(list, function(a, b)
            local ra, rb = a.r.roll or -1, b.r.roll or -1
            if ra ~= rb then return ra > rb end
            return a.r.playerName < b.r.playerName
        end)
    end

    local showWinner = db.wins and winner and UsableName(winner.playerName)
    if not showWinner and #list == 0 then
        return
    end

    Emit(frame, item, "LOOT")
    if showWinner then
        local line = "   " .. ICON_CROWN .. " "
            .. PlayerLink(winner.playerName, ShortName(winner.playerName), winner.playerClass)
            .. "  |cffffd100WON|r"
        local wst = STATE_INFO[winner.state]
        if wst then
            line = line .. "  " .. RollLabel(winner, wst)
        end
        Emit(frame, line, "LOOT")
    end
    for i = 1, #list do
        local r, st = list[i].r, list[i].st
        Emit(frame, "        " .. PlayerLink(r.playerName, ShortName(r.playerName), r.playerClass)
            .. "  " .. RollLabel(r, st), "LOOT")
    end
end

local function OnDropUpdate(encounterID, lootListKey)
    if not HAS_HISTORY or not db or db.format ~= "summary" then
        return
    end
    if issecretvalue and (issecretvalue(encounterID) or issecretvalue(lootListKey)) then
        return
    end
    local key = tostring(encounterID) .. ":" .. tostring(lootListKey)
    if printedDrops[key] then
        return
    end
    local info = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey)
    if type(info) ~= "table" or not (info.winner or info.allPassed) then
        return -- the roll is still in progress
    end
    if printedCount > 400 then
        wipe(printedDrops)
        printedCount = 0
    end
    printedDrops[key] = true
    printedCount = printedCount + 1
    RenderDrop(info)
end

-- After /reload (or logging in mid-dungeon) the loot history already exists: mark finished
-- items as printed so their summaries do not appear a second time.
local function MarkExistingDrops()
    if not HAS_HISTORY or not C_LootHistory.GetAllEncounterInfos or not C_LootHistory.GetSortedDropsForEncounter then
        return
    end
    local encounters = C_LootHistory.GetAllEncounterInfos()
    if type(encounters) ~= "table" then
        return
    end
    for _, enc in ipairs(encounters) do
        local id = enc.encounterID
        if id and not (issecretvalue and issecretvalue(id)) then
            local drops = C_LootHistory.GetSortedDropsForEncounter(id)
            if type(drops) == "table" then
                for _, d in ipairs(drops) do
                    if d.lootListKey and (d.winner or d.allPassed) then
                        local key = tostring(id) .. ":" .. tostring(d.lootListKey)
                        if not printedDrops[key] then
                            printedDrops[key] = true
                            printedCount = printedCount + 1
                        end
                    end
                end
            end
        end
    end
end


-- ===== Fallback: when the game has no loot history, rolls are assembled from chat messages =====
-- The data goes through the same RenderDrop, so the output looks identical.
local KIND_TO_STATE = {
    need = ROLL_STATE.NeedMainSpec, greed = ROLL_STATE.Greed, de = ROLL_STATE.Greed,
    pass = ROLL_STATE.Pass,
}

local function Prune(now)
    for key, rec in pairs(items) do
        if now - rec.time > STALE_SECONDS then
            items[key] = nil
        end
    end
end

local function Summarize(p)
    local rec = items[p.item]
    items[p.item] = nil
    local me = UnitName("player")
    local winnerKey = p.short or p.player
    local info = { itemHyperlink = p.item, allPassed = p.allPassed or false, rollInfos = {} }
    local winnerEntry
    if rec then
        for key, e in pairs(rec.players) do
            local state = KIND_TO_STATE[e.type]
            if state then
                local r = { playerName = e.full or key, state = state, roll = e.roll,
                    isWinner = (key == winnerKey), isSelf = (key == me) }
                info.rollInfos[#info.rollInfos + 1] = r
                if r.isWinner then
                    winnerEntry = r
                end
            end
        end
    end
    if not p.allPassed and p.player then
        if not winnerEntry then
            winnerEntry = { playerName = p.player, state = ROLL_STATE.NoRoll, isWinner = true, isSelf = (winnerKey == me) }
            info.rollInfos[#info.rollInfos + 1] = winnerEntry
        end
        if p.wonType and KIND_TO_STATE[p.wonType] then
            winnerEntry.state = KIND_TO_STATE[p.wonType]
        end
        winnerEntry.roll = winnerEntry.roll or p.roll
        info.winner = winnerEntry
    end
    RenderDrop(info)
end

local function OnLoot(msg)
    if HAS_HISTORY or not db or db.format ~= "summary" then
        return
    end
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then
        return
    end
    local p = Parse(msg)
    if not p or not p.item then
        return
    end
    local now = GetTime()
    Prune(now)
    if p.kind == "win" then
        Summarize(p)
        return
    end
    if not p.player then
        return
    end
    local rec = items[p.item]
    if not rec then
        rec = { time = now, players = {} }
        items[p.item] = rec
    end
    -- key = short name (messages give "Name" sometimes and "Name-Realm" other times); the full name goes into the link
    local key = p.short or p.player
    local e = rec.players[key]
    if not e then
        e = {}
        rec.players[key] = e
    end
    e.type = p.kind
    e.short = key
    if not e.full or (p.player:find("-", 1, true) and not e.full:find("-", 1, true)) then
        e.full = p.player
    end
    if p.roll then
        e.roll = p.roll
    end
end

local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
local addGroup = ChatFrame_AddMessageGroup or (ChatFrameUtil and ChatFrameUtil.AddMessageGroup)

local function EnsureLootGroup()
    local frame = TargetFrame()
    if not frame then
        return
    end
    -- in Forever AddMessageGroup is a chat frame method (ChatFrameMixin); it persists by itself
    if frame.ContainsMessageGroup and frame:ContainsMessageGroup("LOOT") then
        return
    end
    if frame.AddMessageGroup then
        frame:AddMessageGroup("LOOT")
    elseif addGroup then
        addGroup(frame, "LOOT")
    else
        Print("Could not add the Loot message group automatically - enable Loot for this window manually (right-click the tab > Settings).")
    end
end

local function WindowName(i)
    local f = _G["ChatFrame" .. i]
    local name = f and f.name
    if (not name or name == "") and GetChatWindowInfo then
        name = GetChatWindowInfo(i)
    end
    return (name and name ~= "") and name or "-"
end

local function OnOff(v)
    return v and "|cff00ff00ON|r" or "|cffff4040OFF|r"
end

local function Status()
    Print(string.format("window: %d (%s) | format: %s | rolls: %s | winners: %s | other loot hidden: %s",
        db.frame, WindowName(db.frame), db.format, OnOff(db.rolls), OnOff(db.wins), OnOff(db.hideOthers)))
    Print(string.format("roll types: Need %s, Greed %s, Pass %s | class colors: %s",
        OnOff(db.need), OnOff(db.greed), OnOff(db.pass), OnOff(db.classColors)))
end

local function Help()
    Status()
    Print("/wwt - open the settings panel (Esc > Options > AddOns > Who Won That); everything below is also in the panel")
    Print("/wwt test - print a sample roll to the chosen window and check message recognition")
    Print("/wwt list - list chat windows with their numbers")
    Print("/wwt frame <number or name> - where to show rolls and winners")
    Print("/wwt format summary / raw - readable block per item, or Blizzard's original lines")
    Print("/wwt rolls on/off - show other players' rolls")
    Print("/wwt need/greed/pass on/off - single roll types")
    Print("/wwt only need  (or greed, pass) - show only that roll type")
    Print("/wwt all - show all roll types")
    Print("/wwt wins on/off - who won / everyone passed")
    Print("/wwt others on/off - hide the rest of the loot messages in that window (crafted, quest, master looter...)")
    Print("/wwt colors on/off - class colors on names (EllesmereUI colors if installed)")
end

local function ParseBool(s)
    s = (s or ""):lower()
    if s == "on" or s == "1" or s == "yes" then return true end
    if s == "off" or s == "0" or s == "no" then return false end
    return nil
end

local function FindWindow(arg)
    local n = tonumber(arg)
    if n then
        n = math.floor(n)
        if n >= 1 and n <= (NUM_CHAT_WINDOWS or 10) and _G["ChatFrame" .. n] then
            return n
        end
        return nil
    end
    arg = (arg or ""):lower()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local name = WindowName(i)
        if name ~= "-" and name:lower() == arg then
            return i
        end
    end
    return nil
end

local settingsCategory -- category in Esc > Options > AddOns

local TYPE_ALIASES = {
    need = "need", greed = "greed", pass = "pass",
}

-- /wwt test: builds sample messages from the game's REAL strings (LOOT_ROLL_*), checks that
-- the addon recognizes them and (in "summary" mode) renders them through the same code as real rolls.
local function RunTest()
    Print(string.format("TEST: window %d (%s), format: %s, loot history (C_LootHistory): %s",
        db.frame, WindowName(db.frame), db.format, HAS_HISTORY and "YES" or "NO"))

    -- 1) do we recognize the roll chat messages (needed to hide the raw lines in this window)
    local item = "|cffffffff|Hitem:25::::::::::::::|h[Worn Shortsword]|h|r"
    local function pl(n)
        return "|Hplayer:" .. n .. "-Testrealm:1|h[" .. n .. "]|h"
    end
    local cases = {
        { "LOOT_ROLL_NEED", { pl("Brakk"), item } },
        { "LOOT_ROLL_GREED", { pl("Seluna"), item } },
        { "LOOT_ROLL_PASSED", { pl("Morv"), item } },
        { "LOOT_ROLL_ROLLED_NEED", { 74, item, pl("Brakk") } },
        { "LOOT_ROLL_ROLLED_GREED", { 55, item, pl("Seluna") } },
        { "LOOT_ROLL_WON", { pl("Brakk"), item } },
    }
    local unpackFn = unpack or table.unpack
    local problems = 0
    for _, c in ipairs(cases) do
        local name, args = c[1], c[2]
        local fmt = _G[name]
        if type(fmt) ~= "string" then
            problems = problems + 1
            Print("|cffff4040MISSING|r global string " .. name .. " (renamed in this game version?)")
        else
            -- Forever strings have extra fields: fill them in ("1" fits both %s and %d)
            local needed = 0
            for idx in fmt:gmatch("%%(%d+)%$") do
                needed = math.max(needed, tonumber(idx))
            end
            needed = math.max(needed, (select(2, fmt:gsub("%%[sd]", ""))))
            local filled = {}
            for i = 1, math.max(needed, #args) do
                filled[i] = args[i] ~= nil and args[i] or "1"
            end
            local ok, msg = pcall(string.format, fmt, unpackFn(filled))
            if not ok then
                problems = problems + 1
                Print("|cffff4040ERROR|r formatting " .. name .. ": " .. tostring(msg)
                    .. " | text: " .. fmt:gsub("|", "||"))
            else
                local parsed = Parse(msg)
                if parsed then
                    Print(string.format("|cff00ff00OK|r %s -> %s", name, parsed.kind))
                else
                    problems = problems + 1
                    Print("|cffff4040NOT RECOGNIZED|r " .. name .. ": " .. msg:gsub("|", "||"))
                end
            end
        end
    end

    -- 2) summary: sample data in the Blizzard loot history format
    if db.format == "summary" then
        if TargetFrame() then
            local function roll(name, class, state, value, winner)
                return { playerName = name, playerGUID = name, playerClass = class, isSelf = false,
                    state = state, roll = value, isWinner = winner or false }
            end
            local win = roll("Brakk-Testrealm", "WARRIOR", ROLL_STATE.NeedMainSpec, 74, true)
            RenderDrop({
                itemHyperlink = item, allPassed = false, winner = win,
                rollInfos = {
                    win,
                    roll("Seluna-Testrealm", "PRIEST", ROLL_STATE.Greed, 55),
                    roll("Monra-Greytusk", "MAGE", ROLL_STATE.NeedOffSpec, 31),
                    roll("Rax-Testrealm", "ROGUE", ROLL_STATE.Greed, 12),
                    roll("Morv-Testrealm", "HUNTER", ROLL_STATE.Pass),
                },
            })
            Print("You should see a block for [Worn Shortsword] in window " .. WindowName(db.frame) .. ".")
        else
            Print("Window " .. db.frame .. " does not exist - pick another window in the settings.")
        end
    else
        Print("Raw mode: the test only checks message recognition (switch format to summary to see the block).")
    end
    Print(problems == 0 and "TEST finished: everything recognized." or ("TEST finished: problems: " .. problems))
end

-- Opens Esc > Options > AddOns > Who Won That. Returns false if the panel is unavailable.
local function OpenPanel()
    if settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
        return true
    end
    return false
end

local function HandleSlash(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    rest = rest or ""
    if cmd == "" then
        -- plain /wwt opens the settings panel
        if not OpenPanel() then
            Print("The settings panel is not available in this game version.")
            Help()
        end
    elseif cmd == "help" or cmd == "status" then
        Help()
    elseif cmd == "test" then
        RunTest()
    elseif cmd == "config" or cmd == "options" or cmd == "ui" then
        if not OpenPanel() then
            Print("The settings panel is not available in this game version - use the /wwt commands.")
        end
    elseif cmd == "list" then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            if _G["ChatFrame" .. i] then
                Print(string.format("%d - %s%s", i, WindowName(i), i == db.frame and "  <- here" or ""))
            end
        end
    elseif cmd == "frame" or cmd == "window" then
        local n = FindWindow(rest)
        if not n then
            Print("No such window. Type /wwt list.")
            return
        end
        db.frame = n
        EnsureLootGroup()
        Status()
    elseif cmd == "format" then
        rest = rest:lower()
        if rest ~= "summary" and rest ~= "raw" then
            Print("Usage: /wwt format summary  or  raw")
            return
        end
        db.format = rest
        wipe(items)
        Status()
    elseif cmd == "all" then
        db.rolls, db.need, db.greed, db.de, db.pass = true, true, true, true, true
        Status()
    elseif cmd == "only" then
        local t = TYPE_ALIASES[rest:lower()]
        if not t then
            Print("Usage: /wwt only need  (or greed, pass)")
            return
        end
        db.rolls = true
        for _, key in ipairs({ "need", "greed", "pass" }) do
            db[key] = (key == t)
        end
        Status()
    elseif TYPE_ALIASES[cmd] then
        local v = ParseBool(rest)
        if v == nil then
            Print("Usage: /wwt " .. cmd .. " on  or  off")
            return
        end
        db[TYPE_ALIASES[cmd]] = v
        if v then
            db.rolls = true
        end
        Status()
    elseif cmd == "rolls" or cmd == "wins" or cmd == "others" or cmd == "colors" then
        local v = ParseBool(rest)
        if v == nil then
            Print("Usage: /wwt " .. cmd .. " on  or  off")
            return
        end
        if cmd == "rolls" then db.rolls = v
        elseif cmd == "wins" then db.wins = v
        elseif cmd == "colors" then db.classColors = v
        else db.hideOthers = v end
        Status()
    else
        Help()
    end
end

-- Panel in Esc > Options > AddOns > Who Won That (Settings API from Blizzard_Settings_Shared).
-- Settings are saved straight into WhoWonThatDB; the /wwt commands keep working.
local function RegisterPanel()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
        and Settings.CreateCheckbox and Settings.CreateDropdown and Settings.CreateControlTextContainer) then
        return
    end

    local category = Settings.RegisterVerticalLayoutCategory("Who Won That")
    settingsCategory = category

    local function AddBool(key, label, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "WWT_" .. key:upper(), key, db,
            Settings.VarType.Boolean, label, DEFAULTS[key])
        if onChange then
            setting:SetValueChangedCallback(onChange)
        end
        return Settings.CreateCheckbox(category, setting, tooltip)
    end

    -- Chat window: list of windows with numbers and names
    local frameSetting = Settings.RegisterAddOnSetting(category, "WWT_FRAME", "frame", db,
        Settings.VarType.Number, "Chat window", DEFAULTS.frame)
    frameSetting:SetValueChangedCallback(function()
        EnsureLootGroup()
    end)
    local function WindowOptions()
        local container = Settings.CreateControlTextContainer()
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            if _G["ChatFrame" .. i] then
                container:Add(i, i .. " - " .. WindowName(i))
            end
        end
        return container:GetData()
    end
    Settings.CreateDropdown(category, frameSetting, WindowOptions,
        "Chat window that shows rolls and winners (e.g. your party/dungeon tab). Other windows are not changed.")

    -- Format
    local formatSetting = Settings.RegisterAddOnSetting(category, "WWT_FORMAT", "format", db,
        Settings.VarType.String, "Format", DEFAULTS.format)
    formatSetting:SetValueChangedCallback(function()
        wipe(items)
    end)
    local function FormatOptions()
        local container = Settings.CreateControlTextContainer()
        container:Add("summary", "Readable block per item",
            "When a roll ends: the item, who won and what everyone rolled.")
        container:Add("raw", "Original lines",
            "Keeps Blizzard's normal messages (filtered by roll type).")
        return container:GetData()
    end
    Settings.CreateDropdown(category, formatSetting, FormatOptions, "How rolls are shown in that window.")

    -- What to show
    local rollsInit = AddBool("rolls", "Show other players' rolls",
        "Who chose Need/Greed/Pass and what they rolled.")
    local function Child(key, label, tooltip)
        local init = AddBool(key, label, tooltip)
        if init and init.SetParentInitializer and rollsInit then
            init:SetParentInitializer(rollsInit)
        end
    end
    Child("need", "Need", "Show Need rolls.")
    Child("greed", "Greed", "Show Greed rolls.")
    Child("de", "Disenchant", "Show Disenchant rolls (only in the \"Original lines\" format, if the game has them).")
    Child("pass", "Pass", "Show players who passed.")
    AddBool("wins", "Show who won",
        "The roll winner, and a note when everyone passed.")
    AddBool("hideOthers", "Hide other loot in that window",
        "Hides messages about picked up, crafted, quest and master-looter items etc.")
    AddBool("classColors", "Class colors on names",
        "Colors player names by class. If EllesmereUI is installed its class colors are used.")

    -- Buttons: sample roll and command list
    local SettingsPanelRef = _G.SettingsPanel
    if CreateSettingsButtonInitializer and SettingsPanelRef and SettingsPanelRef.GetLayout then
        local layout = SettingsPanelRef:GetLayout(category)
        if layout and layout.AddInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer("Test",
                "Print sample roll", RunTest,
                "Prints a sample roll to the chosen chat window and checks that the game's roll messages are recognized.", true))
            layout:AddInitializer(CreateSettingsButtonInitializer("Chat commands",
                "Show commands", Help,
                "Lists the /wwt chat commands. Every setting is also available in this panel.", true))
        end
    end

    Settings.RegisterAddOnCategory(category)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        WhoWonThatDB = WhoWonThatDB or {}
        db = WhoWonThatDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then
                db[k] = v
            end
        end
        RegisterPanel()
    elseif event == "PLAYER_LOGIN" then
        BuildEntries()
        if addFilter then
            addFilter("CHAT_MSG_LOOT", Filter)
        end
        if HAS_HISTORY then
            MarkExistingDrops()
            if C_Timer and C_Timer.After then
                C_Timer.After(3, MarkExistingDrops) -- the history is sometimes ready only a moment after login
            end
            f:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
        else
            f:RegisterEvent("CHAT_MSG_LOOT") -- fallback: assemble rolls from chat messages
        end
        EnsureLootGroup()
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        OnDropUpdate(arg1, arg2)
    elseif event == "CHAT_MSG_LOOT" then
        OnLoot(arg1)
    end
end)

SLASH_WHOWONTHAT1 = "/wwt"
SLASH_WHOWONTHAT2 = "/whowonthat"
SlashCmdList["WHOWONTHAT"] = function(input)
    if db then
        HandleSlash(input)
    end
end
