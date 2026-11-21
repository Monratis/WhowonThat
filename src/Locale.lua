-- Who Won That: translations. Messages for the player (settings, chat, windows) follow the language chosen in the
-- settings (default: the game's language). Messages sent to the group are never translated: other players read them.
-- Usage: L("id") or L("id", a, b) for a format string. Count("items", n) picks the plural form of a counted noun.
local _, ns = ...

ns.locales = {} -- [locale] = { id = text, ... }, filled by src/locales/*.lua; enUS is the complete base

-- Locales that share another locale's texts
local SAME_AS = { enGB = "enUS", esMX = "esES" }

-- The languages offered in the settings, each named in itself
local LANGUAGES = {
    { "enUS", "English" }, { "deDE", "Deutsch" }, { "frFR", "Fran\195\167ais" },
    { "esES", "Espa\195\177ol" }, { "itIT", "Italiano" }, { "ptBR", "Portugu\195\170s" },
    { "ruRU", "\208\160\209\131\209\129\209\129\208\186\208\184\208\185" },
    { "koKR", "\237\149\156\234\181\173\236\150\180" }, { "zhCN", "\231\174\128\228\189\147\228\184\173\230\150\135" },
    { "zhTW", "\231\185\129\233\171\148\228\184\173\230\150\135" },
}

-- Plural category of n in a locale: "one", "few", "many" or "other"
local function PluralCategory(locale, n)
    if locale == "ruRU" then
        local m10, m100 = n % 10, n % 100
        if m10 == 1 and m100 ~= 11 then
            return "one"
        elseif m10 >= 2 and m10 <= 4 and not (m100 >= 12 and m100 <= 14) then
            return "few"
        end
        return "many"
    elseif locale == "koKR" or locale == "zhCN" or locale == "zhTW" then
        return "other"
    elseif locale == "frFR" or locale == "ptBR" then
        return (n == 0 or n == 1) and "one" or "other"
    end
    return n == 1 and "one" or "other"
end

local function GameLocale()
    local key = GetLocale and GetLocale() or "enUS"
    return SAME_AS[key] or key
end

-- The locale in use: the setting, or the game's language for "auto"; English when there is no translation.
local function Active()
    local chosen = ns.db and ns.db.language
    if not chosen or chosen == "auto" then
        chosen = GameLocale()
    end
    chosen = SAME_AS[chosen] or chosen
    return ns.locales[chosen] and chosen or "enUS"
end

local function Text(id)
    local texts = ns.locales[Active()]
    local text = texts and texts[id]
    if text == nil then
        text = ns.locales.enUS[id]
    end
    return text
end

local L = setmetatable({}, {
    __call = function(_, id, ...)
        local text = Text(id)
        if text == nil then
            return id
        end
        if select("#", ...) > 0 then
            return string.format(text, ...)
        end
        return text
    end,
})

-- "3 items" / "1 item" in the right plural form of the language in use
local function Count(id, n)
    local forms = Text(id)
    if type(forms) ~= "table" then
        return tostring(n)
    end
    local text = forms[PluralCategory(Active(), n)] or forms.other or forms.one
    return string.format(text, n)
end

-- ===== shared with the other files =====
ns.L, ns.Count, ns.LANGUAGES = L, Count, LANGUAGES
