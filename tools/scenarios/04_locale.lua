-- Language of the addon's own messages: follows the game language, can be overridden, group messages stay English.
local World = require("world")
local item = World.item

local function helpText(opts)
    local c = opts.client
    c.slash("/wwt help")
    return World.chatText(c, 1)
end

return {
    { "English client: messages are English", function(w, t)
        local c = w:addClient({ name = "Monra", class = "MAGE" })
        t.has(helpText({ client = c }), "open the settings panel")
    end },

    { "German client: messages follow the game language", function(w, t)
        local c = w:addClient({ name = "Monra", class = "MAGE", locale = "deDE" })
        t.has(helpText({ client = c }), "Einstellungen")
    end },

    { "Mexican Spanish client uses the Spanish texts", function(w, t)
        local c = w:addClient({ name = "Monra", class = "MAGE", locale = "esMX" })
        t.has(helpText({ client = c }), "Configuración")
    end },

    { "a language without translation falls back to English", function(w, t)
        local c = w:addClient({ name = "Monra", class = "MAGE", locale = "xxXX" })
        t.has(helpText({ client = c }), "open the settings panel")
    end },

    { "the language setting overrides the game language", function(w, t)
        local c = w:addClient({ name = "Monra", class = "MAGE", locale = "deDE",
            savedVariables = { language = "frFR" } })
        local text = helpText({ client = c })
        t.has(text, "Paramètres")
        t.lacks(text, "Einstellungen")
    end },

    { "English chosen on a German client", function(w, t)
        local c = w:addClient({ name = "Monra", class = "MAGE", locale = "deDE",
            savedVariables = { language = "enUS" } })
        t.has(helpText({ client = c }), "open the settings panel")
    end },

    { "the message sent to the group stays English on a translated client", function(w, t)
        local names = { { "Monra", "MAGE" }, { "Brakk", "WARRIOR" } }
        local list = {}
        for i, n in ipairs(names) do
            list[i] = w:addClient({ name = n[1], class = n[2], locale = "deDE",
                savedVariables = { announce = "all" } })
        end
        w:formGroup(list)
        w:encounter(100, "Hogger")
        local d = w:drop(100, item(25, "Worn Shortsword"))
        d:roll("Brakk", "need", 74):roll("Monra", "greed", 20)
        d:finish("Brakk")
        w:advance(10)
        local said = {}
        for _, c in ipairs(list) do
            for _, m in ipairs(c.sent) do said[#said + 1] = m.text end
        end
        t.has(table.concat(said, " | "), "won by")
    end },
}
