-- Who Won That: settings panel in Esc > Options > AddOns.
local _, ns = ...

local L = ns.L
local AnnounceActive, DEFAULTS = ns.AnnounceActive, ns.DEFAULTS
local SummaryCall, WipeCoordination = ns.SummaryCall, ns.WipeCoordination

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
-- Sets the "skip items below" limit (silver, 0 = off) from the popup or /wwt minvalue. Goes through the panel's
-- setting when it exists, so the slider follows.
local MIN_VALUE_MAX = 200
local function SetMinValue(text)
    local n = tonumber(text)
    if not n then
        return false
    end
    n = math.max(0, math.min(MIN_VALUE_MAX, math.floor(n + 0.5)))
    if ns.minValueSetting then
        ns.minValueSetting:SetValue(n)
    elseif ns.db then
        ns.db.minValueSilver = n
    end
    ns.Print(n > 0 and L("min_value_set", ns.FormatMoney(n * 100)) or L("min_value_off"))
    return true
end

local function OpenMinValuePopup()
    if not (StaticPopupDialogs and StaticPopup_Show) then
        return
    end
    local function EditBoxOf(dialog)
        return dialog.editBox or (dialog.GetEditBox and dialog:GetEditBox())
    end
    StaticPopupDialogs["WWT_MIN_VALUE"] = {
        text = L("min_value_prompt", MIN_VALUE_MAX),
        button1 = ACCEPT, button2 = CANCEL,
        hasEditBox = 1, maxLetters = 4, timeout = 0, whileDead = 1, hideOnEscape = 1,
        OnShow = function(self)
            local box = EditBoxOf(self)
            if box then
                box:SetText(tostring(ns.db and ns.db.minValueSilver or 0))
                box:HighlightText()
            end
        end,
        OnAccept = function(self)
            local box = EditBoxOf(self)
            if box then
                SetMinValue(box:GetText())
            end
        end,
        EditBoxOnEnterPressed = function(box)
            SetMinValue(box:GetText())
            box:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(box)
            box:GetParent():Hide()
        end,
    }
    StaticPopup_Show("WWT_MIN_VALUE")
end

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

    local function AddBool(key, label, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "WWT_" .. key:upper(), key, ns.db,
            Settings.VarType.Boolean, label, DEFAULTS[key])
        if onChange then
            setting:SetValueChangedCallback(onChange)
        end
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

    -- ===== Roll window =====
    Header(L("hdr_window"))
    AddBool("rollWindow", L("window_opt"), L("window_opt_tip"), function()
        SummaryCall(ns.RollWindow.SetEnabled, ns.db.rollWindow)
    end)

    -- ===== Group chat =====
    Header(L("hdr_group"))

    local announceInit = AddChoice("announce", L("announce"), L("announce_tip"), {
        { "off", L("off"), L("announce_off_tip") },
        { "all", L("announce_all"), L("announce_all_tip") },
    }, nil, UpdateGroupEvents)
    local detailInit = AddChoice("detail", L("detail"), L("detail_tip"), {
        { "all", L("detail_all"), L("detail_all_tip") },
        { "rolls", L("detail_rolls"), L("detail_rolls_tip") },
        { "winner", L("detail_winner"), L("detail_winner_tip") },
    }, nil, ApplyDetail)
    if detailInit and detailInit.SetParentInitializer and announceInit then
        -- only meaningful while announcements are on
        detailInit:SetParentInitializer(announceInit, function()
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

    -- items below this value (silver) are hidden from chat and not announced; 0 turns it off
    if Settings.CreateSlider and Settings.CreateSliderOptions then
        local minSetting = Settings.RegisterAddOnSetting(category, "WWT_MINVALUESILVER", "minValueSilver", ns.db,
            Settings.VarType.Number, L("min_value"), DEFAULTS.minValueSilver)
        local options = Settings.CreateSliderOptions(0, 200, 5)
        local mixin = _G.MinimalSliderWithSteppersMixin
        if mixin and mixin.Label and options.SetLabelFormatter then
            options:SetLabelFormatter(mixin.Label.Right, function(v)
                return v <= 0 and L("off") or ns.FormatMoney(v * 100)
            end)
        end
        local tip = L("min_value_tip")
        if not ns.HasPriceSource() then
            tip = tip .. "\n\n|cffff5555" .. L("min_value_missing") .. "|r"
        end
        ns.minValueSetting = minSetting
        Settings.CreateSlider(category, minSetting, options, tip)
    end

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
            layout:AddInitializer(CreateSettingsButtonInitializer(L("rw_demo_name"),
                L("rw_demo"), function() SummaryCall(ns.RollWindow.Demo) end, L("rw_demo_tip"), true))
            layout:AddInitializer(CreateSettingsButtonInitializer(L("btn_move_name"),
                L("btn_move"), ns.MoveSummaryButton, L("btn_move_tip"), true))
            layout:AddInitializer(CreateSettingsButtonInitializer(L("btn_reset_name"),
                L("btn_reset"), ns.ResetSummaryButtonPos, L("btn_reset_tip"), true))
            layout:AddInitializer(CreateSettingsButtonInitializer(L("min_value"),
                L("min_value_btn"), OpenMinValuePopup, L("min_value_tip"), true))
        end
    end

    Settings.RegisterAddOnCategory(category)
end

-- ===== shared with the other files =====
ns.eventFrame = f
ns.ApplyDetail, ns.RegisterPanel, ns.SetMinValue, ns.UpdateGroupEvents = ApplyDetail, RegisterPanel, SetMinValue, UpdateGroupEvents
