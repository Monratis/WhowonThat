-- Who Won That: dungeon loot summary: end-of-dungeon detection and the Summary table other files use.
local _, ns = ...

local AddRosterName, HAS_HISTORY, InstanceRunInfo, NewRun = ns.AddRosterName, ns.HAS_HISTORY, ns.InstanceRunInfo, ns.NewRun
local PlainNumber, RecordWin, RefreshSummaryWindow, ShowSummarySoon = ns.PlainNumber, ns.RecordWin, ns.RefreshSummaryWindow, ns.ShowSummarySoon
local ShowSummaryWhenSafe, SnapshotRoster, SummaryCommand, UsableName = ns.ShowSummaryWhenSafe, ns.SnapshotRoster, ns.SummaryCommand, ns.UsableName

local SUMMARY_SETTLE = 8          -- seconds after the end of the dungeon before the window opens (final rolls)
local SUMMARY_MAX_WAIT = 75       -- longest wait for open rolls after the end of the dungeon

-- ----- end of the dungeon -----
-- True if the encounter is the last one the Encounter Journal lists for this instance (its final boss).
-- The journal instance is passed to EJ_GetEncounterInfoByIndex directly, so the Encounter Journal's selected
-- instance is left alone (EJ_SelectInstance would change what an open journal shows). Only if that returns
-- nothing and the journal is not open, the instance is selected as a fallback. Results are cached per instance.
local finalEncounterOf = {} -- [journalInstanceID] = dungeonEncounterID of its last journal encounter
local function LastJournalEncounter(journalID)
    local last
    for i = 1, 40 do
        local name, _, _, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(i, journalID)
        if not name then
            break
        end
        last = dungeonEncounterID
    end
    return PlainNumber(last) and last or nil
end

-- Last boss of each known dungeon, by boss fight ID (same on every game language). Checked before the journal,
-- whose last entry is wrong for some dungeons (optional / side bosses). Data cross-checked against Podium's dungeon book.
local FINAL_ENCOUNTERS = {}
for _, id in ipairs({
    167, 2747, 592, 471, 2755, 226, 2767, 2910, 382, 443, 2778, 448, 450, 445, 447, 437, 2785, 554, 600, 429, 493,
    245, 275, 280, 3069, 346, 368, 361, 478, 484,
    3496, 3354, 3303, 3482, 3479, 3451, 3409, 3334, 3502, -- WoW Forever dungeons
}) do
    FINAL_ENCOUNTERS[id] = true
end
-- Dungeons with no single last boss: over when every boss is down (each entry = ids of one boss, any language/build)
local ALL_BOSS_SETS = {
    { { 430, 2732 }, { 431, 2733 }, { 432, 2734 }, { 433, 2735 } }, -- Ragefire Chasm
    { { 2756 }, { 2757 }, { 2758 }, { 2759 }, { 2760 } },           -- The Stockade
}
local FOREVER_FIRST_ID = 3290 -- WoW Forever's own dungeon bosses: only the table above is trusted there

local function KnownFinalEncounter(run, encounterID)
    if FINAL_ENCOUNTERS[encounterID] then
        return true
    end
    run.killedEnc = run.killedEnc or {}
    run.killedEnc[encounterID] = true
    for _, set in ipairs(ALL_BOSS_SETS) do
        local inSet, all = false, true
        for _, ids in ipairs(set) do
            local down = false
            for _, id in ipairs(ids) do
                if id == encounterID then
                    inSet = true
                end
                if run.killedEnc[id] then
                    down = true
                end
            end
            all = all and down
        end
        if inSet then
            return all
        end
    end
    return nil
end

local function IsFinalEncounter(encounterID, run)
    if run then
        local known = KnownFinalEncounter(run, encounterID)
        if known ~= nil then
            return known
        end
    end
    if encounterID >= FOREVER_FIRST_ID then
        return false
    end
    if not (EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex and C_Map and C_Map.GetBestMapForUnit) then
        return false
    end
    local ok, result = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local journalID = PlainNumber(mapID) and EJ_GetInstanceForMap(mapID)
        if not PlainNumber(journalID) or journalID == 0 then
            return false
        end
        local last = finalEncounterOf[journalID]
        if not last then
            last = LastJournalEncounter(journalID)
            local journal = _G.EncounterJournal
            if not last and EJ_SelectInstance and not (journal and journal.IsShown and journal:IsShown()) then
                EJ_SelectInstance(journalID)
                last = LastJournalEncounter(journalID)
            end
            finalEncounterOf[journalID] = last
        end
        return last ~= nil and last == encounterID
    end)
    return ok and result == true
end

-- Rolls that may still finish: an open roll window, a drop just recorded, or a drop of the last boss without
-- a result yet (also "no drops yet": nobody has looted the boss).
local function RollsStillOpen(run)
    if GetActiveLootRollIDs then
        local ok, ids = pcall(GetActiveLootRollIDs)
        if ok and type(ids) == "table" and #ids > 0 then
            return true
        end
    end
    if run.lastRecordAt and GetTime() - run.lastRecordAt < 4 then
        return true
    end
    local enc = run.lastEncounterID
    if enc and HAS_HISTORY and C_LootHistory.GetSortedDropsForEncounter then
        local ok, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, enc)
        if ok and type(drops) == "table" then
            if #drops == 0 then
                return true
            end
            for _, d in ipairs(drops) do
                if type(d) == "table" and not (d.winner or d.allPassed) then
                    return true
                end
            end
        end
    end
    return false
end

-- The dungeon is over (final boss, LFG reward, keystone done): open the window once the last rolls settled.
local function SummaryEnd(run, encounterID)
    if not run or run.ended or run.left then
        return
    end
    run.ended = true
    run.endTime = GetTime()
    if PlainNumber(encounterID) then
        run.lastEncounterID = encounterID
    end
    SnapshotRoster(run)
    if not (C_Timer and C_Timer.After) then
        ShowSummaryWhenSafe(run, true)
        return
    end
    local deadline = GetTime() + SUMMARY_MAX_WAIT
    local function Check()
        if ns.summaryRun ~= run and ns.summaryLast ~= run then
            return -- a newer run replaced it and this one had no items
        end
        local ok, open = pcall(RollsStillOpen, run)
        if ok and open and GetTime() < deadline then
            C_Timer.After(3, Check)
            return
        end
        ShowSummaryWhenSafe(run, true)
    end
    C_Timer.After(SUMMARY_SETTLE, Check)
end

local function SummaryOnEncounterEnd(encounterID, success)
    local run = ns.summaryRun
    if not run or run.left or not PlainNumber(encounterID) or (issecretvalue and issecretvalue(success)) then
        return
    end
    if success ~= 1 and success ~= true then
        return -- wipe
    end
    run.lastEncounterID = encounterID
    if IsFinalEncounter(encounterID, run) then
        SummaryEnd(run, encounterID)
    end
end

-- LFG_COMPLETION_REWARD, CHALLENGE_MODE_COMPLETED, SCENARIO_COMPLETED
local function SummaryOnCompleted(event)
    local run = ns.summaryRun
    if not run or run.left then
        return
    end
    if event == "SCENARIO_COMPLETED" and run.instanceType ~= "party" then
        return
    end
    SummaryEnd(run, run.lastEncounterID)
end

-- Entering / leaving an instance (PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA).
local function SummaryOnZone()
    local id, name, instanceType = InstanceRunInfo()
    local run = ns.summaryRun
    if id then
        -- same instance: back from the graveyard / a repair trip, or a zone change inside it
        if run and run.id == id and not (run.ended and run.left) then
            run.left, run.leftAt = nil, nil
            SnapshotRoster(run)
            return
        end
        if run and #run.drops > 0 then
            ns.summaryLast = run
        end
        ns.summaryRun = NewRun(id, name, instanceType)
        SnapshotRoster(ns.summaryRun)
    elseif run and not run.left then
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
            return -- released to a graveyard outside: the run goes on
        end
        run.left, run.leftAt = true, GetTime()
        -- fallback when no end of the dungeon was seen: the window opens on leaving the instance
        if not run.ended and not run.leaveShown and #run.drops > 0 then
            run.leaveShown = true
            run.endTime = run.endTime or GetTime()
            ShowSummarySoon(run, 2)
        end
    end
end

-- Leaving the group ends the run (a window not shown yet still opens), a new one starts if still inside.
local function SummaryOnGroupLeft()
    local run = ns.summaryRun
    if run and #run.drops > 0 then
        ns.summaryLast = run
        if not run.ended and not run.leaveShown then
            run.leaveShown = true
            run.endTime = run.endTime or GetTime()
            ShowSummarySoon(run, 2)
        end
    end
    ns.summaryRun = nil
    local id, name, instanceType = InstanceRunInfo()
    if id then
        ns.summaryRun = NewRun(id, name, instanceType)
        SnapshotRoster(ns.summaryRun)
    end
end

-- players joining during the run (not while outside of the instance: they were not part of it)
local function SummaryOnRosterUpdate()
    if ns.summaryRun and not ns.summaryRun.left then
        SnapshotRoster(ns.summaryRun)
    end
end

-- /wwt test: opens the window with made-up data (never stored as the "last" run, so /wwt summary stays honest).
local function SummarySample()
    local me = "You"
    if UnitName then
        local ok, n = pcall(UnitName, "player")
        if ok and UsableName(n) then me = n end
    end
    local run = NewRun("sample", "Sample Dungeon", "party")
    run.endTime = run.startTime + 38 * 60 + 12
    local function Player(name, class, isSelf)
        local p = AddRosterName(run, name, class)
        if p and isSelf then p.isSelf = true end
        return p
    end
    local pMe = Player(me, "MAGE", true)
    local pA = Player("Madesky", "WARRIOR")
    local pB = Player("Casandra", "PRIEST")
    local pC = Player("Naysia", "DRUID")
    local pD = Player("Santanico", "PALADIN")
    local function Link(id, color, name)
        return "|cff" .. color .. "|Hitem:" .. id .. "::::::::::::::|h[" .. name .. "]|h|r"
    end
    local function Drop(p, link, kind, roll, tag)
        if p then
            run.drops[#run.drops + 1] = { item = link, player = p, kind = kind, roll = roll, tag = tag }
        end
    end
    Drop(pMe, Link(14551, "a335ee", "Edgemaster's Handguards"), "greed", 94)
    Drop(pMe, Link(11815, "a335ee", "Hand of Justice"), "greed", 71)
    Drop(pMe, Link(13340, "0070dd", "Cape of the Black Baron"), "greed", 66)
    Drop(pB, Link(12640, "a335ee", "Lionheart Helm"), "need", 57) -- plate on a priest: shown in red
    Drop(pB, Link(11815, "0070dd", "Hand of Justice"), "need", 41)
    Drop(pA, Link(14551, "a335ee", "Edgemaster's Handguards"), "need", 88)
    Drop(pC, Link(18832, "0070dd", "Brutality Blade"), "need", 63, "OS")
    Drop(pD, Link(14551, "1eff00", "Edgemaster's Handguards"), "greed", 22)
    ns.ShowSummaryButton(run) -- like a real dungeon end: the button first, the window on click
end

ns.Summary = {
    RecordWin = RecordWin,
    Command = SummaryCommand,
    Sample = SummarySample,
    Refresh = function() RefreshSummaryWindow(ns.summaryShowing) end,
    OnZone = SummaryOnZone,
    OnEncounterEnd = SummaryOnEncounterEnd,
    OnCompleted = SummaryOnCompleted,
    OnGroupLeft = SummaryOnGroupLeft,
    OnRosterUpdate = SummaryOnRosterUpdate,
}

-- Runs a summary handler without letting an error break the rest of the addon.
local function SummaryCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and geterrorhandler then
        geterrorhandler()(err)
    end
end

-- ===== shared with the other files =====
ns.SummaryCall = SummaryCall
