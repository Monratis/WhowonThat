-- Who Won That: event frame, slash command registration and event routing.
local ADDON, ns = ...

local ADDON, ApplyDetail, DEFAULTS, Filter = ns.ADDON, ns.ApplyDetail, ns.DEFAULTS, ns.Filter
local HAS_HISTORY, HandleSlash, InAnyGroup, MarkExistingDrops = ns.HAS_HISTORY, ns.HandleSlash, ns.InAnyGroup, ns.MarkExistingDrops
local OnAddonMessage, OnBossLink, OnDropUpdate, OnGroupChat = ns.OnAddonMessage, ns.OnBossLink, ns.OnDropUpdate, ns.OnGroupChat
local OnGroupRosterUpdate, OnLoot, RegisterComm, RegisterPanel = ns.OnGroupRosterUpdate, ns.OnLoot, ns.RegisterComm, ns.RegisterPanel
local SendVersionSoon, SummaryCall, UpdateGroupEvents, Welcome = ns.SendVersionSoon, ns.SummaryCall, ns.UpdateGroupEvents, ns.Welcome
local addFilter = ns.addFilter

local f = ns.eventFrame
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, arg5)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        WhoWonThatDB = WhoWonThatDB or {}
        ns.db = WhoWonThatDB
        for k, v in pairs(DEFAULTS) do
            if ns.db[k] == nil then
                ns.db[k] = v
            end
        end
        -- leftovers of old test versions: no longer used, so they do not stay in the saved file
        for _, k in ipairs({ "boot", "mainLoaded", "debug", "schema", "transmog", "errors", "strings", "colors" }) do
            ns.db[k] = nil
        end
        -- the "Only my wins" announce mode was removed; saved "mine" becomes "all" (accepted by the author:
        -- such players opted into announcing, and duplicates are prevented by the coordination)
        if ns.db.announce == "mine" then
            ns.db.announce = "all"
        elseif ns.db.announce ~= "all" then
            ns.db.announce = "off"
        end
        if ns.db.summary ~= "off" and ns.db.summary ~= "mine" and ns.db.summary ~= "everyone" then
            ns.db.summary = DEFAULTS.summary
        end
        if ns.db.summaryPos ~= nil and type(ns.db.summaryPos) ~= "table" then
            ns.db.summaryPos = nil
        end
        if ns.db.summaryBtnPos ~= nil and type(ns.db.summaryBtnPos) ~= "table" then
            ns.db.summaryBtnPos = nil
        end
        ApplyDetail()
        -- no switches in the panel for these: always the intended behavior
        ns.db.byBoss, ns.db.classColors, ns.db.header = true, true, true
        ns.db.flagUnusable, ns.db.hideOthers = true, true
        ns.db.format = "summary"
        RegisterPanel()
        RegisterComm() -- addon message prefix "WWT" (skipped quietly if the API is missing)
        f:UnregisterEvent("ADDON_LOADED") -- only ours is needed; stop hearing about every other addon
    elseif event == "PLAYER_LOGIN" then
        f:UnregisterEvent("PLAYER_LOGIN")
        ns.RegisterMovers() -- after every addon has loaded, so the UI addons' mover screens exist
        if ns.commReady then
            ns.StartVersionCheck() -- tells the guild which version we run, so an outdated copy can notice
        end
        if not ns.db.hintSeen then
            -- a moment after login, so it is not buried under the login chat spam and the chat tabs exist;
            -- marked as seen only once it was really shown (a /reload within those seconds must not skip it)
            if C_Timer and C_Timer.After then
                C_Timer.After(4, function()
                    ns.db.hintSeen = true
                    Welcome()
                end)
            else
                ns.db.hintSeen = true
                Welcome()
            end
        end
        if addFilter then
            addFilter("CHAT_MSG_LOOT", Filter)
        end
        if HAS_HISTORY then
            MarkExistingDrops()
            if C_Timer and C_Timer.After then
                C_Timer.After(3, MarkExistingDrops) -- the history is sometimes ready only a moment after login
            end
            f:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
        else
            f:RegisterEvent("CHAT_MSG_LOOT") -- fallback: assemble rolls from chat messages
        end
        UpdateGroupEvents() -- to see announcements made by other players (only when announcing)
        ns.wasInGroup = IsInGroup and IsInGroup() or false
        f:RegisterEvent("GROUP_ROSTER_UPDATE") -- leaving a group resets the announcement state
        if ns.commReady then
            f:RegisterEvent("CHAT_MSG_ADDON")        -- claims and version messages of other members' addons
            f:RegisterEvent("PLAYER_ENTERING_WORLD") -- version message when already grouped (login, /reload)
        end
        if hooksecurefunc and SetItemRef then
            hooksecurefunc("SetItemRef", OnBossLink) -- same way Questie handles its addon links
        end
        -- dungeon summary window: instance runs and the end of a dungeon. Events this client does not know are
        -- skipped (RegisterEvent raises an error for an unknown event).
        for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_END",
            "BOSS_KILL", "LFG_COMPLETION_REWARD", "CHALLENGE_MODE_COMPLETED", "SCENARIO_COMPLETED" }) do
            pcall(f.RegisterEvent, f, ev)
        end
        SummaryCall(ns.Summary.OnZone)
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" or event == "CHAT_MSG_RAID"
        or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_INSTANCE_CHAT"
        or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
        OnGroupChat(arg1, arg2)
    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(arg1, arg2, arg3, arg4) -- prefix, text, channel, sender
    elseif event == "PLAYER_ENTERING_WORLD" then
        if ns.commReady and InAnyGroup() then
            SendVersionSoon()
        end
        SummaryCall(ns.Summary.OnZone)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        SummaryCall(ns.Summary.OnZone)
    elseif event == "ENCOUNTER_END" then
        SummaryCall(ns.Summary.OnEncounterEnd, arg1, arg5) -- encounterID, name, difficultyID, groupSize, success
    elseif event == "BOSS_KILL" then
        -- backup: on some dungeons ENCOUNTER_END never fires (same kill twice is harmless, the run ends once)
        SummaryCall(ns.Summary.OnEncounterEnd, arg1, 1) -- encounterID, name
    elseif event == "LFG_COMPLETION_REWARD" or event == "CHALLENGE_MODE_COMPLETED" or event == "SCENARIO_COMPLETED" then
        SummaryCall(ns.Summary.OnCompleted, event)
    elseif event == "GROUP_ROSTER_UPDATE" then
        local grouped = ns.wasInGroup
        OnGroupRosterUpdate()
        if grouped and not ns.wasInGroup then
            SummaryCall(ns.Summary.OnGroupLeft)
        else
            SummaryCall(ns.Summary.OnRosterUpdate)
        end
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        OnDropUpdate(arg1, arg2)
    elseif event == "CHAT_MSG_LOOT" then
        OnLoot(arg1)
    end
end)

SLASH_WHOWONTHAT1 = "/wwt"
SLASH_WHOWONTHAT2 = "/whowonthat"
SlashCmdList["WHOWONTHAT"] = function(input)
    if ns.db then
        HandleSlash(input)
    end
end
