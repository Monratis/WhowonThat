-- Who Won That: sample roll, welcome, test and the /wwt command.
local _, ns = ...

local L = ns.L
local HAS_HISTORY, Parse, Print, ROLL_STATE = ns.HAS_HISTORY, ns.Parse, ns.Print, ns.ROLL_STATE
local RenderDrop, SummaryCall, TargetFrame = ns.RenderDrop, ns.SummaryCall, ns.TargetFrame

local function WindowName(i)
    local f = _G["ChatFrame" .. i]
    local name = f and f.name
    if (not name or name == "") and GetChatWindowInfo then
        name = GetChatWindowInfo(i)
    end
    return (name and name ~= "") and name or "-"
end

local function Help()
    Print(L("help_settings"))
    Print(L("help_open"))
    Print(L("help_help"))
    Print(L("help_test"))
    Print(L("help_welcome"))
    Print(L("help_summary"))
    Print(L("help_tip"))
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
    Print(L("welcome_ready", "|cffffd100" .. WindowName(ns.db.frame) .. "|r", "|cffffd100/wwt|r"))
    PrintSample()
    Print(L("welcome_sample_note"))
end

-- /wwt test: builds sample messages from the game's REAL strings (LOOT_ROLL_*), checks that
-- the addon recognizes them and (in "summary" mode) renders them through the same code as real rolls.
local function RunTest()
    Print(string.format("TEST: window %d (%s), format: %s, loot history (C_LootHistory): %s",
        ns.db.frame, WindowName(ns.db.frame), ns.db.format, HAS_HISTORY and "YES" or "NO"))

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
    if ns.db.format == "summary" then
        if TargetFrame() then
            PrintSample()
            Print(L("test_see_block", WindowName(ns.db.frame)))
        else
            Print(L("test_no_window", ns.db.frame))
        end
    else
        Print(L("test_raw"))
    end
    -- 3) the loot summary window with sample data (shown whatever the format)
    SummaryCall(ns.Summary.Sample)
    Print(L("test_summary_open"))
    Print(problems == 0 and L("test_ok") or L("test_problems", problems))
end

-- Opens Esc > Options > AddOns > Who Won That. Returns false if the panel is unavailable.
local function OpenPanel()
    if ns.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
        return true
    end
    return false
end

local function HandleSlash(input)
    local cmd = ((input or ""):match("^%s*(%S*)") or ""):lower()
    if cmd == "" then
        -- plain /wwt opens the settings panel
        if not OpenPanel() then
            Print(L("no_panel"))
        end
    elseif cmd == "test" then
        RunTest()
    elseif cmd == "welcome" then
        Welcome()
    elseif cmd == "summary" then
        SummaryCall(ns.Summary.Command)
    else
        Help()
    end
end

-- ===== shared with the other files =====
ns.HandleSlash, ns.RunTest, ns.Welcome, ns.WindowName = HandleSlash, RunTest, Welcome, WindowName
