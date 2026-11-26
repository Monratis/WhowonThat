-- Who Won That: group announcements, addon-to-addon coordination, version notice.
local ADDON, ns = ...

local ADDON, CanClassUse, EncounterName, Print = ns.ADDON, ns.CanClassUse, ns.EncounterName, ns.Print
local RollOrder, STATE_INFO, ShortName = ns.RollOrder, ns.STATE_INFO, ns.ShortName
local UsableName = ns.UsableName

-- ===== Optional group announcement =====
-- The group gets one short line per item (item, winner, everyone else's rolls, who passed), as plain text and
-- respecting the Detail setting. Anyone using this addon with announcements on
-- could send the same block, so:
--  * the winner's own addon announces first, after a short random moment; everyone else's addon waits longer
--    and only steps in if the winner's block did not show up (winner without the addon, or with it turned off),
--  * a drop nobody won (all passed) has no winner, so everyone uses the longer random wait,
--  * if another player's block for the same item already appeared in group chat, we do not send ours,
--  * addons that announce also tell each other through a hidden addon message ("claim", see below) the moment
--    they decide to announce a drop, so the others cancel theirs at once.
-- Everything degrades gracefully: without addon messages (API missing, locked down, nobody else runs the addon)
-- the chat-line detection and the timing fallback below work exactly as before.
local ANNOUNCE_PREFIX = "<Who Won That> "         -- starts the first announcement of a session: [Item]
local ANNOUNCE_PREFIX_SHORT = "<WWT> "            -- every later one is shorter
-- Older versions used other prefixes; still recognised so two players on different versions do not both announce.
local KNOWN_PREFIXES = { ANNOUNCE_PREFIX, ANNOUNCE_PREFIX_SHORT, "Who Won That: ", "WWT: " }
local announcedOnce = false
-- Group chat cannot carry colors or custom icons, but it accepts the raid target markers. Their own colors
-- echo the block in your chat: orange = Need, blue = Greed, grey moon = pass, red X = ninja loot (a Need on an item that is not for that class). Every marker
-- stands BEFORE the names it describes (never trailing a roll), and the winner is named in words ("won by").
local MARK = { need = "{rt2}", greed = "{rt6}", pass = "{rt5}", cantUse = "{rt7}" }
local GROUP_SEP = " // " -- between roll groups; a plain " / " got lost between the icons
-- Random wait after the roll ends before announcing, in seconds. The random part keeps two addons from
-- sending at the same moment.
local ANNOUNCE_DELAY_WINNER_MIN, ANNOUNCE_DELAY_WINNER_MAX = 1, 2     -- we won the item: announce quickly
local ANNOUNCE_DELAY_FALLBACK_MIN, ANNOUNCE_DELAY_FALLBACK_MAX = 4, 7 -- someone else won / all passed: give the
                                                                      -- winner's addon time to go first
local ANNOUNCE_MEMORY = 120 -- seconds an announcement is remembered
local SEND_INTERVAL = 0.5   -- seconds between two lines (keeps clear of the chat flood limit)
local announcedAt = {}      -- [itemID] = { {t = time, s = sender}, ... } one entry per block seen from other players
local MAX_SEEN_PER_ITEM = 20 -- bound for one item's list (a flood of copied lines cannot grow it further)

-- ===== Addon-to-addon coordination (hidden addon messages, prefix "WWT") =====
-- Message formats (plain text, at most a few dozen bytes):
--   "A:<encounterID>:<lootListKey>:<itemID>"  claim: "I am announcing this drop now". Sent only by an addon whose
--                                             announcements are on, the moment it decides to announce, right
--                                             before its public line. The itemID guards against a mismatched key.
--   "V:<version>"                             our addon version (dotted numbers), sent once on joining a group /
--                                             entering the world while grouped (rate limited), and as a reply to
--                                             an older version, so an outdated copy learns of the update once.
--                                             The same message goes once to the guild a few seconds after login.
-- Claims only matter while our own announcements are on; with "off" they are ignored, nothing is sent and the
-- block is shown as before. Every value from other players is untrusted: checked by pattern, length and range,
-- secret values are skipped, and every table is bounded.
local COMM_PREFIX = "WWT"
ns.commReady = false      -- prefix registered and the send API exists
local claims = {}            -- ["enc:key"] = { t = time, itemID = "123", senders = { [shortName] = matchedChatLine } }
local claimCount = 0
local MAX_CLAIMS = 64
local MAX_CLAIM_SENDERS = 8
local pendingDrops = {}      -- ["enc:key"] = state of our own drop still waiting (random delay or grace period)
ns.pendingCount = 0
local MAX_PENDING = 100

local function AnnounceActive()
    return ns.db and ns.db.announce == "all"
end

local function ItemIDOf(link)
    return type(link) == "string" and link:match("item:(%d+)") or nil
end

-- "enc:key" for a loot history drop, or nil if either part is not a plain, short number
local function DropKey(encounterID, lootListKey)
    if encounterID == nil or lootListKey == nil then
        return nil
    end
    if issecretvalue and (issecretvalue(encounterID) or issecretvalue(lootListKey)) then
        return nil
    end
    local a, b = tostring(encounterID), tostring(lootListKey)
    if not (a:match("^%d+$") and b:match("^%d+$")) or #a > 10 or #b > 10 then
        return nil
    end
    return tostring(tonumber(a)) .. ":" .. tostring(tonumber(b))
end

-- The group channel announcements and addon messages go to, or nil when not in a group.
local function GroupChannel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    elseif IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function ChatLocked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() and true or false
end

local function RegisterComm()
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage) then
        return
    end
    local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM_PREFIX)
    if ok and C_ChatInfo.IsAddonMessagePrefixRegistered then
        local ok2, registered = pcall(C_ChatInfo.IsAddonMessagePrefixRegistered, COMM_PREFIX)
        ok = ok2 and registered and true or false
    end
    ns.commReady = ok and true or false
end

-- Sends one addon message to the group. Never raises an error; false if it could not be sent.
local function SendComm(text, channel)
    if not ns.commReady or not channel or ChatLocked() then
        return false
    end
    local ok = pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, text, channel)
    return ok
end

-- True if the sender is this character (own addon messages and chat lines come back to us).
local function IsSelfSender(sender)
    local me = UnitName("player")
    if type(me) ~= "string" or ShortName(sender) ~= me then
        return false
    end
    local realm = sender:match("^[^%-]+%-(.+)$")
    local mine = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and type(mine) == "string" and mine ~= "" then
        return (realm:gsub("[%s%-]", "")) == (mine:gsub("[%s%-]", ""))
    end
    return true
end

local function PruneClaims()
    local now = GetTime()
    for key, c in pairs(claims) do
        if now - c.t > ANNOUNCE_MEMORY then
            claims[key] = nil
            claimCount = claimCount - 1
        end
    end
end

local function WipeCoordination()
    wipe(announcedAt)
    wipe(claims)
    claimCount = 0
end

-- ----- Version notice -----
local function ParseVersion(v)
    if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) or #v > 20 or not v:match("^%d+[%.%d]*$") then
        return nil
    end
    local t = {}
    for n in v:gmatch("%d+") do
        if #t >= 4 or #n > 4 then
            return nil
        end
        t[#t + 1] = tonumber(n)
    end
    return #t > 0 and t or nil
end

local function CompareVersions(a, b) -- -1 if a < b, 0 if equal, 1 if a > b
    for i = 1, 4 do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then
            return x < y and -1 or 1
        end
    end
    return 0
end

local myVersion -- parsed own version, nil if the TOC value is not plain dotted numbers
do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if getMeta then
        local ok, v = pcall(getMeta, ADDON, "Version")
        if ok then
            myVersion = ParseVersion(v)
        end
    end
end
local VERSION_INTERVAL = 60 -- seconds between two version messages of ours
local lastVersionSent = -VERSION_INTERVAL
local newerNoticed = false  -- the "newer version" line is printed once per session

local function SendVersion()
    if not myVersion then
        return
    end
    local now = GetTime()
    if now - lastVersionSent < VERSION_INTERVAL then
        return
    end
    if SendComm("V:" .. table.concat(myVersion, "."), GroupChannel()) then
        lastVersionSent = now
    end
end

local function SendVersionSoon()
    if C_Timer and C_Timer.After then
        C_Timer.After(5, SendVersion) -- the group channel is not always usable the moment the group forms
    else
        SendVersion()
    end
end

-- Guild members hear our version once per session, a few seconds after login (long enough for the guild
-- channel to work; tried a second time if it did not). Someone who logs in later sends theirs, and an older copy
-- that hears ours gets one reply, so nobody has to be online at the same moment as the update's author.
local guildPingSent, guildReplySent = false, false

local function SendGuildVersion()
    if not myVersion or guildPingSent or not (IsInGuild and IsInGuild()) then
        return false
    end
    guildPingSent = SendComm("V:" .. table.concat(myVersion, "."), "GUILD")
    return guildPingSent
end

local function StartVersionCheck()
    if not (C_Timer and C_Timer.After) then
        return
    end
    C_Timer.After(12, function()
        if not SendGuildVersion() then
            C_Timer.After(20, SendGuildVersion)
        end
    end)
end

local function OnVersion(v, channel)
    local theirs = ParseVersion(v)
    if not theirs or not myVersion then
        return
    end
    local cmp = CompareVersions(myVersion, theirs)
    if cmp < 0 then
        if not newerNoticed then
            newerNoticed = true
            Print(ns.L("newer_version", table.concat(theirs, "."), table.concat(myVersion, ".")))
        end
    elseif cmp > 0 then
        if channel == "GUILD" then
            if guildPingSent and not guildReplySent then
                guildReplySent = SendComm("V:" .. table.concat(myVersion, "."), "GUILD") -- once
            end
        else
            SendVersion() -- let the older copy know (rate limited)
        end
    end
end

-- A new group starts from scratch: the full name and the boss line are written again, and what was seen in the
-- old group's chat no longer matters. Called when you leave a group (the next one is always a new party).
ns.wasInGroup = false
local function OnGroupRosterUpdate()
    local inGroup = IsInGroup and IsInGroup() or false
    if ns.wasInGroup and not inGroup then
        announcedOnce = false
        ns.lastAnnouncedBoss = nil
        WipeCoordination()
    elseif inGroup and not ns.wasInGroup then
        SendVersionSoon()
    end
    ns.wasInGroup = inGroup
end

local function PruneAnnouncements()
    local now = GetTime()
    for id, list in pairs(announcedAt) do
        for i = #list, 1, -1 do
            if now - list[i].t > ANNOUNCE_MEMORY then
                table.remove(list, i)
            end
        end
        if #list == 0 then
            announcedAt[id] = nil
        end
    end
end

-- Removes one seen announcement line of this item from this sender. True if there was one.
local function RemoveSeenLine(itemID, sender)
    local list = announcedAt[itemID]
    if not list then
        return false
    end
    for i = 1, #list do
        if list[i].s == sender then
            table.remove(list, i)
            if #list == 0 then
                announcedAt[itemID] = nil
            end
            return true
        end
    end
    return false
end

-- Group chat line from another player: the first line of a block names the item, so remember it.
-- Our own lines are ignored (they would otherwise count as someone else's block).
local function OnGroupChat(msg, sender)
    if type(msg) ~= "string" or (issecretvalue and (issecretvalue(msg) or issecretvalue(sender))) then
        return
    end
    local known = false
    for _, p in ipairs(KNOWN_PREFIXES) do
        if msg:sub(1, #p) == p then
            known = true
            break
        end
    end
    if not known then
        return
    end
    local itemID = ItemIDOf(msg)
    if not itemID then
        return
    end
    local who = UsableName(sender) and #sender <= 64 and ShortName(sender) or nil
    if who and IsSelfSender(sender) then
        return
    end
    PruneAnnouncements()
    -- the public line of a drop whose claim already arrived: the claim stands for it, so it is not counted again
    -- (otherwise it would later be taken for a second copy of the same item)
    if who then
        PruneClaims()
        for _, c in pairs(claims) do
            if c.itemID == itemID and c.senders[who] == false then
                c.senders[who] = true
                return
            end
        end
    end
    local list = announcedAt[itemID]
    if not list then
        list = {}
        announcedAt[itemID] = list
    end
    if #list < MAX_SEEN_PER_ITEM then
        list[#list + 1] = { t = GetTime(), s = who }
    end
end

-- True if another player's addon claimed this drop (and the claim names the same item).
local function Claimed(key, info)
    if not key then
        return false
    end
    local c = claims[key]
    if not c or GetTime() - c.t > ANNOUNCE_MEMORY then
        return false
    end
    return c.itemID == ItemIDOf(info.itemHyperlink)
end

-- Our drop is no longer waiting (processed or cancelled).
local function FinishPending(state)
    if state and not state.done then
        state.done = true
        if pendingDrops[state.key] == state then
            pendingDrops[state.key] = nil
            ns.pendingCount = ns.pendingCount - 1
        end
    end
end

-- Another player's addon is announcing a drop. Only used while our announcements are on.
local function OnClaim(who, key, itemID)
    PruneClaims()
    local c = claims[key]
    if not c then
        if claimCount >= MAX_CLAIMS then
            return -- bounded; the chat-line check and the timing fallback still cover this drop
        end
        c = { t = GetTime(), itemID = itemID, senders = {}, n = 0 }
        claims[key] = c
        claimCount = claimCount + 1
    elseif c.itemID ~= itemID then
        return -- conflicting claim for the same key: keep the first
    end
    if c.senders[who] == nil and c.n < MAX_CLAIM_SENDERS then
        -- if that player's public line arrived before the claim, the claim replaces it (see OnGroupChat)
        c.senders[who] = RemoveSeenLine(itemID, who)
        c.n = c.n + 1
    end
    -- our own copy of this drop is still waiting: settle it now instead of after the delay / grace period
    local st = pendingDrops[key]
    if st and not st.done and ItemIDOf(st.info.itemHyperlink) == itemID then
        FinishPending(st)
    end
end

local function OnAddonMessage(prefix, text, channel, sender)
    if issecretvalue and (issecretvalue(prefix) or issecretvalue(text) or issecretvalue(channel) or issecretvalue(sender)) then
        return
    end
    if prefix ~= COMM_PREFIX or type(text) ~= "string" or #text > 64 then
        return
    end
    local fromGuild = channel == "GUILD"
    if not fromGuild and channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then
        return
    end
    if not UsableName(sender) or #sender > 64 or IsSelfSender(sender) then
        return
    end
    local kind = text:sub(1, 2)
    if kind == "A:" then
        if fromGuild or not AnnounceActive() then
            return -- announcements off: claims do not matter, behavior stays as without the addon messages
        end
        local enc, lk, item = text:match("^A:(%d+):(%d+):(%d+)$")
        if not enc or #enc > 10 or #lk > 10 or #item > 10 then
            return
        end
        OnClaim(ShortName(sender), tostring(tonumber(enc)) .. ":" .. tostring(tonumber(lk)), tostring(tonumber(item)))
    elseif kind == "V:" then
        OnVersion(text:sub(3), channel)
    end
end

-- True if another player already announced a block for this item. Each seen block covers one drop, so
-- two copies of the same item in one kill are handled correctly.
local function AlreadyAnnounced(info)
    local itemID = ItemIDOf(info.itemHyperlink)
    PruneAnnouncements()
    local list = itemID and announcedAt[itemID]
    if list and #list > 0 then
        table.remove(list, 1)
        return true
    end
    return false
end

-- The announcement is ONE chat message (group chat takes a single line of up to 255 bytes): item, winner,
-- the other rolls by rank, who passed. When there are too many rolls to fit, the rest is cut as "+N more".
local MAX_ANNOUNCE_BYTES = 250
local function AnnounceName(full)
    local short = ShortName(full)
    return short:match("^(%S+)") or short
end
local function AnnounceLines(info, encounterID)
    local item = info.itemHyperlink
    local head = (announcedOnce and ANNOUNCE_PREFIX_SHORT or ANNOUNCE_PREFIX) .. item
    -- the "already said" flags are only set once the line was really sent (see Commit / PumpQueue)
    local newBossKey

    local bossName, bossKey
    if ns.db.byBoss then
        bossName, bossKey = EncounterName(encounterID)
    end
    if bossName and bossKey ~= ns.lastAnnouncedBoss then
        -- an overlong head (long item link plus a long, e.g. CJK, boss name) would crowd out the winner
        if #head + #bossName + 3 <= MAX_ANNOUNCE_BYTES - 60 then
            head = head .. " (" .. bossName .. ")"
            newBossKey = bossKey
        end
    end
    local function Commit()
        announcedOnce = true
        if newBossKey then
            ns.lastAnnouncedBoss = newBossKey
        end
    end

    if info.allPassed then
        return { head .. " - " .. MARK.pass .. " everyone passed" }, Commit
    end

    -- A red X after a Need roll on an item that is not for the class. The winner gets the words too: the X alone
    -- tells nobody in group chat what it means, and the winner is the one who got the item.
    local function Flag(r, st, isWinner)
        if ns.db.flagUnusable and st.kind == "need" and not CanClassUse(r.playerClass, item) then
            return " " .. MARK.cantUse .. (isWinner and " ninja loot" or "")
        end
        return ""
    end
    local function Entry(r, st, isWinner)
        return AnnounceName(r.playerName) .. (r.roll and (":" .. r.roll) or "") .. Flag(r, st, isWinner)
    end

    local winner = info.winner
    local others, passers = {}, {}
    if ns.db.rolls then
        for _, r in ipairs(info.rollInfos or {}) do
            local st = STATE_INFO[r.state]
            if st and UsableName(r.playerName) and ns.db[st.kind] and not (r.isWinner and ns.db.wins) then
                if st.kind == "pass" then
                    passers[#passers + 1] = AnnounceName(r.playerName)
                else
                    others[#others + 1] = { r = r, st = st }
                end
            end
        end
        table.sort(others, RollOrder)
    end

    -- Compact layout, rolls grouped by type so the type marker is written once, BEFORE its names:
    --   <WWT> [Item] (Boss) - won by {need} Winner:94 {cantUse} ninja loot // {greed} Second, Third // {pass} Fifth, Sixth
    --   <WWT> [Item] - won by {greed} Winner:93 // {greed} Second:88, Third:74 // {need} OS Fourth:40
    -- (greed rolls that lost to a Need have no number, so they are names only)
    -- tokens = pieces with the separator that goes before them, so the end can be cut cleanly.
    local tokens = {}
    local label
    local function GroupStart(st)
        return MARK[st.kind] .. (st.tag and (" " .. st.tag) or "") .. " "
    end
    if ns.db.wins and type(winner) == "table" and UsableName(winner.playerName) then
        local wst = STATE_INFO[winner.state]
        if wst then
            tokens[#tokens + 1] = { " - ", "won by " .. GroupStart(wst) .. Entry(winner, wst, true) }
        else
            tokens[#tokens + 1] = { " - ", "won by " .. AnnounceName(winner.playerName) }
        end
    end
    -- the winner's own group is closed after the winner, so the losers always start a fresh, marked group
    for _, o in ipairs(others) do
        if o.st.label ~= label then
            label = o.st.label
            tokens[#tokens + 1] = { #tokens == 0 and " - " or GROUP_SEP, GroupStart(o.st) .. Entry(o.r, o.st) }
        else
            tokens[#tokens + 1] = { ", ", Entry(o.r, o.st) }
        end
    end
    for i, name in ipairs(passers) do
        if i == 1 then
            tokens[#tokens + 1] = { #tokens == 0 and " - " or GROUP_SEP, MARK.pass .. " " .. name }
        else
            tokens[#tokens + 1] = { ", ", name }
        end
    end

    local text = head
    for i, tok in ipairs(tokens) do
        local left = #tokens - i + 1
        local tail = (left > 1) and (" +" .. left .. " more") or ""
        if #text + #tok[1] + #tok[2] > MAX_ANNOUNCE_BYTES - #tail then
            if i > 1 then
                text = text .. " +" .. left .. " more"
            end
            break
        end
        text = text .. tok[1] .. tok[2]
    end
    return { text }, Commit
end

-- Lines go out one at a time with a pause between them, from one queue shared by all drops.
local sendQueue, sending = {}, false
local function PumpQueue()
    local entry = table.remove(sendQueue, 1)
    if not entry then
        sending = false
        return
    end
    local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    if not locked then
        entry.send(entry.text, entry.channel)
        if entry.onSent then
            entry.onSent()
        end
    end
    if #sendQueue > 0 and C_Timer and C_Timer.After then
        C_Timer.After(SEND_INTERVAL, PumpQueue)
    elseif #sendQueue > 0 then
        PumpQueue()
    else
        sending = false
    end
end

local function Enqueue(lines, channel, send, onSent)
    for _, text in ipairs(lines) do
        sendQueue[#sendQueue + 1] = { text = text, channel = channel, send = send, onSent = onSent }
    end
    if not sending then
        sending = true
        PumpQueue()
    end
end

-- Announces the block. Returns true if it was queued. Nothing is sent while the game restricts addon chat
-- (e.g. during encounters) or when you are not in a group.
-- key = the drop's "enc:key" (loot history only): when given, the claim goes to the other addons right before the
-- public line is queued, so their own pending announcement of this drop is cancelled at once.
local function Announce(info, encounterID, key)
    local winner = info.winner
    if not AnnounceActive() then
        return false
    end
    local item = info.itemHyperlink
    if type(item) ~= "string" or (issecretvalue and issecretvalue(item)) or not ItemIDOf(item) then
        return false
    end
    if not info.allPassed and (type(winner) ~= "table" or not UsableName(winner.playerName)) then
        return false
    end
    if ChatLocked() then
        return false
    end
    local channel = GroupChannel()
    if not channel then
        return false
    end
    local send = SendChatMessage or (C_ChatInfo and C_ChatInfo.SendChatMessage) -- the same call Questie uses in Forever
    if not send then
        return false
    end
    if key then
        SendComm("A:" .. key .. ":" .. ItemIDOf(item), channel) -- best effort; failure changes nothing else
    end
    local lines, commit = AnnounceLines(info, encounterID)
    Enqueue(lines, channel, send, commit)
    return true
end

-- With a price addon, items worth less than the user's limit (silver, 0 = off) are left out of the roll window and
-- get no group line.
-- No price addon or no price = not cheap (we never hide what we cannot value).
local function IsCheapItem(link)
    local limit = ns.db and tonumber(ns.db.minValueSilver) or 0
    if limit <= 0 then
        return false
    end
    local price = ns.ItemPrice and ns.ItemPrice(link)
    return price ~= nil and price < limit * 100
end

local function InAnyGroup()
    if not IsInGroup then
        return false
    end
    return IsInGroup() or (LE_PARTY_CATEGORY_INSTANCE ~= nil and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) or false
end

-- A finished roll: announced to the group when announcing is on and no other member's addon claimed or posted it
-- yet. The claim is checked first, so it does not use up a seen chat line meant for another copy of the item.
-- state = our pending entry for a loot history drop (nil for the chat fallback, which has no drop key).
local function ProcessDrop(info, encounterID, state)
    if not ns.db or (state and state.done) then
        return -- settled already (a claim arrived while we waited)
    end
    local key = state and state.key
    if AnnounceActive() and not (Claimed(key, info) or AlreadyAnnounced(info)) then
        Announce(info, encounterID, key)
    end
    FinishPending(state)
end

-- ===== shared with the other files =====
ns.ANNOUNCE_DELAY_FALLBACK_MAX, ns.ANNOUNCE_DELAY_FALLBACK_MIN, ns.ANNOUNCE_DELAY_WINNER_MAX, ns.ANNOUNCE_DELAY_WINNER_MIN = ANNOUNCE_DELAY_FALLBACK_MAX, ANNOUNCE_DELAY_FALLBACK_MIN, ANNOUNCE_DELAY_WINNER_MAX, ANNOUNCE_DELAY_WINNER_MIN
ns.AnnounceActive, ns.DropKey, ns.InAnyGroup, ns.IsSelfSender, ns.IsCheapItem = AnnounceActive, DropKey, InAnyGroup, IsSelfSender, IsCheapItem
ns.ItemIDOf, ns.MAX_PENDING, ns.OnAddonMessage, ns.OnGroupChat = ItemIDOf, MAX_PENDING, OnAddonMessage, OnGroupChat
ns.OnGroupRosterUpdate, ns.ProcessDrop, ns.RegisterComm, ns.SendVersionSoon = OnGroupRosterUpdate, ProcessDrop, RegisterComm, SendVersionSoon
ns.StartVersionCheck = StartVersionCheck
ns.WipeCoordination, ns.pendingDrops = WipeCoordination, pendingDrops
