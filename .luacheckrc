-- Luacheck configuration for WoW Forever (Midnight engine, Lua 5.4)
std = "lua54"

-- Ignore certain warnings common in WoW addons
ignore = {
    "212", -- Unused argument (common in WoW event handlers)
    "113", -- Access to undefined global: the WoW API has thousands of globals, not all listed here
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
