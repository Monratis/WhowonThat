-- Who Won That
-- Shows loot rolls and results in a chat window of your choice: one readable block per item once
-- the roll is finished (winner with a crown, then everyone else's roll).
-- "raw" format keeps Blizzard's original lines (filtered by roll type). Other chat windows are untouched.
-- Settings: Esc > Options > AddOns > Who Won That, or /wwt

local ADDON, ns = ...

local DEFAULTS = {
    frame = 1,          -- chat window number that receives rolls and results
    format = "summary", -- "summary" = readable block per item, "raw" = Blizzard's original lines
    rolls = true,       -- master switch: show other players' rolls
    need = true,        -- show Need rolls
    greed = true,       -- show Greed rolls
    de = true,          -- (raw mode only) Disenchant rolls, if the game has them
    pass = true,        -- show passes
    wins = true,        -- show who won / that everyone passed
    hideOthers = true,  -- always on: hide other loot messages in that window (picked up items etc.)
    classColors = true, -- color names by class (custom palette if present, else Blizzard colors)
    header = true,      -- put the addon name in front of each item line
    byBoss = true,      -- always on: "Loot from: <boss>" above the items of one kill
    flagUnusable = true, -- always on: red X on Need rolls for armor the class cannot wear
    announce = "off",   -- send results to group chat: "off" or "all" (an old "mine" is migrated to "all" on load)
    hideWhenAnnounced = true, -- do not print my own block for a result that was announced in group chat
    detail = "all",     -- how much to show: "winner", "rolls" (winner + Need/Greed) or "all" (also passes)
    layout = "auto",    -- "auto" = compact on a narrow chat window, "normal", or "compact"
    hintSeen = false,   -- the one-time "how to choose a chat window" tip was shown
    language = "auto",  -- language of settings and messages: "auto" (the game's language) or a locale such as "deDE"
    summary = "everyone", -- loot summary window at the end of a dungeon: "off", "mine" (only my items) or "everyone"
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
        BuildEntries() -- built lazily: only the fallback and /wwt test need it
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

-- A chat window the player really has: shown or docked (the same test Blizzard uses), not a temporary
-- (whisper) window and not the combat log. The engine creates ChatFrame1..10 even when most are unused.
local function IsUsableWindow(i)
    local f = _G["ChatFrame" .. i]
    if not f or f.isTemporary or (COMBATLOG and f == COMBATLOG) then
        return false
    end
    local getInfo = FCF_GetChatWindowInfo or GetChatWindowInfo
    if getInfo then
        local name, _, _, _, _, _, shown, _, docked = getInfo(i)
        return (name ~= nil and name ~= "") and (shown and true or (docked ~= nil and docked ~= false and docked ~= 0))
    end
    return f:IsShown() and true or false
end

local function TargetFrame()
    if not ns.db then
        return nil
    end
    -- if the saved window is not a real one (any more), use the main window
    local i = IsUsableWindow(ns.db.frame) and ns.db.frame or 1
    return _G["ChatFrame" .. i]
end

-- Returning true = hide the message in this chat window.
-- the saved window's frame without building the "ChatFrameN" name string on every chat message
local FRAME_NAMES = {}
local function TargetFrameRaw()
    local i = ns.db.frame
    local name = FRAME_NAMES[i]
    if not name then
        name = "ChatFrame" .. i
        FRAME_NAMES[i] = name
    end
    return _G[name]
end

-- Summary mode is always on: roll lines are replaced by our block and all other loot lines are hidden
-- in this window too, so every loot message here is hidden and nothing needs to be parsed (cheap path).
local function Filter(self)
    if not ns.db then
        return false
    end
    -- cheap rejection for all the other chat windows before the (slower) usability check
    if self ~= TargetFrameRaw() and self ~= ChatFrame1 then
        return false
    end
    return self == TargetFrame()
end

-- Player as a clickable link with the FULL name (Name-Realm), so chat addons
-- (name coloring etc.) recognize the player like in a regular message.
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

local colorCodes = {}

local function PlayerLink(full, short, classFile, display)
    -- short name in the text, full name (Name-Realm) in the link
    local link = "|Hplayer:" .. full .. "|h[" .. (display or short or full) .. "]|h"
    if ns.db.classColors then
        local class = classFile
        if not class then
            _, class = UnitClass(full)
        end
        if not class and short then
            _, class = UnitClass(short)
        end
        -- the color code per class is computed once per block (cleared in RenderDrop), not once per player
        local code = class and colorCodes[class]
        if code == nil then
            local c = ClassColor(class)
            code = c and string.format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5)) or false
            if class then
                colorCodes[class] = code
            end
        end
        if code then
            return code .. link .. "|r"
        end
    end
    return link
end

-- ===== shared with the other files =====
ns.ADDON, ns.ClassColor, ns.DEFAULTS, ns.Emit = ADDON, ClassColor, DEFAULTS, Emit
ns.Filter, ns.HAS_HISTORY, ns.IsUsableWindow, ns.Parse = Filter, HAS_HISTORY, IsUsableWindow, Parse
ns.PlayerLink, ns.Print, ns.STALE_SECONDS, ns.TargetFrame = PlayerLink, Print, STALE_SECONDS, TargetFrame
ns.colorCodes, ns.items = colorCodes, items
