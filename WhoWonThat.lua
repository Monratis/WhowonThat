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
    hideOthers = true,  -- always on: hide other loot messages in that window (picked up items etc.)
    classColors = true, -- color names by class (custom palette if present, else Blizzard colors)
    header = true,      -- put the addon name in front of each item line
    byBoss = true,      -- always on: "Loot from: <boss>" above the items of one kill
    flagUnusable = true, -- always on: red X on Need rolls for armor the class cannot wear
    announce = "off",   -- send results to group chat: "off", "mine" (only my wins) or "all"
    hideWhenAnnounced = true, -- do not print my own block for a result that was announced in group chat
    detail = "all",     -- how much to show: "winner", "rolls" (winner + Need/Greed) or "all" (also passes)
    layout = "auto",    -- "auto" = compact on a narrow chat window, "normal", or "compact"
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

-- A chat window the player really has: shown or docked (the same test Blizzard uses), not a temporary
-- (whisper) window and not the combat log. The engine creates ChatFrame1..10 even when most are unused.
local function IsUsableWindow(i)
    local f = _G["ChatFrame" .. i]
    if not f or f.isTemporary or (COMBATLOG and f == COMBATLOG) then
        return false
    end
    local getInfo = FCF_GetChatWindowInfo or GetChatWindowInfo
    if getInfo then
        local name, _, _, _, _, _, shown, _, docked = getInfo(i)
        return (name ~= nil and name ~= "") and (shown and true or (docked ~= nil and docked ~= false and docked ~= 0))
    end
    return f:IsShown() and true or false
end

local function TargetFrame()
    if not db then
        return nil
    end
    -- if the saved window is not a real one (any more), use the main window
    local i = IsUsableWindow(db.frame) and db.frame or 1
    return _G["ChatFrame" .. i]
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
-- Class color: the user's custom palette if they use one, otherwise Blizzard's standard class colors.
local function ClassColor(classFile)
    if not classFile then
        return nil
    end
    -- user-defined palettes: the "ClassColors" addon, then EllesmereUI
    if type(CUSTOM_CLASS_COLORS) == "table" and CUSTOM_CLASS_COLORS[classFile] then
        return CUSTOM_CLASS_COLORS[classFile]
    end
    if type(EllesmereUI) == "table" and EllesmereUI.GetRawClassColor then
        local c = EllesmereUI.GetRawClassColor(classFile)
        if c then
            return c
        end
    end
    -- nothing installed: Blizzard's standard class colors
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
end

local function PlayerLink(full, short, classFile, display)
    -- short name in the text, full name (Name-Realm) in the link
    local link = "|Hplayer:" .. full .. "|h[" .. (display or short or full) .. "]|h"
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
-- Roll type colors: Need warm orange, Greed light blue, Pass grey
local LABEL_COLOR = { need = "ff9d4d", greed = "6fb7ff", pass = "9d9d9d" }

local function RollLabel(r, st, isWinner, extra)
    local icon = KIND_ICON[st.kind]
    -- the winning number is green, everyone else's is white
    local numberColor = isWinner and "|cff33ff33" or "|cffffffff"
    return (icon and (icon .. " ") or "")
        .. "|cff" .. (LABEL_COLOR[st.kind] or "aaaaaa") .. st.label .. "|r"
        .. (r.roll and (" " .. numberColor .. r.roll .. "|r") or "")
        .. (r.isSelf and "  |cffffd100(You)|r" or "")
        .. (extra or "")
end

-- Compact layout for narrow chat windows: smaller indents and shortened long names.
local COMPACT_WIDTH = 380 -- chat windows narrower than this (UI units) use the compact layout in "auto" mode
local COMPACT_NAME_LENGTH = 8

local function IsCompact(frame)
    if db.layout == "compact" then
        return true
    elseif db.layout == "normal" then
        return false
    end
    local width = frame and frame.GetWidth and frame:GetWidth()
    return type(width) == "number" and width > 0 and width < COMPACT_WIDTH
end

-- Cuts a name to max characters and appends ".." (UTF-8 aware, so accented letters are not split).
local function Truncate(name, max)
    local chars = {}
    for ch in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars[#chars + 1] = ch
    end
    if #chars <= max then
        return name
    end
    return table.concat(chars, "", 1, max - 2) .. ".."
end

-- Red X icon (the game's "not ready" mark), used to flag a Need roll the player's class cannot use
local ICON_CANT_USE = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14:0:0|t"

-- Chat windows cannot center text, so we measure it: the width of the window and of the text in the
-- window's own font tell us how many spaces to put in front of the line.
local measurer
local function TextWidth(frame, text)
    if not measurer then
        local host = UIParent or frame
        if not (host and host.CreateFontString) then
            return nil
        end
        measurer = host:CreateFontString(nil, "OVERLAY")
        measurer:Hide()
    end
    local font, size, flags = frame:GetFont()
    if not font then
        return nil
    end
    measurer:SetFont(font, size, flags)
    measurer:SetText(text)
    return measurer:GetStringWidth()
end

-- Returns the spaces that center `text` (plain, without color codes) in the chat frame.
local function CenterPadding(frame, text)
    if not (frame.GetFont and frame.GetWidth) then
        return ""
    end
    local available = (frame:GetWidth() or 0) - 20 -- margins and scroll bar
    local textWidth = TextWidth(frame, text)
    local spaceWidth
    if textWidth then
        spaceWidth = TextWidth(frame, "a a") - TextWidth(frame, "aa")
    end
    if not textWidth or not spaceWidth or spaceWidth <= 0 or available <= textWidth then
        return ""
    end
    return string.rep(" ", math.floor((available - textWidth) / 2 / spaceWidth))
end

-- `plain` is what is measured, `colored` is what is printed (same visible text, with color codes)
local function Centered(frame, plain, colored)
    return CenterPadding(frame, plain) .. colored
end

-- ===== Clickable boss name =====
-- The boss name is a link that opens the player's own loot browser on the page of the item that dropped:
-- DungeonJournal (ForeverDungeonJournal) first, then AtlasLoot. Without either, the name stays plain text.
local BOSS_LINK = "addon:WhoWonThat:boss:"

local function BossBrowser()
    local journal = _G.ForeverDungeonJournal_NS
    if type(journal) == "table" and type(journal.OpenItemSource) == "function" then
        return "journal"
    end
    local atlas = _G.AtlasLoot
    if type(atlas) == "table" and type(atlas.GUI) == "table" and type(atlas.GUI.Toggle) == "function" then
        return "atlas"
    end
    return nil
end

local function OpenBossSource(itemID)
    local browser = BossBrowser()
    if browser == "journal" then
        local ok, opened = pcall(_G.ForeverDungeonJournal_NS.OpenItemSource, itemID)
        if ok and opened then
            return true
        end
        return false
    elseif browser == "atlas" then
        -- AtlasLoot has no call to jump to a boss, so this opens its window.
        local gui = _G.AtlasLoot.GUI
        if not (gui.frame and gui.frame.IsVisible and gui.frame:IsVisible()) then
            pcall(gui.Toggle, gui)
        end
        return true
    end
    return false
end

local function OnBossLink(link)
    if type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then
        return
    end
    if link:sub(1, #BOSS_LINK) ~= BOSS_LINK then
        return
    end
    local itemID = tonumber(link:sub(#BOSS_LINK + 1))
    if itemID then
        OpenBossSource(itemID)
    end
end

-- Small item icon in front of the link (like the loot window); empty if the game has no data for the item
local function ItemIcon(item)
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getInfo then
        return ""
    end
    local _, _, _, _, icon = getInfo(item)
    if type(icon) == "number" or type(icon) == "string" then
        return "|T" .. icon .. ":14:14:0:0|t "
    end
    return ""
end

local function ItemLine(item)
    return ItemIcon(item) .. item
end

-- Name of the encounter (boss) a drop belongs to, from the game's loot history. Nil if unknown.
local lastEncounterKey
local lastTitleAt = 0
local TITLE_PAUSE = 30 -- seconds without a block after which the title is printed again (no boss data)
local function EncounterName(encounterID)
    if not encounterID or not C_LootHistory or not C_LootHistory.GetInfoForEncounter then
        return nil
    end
    local info = C_LootHistory.GetInfoForEncounter(encounterID)
    if type(info) ~= "table" then
        return nil
    end
    local name = info.encounterName
    if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then
        return nil
    end
    return name, tostring(encounterID) .. ":" .. tostring(info.startTime)
end

-- Heaviest armor each class can wear: 1 cloth, 2 leather, 3 mail, 4 plate.
local ARMOR_CAP = {
    PRIEST = 1, MAGE = 1, WARLOCK = 1,
    ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
    HUNTER = 3, SHAMAN = 3, EVOKER = 3,
    WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
}
local SHIELD_CLASSES = { WARRIOR = true, PALADIN = true, SHAMAN = true }

-- Returns false only when the class clearly cannot equip the item (armor heavier than it can wear, or a
-- shield). Anything uncertain (weapons, jewelry, unknown items or classes) returns true.
local function CanClassUse(classFile, item)
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getInfo or type(classFile) ~= "string" then
        return true
    end
    local _, _, _, equipLoc, _, classID, subClassID = getInfo(item)
    if classID ~= 4 or type(subClassID) ~= "number" or equipLoc == "INVTYPE_CLOAK" then
        return true
    end
    if subClassID == 6 then -- shield
        return SHIELD_CLASSES[classFile] == true
    end
    local cap = ARMOR_CAP[classFile]
    if cap and subClassID >= 1 and subClassID <= 4 and subClassID > cap then
        return false
    end
    return true
end

-- Prints the summary of one item (data from C_LootHistory) on several lines:
--   [Item]
--      [crown] Winner  WON  [dice] Need 74
--          Player2  [coin] Greed 55
--          Player3  [dice] Need OS 31
local function RenderDrop(info, encounterID)
    local frame = TargetFrame()
    if not frame or type(info) ~= "table" then
        return
    end
    local item = info.itemHyperlink
    if type(item) ~= "string" or (issecretvalue and issecretvalue(item)) then
        return
    end
    -- boss header: printed once per kill, above the first item that is shown
    local bossName, bossKey
    if db.byBoss then
        bossName, bossKey = EncounterName(encounterID)
    end
    -- Heading: the addon title (centered, alone on its line) and, when a new kill starts, "Loot from: <boss>"
    -- (centered, next line). Without boss data the title is repeated only after a pause.
    local function BossHeader()
        local newBoss = bossName and bossKey ~= lastEncounterKey
        if newBoss then
            lastEncounterKey = bossKey
        end
        local now = GetTime()
        if db.header and (newBoss or (not bossName and now - lastTitleAt > TITLE_PAUSE)) then
            Emit(frame, Centered(frame, "Who Won That", "|cff58c6faWho Won That|r"), "LOOT")
            lastTitleAt = now
        end
        if newBoss then
            local itemID = tonumber(item:match("item:(%d+)"))
            if itemID and BossBrowser() then
                -- clickable: "[Boss]" opens the journal / AtlasLoot
                Emit(frame, Centered(frame, "Loot from: [" .. bossName .. "]",
                    "|cff9d9d9dLoot from:|r |cffffd100|H" .. BOSS_LINK .. itemID .. "|h[" .. bossName .. "]|h|r"), "LOOT")
            else
                Emit(frame, Centered(frame, "Loot from: " .. bossName,
                    "|cff9d9d9dLoot from:|r |cffffd100" .. bossName .. "|r"), "LOOT")
            end
        end
    end

    if info.allPassed then
        if db.wins then
            local compact = IsCompact(frame)
            BossHeader()
            Emit(frame, ItemLine(item), "LOOT")
            Emit(frame, (compact and "  " or "     ") .. "|cffaaaaaaNobody wanted it (everyone passed)|r", "LOOT")
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

    local compact = IsCompact(frame)
    local indentWinner, indentOthers = "   ", "        "
    if compact then
        indentWinner, indentOthers = " ", "   "
    end
    local function Display(name)
        local short = ShortName(name)
        return compact and Truncate(short, COMPACT_NAME_LENGTH) or short
    end

    -- red X (and "can't use" text on a wide window) at the end of a Need roll on armor the class cannot wear
    local function Flag(r, st)
        if db.flagUnusable and st.kind == "need" and not CanClassUse(r.playerClass, item) then
            return "  " .. ICON_CANT_USE .. (compact and "" or " |cffff4040can't use|r")
        end
        return nil
    end

    BossHeader()
    Emit(frame, ItemLine(item), "LOOT")
    if showWinner then
        local line = indentWinner .. ICON_CROWN .. " "
            .. PlayerLink(winner.playerName, ShortName(winner.playerName), winner.playerClass, Display(winner.playerName))
            .. "  |cffffd100WON|r"
        local wst = STATE_INFO[winner.state]
        if wst then
            line = line .. "  " .. RollLabel(winner, wst, true, Flag(winner, wst))
        end
        Emit(frame, line, "LOOT")
    end
    local passers = {}
    for i = 1, #list do
        local r, st = list[i].r, list[i].st
        if st.kind == "pass" then
            passers[#passers + 1] = PlayerLink(r.playerName, ShortName(r.playerName), r.playerClass, Display(r.playerName))
        else
            Emit(frame, indentOthers .. PlayerLink(r.playerName, ShortName(r.playerName), r.playerClass, Display(r.playerName))
                .. "  " .. RollLabel(r, st, false, Flag(r, st)), "LOOT")
        end
    end
    if #passers > 0 then
        -- everyone who passed on one quiet line instead of one line each
        Emit(frame, indentOthers .. KIND_ICON.pass .. " |cff9d9d9d" .. (compact and "Pass: " or "Passed: ") .. "|r"
            .. table.concat(passers, "|cff9d9d9d, |r"), "LOOT")
    end
end

-- ===== Optional group announcement =====
-- Anyone using this addon with announcements on could send the same line, so:
--  * we wait a random moment after the roll ends (the first client to wake up announces),
--  * if a line for the same item and winner already appeared in group chat, we do not send another,
--  * a result that was announced is not printed again as our own block (option, on by default).
local ANNOUNCE_PREFIX = "Who Won That: "
local ANNOUNCE_DELAY_MIN, ANNOUNCE_DELAY_MAX = 2, 7 -- seconds
local ANNOUNCE_MEMORY = 120 -- seconds an announcement is remembered
local announcedAt = {}      -- ["itemID:Winner"] = time

local function AnnounceActive()
    return db and (db.announce == "mine" or db.announce == "all")
end

local function ItemIDOf(link)
    return type(link) == "string" and link:match("item:(%d+)") or nil
end

local function AnnounceKey(itemID, winnerShort)
    return itemID .. ":" .. winnerShort
end

local function RememberAnnouncement(key)
    local now = GetTime()
    for k, t in pairs(announcedAt) do
        if now - t > ANNOUNCE_MEMORY then
            announcedAt[k] = nil
        end
    end
    announcedAt[key] = now
end

-- Group chat line from another player (or from us): remember who announced what.
local function OnGroupChat(msg, sender)
    if type(msg) ~= "string" or (issecretvalue and (issecretvalue(msg) or issecretvalue(sender))) then
        return
    end
    if msg:sub(1, #ANNOUNCE_PREFIX) ~= ANNOUNCE_PREFIX then
        return
    end
    local who = msg:match("^Who Won That: (%S+) won ")
    local itemID = ItemIDOf(msg)
    if not who or not itemID then
        return
    end
    if who == "I" then
        who = ShortName(type(sender) == "string" and sender or "")
    end
    if who ~= "" then
        RememberAnnouncement(AnnounceKey(itemID, who))
    end
end

local function DropAnnounceKey(info)
    local winner = info.winner
    local itemID = ItemIDOf(info.itemHyperlink)
    if info.allPassed or type(winner) ~= "table" or not itemID or not UsableName(winner.playerName) then
        return nil
    end
    return AnnounceKey(itemID, ShortName(winner.playerName))
end

local function AlreadyAnnounced(info)
    local key = DropAnnounceKey(info)
    local t = key and announcedAt[key]
    return t ~= nil and GetTime() - t <= ANNOUNCE_MEMORY
end

-- Sends the announcement. Returns true if a line was sent. Not sent while the game restricts addon chat
-- (e.g. during encounters) or when you are not in a group.
local function Announce(info)
    local mode = db.announce
    local key = DropAnnounceKey(info)
    local winner = info.winner
    if (mode ~= "mine" and mode ~= "all") or not key then
        return false
    end
    if mode == "mine" and not winner.isSelf then
        return false
    end
    local item = info.itemHyperlink
    if type(item) ~= "string" or (issecretvalue and issecretvalue(item)) then
        return false
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false
    end
    local channel
    if IsInRaid and IsInRaid() then
        channel = "RAID"
    elseif IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif IsInGroup and IsInGroup() then
        channel = "PARTY"
    else
        return false
    end
    local send = SendChatMessage or (C_ChatInfo and C_ChatInfo.SendChatMessage) -- the same call Questie uses in Forever
    if not send then
        return false
    end
    local st = STATE_INFO[winner.state]
    local detail = st and (" (" .. st.label .. (winner.roll and (" " .. winner.roll) or "") .. ")") or ""
    local who = winner.isSelf and "I" or ShortName(winner.playerName)
    RememberAnnouncement(key)
    send(ANNOUNCE_PREFIX .. who .. " won " .. item .. detail, channel)
    return true
end

-- A finished roll: announce it (if enabled and nobody did yet) and print our own block (unless the result was
-- announced and the option to hide it is on).
local function ProcessDrop(info, encounterID)
    if not db then
        return
    end
    local announced = false
    if AnnounceActive() then
        announced = AlreadyAnnounced(info) or Announce(info)
    end
    if announced and db.hideWhenAnnounced then
        return
    end
    RenderDrop(info, encounterID)
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
    if AnnounceActive() and C_Timer and C_Timer.After then
        -- random delay so that group members' addons do not all announce at the same moment
        C_Timer.After(ANNOUNCE_DELAY_MIN + math.random() * (ANNOUNCE_DELAY_MAX - ANNOUNCE_DELAY_MIN), function()
            ProcessDrop(info, encounterID)
        end)
    else
        ProcessDrop(info, encounterID)
    end
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

local settingsCategory -- category in Esc > Options > AddOns

local function Help()
    Print("Settings: Esc > Options > AddOns > Who Won That")
    Print("/wwt - open the settings panel")
    Print("/wwt help - show this help")
    Print("/wwt test - print a sample roll to the chosen chat window")
end

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
    local cmd = ((input or ""):match("^%s*(%S*)") or ""):lower()
    if cmd == "" then
        -- plain /wwt opens the settings panel
        if not OpenPanel() then
            Print("The settings panel is not available in this game version.")
        end
    elseif cmd == "test" then
        RunTest()
    else
        Help()
    end
end

-- The panel offers one "detail" choice; it sets the individual switches the display code reads.
local function ApplyDetail()
    local detail = db.detail
    db.wins = true
    db.de = true
    if detail == "winner" then
        db.rolls, db.need, db.greed, db.pass = false, true, true, true
    elseif detail == "rolls" then
        db.rolls, db.need, db.greed, db.pass = true, true, true, false
    else
        db.detail = "all"
        db.rolls, db.need, db.greed, db.pass = true, true, true, true
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

    -- Section headers (skipped quietly if this game version has no such widget)
    local function Header(text)
        local panel = _G.SettingsPanel
        if CreateSettingsListSectionHeaderInitializer and panel and panel.GetLayout then
            local layout = panel:GetLayout(category)
            if layout and layout.AddInitializer then
                layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
            end
        end
    end

    local function AddBool(key, label, tooltip)
        local setting = Settings.RegisterAddOnSetting(category, "WWT_" .. key:upper(), key, db,
            Settings.VarType.Boolean, label, DEFAULTS[key])
        return Settings.CreateCheckbox(category, setting, tooltip)
    end

    -- Dropdown from a list of { value, label, tooltip }
    local function AddChoice(key, label, tooltip, choices, varType, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "WWT_" .. key:upper(), key, db,
            varType or Settings.VarType.String, label, DEFAULTS[key])
        if onChange then
            setting:SetValueChangedCallback(onChange)
        end
        local function Options()
            local container = Settings.CreateControlTextContainer()
            for _, c in ipairs(choices) do
                container:Add(c[1], c[2], c[3])
            end
            return container:GetData()
        end
        return Settings.CreateDropdown(category, setting, Options, tooltip)
    end

    -- ===== Where =====
    Header("Chat")

    -- only windows the player really has (see IsUsableWindow)
    local frameSetting = Settings.RegisterAddOnSetting(category, "WWT_FRAME", "frame", db,
        Settings.VarType.Number, "Chat window", DEFAULTS.frame)
    frameSetting:SetValueChangedCallback(function()
        EnsureLootGroup()
    end)
    local function WindowOptions()
        local container = Settings.CreateControlTextContainer()
        local count = 0
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            if IsUsableWindow(i) then
                container:Add(i, i .. " - " .. WindowName(i))
                count = count + 1
            end
        end
        if count == 0 then
            container:Add(1, "1 - " .. WindowName(1))
        end
        -- This function runs every time the list is shown, so it must not change the saved value.
        -- If the saved window is not available right now it is listed as such; the addon uses window 1
        -- meanwhile (see TargetFrame) and goes back to the saved one when it is there again.
        if not IsUsableWindow(db.frame) and type(db.frame) == "number" then
            local name = WindowName(db.frame)
            container:Add(db.frame, db.frame .. " - " .. (name ~= "-" and name or "window") .. " (not shown)")
        end
        return container:GetData()
    end
    Settings.CreateDropdown(category, frameSetting, WindowOptions,
        "The chat tab that shows the roll results (e.g. your party/dungeon tab). Other tabs are not touched.")

    AddChoice("layout", "Layout",
        "Compact uses smaller indents and shortens long names, for small chat windows.", {
            { "auto", "Automatic", "Compact when the chat window is narrow." },
            { "normal", "Normal", "Full names and wide indents." },
            { "compact", "Compact", "Smaller indents, long names shortened with .." },
        })

    AddChoice("detail", "Detail",
        "How much of each roll is printed.", {
            { "all", "Everyone's rolls", "Winner, every Need/Greed roll, and who passed." },
            { "rolls", "Winner and Need/Greed", "Winner and the Need/Greed rolls, without the passes." },
            { "winner", "Winner only", "Just who won each item." },
        }, nil, ApplyDetail)


    -- ===== Group chat =====
    Header("Group chat")

    local announceInit = AddChoice("announce", "Announce results",
        "Tells your group who won. Not sent while the game restricts addon chat. Waits a random moment and never repeats a line another player's addon already sent.", {
            { "off", "Off", "Nothing is sent to other players." },
            { "mine", "Only my wins", "One line to party/raid chat when you win an item." },
            { "all", "All results", "One line per item. If several group members use this, expect duplicates only when they announce at the same moment." },
        })
    local hideInit = AddBool("hideWhenAnnounced", "Hide my block when announced",
        "If the result was announced in group chat (by you or another player), your own detailed block is not printed again.")
    if hideInit and hideInit.SetParentInitializer and announceInit then
        -- only meaningful while announcements are on
        hideInit:SetParentInitializer(announceInit, function()
            return db.announce ~= "off"
        end)
    end

    -- ===== Test =====
    local panel = _G.SettingsPanel
    if CreateSettingsButtonInitializer and panel and panel.GetLayout then
        local layout = panel:GetLayout(category)
        if layout and layout.AddInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer("Sample roll",
                "Print sample roll", RunTest,
                "Prints a sample roll to the chosen chat tab so you can see how it looks.", true))
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
        -- leftovers of old test versions: no longer used, so they do not stay in the saved file
        for _, k in ipairs({ "boot", "mainLoaded", "debug", "schema", "transmog", "errors", "strings", "colors" }) do
            db[k] = nil
        end
        ApplyDetail()
        -- no switches in the panel for these: always the intended behavior
        db.byBoss, db.classColors, db.header = true, true, true
        db.flagUnusable, db.hideOthers = true, true
        db.format = "summary"
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
        for _, e in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
            "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
            f:RegisterEvent(e) -- to see announcements made by other players
        end
        if hooksecurefunc and SetItemRef then
            hooksecurefunc("SetItemRef", OnBossLink) -- same way Questie handles its addon links
        end
        EnsureLootGroup()
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" or event == "CHAT_MSG_RAID"
        or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_INSTANCE_CHAT"
        or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
        OnGroupChat(arg1, arg2)
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
