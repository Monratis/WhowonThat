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
    hintSeen = false,   -- the one-time "how to choose a chat window" tip was shown
}

local TYPE_LABEL = { need = "Need", greed = "Greed", de = "Disenchant", pass = "Pass" }
local PRIORITY = { win = 1, de = 2, greed = 3, need = 4, pass = 5, other = 6 }
-- Forever (Midnight engine) has a loot history with structured roll data (C_LootHistory) - the main data source.
-- Chat text parsing is only used to hide the raw lines and as a fallback.
local HAS_HISTORY = (C_LootHistory ~= nil and C_LootHistory.GetSortedInfoForDrop ~= nil)
local STALE_SECONDS = 180

local db
local entries = {}  -- {pattern, kinds, kind, wonType, self, prio}
local entriesBuilt = false
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
    if not entriesBuilt then
        entriesBuilt = true
        BuildEntries() -- built lazily: only the fallback and /wwt test need it
    end
    for i = 1, #entries do
        local e = entries[i]
        local c1 = msg:match(e.pattern)
        if c1 then
            local caps = { msg:match(e.pattern) }
            local r ={ kind = e.kind, wonType = e.wonType, allPassed = e.allPassed }
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
-- the saved window's frame without building the "ChatFrameN" name string on every chat message
local FRAME_NAMES = {}
local function TargetFrameRaw()
    local i = db.frame
    local name = FRAME_NAMES[i]
    if not name then
        name = "ChatFrame" .. i
        FRAME_NAMES[i] = name
    end
    return _G[name]
end

-- Summary mode is always on: roll lines are replaced by our block and all other loot lines are hidden
-- in this window too, so every loot message here is hidden and nothing needs to be parsed (cheap path).
local function Filter(self)
    if not db then
        return false
    end
    -- cheap rejection for all the other chat windows before the (slower) usability check
    if self ~= TargetFrameRaw() and self ~= ChatFrame1 then
        return false
    end
    return self == TargetFrame()
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

local colorCodes = {}

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
        -- the color code per class is computed once per block (cleared in RenderDrop), not once per player
        local code = class and colorCodes[class]
        if code == nil then
            local c = ClassColor(class)
            code = c and string.format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5)) or false
            if class then
                colorCodes[class] = code
            end
        end
        if code then
            return code .. link .. "|r"
        end
    end
    return link
end

-- ===== Main data source: Blizzard loot history (LOOT_HISTORY_UPDATE_DROP event) =====
local ROLL_STATE = (Enum and Enum.EncounterLootDropRollState)
    or { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
local STATE_INFO = {
    [ROLL_STATE.NeedMainSpec] = { kind = "need", label = "Need", rank = 1 },
    [ROLL_STATE.NeedOffSpec] = { kind = "need", label = "Need OS", tag = "OS", rank = 2 },
    [ROLL_STATE.Greed] = { kind = "greed", label = "Greed", rank = 3 },
    [ROLL_STATE.Pass] = { kind = "pass", label = "Pass", rank = 4 },
    -- NoRoll: the player has not chosen yet - skipped
}
-- Need MS first, then Need OS, then Greed; inside a type by roll (like the game decides the winner)
local function RollOrder(a, b)
    if a.st.rank ~= b.st.rank then return a.st.rank < b.st.rank end
    local ra, rb = a.r.roll or -1, b.r.roll or -1
    if ra ~= rb then return ra > rb end
    return a.r.playerName < b.r.playerName
end
local printedDrops = {} -- [encounterID][lootListKey] = true (nested: no string building per event)
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
    -- the icon says Need/Greed/Pass; only the off-spec Need gets a small "OS" tag
    return (icon and icon or ("|cff" .. (LABEL_COLOR[st.kind] or "aaaaaa") .. st.label .. "|r"))
        .. (st.tag and (" |cff" .. (LABEL_COLOR[st.kind] or "aaaaaa") .. st.tag .. "|r") or "")
        .. (r.roll and (" " .. numberColor .. r.roll .. "|r") or "")
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
local lastAnnouncedBoss -- same idea for the boss line of group announcements
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
    -- "Miscellaneous" is the game's catch-all for loot that is not from a boss: no "Loot from:" for it,
    -- the block simply shows the item (same as when there is no boss data)
    if name == "Miscellaneous" or name == _G.MISCELLANEOUS then
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
local function RenderDropBody(Emit, frame, info, encounterID)
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
        if not newBoss then
            return ""
        end
        -- "Loot from: [Boss]" goes in front of the first item of the kill, on the same line
        local itemID = tonumber(item:match("item:(%d+)"))
        if itemID and BossBrowser() then
            -- clickable: "[Boss]" opens the journal / AtlasLoot
            return "|cff9d9d9dLoot from:|r |cffffd100|H" .. BOSS_LINK .. itemID .. "|h[" .. bossName .. "]|h|r  "
        end
        return "|cff9d9d9dLoot from:|r |cffffd100" .. bossName .. "|r  "
    end

    if info.allPassed then
        if db.wins then
            local compact = IsCompact(frame)
            Emit(frame, BossHeader() .. ItemLine(item), "LOOT")
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
        table.sort(list, RollOrder)
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

    Emit(frame, BossHeader() .. ItemLine(item), "LOOT")
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
    -- players without a number (e.g. Greed when someone rolled Need: the game does not roll for them) are
    -- collected on one line per type instead of one line each
    local silent, silentOrder = {}, {}
    for i = 1, #list do
        local r, st = list[i].r, list[i].st
        if st.kind == "pass" then
            passers[#passers + 1] = PlayerLink(r.playerName, ShortName(r.playerName), r.playerClass, Display(r.playerName))
        elseif not r.roll then
            local g = silent[st.label]
            if not g then
                g = { st = st, names = {} }
                silent[st.label] = g
                silentOrder[#silentOrder + 1] = g
            end
            g.names[#g.names + 1] = PlayerLink(r.playerName, ShortName(r.playerName), r.playerClass, Display(r.playerName))
                .. (Flag(r, st) or "")
        else
            Emit(frame, indentOthers .. PlayerLink(r.playerName, ShortName(r.playerName), r.playerClass, Display(r.playerName))
                .. "  " .. RollLabel(r, st, false, Flag(r, st)), "LOOT")
        end
    end
    for _, g in ipairs(silentOrder) do
        Emit(frame, indentOthers .. KIND_ICON[g.st.kind] .. (g.st.tag and (" |cff" .. (LABEL_COLOR[g.st.kind] or "aaaaaa") .. g.st.tag .. "|r") or "")
            .. " " .. table.concat(g.names, "|cff9d9d9d, |r"), "LOOT")
    end
    if #passers > 0 then
        -- everyone who passed on one quiet line instead of one line each
        Emit(frame, indentOthers .. KIND_ICON.pass .. " "
            .. table.concat(passers, "|cff9d9d9d, |r"), "LOOT")
    end
end

-- The whole block is ONE chat message (lines joined with line breaks), so it stays together, has one
-- timestamp and cannot be interleaved with other chat.
local function RenderDrop(info, encounterID)
    local frame = TargetFrame()
    if not frame or type(info) ~= "table" then
        return
    end
    local buf = {}
    wipe(colorCodes)
    RenderDropBody(function(_, text) buf[#buf + 1] = text end, frame, info, encounterID)
    if #buf > 0 then
        Emit(frame, table.concat(buf, "\n"), "LOOT")
    end
end

-- ===== Optional group announcement =====
-- The group gets the same structure as the block in your own chat (item, winner, everyone else's rolls, who
-- passed), as plain text and respecting the Detail setting. Anyone using this addon with announcements on
-- could send the same block, so:
--  * we wait a random moment after the roll ends (the first client to wake up announces),
--  * if another player's block for the same item already appeared in group chat, we do not send ours,
--  * a result that was announced is not printed again as our own block (option, on by default).
local ANNOUNCE_PREFIX = "<Who Won That> "         -- starts the first announcement of a session: [Item]
local ANNOUNCE_PREFIX_SHORT = "<WWT> "            -- every later one is shorter
-- Older versions used other prefixes; still recognised so two players on different versions do not both announce.
local KNOWN_PREFIXES = { ANNOUNCE_PREFIX, ANNOUNCE_PREFIX_SHORT, "Who Won That: ", "WWT: " }
local announcedOnce = false
-- Group chat cannot carry colors or custom icons, but it accepts the raid target markers. Their own colors
-- echo the block in your chat: gold star = winner, orange = Need, blue = Greed, grey moon = pass, red X = cannot use.
local MARK = { winner = "{rt1}", need = "{rt2}", greed = "{rt6}", pass = "{rt5}", cantUse = "{rt7}" }
local ANNOUNCE_DELAY_MIN, ANNOUNCE_DELAY_MAX = 2, 7 -- seconds
local ANNOUNCE_MEMORY = 120 -- seconds an announcement is remembered
local SEND_INTERVAL = 0.5   -- seconds between two lines (keeps clear of the chat flood limit)
local announcedAt = {}      -- [itemID] = { time, time, ... } one entry per block seen from other players

-- A new group starts from scratch: the full name and the boss line are written again, and what was seen in the
-- old group's chat no longer matters. Called when you leave a group (the next one is always a new party).
local wasInGroup = false
local function OnGroupRosterUpdate()
    local inGroup = IsInGroup and IsInGroup() or false
    if wasInGroup and not inGroup then
        announcedOnce = false
        lastAnnouncedBoss = nil
        wipe(announcedAt)
    end
    wasInGroup = inGroup
end

local function AnnounceActive()
    return db and (db.announce == "mine" or db.announce == "all")
end

local function ItemIDOf(link)
    return type(link) == "string" and link:match("item:(%d+)") or nil
end

local function PruneAnnouncements()
    local now = GetTime()
    for id, list in pairs(announcedAt) do
        for i = #list, 1, -1 do
            if now - list[i] > ANNOUNCE_MEMORY then
                table.remove(list, i)
            end
        end
        if #list == 0 then
            announcedAt[id] = nil
        end
    end
end

-- Group chat line from another player: the first line of a block names the item, so remember it.
-- Our own lines are ignored (they would otherwise count as someone else's block).
local function OnGroupChat(msg, sender)
    if type(msg) ~= "string" or (issecretvalue and (issecretvalue(msg) or issecretvalue(sender))) then
        return
    end
    local known = false
    for _, p in ipairs(KNOWN_PREFIXES) do
        if msg:sub(1, #p) == p then
            known = true
            break
        end
    end
    if not known then
        return
    end
    local itemID = ItemIDOf(msg)
    if not itemID then
        return
    end
    if type(sender) == "string" and ShortName(sender) == UnitName("player") then
        return
    end
    PruneAnnouncements()
    local list = announcedAt[itemID]
    if not list then
        list = {}
        announcedAt[itemID] = list
    end
    list[#list + 1] = GetTime()
end

-- True if another player already announced a block for this item. Each seen block covers one drop, so
-- two copies of the same item in one kill are handled correctly.
local function AlreadyAnnounced(info)
    local itemID = ItemIDOf(info.itemHyperlink)
    PruneAnnouncements()
    local list = itemID and announcedAt[itemID]
    if list and #list > 0 then
        table.remove(list, 1)
        return true
    end
    return false
end

-- The announcement is ONE chat message (group chat takes a single line of up to 255 bytes): item, winner,
-- the other rolls by rank, who passed. When there are too many rolls to fit, the rest is cut as "+N more".
local MAX_ANNOUNCE_BYTES = 250
local function AnnounceName(full)
    local short = ShortName(full)
    return short:match("^(%S+)") or short
end
local function AnnounceLines(info, encounterID)
    local item = info.itemHyperlink
    local head = (announcedOnce and ANNOUNCE_PREFIX_SHORT or ANNOUNCE_PREFIX) .. item
    -- the "already said" flags are only set once the line was really sent (see Commit / PumpQueue)
    local newBossKey

    local bossName, bossKey
    if db.byBoss then
        bossName, bossKey = EncounterName(encounterID)
    end
    if bossName and bossKey ~= lastAnnouncedBoss then
        -- an overlong head (long item link plus a long, e.g. CJK, boss name) would crowd out the winner
        if #head + #bossName + 3 <= MAX_ANNOUNCE_BYTES - 60 then
            head = head .. " (" .. bossName .. ")"
            newBossKey = bossKey
        end
    end
    local function Commit()
        announcedOnce = true
        if newBossKey then
            lastAnnouncedBoss = newBossKey
        end
    end

    if info.allPassed then
        return { head .. " - " .. MARK.pass .. " everyone passed" }, Commit
    end

    local function Flag(r, st)
        if db.flagUnusable and st.kind == "need" and not CanClassUse(r.playerClass, item) then
            return " " .. MARK.cantUse
        end
        return ""
    end
    local function Entry(r, st)
        return AnnounceName(r.playerName) .. (r.roll and (":" .. r.roll) or "") .. Flag(r, st)
    end

    local winner = info.winner
    local others, passers = {}, {}
    if db.rolls then
        for _, r in ipairs(info.rollInfos or {}) do
            local st = STATE_INFO[r.state]
            if st and UsableName(r.playerName) and db[st.kind] and not (r.isWinner and db.wins) then
                if st.kind == "pass" then
                    passers[#passers + 1] = AnnounceName(r.playerName)
                else
                    others[#others + 1] = { r = r, st = st }
                end
            end
        end
        table.sort(others, RollOrder)
    end

    -- Compact layout, rolls grouped by type so the type is written once, not once per player:
    --   {star} Winner:93 (Greed) / {greed} Greed: Second:88, Third:74 / Need OS: Fourth:40 / {pass} Pass: Fifth, Sixth
    -- tokens = pieces with the separator that goes before them, so the end can be cut cleanly.
    local tokens = {}
    local label
    if db.wins and type(winner) == "table" and UsableName(winner.playerName) then
        local wst = STATE_INFO[winner.state]
        if wst then
            label = wst.label
            tokens[#tokens + 1] = { " ", MARK.winner .. " " .. AnnounceName(winner.playerName)
                .. (winner.roll and (":" .. winner.roll) or "") .. " (" .. label .. ")" .. Flag(winner, wst) }
        else
            tokens[#tokens + 1] = { " ", MARK.winner .. " " .. AnnounceName(winner.playerName) .. " WON" }
        end
    end
    for _, o in ipairs(others) do
        if o.st.label ~= label then
            label = o.st.label
            tokens[#tokens + 1] = { #tokens == 0 and " " or " / ", MARK[o.st.kind] .. " " .. label .. ": " .. Entry(o.r, o.st) }
        else
            tokens[#tokens + 1] = { ", ", Entry(o.r, o.st) }
        end
    end
    for i, name in ipairs(passers) do
        if i == 1 then
            tokens[#tokens + 1] = { #tokens == 0 and " " or " / ", MARK.pass .. " Pass: " .. name }
        else
            tokens[#tokens + 1] = { ", ", name }
        end
    end

    local text = head
    for i, tok in ipairs(tokens) do
        local left = #tokens - i + 1
        local tail = (left > 1) and (" +" .. left .. " more") or ""
        if #text + #tok[1] + #tok[2] > MAX_ANNOUNCE_BYTES - #tail then
            if i > 1 then
                text = text .. " +" .. left .. " more"
            end
            break
        end
        text = text .. tok[1] .. tok[2]
    end
    return { text }, Commit
end

-- Lines go out one at a time with a pause between them, from one queue shared by all drops.
local sendQueue, sending = {}, false
local function PumpQueue()
    local entry = table.remove(sendQueue, 1)
    if not entry then
        sending = false
        return
    end
    local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    if not locked then
        entry.send(entry.text, entry.channel)
        if entry.onSent then
            entry.onSent()
        end
    end
    if #sendQueue > 0 and C_Timer and C_Timer.After then
        C_Timer.After(SEND_INTERVAL, PumpQueue)
    elseif #sendQueue > 0 then
        PumpQueue()
    else
        sending = false
    end
end

local function Enqueue(lines, channel, send, onSent)
    for _, text in ipairs(lines) do
        sendQueue[#sendQueue + 1] = { text = text, channel = channel, send = send, onSent = onSent }
    end
    if not sending then
        sending = true
        PumpQueue()
    end
end

-- Announces the block. Returns true if it was queued. Nothing is sent while the game restricts addon chat
-- (e.g. during encounters) or when you are not in a group.
local function Announce(info, encounterID)
    local mode = db.announce
    local winner = info.winner
    if mode ~= "mine" and mode ~= "all" then
        return false
    end
    local item = info.itemHyperlink
    if type(item) ~= "string" or (issecretvalue and issecretvalue(item)) or not ItemIDOf(item) then
        return false
    end
    if not info.allPassed then
        if type(winner) ~= "table" or not UsableName(winner.playerName) then
            return false
        end
        if mode == "mine" and not winner.isSelf then
            return false
        end
    elseif mode == "mine" then
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
    local lines, commit = AnnounceLines(info, encounterID)
    Enqueue(lines, channel, send, commit)
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
        announced = AlreadyAnnounced(info) or Announce(info, encounterID)
    end
    if announced and db.hideWhenAnnounced then
        return
    end
    RenderDrop(info, encounterID)
end

local function CheckDrop(encounterID, lootListKey)
    local seen = printedDrops[encounterID]
    if seen and seen[lootListKey] then
        return
    end
    local info = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey)
    if type(info) ~= "table" or not (info.winner or info.allPassed) then
        return -- the roll is still in progress
    end
    if printedCount > 400 then
        wipe(printedDrops)
        printedCount = 0
        seen = nil
    end
    if not seen then
        seen = {}
        printedDrops[encounterID] = seen
    end
    seen[lootListKey] = true
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

-- The game fires LOOT_HISTORY_UPDATE_DROP for every single roll of every player, and each check builds a sorted
-- copy of the drop. Updates are collected for a moment and each drop is checked once per batch instead.
local COALESCE = 0.25 -- seconds
local pendEnc, pendKey, pendSet, pendTimer = {}, {}, {}, false

local function FlushDrops()
    -- take the batch and reset the queue first, so an error while printing one drop (e.g. from another
    -- addon hooking AddMessage) can neither lose the other drops nor leave the queue in a broken state
    local encs, keys = pendEnc, pendKey
    pendEnc, pendKey, pendSet, pendTimer = {}, {}, {}, false
    for i = 1, #encs do
        local ok, err = pcall(CheckDrop, encs[i], keys[i])
        if not ok and geterrorhandler then
            geterrorhandler()(err)
        end
    end
end

local function OnDropUpdate(encounterID, lootListKey)
    if not HAS_HISTORY or not db or db.format ~= "summary" then
        return
    end
    if encounterID == nil or lootListKey == nil then
        return
    end
    if issecretvalue and (issecretvalue(encounterID) or issecretvalue(lootListKey)) then
        return
    end
    local seen = printedDrops[encounterID]
    if seen and seen[lootListKey] then
        return
    end
    if not (C_Timer and C_Timer.After) then
        return CheckDrop(encounterID, lootListKey)
    end
    local set = pendSet[encounterID]
    if not set then
        set = {}
        pendSet[encounterID] = set
    end
    if not set[lootListKey] then
        set[lootListKey] = true
        local n = #pendEnc + 1
        pendEnc[n], pendKey[n] = encounterID, lootListKey
    end
    if not pendTimer then
        pendTimer = true
        C_Timer.After(COALESCE, FlushDrops)
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
                        local seen = printedDrops[id]
                        if not seen then
                            seen = {}
                            printedDrops[id] = seen
                        end
                        local queued = pendSet[id] and pendSet[id][d.lootListKey]
                        if not seen[d.lootListKey] and not queued then -- queued = still waiting in the batch
                            seen[d.lootListKey] = true
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
    Print("/wwt welcome - show the first-run introduction again")
    Print("Tip: results go to the chat tab you pick in the settings (e.g. your Party tab). That tab does not need Loot messages enabled. For a quiet chat, turn Loot off in all tabs: right-click the tab > Settings > Loot.")
end

-- Prints one made-up roll block to the chosen chat window (used by /wwt test and the welcome).
local function PrintSample()
    local function roll(name, class, state, value, winner)
        return { playerName = name, playerGUID = name, playerClass = class, isSelf = false,
            state = state, roll = value, isWinner = winner or false }
    end
    local win = roll("Brakk-Testrealm", "WARRIOR", ROLL_STATE.NeedMainSpec, 74, true)
    RenderDrop({
        itemHyperlink = "|cffffffff|Hitem:25::::::::::::::|h[Worn Shortsword]|h|r", allPassed = false, winner = win,
        rollInfos = {
            win,
            roll("Seluna-Testrealm", "PRIEST", ROLL_STATE.Greed, 55),
            roll("Monra-Greytusk", "MAGE", ROLL_STATE.NeedOffSpec, 31),
            roll("Rax-Testrealm", "ROGUE", ROLL_STATE.Greed, 12),
            roll("Morv-Testrealm", "HUNTER", ROLL_STATE.Pass),
        },
    })
end

-- First-run welcome: short, shows what the addon does by printing a sample block in the chosen tab.
local function Welcome()
    Print("Ready. Loot rolls will show in chat tab |cffffd100" .. WindowName(db.frame)
        .. "|r. Type |cffffd100/wwt|r to pick another tab (e.g. Party) or change the options. Here is a sample:")
    PrintSample()
    Print("That was only a sample. Other loot messages are hidden in that tab, so a separate tab works best.")
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
            PrintSample()
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
    elseif cmd == "welcome" then
        Welcome()
    else
        Help()
    end
end

local f -- the event frame (created at the bottom)
local GROUP_EVENTS = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }

-- Group chat is only watched while announcements are on: with "off" the addon receives no group chat at all.
local function UpdateGroupEvents()
    if not f then return end
    local on = AnnounceActive()
    for i = 1, #GROUP_EVENTS do
        if on then
            f:RegisterEvent(GROUP_EVENTS[i])
        else
            f:UnregisterEvent(GROUP_EVENTS[i])
        end
    end
    if not on then
        wipe(announcedAt)
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
        "The chat tab that shows the results (e.g. your party/dungeon tab). It does not need Loot messages enabled. For a quiet chat, turn Loot off in every tab (right-click the tab > Settings > Loot); you then see only these blocks. Other tabs are not touched.")

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
        "Posts the roll results to your group in the same structure as your own block. Not sent while the game restricts addon chat. Waits a random moment and does not post an item another player's addon already posted.", {
            { "off", "Off", "Nothing is sent to other players." },
            { "mine", "Only my wins", "When you win an item, the same block you see (item, winner, rolls) goes to party/raid chat, with raid markers for the colors." },
            { "all", "All results", "The block for every item goes to party/raid chat. Follows the Detail setting. Duplicates are only possible if two members announce at the very same moment." },
        }, nil, UpdateGroupEvents)
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

f = CreateFrame("Frame")
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
        f:UnregisterEvent("ADDON_LOADED") -- only ours is needed; stop hearing about every other addon
    elseif event == "PLAYER_LOGIN" then
        f:UnregisterEvent("PLAYER_LOGIN")
        if not db.hintSeen then
            -- a moment after login, so it is not buried under the login chat spam and the chat tabs exist;
            -- marked as seen only once it was really shown (a /reload within those seconds must not skip it)
            if C_Timer and C_Timer.After then
                C_Timer.After(4, function()
                    db.hintSeen = true
                    Welcome()
                end)
            else
                db.hintSeen = true
                Welcome()
            end
        end
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
        UpdateGroupEvents() -- to see announcements made by other players (only when announcing)
        wasInGroup = IsInGroup and IsInGroup() or false
        f:RegisterEvent("GROUP_ROSTER_UPDATE") -- leaving a group resets the announcement state
        if hooksecurefunc and SetItemRef then
            hooksecurefunc("SetItemRef", OnBossLink) -- same way Questie handles its addon links
        end
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" or event == "CHAT_MSG_RAID"
        or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_INSTANCE_CHAT"
        or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
        OnGroupChat(arg1, arg2)
    elseif event == "GROUP_ROSTER_UPDATE" then
        OnGroupRosterUpdate()
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
