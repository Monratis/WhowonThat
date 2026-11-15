-- Luacheck configuration for WoW Forever (Midnight engine, Lua 5.4)
std = "lua54"
max_line_length = false
unused = false
allow_defined_top = true

-- Ignore certain warnings common in WoW addons
ignore = {
    "212", -- Unused argument (common in WoW event handlers)
    "11", -- undefined / non-standard globals: the WoW API has thousands of globals, not all listed here
    "14", -- undefined fields of globals (Settings.*, C_LootHistory.* ...)
    "4", -- shadowing
    "6", -- whitespace
}

-- WoW Engine and Addon globals
globals = {
    -- WoW Engine & UI
    "CreateFrame",
    "DEFAULT_CHAT_FRAME",
    "NUM_CHAT_WINDOWS",
    "ChatTypeInfo",
    "Settings",
    "SlashCmdList",
    "SLASH_WHOWONTHAT1",
    "SLASH_WHOWONTHAT2",
    "UnitName",
    "GetRealmName",
    "GetNormalizedRealmName",
    "GetItemInfo",
    "wipe",
    "date",
    "time",
    "issecretvalue",

    -- Modern WoW APIs
    "C_LootHistory",
    "C_Timer",

    -- SavedVariables
    "WhoWonThatDB",

    -- Global table
    "_G",
}
