-- WoW client simulator: runs the REAL addon files (in .toc order) against a fake game, so behavior can be tested
-- without starting WoW. One Wow.new() = one client (own globals, own saved variables, own virtual clock source),
-- so several clients can be linked to emulate a group whose members all run the addon.
--
-- What is emulated for real (state + logic): events, frames and their scripts, virtual time and timers, chat
-- frames and chat filters, the group roster, group/addon chat, the loot history (C_LootHistory), instances and
-- encounters, saved variables. Purely visual frame methods are accepted and ignored (and listed in
-- client.missing so gaps stay visible).
local Wow = {}

local unpack = table.unpack

-- ===== game strings (enUS; the addon builds its patterns from every global LOOT_ROLL_*) =====
local GLOBAL_STRINGS = {
    LOOT_ROLL_NEED = "%s has selected Need for: %s",
    LOOT_ROLL_NEED_SELF = "You have selected Need for: %s",
    LOOT_ROLL_GREED = "%s has selected Greed for: %s",
    LOOT_ROLL_GREED_SELF = "You have selected Greed for: %s",
    LOOT_ROLL_PASSED = "%s passed on: %s",
    LOOT_ROLL_PASSED_SELF = "You passed on: %s",
    LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s",
    LOOT_ROLL_ROLLED_GREED = "Greed Roll - %d for %s by %s",
    LOOT_ROLL_WON = "%s won: %s",
    LOOT_ROLL_YOU_WON = "You won: %s",
    LOOT_ROLL_ALL_PASSED = "Everyone passed on: %s",
    UNITDIESOTHER = "%s dies.",
    SELFKILLOTHER = "You have slain %s!",
    MISCELLANEOUS = "Miscellaneous",
}

local CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
    PRIEST = { r = 1, g = 1, b = 1 }, DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    SHAMAN = { r = 0, g = 0.44, b = 0.87 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 }, MONK = { r = 0, g = 1, b = 0.6 },
    DRUID = { r = 1, g = 0.49, b = 0.04 }, DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    EVOKER = { r = 0.2, g = 0.58, b = 0.5 },
}

-- ===== frames =====
-- Methods with real behavior are listed here; any other method is accepted and recorded in client.missing.
local function NewFrameClass(client)
    local Frame = {}
    Frame.__index = Frame

    local function make(kind, name, parent)
        local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true, _scripts = {},
            _hooks = {}, _events = {}, _points = {}, _children = {}, _text = "", _w = 0, _h = 0,
            _alpha = 1, _level = 1, _strata = "MEDIUM" }, Frame)
        if name then client.env[name] = f end
        client.frames[#client.frames + 1] = f
        if parent and parent._children then parent._children[#parent._children + 1] = f end
        return f
    end
    client.makeFrame = make

    function Frame:GetName() return self._name end
    function Frame:GetObjectType() return self._kind end
    function Frame:GetParent() return self._parent end
    function Frame:SetParent(p) self._parent = p end
    function Frame:Show() self._shown = true; local h = self._scripts.OnShow; if h then h(self) end end
    function Frame:Hide() local was = self._shown; self._shown = false
        local h = self._scripts.OnHide; if was and h then h(self) end end
    function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
    function Frame:IsShown() return self._shown end
    function Frame:IsVisible()
        local f = self
        while f do
            if not f._shown then return false end
            f = f._parent
        end
        return true
    end
    function Frame:SetText(t) self._text = t == nil and "" or tostring(t) end
    function Frame:GetText() return self._text end
    function Frame:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
    function Frame:GetStringWidth() return #(self._text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6 end
    function Frame:GetStringHeight() return 12 end
    function Frame:SetFont(font, size, flags) self._font = { font, size, flags } end
    function Frame:GetFont() return "Fonts\\FRIZQT__.TTF", 14, "" end
    function Frame:SetWidth(w) self._w = w end
    function Frame:SetHeight(h) self._h = h end
    function Frame:SetSize(w, h) self._w, self._h = w, h end
    function Frame:GetWidth() return self._w end
    function Frame:GetHeight() return self._h end
    function Frame:GetSize() return self._w, self._h end
    function Frame:SetAlpha(a) self._alpha = a end
    function Frame:GetAlpha() return self._alpha end
    function Frame:SetFrameStrata(s) self._strata = s end
    function Frame:GetFrameStrata() return self._strata end
    function Frame:SetFrameLevel(l) self._level = l end
    function Frame:GetFrameLevel() return self._level end
    function Frame:SetPoint(point, rel, relPoint, x, y)
        if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
        self._points[#self._points + 1] = { point, rel, relPoint or point, x or 0, y or 0 }
    end
    function Frame:ClearAllPoints() self._points = {} end
    function Frame:GetPoint(i)
        local p = self._points[i or 1]
        if not p then return nil end
        return p[1], p[2] or client.env.UIParent, p[3], p[4], p[5]
    end
    function Frame:GetNumPoints() return #self._points end
    function Frame:GetLeft() return 100 end
    function Frame:GetRight() return 100 + self._w end
    function Frame:GetTop() return 600 end
    function Frame:GetBottom() return 600 - self._h end
    function Frame:GetEffectiveScale() return 1 end
    function Frame:GetScale() return 1 end
    function Frame:IsMouseOver() return false end

    -- scripts
    function Frame:SetScript(name, fn) self._scripts[name] = fn end
    function Frame:GetScript(name) return self._scripts[name] end
    function Frame:HookScript(name, fn)
        local old = self._scripts[name]
        self._scripts[name] = old and function(...) old(...); fn(...) end or fn
    end
    function Frame:HasScript() return true end

    -- events
    function Frame:RegisterEvent(ev)
        if not client.knownEvents[ev] and not ev:match("^CHAT_MSG_") then
            error("Unknown event " .. tostring(ev), 2) -- like the real client
        end
        self._events[ev] = true
    end
    function Frame:UnregisterEvent(ev) self._events[ev] = nil end
    function Frame:UnregisterAllEvents() self._events = {} end
    function Frame:IsEventRegistered(ev) return self._events[ev] == true end

    -- children
    function Frame:CreateTexture(name) return make("Texture", name, self) end
    function Frame:CreateFontString(name) return make("FontString", name, self) end
    function Frame:CreateAnimationGroup()
        local g = make("AnimationGroup", nil, self)
        function g:Play() self._playing = true end
        function g:Stop() self._playing = false end
        function g:IsPlaying() return self._playing == true end
        function g:CreateAnimation() return make("Animation", nil, self) end
        return g
    end
    function Frame:SetAllPoints() end
    function Frame:SetScrollChild(c) self._scrollChild = c end
    function Frame:SetVerticalScroll(v) self._vscroll = v end
    function Frame:GetVerticalScroll() return self._vscroll or 0 end

    -- movable / mouse (no real mouse; tests call the scripts directly)
    function Frame:SetMovable(v) self._movable = v end
    function Frame:StartMoving() self._moving = true end
    function Frame:StopMovingOrSizing() self._moving = false end

    -- anything else: visual-only, accepted, remembered in client.missing. Getters return neutral values.
    setmetatable(Frame, { __index = function(_, key)
        -- only method-looking names (Capitalized); plain fields like isTemporary must read as nil
        if type(key) ~= "string" or not key:match("^%u") then return nil end
        return function(self, ...)
            client.missing["frame:" .. key] = true
            if key:sub(1, 3) == "Get" then return nil end
            if key:sub(1, 2) == "Is" or key:sub(1, 3) == "Has" then return false end
            return self
        end
    end })
    return Frame
end

-- ===== the client =====
function Wow.new(opts)
    opts = opts or {}
    local client = {
        name = opts.name or "Player", realm = opts.realm or "Testrealm", class = opts.class or "MAGE",
        now = 0, timers = {}, frames = {}, missing = {}, errors = {}, comm = {}, sent = {}, guildNotice = {},
        filters = {}, group = nil, instance = nil, addonMessages = {}, db = nil, peers = {}, seq = 0,
        knownEvents = {},
    }
    for ev in ([[ADDON_LOADED PLAYER_LOGIN PLAYER_ENTERING_WORLD ZONE_CHANGED_NEW_AREA ENCOUNTER_END BOSS_KILL CHAT_MSG_COMBAT_HOSTILE_DEATH
        LFG_COMPLETION_REWARD CHALLENGE_MODE_COMPLETED SCENARIO_COMPLETED GROUP_ROSTER_UPDATE
        LOOT_HISTORY_UPDATE_DROP CHAT_MSG_LOOT CHAT_MSG_ADDON START_LOOT_ROLL GET_ITEM_INFO_RECEIVED
        CANCEL_LOOT_ROLL CANCEL_ALL_LOOT_ROLLS LOOT_ITEM_ROLL_WON]]):gmatch("%S+") do
        client.knownEvents[ev] = true
    end
    for _, ev in ipairs(opts.unknownEvents or {}) do client.knownEvents[ev] = nil end
    local env = {}
    client.env = env
    local Frame = NewFrameClass(client)

    -- Lua standard library, as WoW exposes it (no io/os/debug). math.random is seeded for repeatable runs.
    for _, k in ipairs({ "type", "pcall", "xpcall", "ipairs", "pairs", "next", "select", "tostring", "tonumber",
        "string", "table", "math", "error", "assert", "setmetatable", "getmetatable", "rawget", "rawset",
        "rawequal", "unpack", "utf8" }) do
        env[k] = _G[k]
    end
    env.unpack = unpack
    env.math = setmetatable({ random = nil }, { __index = math })
    do
        -- different players must draw different random delays (the announce timing relies on it)
        local state = opts.seed or 12345
        for i = 1, #client.name do state = (state * 31 + client.name:byte(i)) % 2147483648 end
        env.math.random = function(a, b) -- own generator: the same sequence on every Lua build
            state = (state * 1103515245 + 12345) % 2147483648
            local r = state / 2147483648
            if a == nil then return r end
            if b == nil then a, b = 1, a end
            return a + math.floor(r * (b - a + 1))
        end
    end
    env._G = env
    env.string = setmetatable({}, { __index = string })
    env.table = setmetatable({}, { __index = table })
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.table.wipe = env.wipe
    env.strsplit = function(sep, s) local out = {}; for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end return unpack(out) end
    env.tinsert, env.tremove = table.insert, table.remove

    -- unknown global reads are recorded (and return nil, like the real client)
    setmetatable(env, { __index = function(_, k)
        if type(k) == "string" then client.missing["global:" .. k] = true end
        return nil
    end })

    -- ----- time and timers -----
    env.GetTime = function() return client.now end
    env.GetLocale = function() return opts.locale or "enUS" end
    local function addTimer(delay, fn, repeating)
        client.seq = client.seq + 1
        local t = { at = client.now + delay, fn = fn, seq = client.seq, interval = repeating and delay or nil }
        client.timers[#client.timers + 1] = t
        return t
    end
    client.addAt = function(delay, fn) addTimer(delay, fn) end
    env.C_Timer = {
        After = function(delay, fn) addTimer(delay, fn) end,
        NewTimer = function(delay, fn)
            local t = addTimer(delay, fn)
            return { Cancel = function() t.cancelled = true end, IsCancelled = function() return t.cancelled == true end }
        end,
        NewTicker = function(interval, fn)
            local t = addTimer(interval, fn, true)
            return { Cancel = function() t.cancelled = true end }
        end,
    }

    -- ----- errors: everything routed to the error handler is recorded, tests fail on them -----
    env.geterrorhandler = function() return function(err) client.errors[#client.errors + 1] = tostring(err) end end
    env.issecretvalue = function() return false end
    env.hooksecurefunc = function(a, b, c)
        local tbl, name, fn = env, a, b
        if type(a) == "table" then tbl, name, fn = a, b, c end
        local orig = tbl[name]
        tbl[name] = function(...)
            local r = orig and orig(...)
            fn(...)
            return r
        end
    end

    -- ----- frames and chat windows -----
    env.UIParent = client.makeFrame("Frame", "UIParent")
    env.UIParent._w, env.UIParent._h = 1920, 1080
    env.CreateFrame = function(kind, name, parent, template)
        local f = client.makeFrame(kind, name, parent or env.UIParent)
        if template and tostring(template):find("Backdrop") then client.missing["template:" .. template] = nil end
        if kind == "GameTooltip" then
            f._lines = {}
            f.AddLine = function(self, t) self._lines[#self._lines + 1] = t end
            f.AddDoubleLine = function(self, a, b) self._lines[#self._lines + 1] = tostring(a) .. " " .. tostring(b) end
            f.ClearLines = function(self) self._lines = {} end
            f.SetOwner = function() end
            f._shown = false
        end
        if kind == "Button" or kind == "CheckButton" then
            f.Click = function(self, ...) local h = self._scripts.OnClick; if h then h(self, ...) end end
        end
        return f
    end
    env.GameTooltip = env.CreateFrame("GameTooltip", "GameTooltip")
    env.UISpecialFrames = {}
    env.SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
    env.PlaySound = function(id) client.sounds = (client.sounds or 0) + 1 end
    env.HideUIPanel = function(f) if f and f.Hide then f:Hide() end end
    env.BackdropTemplateMixin = {}
    env.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1,
        GetRGB = function(self) return self.r, self.g, self.b end } end
    env.ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff" } end })
    env.GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end
    env.CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
    env.RAID_CLASS_COLORS = CLASS_COLORS
    env.C_Texture = { GetAtlasInfo = function() return nil end }
    env.IsShiftKeyDown = function() return client.shift == true end
    env.InCombatLockdown = function() return client.combat == true end
    env.IsEncounterInProgress = function() return client.inEncounter == true end

    -- chat frames: AddMessage records every line (this is what the player would read)
    env.NUM_CHAT_WINDOWS = 10
    client.chatWindows = opts.chatWindows or { [1] = "General", [2] = "Combat Log", [3] = "Loot" }
    for i = 1, 10 do
        local cf = client.makeFrame("MessageFrame", "ChatFrame" .. i)
        cf.lines, cf._w, cf._h, cf.name = {}, 430, 120, client.chatWindows[i]
        cf.AddMessage = function(self, text, r, g, b, id)
            self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b, id = id }
        end
        cf._shown = client.chatWindows[i] ~= nil
        if i == 2 then env.COMBATLOG = cf end
    end
    env.DEFAULT_CHAT_FRAME = env.ChatFrame1
    env.FCF_GetChatWindowInfo = nil
    env.GetChatWindowInfo = function(i)
        local name = client.chatWindows[i]
        return name or "", 14, 1, 1, 1, 1, name ~= nil, 0, name ~= nil and 1 or nil
    end
    env.ChatTypeInfo = setmetatable({}, { __index = function(_, k) return { r = 1, g = 1, b = 0, id = 1 } end })
    env.ChatFrame_AddMessageEventFilter = function(event, fn)
        client.filters[event] = client.filters[event] or {}
        table.insert(client.filters[event], fn)
    end
    env.ChatFrame_SendTell, env.ChatEdit_InsertLink = function() end, function() end
    env.HandleModifiedItemClick = function() end
    env.SetItemRef = function() end

    -- ----- player, realm, group -----
    env.UnitName = function(unit)
        local m = client.unitMember(unit)
        if not m then return nil end
        return m.name, m.realm ~= client.realm and m.realm or nil
    end
    env.UnitClass = function(unit)
        local m = client.unitMember(unit)
        if not m then return nil end
        return m.class:sub(1, 1) .. m.class:sub(2):lower(), m.class
    end
    env.UnitExists = function(unit) return client.unitMember(unit) ~= nil end
    env.UnitIsUnit = function(a, b)
        local x, y = client.unitMember(a), client.unitMember(b)
        return x ~= nil and x == y
    end
    env.UnitIsDeadOrGhost = function() return client.dead == true end
    env.GetNormalizedRealmName = function() return (client.realm:gsub("%s", "")) end
    env.GetRealmName = function() return client.realm end
    env.IsInGuild = function() return client.guild == true end
    env.LE_PARTY_CATEGORY_INSTANCE = 2
    env.IsInGroup = function(category)
        if not client.group then return false end
        if category == 2 then return client.group.instance == true end
        return true
    end
    env.IsInRaid = function() return client.group ~= nil and client.group.raid == true end
    env.GetNumGroupMembers = function() return client.group and (#client.group.members + 1) or 0 end

    local me = { name = client.name, realm = client.realm, class = client.class }
    client.me = me
    function client.unitMember(unit)
        if unit == "player" or unit == client.name or unit == client.name .. "-" .. client.realm:gsub("%s", "") then
            return me
        end
        if type(unit) ~= "string" then return nil end
        if client.group then
            local idx = unit:match("^party(%d)$") or unit:match("^raid(%d+)$")
            if idx then return client.group.members[tonumber(idx)] end
            local short = unit:match("^([^%-]+)")
            for _, m in ipairs(client.group.members) do
                if m.name == short then return m end
            end
        end
        return nil
    end

    -- ----- addon messages and chat sending -----
    local registered = {}
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix) registered[prefix] = true; return true end,
        IsAddonMessagePrefixRegistered = function(prefix) return registered[prefix] == true end,
        InChatMessagingLockdown = function() return client.locked == true end,
        SendAddonMessage = function(prefix, text, channel, target)
            local msg = { prefix = prefix, text = text, channel = channel, t = client.now }
            client.addonMessages[#client.addonMessages + 1] = msg
            if client.onSendAddon then client.onSendAddon(client, msg) end
            return true
        end,
        SendChatMessage = nil,
    }
    env.SendChatMessage = function(text, channel)
        local msg = { text = text, channel = channel, t = client.now }
        client.sent[#client.sent + 1] = msg
        if client.onSendChat then client.onSendChat(client, msg) end
    end
    env.C_AddOns = { GetAddOnMetadata = function(_, field) return client.toc and client.toc[field] end }
    env.GetAddOnMetadata = nil

    -- ----- world: instance, encounter journal, map -----
    env.GetInstanceInfo = function()
        local i = client.instance
        if not i then return "Azeroth", "none", 0, "", 0, 0, false, 1, 0 end
        return i.name, i.type or "party", i.difficulty or 1, "", 5, 0, false, i.id, 5
    end
    env.C_Map = { GetBestMapForUnit = function() return client.instance and client.instance.mapID or 1 end }
    env.EJ_GetInstanceForMap = function() return client.instance and client.instance.journalID or 0 end
    env.EJ_GetEncounterInfoByIndex = function(i, journalID)
        local inst = client.instance
        local e = inst and inst.encounters and inst.encounters[i]
        if not e then return nil end
        return e.name, "", e.id, 0, 0, journalID, e.id
    end
    env.EJ_SelectInstance = function() end
    -- ----- open loot rolls (the game's roll frame): client.startRoll(id, link, seconds, opts) opens one -----
    client.lootRolls, client.rolledOn, client.closedEvents = {}, {}, {}
    -- the game's internal event router (it opens the roll popups from START_LOOT_ROLL)
    env.GameEvent = { UnregisterInternalEvent = function(ev) client.closedEvents[ev] = true end }
    env.GetActiveLootRollIDs = function()
        local ids = {}
        for _, id in ipairs(client.activeRolls or {}) do ids[#ids + 1] = id end
        for id in pairs(client.lootRolls) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end
    env.GetLootRollItemLink = function(id) local r = client.lootRolls[id]; return r and r.link end
    env.GetLootRollItemInfo = function(id)
        local r = client.lootRolls[id]
        if not r then return nil end
        return r.icon or 134400, r.link:match("%[(.-)%]"), 1, r.quality or 2, r.bop == true, r.canNeed ~= false,
            r.canGreed ~= false, r.canDE == true, r.canNeed == false and 1 or 0, 0, 0, 0, false
    end
    env.GetLootRollTimeLeft = function(id)
        local r = client.lootRolls[id]
        return r and math.max(0, (r.endsAt - client.now) * 1000) or 0
    end
    env.RollOnLoot = function(id, kind) client.rolledOn[#client.rolledOn + 1] = { id = id, kind = kind } end
    env.ConfirmLootRoll = function() end
    function client.startRoll(id, link, seconds, o)
        local r = o or {}
        r.link, r.endsAt = link, client.now + (seconds or 60)
        client.lootRolls[id] = r
        client.fire("START_LOOT_ROLL", id, (seconds or 60) * 1000)
    end
    function client.endRoll(id)
        client.lootRolls[id] = nil
        client.fire("CANCEL_LOOT_ROLL", id)
    end

    -- ----- items -----
    -- client.items[itemID] = { icon=, classID=, subClassID=, equipLoc=, stats={...} } (set by tests; default: unknown)
    client.items = opts.items or {}
    local function itemID(link) return tonumber(tostring(link):match("item:(%d+)")) or tonumber(link) end
    env.C_Item = {
        GetItemInfoInstant = function(link)
            local it = client.items[itemID(link)]
            if not it then return itemID(link) end
            return itemID(link), "", "", it.equipLoc or "", it.icon or 134400, it.classID, it.subClassID
        end,
        GetItemStats = function(link)
            local it = client.items[itemID(link)]
            return it and it.stats or {}
        end,
        GetItemInfo = function(link)
            local it = client.items[itemID(link)]
            if not it then return nil end -- like the game: nothing until the item is loaded
            return it.name or "Item", link, it.quality or 1
        end,
        GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end,
    }
    env.GetItemInfoInstant = env.C_Item.GetItemInfoInstant
    env.GetItemInfo, env.GetItemStats, env.GetItemQualityColor = nil, nil, nil
    env.GetItemInfo = env.C_Item.GetItemInfo

    -- ----- loot history (Midnight engine structure) -----
    env.Enum = { EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3,
        NoRoll = 4, Pass = 5 } }
    client.loot = { encounters = {}, order = {}, nextKey = 1 }
    local function sortedDrop(d)
        local copy = { itemHyperlink = d.itemHyperlink, lootListKey = d.lootListKey, allPassed = d.allPassed,
            rollInfos = {}, winner = d.winner }
        for _, r in ipairs(d.rollInfos) do copy.rollInfos[#copy.rollInfos + 1] = r end
        return copy
    end
    env.C_LootHistory = {
        GetAllEncounterInfos = function()
            local out = {}
            for _, id in ipairs(client.loot.order) do
                local e = client.loot.encounters[id]
                out[#out + 1] = { encounterID = id, encounterName = e.name, startTime = e.startTime }
            end
            return out
        end,
        GetInfoForEncounter = function(id)
            local e = client.loot.encounters[id]
            return e and { encounterID = id, encounterName = e.name, startTime = e.startTime } or nil
        end,
        GetSortedDropsForEncounter = function(id)
            local e = client.loot.encounters[id]
            if not e then return nil end
            local out = {}
            for _, d in ipairs(e.drops) do out[#out + 1] = sortedDrop(d) end
            return out
        end,
        GetSortedInfoForDrop = function(id, key)
            local e = client.loot.encounters[id]
            if not e then return nil end
            for _, d in ipairs(e.drops) do
                if d.lootListKey == key then return sortedDrop(d) end
            end
            return nil
        end,
    }

    -- ----- Settings API (the panel registers its controls; tests can read what was registered) -----
    client.settings = { settings = {}, categories = {} }
    local function widget() return setmetatable({}, { __index = function() return function() end end }) end
    env.Settings = {
        VarType = { Boolean = "boolean", String = "string", Number = "number" },
        RegisterVerticalLayoutCategory = function(name)
            local c = { name = name, GetID = function() return 1 end }
            client.settings.categories[#client.settings.categories + 1] = c
            return c
        end,
        RegisterAddOnCategory = function() end,
        RegisterAddOnSetting = function(_, id, key, tbl, _, label, default)
            local s = { id = id, key = key, tbl = tbl, label = label, default = default,
                SetValueChangedCallback = function(self, fn) self.onChange = fn end }
            client.settings.settings[#client.settings.settings + 1] = s
            return s
        end,
        CreateCheckbox = function() return widget() end,
        CreateDropdown = function() return widget() end,
        CreateControlTextContainer = function()
            return { Add = function() end, GetData = function() return {} end }
        end,
        OpenToCategory = function(id) client.openedCategory = id end,
        CreateSettingsButtonInitializer = function() return widget() end,
    }
    env.CreateSettingsButtonInitializer = env.Settings.CreateSettingsButtonInitializer
    env.SlashCmdList = {}

    for k, v in pairs(GLOBAL_STRINGS) do env[k] = v end
    for _, k in ipairs(opts.removeGlobals or {}) do env[k] = nil end
    if opts.noLootHistory then env.C_LootHistory = nil end
    for k, v in pairs(opts.globals or {}) do env[k] = v end

    -- ===== scheduler =====
    -- Advances virtual time, running timers (and OnUpdate scripts are not needed: the addon uses C_Timer).
    function client.advance(seconds, step)
        local target = client.now + seconds
        while true do
            local best
            for _, t in ipairs(client.timers) do
                if not t.cancelled and t.at <= target and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
                    best = t
                end
            end
            if not best then break end
            client.now = math.max(client.now, best.at)
            if best.interval then
                best.at = best.at + best.interval
                client.seq = client.seq + 1
                best.seq = client.seq
            else
                best.cancelled = true
            end
            local ok, err = pcall(best.fn)
            if not ok then client.errors[#client.errors + 1] = tostring(err) end
        end
        client.now = target
        -- drop finished timers
        local keep = {}
        for _, t in ipairs(client.timers) do if not t.cancelled then keep[#keep + 1] = t end end
        client.timers = keep
    end

    -- ===== events =====
    function client.fire(event, ...)
        local list = {}
        for _, f in ipairs(client.frames) do
            if f._events[event] then list[#list + 1] = f end
        end
        for _, f in ipairs(list) do
            local h = f._scripts.OnEvent
            if h then
                local ok, err = pcall(h, f, event, ...)
                if not ok then client.errors[#client.errors + 1] = event .. ": " .. tostring(err) end
            end
        end
    end

    -- Chat line the way the game delivers it: filters first (a filter returning true hides it in a window), then
    -- the event. `window` = chat frame the filters are asked about.
    function client.chatHidden(event, window, msg, ...)
        for _, fn in ipairs(client.filters[event] or {}) do
            local ok, hide = pcall(fn, window, event, msg, ...)
            if ok and hide then return true end
        end
        return false
    end

    -- ===== loading the addon =====
    function client.load(root)
        root = root or "."
        client.root = root
        local ns, files = {}, {}
        client.ns = ns
        client.toc = {}
        for line in io.lines(root .. "/WhoWonThat.toc") do
            local k, v = line:match("^## ([%w%-]+):%s*(.-)%s*$")
            if k then client.toc[k] = v end
            local f = line:match("^(%S+%.lua)%s*$")
            if f then files[#files + 1] = f end
        end
        for _, f in ipairs(files) do
            local chunk, err = loadfile(root .. "/" .. f, "t", env)
            if not chunk then error(err) end
            local ok, e = pcall(chunk, "WhoWonThat", ns)
            if not ok then error(f .. ": " .. tostring(e)) end
        end
        client.files = files
        env.WhoWonThatDB = opts.savedVariables
        client.fire("ADDON_LOADED", "WhoWonThat")
        return client
    end

    function client.login()
        client.fire("PLAYER_LOGIN")
        client.fire("PLAYER_ENTERING_WORLD", true, false)
        client.advance(0)
        return client
    end

    function client.reload()
        local saved = env.WhoWonThatDB
        client.fire("PLAYER_LOGOUT")
        return saved
    end

    function client.slash(text)
        local cmd, rest = text:match("^(/%S+)%s*(.*)$")
        for key, fn in pairs(env.SlashCmdList) do
            for i = 1, 5 do
                if env["SLASH_" .. key .. i] == cmd then fn(rest); return true end
            end
        end
        return false
    end

    return client
end

return Wow
