-- Loot rolls in a group, seen from one player's client: the game's roll lines leave the chat, the roll window
-- shows the result.
local World = require("world")
local item = World.item

local function shown(c)
    local f = c.env.WhoWonThatRollWindow
    return f ~= nil and f:IsShown()
end

return {
    { "the game's roll lines are hidden in every chat window, other loot messages stay", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE" })
        local b = w:addClient({ name = "Brakk", class = "WARRIOR" })
        w:formGroup({ me, b })
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):roll("Monra", "pass"):finish("Brakk")
        w:advance(3)
        for i = 1, 3 do
            t.count(World.rawLines(me, i), 0, "raw roll lines in window " .. i)
            t.count(World.chat(me, i), 0, "addon lines in window " .. i)
        end
        t.ok(not me.chatHidden("CHAT_MSG_LOOT", me.env.ChatFrame1, "You receive loot: " .. item(26, "Rusty Hatchet") .. "."),
            "a picked up item still shows in chat")
        t.has(World.screen(me), "Brakk wins!")
    end },

    { "with the roll window off, the game's roll lines stay in chat", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = { rollWindow = false } })
        local b = w:addClient({ name = "Brakk", class = "WARRIOR" })
        w:formGroup({ me, b })
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
        w:advance(3)
        t.ok(#World.rawLines(me, 1) > 0, "raw roll lines must stay when the window is off")
        t.ok(not shown(me), "no window")
    end },

    { "everyone passed", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE" })
        w:addClient({ name = "Brakk", class = "WARRIOR" })
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "pass"):roll("Monra", "pass"):allPassed()
        w:advance(2)
        t.has(World.screen(me), "Everyone passed")
    end },

    { "a finished drop is not shown again when updates repeat", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE" })
        w:addClient({ name = "Brakk", class = "WARRIOR" })
        w:encounter(100, "Hogger")
        local d = w:drop(100, item(25, "Worn Shortsword"))
        d:roll("Brakk", "need", 50):roll("Monra", "greed", 20):finish("Brakk")
        w:advance(15)
        t.ok(not shown(me), "gone after the result")
        for _ = 1, 3 do me.fire("LOOT_HISTORY_UPDATE_DROP", 100, d.key) end
        w:advance(2)
        t.ok(not shown(me), "repeated updates do not bring it back")
    end },

    { "no loot history: rolls are assembled from chat messages", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE", noLootHistory = true })
        local g = me.env
        local pl = function(n) return "|Hplayer:" .. n .. "-Testrealm:1|h[" .. n .. "]|h" end
        local link = item(25, "Worn Shortsword")
        me.fire("CHAT_MSG_LOOT", string.format(g.LOOT_ROLL_NEED, pl("Brakk"), link))
        me.fire("CHAT_MSG_LOOT", string.format(g.LOOT_ROLL_ROLLED_NEED, 74, link, pl("Brakk")))
        me.fire("CHAT_MSG_LOOT", string.format(g.LOOT_ROLL_WON, pl("Brakk"), link))
        w:advance(3)
        local screen = World.screen(me)
        t.has(screen, "Worn Shortsword")
        t.has(screen, "Brakk wins!")
    end },
}
