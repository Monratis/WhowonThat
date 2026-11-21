-- Loot rolls in a 5-player group, seen from one player's client.
local World = require("world")
local item = World.item

return {
    { "a finished roll prints one readable block in the chosen window", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = { frame = 3 } })
        local b = w:addClient({ name = "Brakk", class = "WARRIOR" })
        local s = w:addClient({ name = "Seluna", class = "PRIEST" })
        w:formGroup({ me, b, s })
        w:encounter(100, "Hogger")
        local sword = item(25, "Worn Shortsword")
        local d = w:drop(100, sword)
        d:roll("Brakk", "need", 74):roll("Seluna", "greed", 55):roll("Monra", "pass")
        d:finish("Brakk")
        w:advance(10)
        local text = World.chatText(me, 3, true)
        t.has(text, "Loot from: Hogger")
        t.has(text, "[Worn Shortsword]")
        t.has(text, "Brakk")
        t.has(text, "WON")
        t.has(text, "74")
        t.has(text, "Seluna")
        -- raw Blizzard lines are hidden in that window, shown elsewhere
        t.count(World.rawLines(me, 3), 0, "raw lines in the addon window")
        t.ok(#World.rawLines(me, 1) > 0, "raw lines must still appear in the main window")
    end },

    { "the winner line comes before the others, need before greed", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = { frame = 3 } })
        w:addClient({ name = "Brakk", class = "WARRIOR" })
        w:addClient({ name = "Seluna", class = "PRIEST" })
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Seluna", "greed", 99):roll("Brakk", "need", 10):finish("Brakk")
        w:advance(10)
        local text = World.chatText(me, 3)
        local won, sel = text:find("Brakk]  WON", 1, true), text:find("Seluna", 1, true)
        t.ok(won and sel and won < sel, "winner first:\n" .. text)
    end },

    { "everyone passed", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = { frame = 3 } })
        w:addClient({ name = "Brakk", class = "WARRIOR" })
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "pass"):roll("Monra", "pass"):allPassed()
        w:advance(10)
        t.has(World.chatText(me, 3), "Nobody wanted it")
    end },

    { "a drop is printed once even if updates repeat", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = { frame = 3 } })
        w:addClient({ name = "Brakk", class = "WARRIOR" })
        w:encounter(100, "Hogger")
        local d = w:drop(100, item(25, "Worn Shortsword"))
        d:roll("Brakk", "need", 50):roll("Monra", "greed", 20):finish("Brakk")
        w:advance(10)
        for _ = 1, 3 do me.fire("LOOT_HISTORY_UPDATE_DROP", 100, d.key) end
        w:advance(10)
        local n = 0
        for _, l in ipairs(World.chat(me, 3)) do if World.plain(l):find("Worn Shortsword", 1, true) then n = n + 1 end end
        t.eq(n, 1, "blocks for the item")
    end },

    { "ninja loot: a Need on armor the class cannot wear is flagged", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = { frame = 3 },
            items = { [12640] = { classID = 4, subClassID = 4, equipLoc = "INVTYPE_HEAD" } } }) -- plate
        w:addClient({ name = "Seluna", class = "PRIEST" })
        w:encounter(100, "Hogger")
        w:drop(100, item(12640, "Lionheart Helm")):roll("Seluna", "need", 80):finish("Seluna")
        w:advance(10)
        t.has(World.chatText(me, 3), "NINJA LOOT")
    end },

    { "no loot history: rolls are assembled from chat messages", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = { frame = 3 }, noLootHistory = true })
        local g = me.env
        local pl = function(n) return "|Hplayer:" .. n .. "-Testrealm:1|h[" .. n .. "]|h" end
        local link = item(25, "Worn Shortsword")
        me.fire("CHAT_MSG_LOOT", string.format(g.LOOT_ROLL_NEED, pl("Brakk"), link))
        me.fire("CHAT_MSG_LOOT", string.format(g.LOOT_ROLL_ROLLED_NEED, 74, link, pl("Brakk")))
        me.fire("CHAT_MSG_LOOT", string.format(g.LOOT_ROLL_WON, pl("Brakk"), link))
        w:advance(10)
        local text = World.chatText(me, 3)
        t.has(text, "Brakk")
        t.has(text, "WON")
    end },
}
