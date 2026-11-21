-- Who Won That: dungeon book. Knows the last boss of each dungeon, so the end of a run can be recognized by the boss
-- fight ID or, when the game reports ID 0 or none (new WoW Forever dungeons), by the boss name or the combat death
-- message. Fight IDs of the classic dungeons: warcraft.wiki.gg "DungeonEncounterID" (CC BY-SA 4.0); the WoW Forever
-- IDs were read from the game itself.
local _, ns = ...

-- { instance name, last boss name, fight ID, ... }. Names are lowercase letters and spaces only (see Simple); the
-- instance name has no leading "the". "family" marks wings that share one instance name prefix.
local LAST_BOSSES = {
    { "deadmines", "edwin vancleef", 167, 2747 },
    { "wailing caverns", "mutanus the devourer", 592 },
    { "shadowfang keep", "archmage arugal", 471, 2755 },
    { "blackfathom deeps", "akumai", 226, 2767, 2910 },
    { "gnomeregan", "mekgineer thermaplugg", 382 },
    { "razorfen kraul", "charlga razorflank", 443, 2778 },
    { "scarlet monastery", "bloodmage thalnos", 445, family = true },
    { "scarlet monastery", "arcanist doan", 447, family = true },
    { "scarlet monastery", "herod", 448, family = true },
    { "scarlet monastery", "high inquisitor whitemane", 450, family = true },
    { "razorfen downs", "amnennar the coldbringer", 437, 2785 },
    { "uldaman", "archaedas", 554 },
    { "zulfarrak", "chief ukorz sandscalp", 600 },
    { "maraudon", "princess theradras", 429 },
    { "sunken temple", "shade of eranikus", 493, 3584 },
    { "blackrock depths", "emperor dagran thaurissan", 245 },
    { "blackrock spire", "overlord wyrmthalak", 275, family = true },
    { "blackrock spire", "general drakkisath", 280, 3069, family = true },
    { "dire maul", "alzzin the wildshaper", 346, family = true },
    { "dire maul", "prince tortheldrin", 361, family = true },
    { "dire maul", "king gordok", 368, family = true },
    { "scholomance", "darkmaster gandling", 463 },
    { "stratholme", "balnazzar", 478, family = true },
    { "stratholme", "baron rivendare", 484, family = true },
    -- WoW Forever dungeons
    { "alcaz prison", "blazeroar", 3409 },
    { "blackmaw hold", "varrox bleakhoof", 3334 },
    { "city of dalaran", "shade of the archmage", 3303 },
    { "excavation site wetlands", "relic guardian", 3482 },
    { "hall of thanes", "durgen dirgehammer", 3496 },
    { "kroldok stronghold", "overlord mugg", 3451 },
    { "ruins of lordaeron", "rathmael", 3354 },
    { "drowned city", "minloth the serpent", 3479 },
    { "shapers terrace", "nanaya", 3502 },
}

-- Dungeons with no single last boss: over when every boss of the set is down.
-- { instance name, { boss name, fight ID, ... }, ... }
local BOSS_SETS = {
    { "ragefire chasm", { "oggleflint", 430, 2732 }, { "taragaman the hungerer", 431, 2733 },
        { "jergosh the invoker", 432, 2734 }, { "bazzalan", 433, 2735 } },
    { "stockade", { "targorr the dread", 2756 }, { "kam deepfury", 2757 }, { "hamhock", 2758 },
        { "dextren ward", 2759 }, { "bazil thredd", 2760 } },
}

local function Simple(str)
    if type(str) ~= "string" or (issecretvalue and issecretvalue(str)) then
        return nil
    end
    return (str:lower():gsub("[^%a%s]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

-- Boss objects, found by fight ID or name. A boss of a set carries the list of its set.
local LAST_BY_ID, LAST_BY_NAME, SET_BY_ID, SET_BY_NAME = {}, {}, {}, {}
local KNOWN_INSTANCES, KNOWN_FAMILIES = {}, {}

for _, entry in ipairs(LAST_BOSSES) do
    local boss = { name = entry[2] }
    LAST_BY_NAME[boss.name] = boss
    for i = 3, #entry do
        LAST_BY_ID[entry[i]] = boss
    end
    if entry.family then
        KNOWN_FAMILIES[entry[1]] = true
    else
        KNOWN_INSTANCES[entry[1]] = true
    end
end

for _, set in ipairs(BOSS_SETS) do
    KNOWN_INSTANCES[set[1]] = true
    local members = {}
    for i = 2, #set do
        local boss = { name = set[i][1], members = members }
        members[#members + 1] = boss
        SET_BY_NAME[boss.name] = boss
        for j = 2, #set[i] do
            SET_BY_ID[set[i][j]] = boss
        end
    end
end

-- True if the run is in a dungeon this book knows (then a kill that is not its end is simply not the end).
local function KnowsInstance(instanceName)
    local name = Simple(instanceName)
    name = name and name:gsub("^the ", "")
    if not name then
        return false
    end
    if KNOWN_INSTANCES[name] then
        return true
    end
    for family in pairs(KNOWN_FAMILIES) do
        if name:find(family, 1, true) == 1 then
            return true
        end
    end
    return false
end

local function BossOf(encounterID, name)
    name = Simple(name)
    return (encounterID and (LAST_BY_ID[encounterID] or SET_BY_ID[encounterID]))
        or (name and (LAST_BY_NAME[name] or SET_BY_NAME[name]))
end

-- Notes a boss kill in the run and answers: true = this kill finishes the dungeon, false = it does not,
-- nil = the book does not know the dungeon (the caller falls back to its other checks).
local function EndedBy(run, encounterID, name)
    local boss = BossOf(encounterID, name)
    if boss and not boss.members then
        return true
    end
    if boss then
        run.killedBosses = run.killedBosses or {}
        run.killedBosses[boss] = true
        for _, member in ipairs(boss.members) do
            if not run.killedBosses[member] then
                return false
            end
        end
        return true
    end
    if KnowsInstance(run.name) then
        return false
    end
    return nil
end

local function WasKilled(run, boss)
    return run.killedBosses ~= nil and run.killedBosses[boss] == true
end

-- The boss named in a combat death message ("Edwin VanCleef dies.", "You have slain Edwin VanCleef!"), if it is a
-- boss the book tracks. The patterns come from the game's own strings, so it works in any language as long as
-- the boss name the client prints is the English one.
local deathPatterns
local function MessagePattern(format)
    if type(format) ~= "string" then
        return nil
    end
    local escaped = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%d%$s", "%%s")
    return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

local function BossOfDeathMessage(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
        return nil
    end
    deathPatterns = deathPatterns or { MessagePattern(_G.UNITDIESOTHER), MessagePattern(_G.SELFKILLOTHER) }
    for _, pattern in pairs(deathPatterns) do
        local name = text:match(pattern)
        if name then
            return BossOf(nil, name)
        end
    end
    return nil
end

-- ===== shared with the other files =====
ns.DungeonBook = { EndedBy = EndedBy, WasKilled = WasKilled, BossOfDeathMessage = BossOfDeathMessage }
