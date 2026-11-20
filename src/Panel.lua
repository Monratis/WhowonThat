-- Who Won That: settings panel in Esc > Options > AddOns.
local _, ns = ...

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
    Header("Chat")

    -- only windows the player really has (see IsUsableWindow)
    local frameSetting = Settings.RegisterAddOnSetting(category, "WWT_FRAME", "frame", ns.db,
        Settings.VarType.Number, "Chat window", DEFAULTS.frame)
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
            container:Add(ns.db.frame, ns.db.frame .. " - " .. (name ~= "-" and name or "window") .. " (not shown)")
        end
        return container:GetData()
    end
    Settings.CreateDropdown(category, frameSetting, WindowOptions,
        "The chat tab that shows the results (e.g. your party/dungeon tab). It does not need Loot messages enabled. For a quiet chat, turn Loot off in every tab (right-click the tab > Settings > Loot); you then see only these blocks. Other tabs are not touched.")

    AddChoice("layout", "Layout",
        "Compact uses smaller indents and shortens long names, for small chat windows.", {
            { "auto", "Automatic", "Compact when the chat window is narrow." },
            { "normal", "Normal", "Full names and wide indents." },
            { "compact", "Compact", "Smaller indents, long names shortened with .." },
        })

    AddChoice("detail", "Detail",
        "How much of each roll is printed.", {
            { "all", "Everyone's rolls", "Winner, every Need/Greed roll, and who passed." },
            { "rolls", "Winner and Need/Greed", "Winner and the Need/Greed rolls, without the passes." },
            { "winner", "Winner only", "Just who won each item." },
        }, nil, ApplyDetail)

    -- ===== Group chat =====
    Header("Group chat")

    local announceInit = AddChoice("announce", "Announce results",
        "Posts the roll results to your group in the same structure as your own block. Not sent while the game restricts addon chat. Waits a random moment and does not post an item another player's addon already posted.", {
            { "off", "Off", "Nothing is sent to other players." },
            { "all", "All results", "The block for every item (item, winner, rolls) goes to party/raid chat, with raid markers for the colors. Follows the Detail setting. Other members using this addon coordinate so each result is posted once." },
        }, nil, UpdateGroupEvents)
    local hideInit = AddBool("hideWhenAnnounced", "Hide my block when announced",
        "If the result was announced in group chat (by you or another player), your own detailed block is not printed again.")
    if hideInit and hideInit.SetParentInitializer and announceInit then
        -- only meaningful while announcements are on
        hideInit:SetParentInitializer(announceInit, function()
            return ns.db.announce ~= "off"
        end)
    end

    -- ===== Dungeon summary =====
    Header("Dungeon summary")

    AddChoice("summary", "Loot summary window",
        "At the end of a dungeon (and when you leave it) a small window lists who won which item during the run. Never opens during combat. /wwt summary opens it again.", {
            { "everyone", "Everyone", "Every player of the run with the items they won." },
            { "mine", "Only my items", "Only the items you won." },
            { "off", "Off", "The window does not open by itself (/wwt summary still works)." },
        }, nil, function()
            SummaryCall(ns.Summary.Refresh)
        end)

    -- ===== Buttons =====
    local panel = _G.SettingsPanel
    if CreateSettingsButtonInitializer and panel and panel.GetLayout then
        local layout = panel:GetLayout(category)
        if layout and layout.AddInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer("Pop-up button position",
                "Move pop-up button", ns.MoveSummaryButton,
                "Shows the loot summary pop-up button so you can drag it where you want. Click it when done.", true))
            layout:AddInitializer(CreateSettingsButtonInitializer("Pop-up button reset",
                "Reset position", ns.ResetSummaryButtonPos,
                "Puts the loot summary pop-up button back at the top of the screen.", true))
            layout:AddInitializer(CreateSettingsButtonInitializer("Sample roll",
                "Print sample roll", RunTest,
                "Prints a sample roll to the chosen chat tab so you can see how it looks.", true))
        end
    end

    Settings.RegisterAddOnCategory(category)
end

-- ===== shared with the other files =====
ns.eventFrame = f
ns.ApplyDetail, ns.RegisterPanel, ns.UpdateGroupEvents = ApplyDetail, RegisterPanel, UpdateGroupEvents
