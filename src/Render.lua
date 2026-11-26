-- Who Won That: loot history data shared by the roll window, the summary and the announcements
-- (roll states, class checks for ninja loot, boss names).
local _, ns = ...

-- ===== Main data source: Blizzard loot history (LOOT_HISTORY_UPDATE_DROP event) =====
local ROLL_STATE = (Enum and Enum.EncounterLootDropRollState)
    or { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
local STATE_INFO = {
    [ROLL_STATE.NeedMainSpec] = { kind = "need", label = "roll_need", rank = 1 },
    [ROLL_STATE.NeedOffSpec] = { kind = "need", label = "roll_need_os", tag = "OS", rank = 2 },
    [ROLL_STATE.Greed] = { kind = "greed", label = "roll_greed", rank = 3 },
    [ROLL_STATE.Pass] = { kind = "pass", label = "roll_pass", rank = 4 },
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
local KIND_ICON = {
    need = "|TInterface\\Buttons\\UI-GroupLoot-Dice-Up:14:14:0:0|t",
    greed = "|TInterface\\Buttons\\UI-GroupLoot-Coin-Up:14:14:0:0|t",
    pass = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14:0:0|t",
}

-- Roll type colors: Need warm orange, Greed light blue, Pass grey
local LABEL_COLOR = { need = "ff9d4d", greed = "6fb7ff", pass = "9d9d9d" }

-- Ninja icon (the game's stealth icon, cropped to its picture) flags ninja loot: a Need roll on an item that is
-- not for the player's class. The path is also used by the loot summary window.
local NINJA_ICON_PATH = "Interface\\Icons\\Ability_Stealth"
local ICON_NINJA = "|T" .. NINJA_ICON_PATH .. ":14:14:0:0:64:64:5:59:5:59|t"

-- Name of the encounter (boss) a drop belongs to, from the game's loot history. Nil if unknown.
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

-- Item stats the GearQuest Forever addon keeps for many items ({ str = 10, ... } by item ID), read only when that
-- addon is installed. Its data addon loads on demand, so it is asked to load once.
local function GearQuestStats(item)
    local itemID = tonumber(item:match("item:(%d+)"))
    local gearQuest = _G.GearQuest
    if not (itemID and type(gearQuest) == "table") then
        return nil
    end
    if not (type(gearQuest.Data) == "table" and gearQuest.Data.itemStats) then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then
            pcall(load, "GearQuestForever_ItemStats")
        end
    end
    local stats = type(gearQuest.Data) == "table" and type(gearQuest.Data.itemStats) == "table"
        and gearQuest.Data.itemStats[itemID]
    return type(stats) == "table" and stats or nil
end

-- Primary stats of an item as { str = true, ... } from the game's own item stats, or from GearQuest's data when
-- the client has none yet; nil when neither can tell, which never flags anything.
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
    local known = GearQuestStats(item)
    if known then
        local found = {}
        for _, short in pairs(PRIMARY_STAT_KEYS) do
            if type(known[short]) == "number" and known[short] > 0 then
                found[short] = true
            end
        end
        return found
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

-- ===== shared with the other files =====
ns.CanClassUse, ns.EncounterName, ns.KIND_ICON, ns.LABEL_COLOR = CanClassUse, EncounterName, KIND_ICON, LABEL_COLOR
ns.ICON_NINJA, ns.NINJA_ICON_PATH, ns.ROLL_STATE, ns.RollOrder = ICON_NINJA, NINJA_ICON_PATH, ROLL_STATE, RollOrder
ns.STATE_INFO, ns.ShortName, ns.UsableName, ns.printedDrops = STATE_INFO, ShortName, UsableName, printedDrops
