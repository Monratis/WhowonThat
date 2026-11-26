-- Who Won That
-- Shows loot rolls live in a small roll window instead of the game's roll lines in chat, keeps a dungeon loot
-- summary and can announce results to the group.
-- Settings: Esc > Options > AddOns > Who Won That, or /wwt

local ADDON, ns = ...

local DEFAULTS = {
    rolls = true,       -- master switch: show other players' rolls
    need = true,        -- show Need rolls
    greed = true,       -- show Greed rolls
    de = true,          -- (raw mode only) Disenchant rolls, if the game has them
    pass = true,        -- show passes
    wins = true,        -- show who won / that everyone passed
    byBoss = true,      -- always on: the boss name in announcements
    flagUnusable = true, -- always on: red X on Need rolls for armor the class cannot wear
    announce = "off",   -- send results to group chat: "off" or "all" (an old "mine" is migrated to "all" on load)
    detail = "all",     -- how much an announcement says: "winner", "rolls" (winner + Need/Greed) or "all" (also passes)
    hintSeen = false,   -- the first-run introduction was shown
    showValues = true,  -- show auction house values (from Auctionator, TSM or Booty Bay Broker) in the loot summary
    minValueSilver = 20, -- with a price addon: items worth less than this many silver are not shown or announced (0 = off)
    language = "auto",  -- language of settings and messages: "auto" (the game's language) or a locale such as "deDE"
    summary = "everyone", -- loot summary window at the end of a dungeon: "off", "mine" (only my items) or "everyone"
    rollWindow = true,  -- the roll window: live rolls and, between them, what the group has won
}

local TYPE_LABEL = { need = "Need", greed = "Greed", de = "Disenchant", pass = "Pass" }
local PRIORITY = { win = 1, de = 2, greed = 3, need = 4, pass = 5, other = 6 }
-- Forever (Midnight engine) has a loot history with structured roll data (C_LootHistory) - the main data source.
-- Chat text parsing is only used to hide the raw lines and as a fallback.
local HAS_HISTORY = (C_LootHistory ~= nil and C_LootHistory.GetSortedInfoForDrop ~= nil)
local STALE_SECONDS = 180

local entries = {}  -- {pattern, kinds, kind, wonType, self, prio}
local entriesBuilt = false
local items = {}    -- [itemLink] = { time = t, players = { [name] = { type, roll } } }

-- Prints to a chat frame the way Blizzard does: AddMessage(text, r, g, b, id).
-- The full argument list matters - addons hooking AddMessage (e.g. EllesmereUIChat)
-- read the 5th argument (chatTypeID) and raise "bad argument #5" without it.
local function Emit(frame, text, chatType)
    local info = ChatTypeInfo and (ChatTypeInfo[chatType] or ChatTypeInfo.SYSTEM)
    if info then
        frame:AddMessage(text, info.r, info.g, info.b, info.id)
    else
        frame:AddMessage(text, 1, 1, 1, 0)
    end
end

local function Print(msg)
    Emit(DEFAULT_CHAT_FRAME, "|cff58c6faWho Won That:|r " .. msg, "SYSTEM")
end

-- Turns a Blizzard format string (e.g. "%s won: %s") into a language-independent Lua pattern
-- with captures. Returns the pattern and the list of captured field types ("s" or "d").
local function Compile(fmt)
    local kinds = {}
    local p = fmt:gsub("%%%%", "\3")
    p = p:gsub("%%(%d*)%$?([sd])", function(_, t)
        kinds[#kinds + 1] = t
        return t == "s" and "\1" or "\2"
    end)
    p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("\1", "(.+)")
    p = p:gsub("\2", "(%%d+)")
    p = p:gsub("\3", "%%%%")
    return "^" .. p .. "$", kinds
end

-- Classifies a message by the name of its global string (e.g. LOOT_ROLL_ROLLED_NEED).
local function ClassifyName(name)
    if name:find("WON") or name:find("ALL_PASSED") then
        return "win"
    end
    if name:find("TRANSMOG") then
        return "other" -- Transmog rolls are intentionally not supported
    end
    if name:find("DISENCHANT") or name:find("_DE$") or name:find("_DE_") then
        return "de"
    end
    if name:find("GREED") then
        return "greed"
    end
    if name:find("NEED") then
        return "need"
    end
    if name:find("PASS") then
        return "pass"
    end
    return "other"
end

local function WonType(name)
    if name:find("DISENCHANT") or name:find("_DE$") or name:find("_DE_") then return "de" end
    if name:find("GREED") then return "greed" end
    if name:find("NEED") then return "need" end
    return nil
end

local function BuildEntries()
    wipe(entries)
    for name, text in pairs(_G) do
        if type(name) == "string" and type(text) == "string" and name:find("^LOOT_ROLL_") then
            local pattern, kinds = Compile(text)
            -- skip patterns that would match every message
            if pattern ~= "^(.+)$" and pattern ~= "^$" then
                local kind = ClassifyName(name)
                local literal = #(text:gsub("%%%d*%$?[sd]", ""))
                entries[#entries + 1] = {
                    literal = literal,
                    pattern = pattern,
                    kinds = kinds,
                    kind = kind,
                    name = name,
                    wonType = (kind == "win") and WonType(name) or nil,
                    allPassed = name:find("ALL_PASSED") ~= nil,
                    self = (name:find("_SELF") or name:find("YOU_")) and true or false,
                    prio = PRIORITY[kind],
                }
            end
        end
    end
    -- wins before rolls ("everyone passed" also matches the "X passed" pattern),
    -- and within a group the patterns with the most literal text first, because the generic
    -- "%s won: %s" would also match "You won: %s" and "%s won: %s (Need - 74)"
    table.sort(entries, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        if a.literal ~= b.literal then return a.literal > b.literal end
        return a.name < b.name
    end)
end

-- Returns the full player name ("Name-Realm", if the client provides it) and the short name.
-- Blizzard messages contain a link |Hplayer:Name-Realm:...|h[Name]|h; the full name comes from it.
local function PlayerInfo(raw)
    if not raw then return nil end
    local full = raw:match("|Hplayer:([^:|]+)")
    local short = raw:match("|h%[(.-)%]|h")
    if full then
        return full, short or (full:match("^([^%-]+)") or full)
    end
    return raw, (raw:match("^([^%-]+)") or raw)
end

local function SelfInfo()
    local name = UnitName("player")
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    if realm and realm ~= "" then
        realm = realm:gsub("%s", "")
        return name .. "-" .. realm, name
    end
    return name, name
end

-- Returns a table {kind, item, player, roll, wonType, allPassed}, or nil if the message is not a roll.
local function Parse(msg)
    if not entriesBuilt then
        entriesBuilt = true
        BuildEntries() -- built lazily, on the first loot message
    end
    for i = 1, #entries do
        local e = entries[i]
        local c1 = msg:match(e.pattern)
        if c1 then
            local caps = { msg:match(e.pattern) }
            local r ={ kind = e.kind, wonType = e.wonType, allPassed = e.allPassed }
            for j = 1, #e.kinds do
                local c = caps[j]
                if c then
                    if e.kinds[j] == "d" then
                        r.roll = tonumber(c)
                    elseif c:find("|Hitem:") then
                        r.item = r.item or c
                    elseif not r.player then
                        r.player, r.short = PlayerInfo(c)
                    end
                end
            end
            if e.self then
                r.player, r.short = SelfInfo()
            end
            return r
        end
    end
    return nil
end

-- Chat filter: while the roll window is on, the game's own roll lines (who picked Need / Greed / Pass, rolled,
-- won) are hidden in every chat window; the window shows them. Other loot messages stay. The same message is
-- asked about once per chat window, so the last answer is kept.
local lastMsg, lastHide = nil, false
local function Filter(_, _, msg)
    if not (ns.db and ns.db.rollWindow) or type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then
        return false
    end
    if msg ~= lastMsg then
        local p = Parse(msg)
        lastMsg, lastHide = msg, (p ~= nil and p.kind ~= "other")
    end
    return lastHide
end

-- Class color: the user's custom palette if they use one, otherwise Blizzard's standard class colors.
local function ClassColor(classFile)
    if not classFile then
        return nil
    end
    -- user-defined palettes: the "ClassColors" addon, then EllesmereUI
    if type(CUSTOM_CLASS_COLORS) == "table" and CUSTOM_CLASS_COLORS[classFile] then
        return CUSTOM_CLASS_COLORS[classFile]
    end
    if type(EllesmereUI) == "table" and EllesmereUI.GetRawClassColor then
        local c = EllesmereUI.GetRawClassColor(classFile)
        if c then
            return c
        end
    end
    -- nothing installed: Blizzard's standard class colors
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
end

-- ===== shared with the other files =====
ns.ADDON, ns.ClassColor, ns.DEFAULTS, ns.Emit = ADDON, ClassColor, DEFAULTS, Emit
ns.Filter, ns.HAS_HISTORY, ns.Parse, ns.Print = Filter, HAS_HISTORY, Parse, Print
ns.STALE_SECONDS, ns.items = STALE_SECONDS, items
