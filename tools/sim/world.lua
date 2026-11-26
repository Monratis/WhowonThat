-- A small world around the WoW clients: a group of players who all run the addon, group chat and addon messages
-- delivered between them, shared loot drops, instances, and a plain-text "screenshot" of what a player sees.
local Wow = require("wow")

local World = {}
World.__index = World

local STATE = { need = 0, needos = 1, greed = 3, noroll = 4, pass = 5 }
World.STATE = STATE

-- ===== plain text of what the player reads =====
local function plain(s)
    s = tostring(s)
    s = s:gsub("|T[^|]*|t", "")               -- inline icons
    s = s:gsub("|H[^|]*|h(%[.-%])|h", "%1")   -- links keep their visible text
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return s
end
World.plain = plain

-- Icons carry information in this addon (crown, dice, coin), so a variant keeps them as {tags}.
local function tagged(s)
    s = tostring(s)
    s = s:gsub("|T([^|:]*)[^|]*|t", function(path)
        local n = path:match("([^\\]+)$") or path
        return "{" .. n .. "}"
    end)
    return plain(s)
end
World.tagged = tagged

function World.new(opts)
    opts = opts or {}
    local w = setmetatable({ clients = {}, byName = {}, root = opts.root or ".", latency = opts.latency or 0.05,
        step = opts.step or 0.1, nextKey = 1, groupKind = nil, guild = {} }, World)
    return w
end

-- ===== clients =====
-- spec: name, class, realm, savedVariables, noLootHistory, globals, ...
function World:addClient(spec)
    spec.root = self.root
    -- the one-time welcome sample would mix into every transcript; scenarios opt in with hintSeen = false
    spec.savedVariables = spec.savedVariables or {}
    if spec.savedVariables.hintSeen == nil then spec.savedVariables.hintSeen = true end
    if spec.savedVariables.windowHintSeen == nil then spec.savedVariables.windowHintSeen = true end
    spec.savedVariables.frame = spec.savedVariables.frame or 3
    local c = Wow.new(spec)
    c.world = self
    c.onSendChat = function(from, msg) self:deliverChat(from, msg) end
    c.onSendAddon = function(from, msg) self:deliverAddon(from, msg) end
    c.load(self.root)
    if spec.login ~= false then c.login() end
    self.clients[#self.clients + 1] = c
    self.byName[c.name] = c
    return c
end

local function fullName(c) return c.name .. "-" .. c.realm:gsub("%s", "") end

-- Puts the given clients into one group (they see each other as party1..4 / raid1..n).
-- kind: "party" (default), "raid" or "instance" (an instance group: LFG / looking-for-dungeon).
function World:formGroup(list, kind)
    kind = kind or "party"
    for _, c in ipairs(list) do
        local members = {}
        for _, o in ipairs(list) do
            if o ~= c then members[#members + 1] = { name = o.name, realm = o.realm, class = o.class } end
        end
        c.group = { members = members, raid = kind == "raid", instance = kind == "instance", list = list }
    end
    for _, c in ipairs(list) do c.fire("GROUP_ROSTER_UPDATE") end
    self:advance(0)
end

function World:leaveGroup(c)
    c.group = nil
    c.fire("GROUP_ROSTER_UPDATE")
    self:advance(0)
end

function World:addToGuild(list)
    for _, c in ipairs(list) do c.guild = true; self.guild[#self.guild + 1] = c end
end

-- Moves every given client into an instance (or out of it when `inst` is nil).
-- inst = { name=, id=, type="party", mapID=, journalID=, encounters={{id=,name=},...} }
function World:enterInstance(list, inst)
    for _, c in ipairs(list) do
        c.instance = inst
        c.fire("PLAYER_ENTERING_WORLD", false, false)
        c.fire("ZONE_CHANGED_NEW_AREA")
    end
    self:advance(0)
end

-- ===== message delivery between clients =====
function World:deliverChat(from, msg)
    local event = ({ PARTY = "CHAT_MSG_PARTY", RAID = "CHAT_MSG_RAID", INSTANCE_CHAT = "CHAT_MSG_INSTANCE_CHAT" })[msg.channel]
    if not event or not from.group then return end
    local sender = fullName(from)
    for _, c in ipairs(from.group.list) do
        c.addAt(self.latency, function() c.fire(event, msg.text, sender) end)
    end
    self.chatLog = self.chatLog or {}
    self.chatLog[#self.chatLog + 1] = { from = from.name, channel = msg.channel, text = msg.text, t = from.now }
end

function World:deliverAddon(from, msg)
    local sender = fullName(from)
    local targets = {}
    if msg.channel == "GUILD" then
        targets = self.guild
    elseif from.group then
        targets = from.group.list
    end
    for _, c in ipairs(targets) do
        c.addAt(self.latency, function() c.fire("CHAT_MSG_ADDON", msg.prefix, msg.text, msg.channel, sender) end)
    end
end

-- ===== time =====
-- All clients move forward together in small steps, so messages between them arrive in a sensible order.
function World:advance(seconds)
    local left = seconds
    repeat
        local dt = math.min(self.step, left)
        for _, c in ipairs(self.clients) do c.advance(dt) end
        left = left - dt
    until left <= 1e-9
end

-- ===== loot =====
-- Starts an encounter in every client's loot history.
function World:encounter(id, name)
    for _, c in ipairs(self.clients) do
        c.loot.encounters[id] = c.loot.encounters[id] or { name = name, startTime = c.now, drops = {} }
        c.loot.encounters[id].name = name
        local known = false
        for _, e in ipairs(c.loot.order) do if e == id then known = true end end
        if not known then c.loot.order[#c.loot.order + 1] = id end
    end
end

local function item(id, name, color)
    return string.format("|cff%s|Hitem:%d::::::::::::::|h[%s]|h|r", color or "a335ee", id, name)
end
World.item = item

-- A drop: rolls are added with :roll(), finished with :finish(). Each change is mirrored to every client in the
-- format the game gives it (isSelf differs per client) and fires LOOT_HISTORY_UPDATE_DROP.
function World:drop(encounterID, link)
    local d = { world = self, enc = encounterID, link = link, key = self.nextKey, rolls = {}, order = {} }
    self.nextKey = self.nextKey + 1
    function d:roll(who, kind, value)
        if not self.rolls[who] then self.order[#self.order + 1] = who end
        self.rolls[who] = { state = STATE[kind], value = value }
        self.world:syncDrop(self, "roll", who, kind, value)
        return self
    end
    function d:finish(winner)
        self.done = true
        self.winner = winner
        self.world:syncDrop(self, "finish")
        return self
    end
    function d:allPassed()
        self.done, self.passed = true, true
        self.world:syncDrop(self, "finish")
        return self
    end
    self:syncDrop(d, "new")
    return d
end

function World:syncDrop(d, what, who, kind, value)
    for _, c in ipairs(self.clients) do
        local enc = c.loot.encounters[d.enc]
        local entry
        for _, e in ipairs(enc.drops) do if e.lootListKey == d.key then entry = e end end
        if not entry then
            entry = { itemHyperlink = d.link, lootListKey = d.key, allPassed = false, rollInfos = {} }
            enc.drops[#enc.drops + 1] = entry
        end
        entry.rollInfos = {}
        entry.winner = nil
        for _, name in ipairs(d.order) do
            local r = d.rolls[name]
            local other = self.byName[name]
            local info = { playerName = name .. "-" .. (other and other.realm or "Testrealm"):gsub("%s", ""),
                playerGUID = name, playerClass = other and other.class or "WARRIOR", isSelf = (name == c.name),
                state = r.state, roll = r.value, isWinner = (d.winner == name) }
            entry.rollInfos[#entry.rollInfos + 1] = info
            if info.isWinner then entry.winner = info end
        end
        entry.allPassed = d.passed == true
        c.fire("LOOT_HISTORY_UPDATE_DROP", d.enc, d.key)
        -- Blizzard's own chat lines still arrive (the addon hides them in its window)
        if what == "roll" then self:blizzardLine(c, who, kind, value, d.link) end
        if what == "finish" and not d.passed then self:blizzardLine(c, d.winner, "won", nil, d.link) end
    end
end

-- The raw Blizzard chat line, delivered to every visible chat window unless a filter hides it there.
function World:blizzardLine(c, who, kind, value, link)
    local pl = "|Hplayer:" .. who .. "-" .. c.realm:gsub("%s", "") .. ":1|h[" .. who .. "]|h"
    local g = c.env
    local text
    if kind == "need" or kind == "needos" then text = string.format(g.LOOT_ROLL_NEED, pl, link)
    elseif kind == "greed" then text = string.format(g.LOOT_ROLL_GREED, pl, link)
    elseif kind == "pass" then text = string.format(g.LOOT_ROLL_PASSED, pl, link)
    elseif kind == "won" then text = string.format(g.LOOT_ROLL_WON, pl, link)
    end
    if not text then return end
    for i = 1, 10 do
        local cf = g["ChatFrame" .. i]
        if cf._shown and not c.chatHidden("CHAT_MSG_LOOT", cf, text) then
            cf.lines[#cf.lines + 1] = { text = text, blizzard = true }
        end
    end
    c.fire("CHAT_MSG_LOOT", text)
end

-- ===== reading what a client shows =====
-- Lines the ADDON put in a chat window (Blizzard's raw lines are excluded unless includeRaw).
function World.chat(c, windowNumber, includeRaw)
    local cf = c.env["ChatFrame" .. (windowNumber or 1)]
    local out = {}
    for _, l in ipairs(cf.lines) do
        if includeRaw or not l.blizzard then out[#out + 1] = l.text end
    end
    return out
end

function World.rawLines(c, windowNumber)
    local cf = c.env["ChatFrame" .. (windowNumber or 1)]
    local out = {}
    for _, l in ipairs(cf.lines) do if l.blizzard then out[#out + 1] = l.text end end
    return out
end

function World.clearChat(c)
    for i = 1, 10 do c.env["ChatFrame" .. i].lines = {} end
end

-- Everything the addon wrote into one chat window as one plain-text string (blocks are multi-line messages).
function World.chatText(c, windowNumber, tags)
    local f = tags and tagged or plain
    local out = {}
    for _, l in ipairs(World.chat(c, windowNumber)) do out[#out + 1] = f(l) end
    return table.concat(out, "\n")
end

-- Visible text of every visible non-chat frame: a text "screenshot" of the addon's windows and buttons.
function World.screen(c, tags)
    local f = tags and tagged or plain
    local out = {}
    local function walk(frame, depth)
        if not frame:IsVisible() then return end
        local label = frame._name or frame._kind
        local texts = {}
        for _, ch in ipairs(frame._children) do
            if ch._kind == "FontString" and ch._shown and ch._text ~= "" then texts[#texts + 1] = f(ch._text) end
        end
        if frame._text ~= "" and frame._kind ~= "FontString" then texts[#texts + 1] = f(frame._text) end
        if #texts > 0 then
            out[#out + 1] = string.rep("  ", depth) .. "[" .. label .. "] " .. table.concat(texts, " | ")
        end
        for _, ch in ipairs(frame._children) do
            if ch._kind ~= "FontString" and ch._kind ~= "Texture" then walk(ch, depth + 1) end
        end
    end
    for _, fr in ipairs(c.frames) do
        if fr._parent == c.env.UIParent and fr._kind ~= "MessageFrame" then walk(fr, 0) end
    end
    return table.concat(out, "\n")
end

-- Chat lines sent to the group by one client (what other players read in party chat).
function World.said(c)
    local out = {}
    for _, m in ipairs(c.sent) do out[#out + 1] = m.text end
    return out
end

return World
