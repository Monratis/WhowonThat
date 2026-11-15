-- Luacheck configuration for World of Warcraft Addon
std = "lua51"

-- Ignore certain warnings common in WoW addons
ignore = {
    "212", -- Unused argument (common in WoW event handlers)
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
    "debugstack",
    "seterrorhandler",
    "geterrorhandler",
    "issecretvalue",

    -- Modern WoW APIs
    "C_LootHistory",
    "C_Timer",

    -- SavedVariables
    "WhoWonThatDB",
    "RollsOnlyDB",

    -- Global table
    "_G",
}
