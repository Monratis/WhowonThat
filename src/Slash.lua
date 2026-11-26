-- Who Won That: welcome, test and the /wwt command.
local _, ns = ...

local L = ns.L
local HAS_HISTORY, Parse, Print = ns.HAS_HISTORY, ns.Parse, ns.Print
local SummaryCall = ns.SummaryCall

local function Help()
    Print(L("help_settings"))
    Print(L("help_open"))
    Print(L("help_help"))
    Print(L("help_test"))
    Print(L("help_welcome"))
    Print(L("help_summary"))
    Print(L("help_window"))
    Print(L("help_demo"))
    Print(L("help_minvalue"))
end

-- Introduces the roll window once (first run, or the first login after the update that added it).
local function WindowIntro()
    ns.db.windowHintSeen = true
    if ns.db.rollWindow then
        Print(L("welcome_window", "|cffffd100/wwt|r"))
        SummaryCall(ns.RollWindow.Demo)
    end
end

-- First-run welcome: the roll window plays a sample roll.
local Welcome = WindowIntro

-- /wwt test: builds sample messages from the game's REAL strings (LOOT_ROLL_*), checks that the addon recognizes
-- them (needed to hide the game's roll lines and for the fallback without loot history), then opens the sample
-- loot summary and plays a sample roll in the roll window.
local function RunTest()
    Print(string.format("TEST: loot history (C_LootHistory): %s", HAS_HISTORY and "YES" or "NO"))
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

    SummaryCall(ns.Summary.Sample)
    SummaryCall(ns.RollWindow.Demo)
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
    elseif cmd == "window" then
        if ((input or ""):match("^%s*%S+%s+(%S+)") or ""):lower() == "reset" then
            SummaryCall(ns.RollWindow.ResetPos)
        else
            SummaryCall(ns.RollWindow.Toggle)
        end
    elseif cmd == "demo" then
        SummaryCall(ns.RollWindow.Demo)
    elseif cmd == "price" then
        local link = (input or ""):match("(|c[^|]*|Hitem:.-|h%[.-%]|h|r)") or (input or ""):match("(|Hitem:.-|h%[.-%]|h)")
        if not link then
            Print(L("help_price"))
        else
            local report = ns.PriceReport(link)
            if #report == 0 then
                Print(L("min_value_missing"))
            end
            for _, r in ipairs(report) do
                Print(r.name .. ": " .. (r.price and ns.FormatMoney(r.price) or L("price_none")))
            end
        end
    elseif cmd == "minvalue" then
        if not ns.SetMinValue((input or ""):match("^%s*%S+%s+(%S+)")) then
            Print(L("help_minvalue"))
        end
    else
        Help()
    end
end

-- ===== shared with the other files =====
ns.HandleSlash, ns.RunTest, ns.Welcome = HandleSlash, RunTest, Welcome
ns.WindowIntro = WindowIntro
