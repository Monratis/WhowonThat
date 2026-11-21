-- Who Won That: settings panel in Esc > Options > AddOns.
local _, ns = ...

local L = ns.L
local AnnounceActive, DEFAULTS, IsUsableWindow, RunTest = ns.AnnounceActive, ns.DEFAULTS, ns.IsUsableWindow, ns.RunTest
local SummaryCall, WindowName, WipeCoordination = ns.SummaryCall, ns.WindowName, ns.WipeCoordination

local f = CreateFrame("Frame") -- the event frame (its events are registered in Main.lua)
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
        WipeCoordination() -- claims are only kept while announcing
    end
end

-- The panel offers one "detail" choice; it sets the individual switches the display code reads.
local function ApplyDetail()
    local detail = ns.db.detail
    ns.db.wins = true
    ns.db.de = true
    if detail == "winner" then
        ns.db.rolls, ns.db.need, ns.db.greed, ns.db.pass = false, true, true, true
    elseif detail == "rolls" then
        ns.db.rolls, ns.db.need, ns.db.greed, ns.db.pass = true, true, true, false
    else
        ns.db.detail = "all"
        ns.db.rolls, ns.db.need, ns.db.greed, ns.db.pass = true, true, true, true
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
    ns.settingsCategory = category

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
        local setting = Settings.RegisterAddOnSetting(category, "WWT_" .. key:upper(), key, ns.db,
            Settings.VarType.Boolean, label, DEFAULTS[key])
        return Settings.CreateCheckbox(category, setting, tooltip)
    end

    -- Dropdown from a list of { value, label, tooltip }
    local function AddChoice(key, label, tooltip, choices, varType, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "WWT_" .. key:upper(), key, ns.db,
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
    Header(L("hdr_chat"))

    -- only windows the player really has (see IsUsableWindow)
    local frameSetting = Settings.RegisterAddOnSetting(category, "WWT_FRAME", "frame", ns.db,
        Settings.VarType.Number, L("chat_window"), DEFAULTS.frame)
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
        if not IsUsableWindow(ns.db.frame) and type(ns.db.frame) == "number" then
            local name = WindowName(ns.db.frame)
            container:Add(ns.db.frame, ns.db.frame .. " - " .. (name ~= "-" and name or L("window_word")) .. " " .. L("not_shown"))
        end
        return container:GetData()
    end
    Settings.CreateDropdown(category, frameSetting, WindowOptions,
        L("chat_window_tip"))

    AddChoice("layout", L("layout"), L("layout_tip"), {
        { "auto", L("auto"), L("layout_auto_tip") },
        { "normal", L("normal"), L("layout_normal_tip") },
        { "compact", L("compact"), L("layout_compact_tip") },
    })

    AddChoice("detail", L("detail"), L("detail_tip"), {
        { "all", L("detail_all"), L("detail_all_tip") },
        { "rolls", L("detail_rolls"), L("detail_rolls_tip") },
        { "winner", L("detail_winner"), L("detail_winner_tip") },
    }, nil, ApplyDetail)

    -- ===== Group chat =====
    Header(L("hdr_group"))

    local announceInit = AddChoice("announce", L("announce"), L("announce_tip"), {
        { "off", L("off"), L("announce_off_tip") },
        { "all", L("announce_all"), L("announce_all_tip") },
    }, nil, UpdateGroupEvents)
    local hideInit = AddBool("hideWhenAnnounced", L("hide_block"), L("hide_block_tip"))
    if hideInit and hideInit.SetParentInitializer and announceInit then
        -- only meaningful while announcements are on
        hideInit:SetParentInitializer(announceInit, function()
            return ns.db.announce ~= "off"
        end)
    end

    -- ===== Dungeon summary =====
    Header(L("hdr_summary"))

    AddChoice("summary", L("summary"), L("summary_tip"), {
        { "everyone", L("summary_everyone"), L("summary_everyone_tip") },
        { "mine", L("summary_mine"), L("summary_mine_tip") },
        { "off", L("off"), L("summary_off_tip") },
    }, nil, function()
        SummaryCall(ns.Summary.Refresh)
    end)

    AddBool("showValues", L("values_opt"), L("values_opt_tip"))

    -- ===== Language =====
    Header(L("hdr_language"))

    local languages = { { "auto", L("lang_auto"), L("language_tip") } }
    for _, lang in ipairs(ns.LANGUAGES) do
        languages[#languages + 1] = { lang[1], lang[2], "" }
    end
    AddChoice("language", L("language"), L("language_tip"), languages, nil, function()
        ns.Print(L("lang_reload"))
    end)

    -- ===== Buttons =====
    local panel = _G.SettingsPanel
    if CreateSettingsButtonInitializer and panel and panel.GetLayout then
        local layout = panel:GetLayout(category)
        if layout and layout.AddInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer(L("btn_move_name"),
                L("btn_move"), ns.MoveSummaryButton, L("btn_move_tip"), true))
            layout:AddInitializer(CreateSettingsButtonInitializer(L("btn_reset_name"),
                L("btn_reset"), ns.ResetSummaryButtonPos, L("btn_reset_tip"), true))
            layout:AddInitializer(CreateSettingsButtonInitializer(L("btn_sample_name"),
                L("btn_sample"), RunTest, L("btn_sample_tip"), true))
        end
    end

    Settings.RegisterAddOnCategory(category)
end

-- ===== shared with the other files =====
ns.eventFrame = f
ns.ApplyDetail, ns.RegisterPanel, ns.UpdateGroupEvents = ApplyDetail, RegisterPanel, UpdateGroupEvents
