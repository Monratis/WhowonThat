-- Who Won That: dungeon loot summary: runs, roster and recorded wins.
local _, ns = ...

local DropKey, IsSelfSender, ItemIDOf, STATE_INFO = ns.DropKey, ns.IsSelfSender, ns.ItemIDOf, ns.STATE_INFO
local ShortName, UsableName = ns.ShortName, ns.UsableName

local SUMMARY_MAX_DROPS = 200     -- bound for one run's list
local SUMMARY_MAX_PLAYERS = 60    -- bound for one run's roster (a raid plus replacements)
local SUMMARY_LATE_RECORD = 90    -- seconds after leaving the instance in which finished rolls still count

local function PlainNumber(v)
    return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

-- id, name, type of the dungeon / raid you are in, or nil outside of one
local function InstanceRunInfo()
    if not GetInstanceInfo then
        return nil
    end
    local ok, name, instanceType, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
    if not ok or (issecretvalue and issecretvalue(instanceType)) then
        return nil
    end
    if instanceType ~= "party" and instanceType ~= "raid" then
        return nil
    end
    local display = UsableName(name) and name or "Dungeon"
    local id = PlainNumber(instanceID) and instanceID or display
    return id, display, instanceType
end

local function NewRun(id, name, instanceType)
    return { id = id, name = name, instanceType = instanceType, startTime = GetTime(), drops = {}, roster = {},
        rosterCount = 0, seen = {} }
end

-- Adds a player to the run's roster (keyed by the short name) and returns the entry, or nil.
local function AddRosterName(run, full, class)
    if not UsableName(full) or #full > 64 then
        return nil
    end
    local key = ShortName(full)
    local p = run.roster[key]
    if not p then
        -- Loot history may write the realm after a space ("Name Realm") instead of a hyphen; if the first word is
        -- already in the roster, it is the same player.
        local first = key:match("^(%S+)%s")
        p = first and run.roster[first] or nil
    end
    if not p then
        if run.rosterCount >= SUMMARY_MAX_PLAYERS then
            return nil
        end
        run.rosterCount = run.rosterCount + 1
        p = { full = full, short = key, order = run.rosterCount }
        run.roster[key] = p
    elseif full:find("-", 1, true) and not p.full:find("-", 1, true) then
        p.full = full
    end
    if not p.class and UsableName(class) then
        p.class = class
    end
    return p
end

-- Everyone in the group is added to the run (players who leave stay listed, so the board shows the whole run).
local function SnapshotRoster(run)
    if not run or not UnitName then
        return
    end
    local units = { "player" }
    if IsInRaid and IsInRaid() and GetNumGroupMembers then
        local n = math.min(GetNumGroupMembers() or 0, 40)
        for i = 1, n do
            units[#units + 1] = "raid" .. i
        end
    else
        for i = 1, 4 do
            units[#units + 1] = "party" .. i
        end
    end
    for _, unit in ipairs(units) do
        if not UnitExists or UnitExists(unit) then
            local ok, name, realm = pcall(UnitName, unit)
            if ok and UsableName(name) then
                local full = UsableName(realm) and (name .. "-" .. realm) or name
                local okc, _, class = pcall(UnitClass, unit)
                local p = AddRosterName(run, full, okc and class or nil)
                if p and (unit == "player" or (UnitIsUnit and UnitIsUnit(unit, "player"))) then
                    p.isSelf = true
                end
            end
        end
    end
end

local function VisibleCount(run, mineOnly)
    if not mineOnly then
        return #run.drops
    end
    local n = 0
    for _, d in ipairs(run.drops) do
        if d.player.isSelf then
            n = n + 1
        end
    end
    return n
end

local function RefreshSummaryWindow(run)
    if ns.summaryFrame and ns.summaryFrame:IsShown() and ns.summaryShowing == run and ns.RenderSummary then
        ns.RenderSummary()
    end
end

-- A finished drop with a winner: remembered for the run's summary. encounterID / lootListKey (loot history
-- only) keep the same drop from being counted twice.
local function RecordWin(info, encounterID, lootListKey)
    local run = ns.summaryRun
    if not run or type(info) ~= "table" or info.allPassed == true then
        return
    end
    local dropKey = DropKey(encounterID, lootListKey)
    if dropKey and run.seen[dropKey] then
        return
    end
    if run.left and GetTime() - (run.leftAt or 0) > SUMMARY_LATE_RECORD then
        return -- outside of the instance for a while: not loot of this run
    end
    local winner, item = info.winner, info.itemHyperlink
    if type(winner) ~= "table" or not UsableName(winner.playerName) then
        return
    end
    if not UsableName(item) or #item > 512 or not ItemIDOf(item) or #run.drops >= SUMMARY_MAX_DROPS then
        return
    end
    local p = AddRosterName(run, winner.playerName, winner.playerClass)
    if not p then
        return
    end
    if not p.class and UnitClass then
        local ok, _, class = pcall(UnitClass, p.full)
        if not (ok and UsableName(class)) then
            ok, _, class = pcall(UnitClass, p.short)
        end
        if ok and UsableName(class) then
            p.class = class
        end
    end
    if IsSelfSender(winner.playerName) then
        p.isSelf = true
    end
    local st = PlainNumber(winner.state) and STATE_INFO[winner.state] or nil
    run.drops[#run.drops + 1] = { item = item, player = p, kind = st and st.kind, tag = st and st.tag,
        roll = PlainNumber(winner.roll) and winner.roll or nil }
    if dropKey then
        run.seen[dropKey] = true
    end
    run.lastRecordAt = GetTime()
    RefreshSummaryWindow(run)
end

-- ===== shared with the other files =====
ns.AddRosterName, ns.InstanceRunInfo, ns.NewRun, ns.PlainNumber = AddRosterName, InstanceRunInfo, NewRun, PlainNumber
ns.RecordWin, ns.RefreshSummaryWindow, ns.SnapshotRoster, ns.VisibleCount = RecordWin, RefreshSummaryWindow, SnapshotRoster, VisibleCount
