-- Who Won That: loot history data, the readable roll block printed to the chat window.
local _, ns = ...

local Emit, PlayerLink, TargetFrame, colorCodes = ns.Emit, ns.PlayerLink, ns.TargetFrame, ns.colorCodes

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
ns.printedCount = 0

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
    if ns.db.layout == "compact" then
        return true
    elseif ns.db.layout == "normal" then
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

-- Ninja icon (the game's stealth icon, cropped to its picture) flags ninja loot: a Need roll on an item that is
-- not for the player's class. The path is also used by the loot summary window.
local NINJA_ICON_PATH = "Interface\\Icons\\Ability_Stealth"
local ICON_NINJA = "|T" .. NINJA_ICON_PATH .. ":14:14:0:0:64:64:5:59:5:59|t"

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
-- Weapons only the named classes can use at all (item subclass -> classes); weapons not listed here are
-- never flagged, because who may use axes, maces and swords differs between game versions.
local RANGED_CLASSES = { HUNTER = true, WARRIOR = true, ROGUE = true }
local WAND_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true }
local WEAPON_CLASSES = { [2] = RANGED_CLASSES, [3] = RANGED_CLASSES, [18] = RANGED_CLASSES, [19] = WAND_CLASSES }

-- True when the class clearly cannot equip the item (armor heavier than it can wear, a shield, a bow / gun /
-- crossbow or a wand for a class without them). Anything uncertain (other weapons, jewelry, unknown items or
-- classes) is not reported.
local function CannotWear(classFile, item)
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getInfo then
        return false
    end
    local _, _, _, equipLoc, _, classID, subClassID = getInfo(item)
    if classID == 2 and WEAPON_CLASSES[subClassID] then
        return WEAPON_CLASSES[subClassID][classFile] ~= true
    end
    if classID ~= 4 or type(subClassID) ~= "number" or equipLoc == "INVTYPE_CLOAK" then
        return false
    end
    if subClassID == 6 then -- shield
        return SHIELD_CLASSES[classFile] ~= true
    end
    local cap = ARMOR_CAP[classFile]
    return cap ~= nil and subClassID >= 1 and subClassID <= 4 and subClassID > cap
end

-- Primary stat each class gains from gear. An item whose primary stats are all outside this is not meant for
-- the class, even when it can wear it (an intellect robe for a warrior).
local CLASS_PRIMARY = {
    WARRIOR = { str = true }, DEATHKNIGHT = { str = true }, PALADIN = { str = true, int = true },
    HUNTER = { agi = true }, ROGUE = { agi = true }, DEMONHUNTER = { agi = true },
    SHAMAN = { agi = true, int = true }, DRUID = { agi = true, int = true }, MONK = { agi = true, int = true },
    MAGE = { int = true }, WARLOCK = { int = true }, PRIEST = { int = true }, EVOKER = { int = true },
}
local PRIMARY_STAT_KEYS = { ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi",
    ITEM_MOD_INTELLECT_SHORT = "int" }

-- Primary stats of an item as { str = true, ... } from the game's own item stats; nil when the client cannot
-- tell (item data not loaded yet), which never flags anything.
local function PrimaryStats(item)
    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    if getStats then
        local ok, t = pcall(getStats, item)
        if ok and type(t) == "table" and next(t) ~= nil then
            local found = {}
            for key, amount in pairs(t) do
                local short = PRIMARY_STAT_KEYS[key]
                if short and type(amount) == "number" and amount > 0 then
                    found[short] = true
                end
            end
            return found
        end
    end
    return nil
end

local function WrongPrimaryStat(classFile, item)
    local allowed = CLASS_PRIMARY[classFile]
    local stats = allowed and PrimaryStats(item)
    if not stats or next(stats) == nil then
        return false -- unknown, or no primary stat at all (trinkets, rings): never reported
    end
    for short in pairs(stats) do
        if allowed[short] then
            return false
        end
    end
    return true
end

-- False when this class would not use the item: it cannot wear it, or its primary stat is not the class's.
-- Anything uncertain returns true. A Need roll on such an item is flagged as ninja looting.
local function CanClassUse(classFile, item)
    if type(classFile) ~= "string" or type(item) ~= "string" then
        return true
    end
    return not (CannotWear(classFile, item) or WrongPrimaryStat(classFile, item))
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
    if ns.db.byBoss then
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
        if ns.db.header and (newBoss or (not bossName and now - lastTitleAt > TITLE_PAUSE)) then
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
        if ns.db.wins then
            local compact = IsCompact(frame)
            Emit(frame, BossHeader() .. ItemLine(item), "LOOT")
            Emit(frame, (compact and "  " or "     ") .. "|cffaaaaaaNobody wanted it (everyone passed)|r", "LOOT")
        end
        return
    end

    local winner = info.winner
    local list = {}
    if ns.db.rolls then
        for _, r in ipairs(info.rollInfos or {}) do
            local st = STATE_INFO[r.state]
            -- the winner is printed separately, unless winners are turned off
            if st and UsableName(r.playerName) and ns.db[st.kind] and not (r.isWinner and ns.db.wins) then
                list[#list + 1] = { r = r, st = st }
            end
        end
        table.sort(list, RollOrder)
    end

    local showWinner = ns.db.wins and winner and UsableName(winner.playerName)
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

    -- ninja icon (and "ninja loot" text on a wide window) at the end of a Need roll on an item that is not for the
    -- class; for the winner it is shouted, because that one actually got the item
    local function Flag(r, st, isWinner)
        if ns.db.flagUnusable and st.kind == "need" and not CanClassUse(r.playerClass, item) then
            local word = isWinner and "NINJA LOOT" or "ninja loot"
            return "  " .. ICON_NINJA .. (compact and "" or (" |cffff4040" .. word .. "|r"))
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
            line = line .. "  " .. RollLabel(winner, wst, true, Flag(winner, wst, true))
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

-- ===== shared with the other files =====
ns.CanClassUse, ns.EncounterName, ns.KIND_ICON, ns.LABEL_COLOR = CanClassUse, EncounterName, KIND_ICON, LABEL_COLOR
ns.ICON_NINJA, ns.NINJA_ICON_PATH = ICON_NINJA, NINJA_ICON_PATH
ns.OnBossLink, ns.ROLL_STATE, ns.RenderDrop, ns.RollOrder = OnBossLink, ROLL_STATE, RenderDrop, RollOrder
ns.STATE_INFO, ns.ShortName, ns.UsableName, ns.printedDrops = STATE_INFO, ShortName, UsableName, printedDrops
