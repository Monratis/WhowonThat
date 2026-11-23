-- Who Won That: finished rolls: loot history events and the chat fallback.
local _, ns = ...

local ANNOUNCE_DELAY_FALLBACK_MAX, ANNOUNCE_DELAY_FALLBACK_MIN, ANNOUNCE_DELAY_WINNER_MAX, ANNOUNCE_DELAY_WINNER_MIN = ns.ANNOUNCE_DELAY_FALLBACK_MAX, ns.ANNOUNCE_DELAY_FALLBACK_MIN, ns.ANNOUNCE_DELAY_WINNER_MAX, ns.ANNOUNCE_DELAY_WINNER_MIN
local AnnounceActive, DropKey, HAS_HISTORY, MAX_PENDING = ns.AnnounceActive, ns.DropKey, ns.HAS_HISTORY, ns.MAX_PENDING
local Parse, ProcessDrop, ROLL_STATE, STALE_SECONDS = ns.Parse, ns.ProcessDrop, ns.ROLL_STATE, ns.STALE_SECONDS
local SummaryCall, items, pendingDrops, printedDrops = ns.SummaryCall, ns.items, ns.pendingDrops, ns.printedDrops

-- Items that drop so often they would only spam the chat (matched by item ID, or by name as a fallback).
local IGNORED_ITEM_IDS = { [11754] = true, [7909] = true } -- Black Diamond, Aquamarine
local IGNORED_ITEM_NAMES = {
    ["Black Diamond"] = true, ["Aquamarine"] = true, ["Star Ruby"] = true, ["Citrine"] = true,
    ["Jade"] = true, ["Lesser Moonstone"] = true, ["Moss Agate"] = true, ["Shadowgem"] = true,
    ["Malachite"] = true, ["Tigerseye"] = true,
}

local function IsIgnoredItem(link)
    if type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then
        return false
    end
    local id = tonumber(link:match("item:(%d+)"))
    if id and IGNORED_ITEM_IDS[id] then
        return true
    end
    local name = link:match("%[(.-)%]")
    return name ~= nil and IGNORED_ITEM_NAMES[name] == true
end

-- Every finished roll goes through here (loot history and the chat fallback alike).
-- lootListKey is only known for loot history drops; it makes the drop claimable between addons.
local function ScheduleDrop(info, encounterID, lootListKey)
    if IsIgnoredItem(info.itemHyperlink) then
        return
    end
    SummaryCall(ns.Summary.RecordWin, info, encounterID, lootListKey) -- remembered for the dungeon summary window
    if ns.IsCheapItem(info.itemHyperlink) then
        return -- no chat block and no announcement; the summary window still lists it
    end
    local doneAt = GetTime()
    if AnnounceActive() and C_Timer and C_Timer.After then
        local state
        local key = DropKey(encounterID, lootListKey)
        if key and not pendingDrops[key] and ns.pendingCount < MAX_PENDING then
            state = { key = key, info = info, encounterID = encounterID }
            pendingDrops[key] = state
            ns.pendingCount = ns.pendingCount + 1
        end
        -- winner first: our win gets the short delay, everything else the longer fallback delay
        local winner = info.winner
        local lo, hi = ANNOUNCE_DELAY_FALLBACK_MIN, ANNOUNCE_DELAY_FALLBACK_MAX
        if not info.allPassed and type(winner) == "table" and winner.isSelf == true then
            lo, hi = ANNOUNCE_DELAY_WINNER_MIN, ANNOUNCE_DELAY_WINNER_MAX
        end
        C_Timer.After(lo + math.random() * (hi - lo), function()
            ProcessDrop(info, encounterID, doneAt, nil, state)
        end)
    else
        ProcessDrop(info, encounterID, doneAt)
    end
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
    if ns.printedCount > 400 then
        wipe(printedDrops)
        ns.printedCount = 0
        seen = nil
    end
    if not seen then
        seen = {}
        printedDrops[encounterID] = seen
    end
    seen[lootListKey] = true
    ns.printedCount = ns.printedCount + 1
    ScheduleDrop(info, encounterID, lootListKey)
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
    if not HAS_HISTORY or not ns.db or ns.db.format ~= "summary" then
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
                            ns.printedCount = ns.printedCount + 1
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
    ScheduleDrop(info) -- same path as the loot history: announce / hide when announced
end

local function OnLoot(msg)
    if HAS_HISTORY or not ns.db or ns.db.format ~= "summary" then
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

-- ===== shared with the other files =====
ns.MarkExistingDrops, ns.OnDropUpdate, ns.OnLoot, ns.addFilter = MarkExistingDrops, OnDropUpdate, OnLoot, addFilter
