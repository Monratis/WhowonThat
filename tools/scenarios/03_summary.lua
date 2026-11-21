-- Dungeon loot summary: run tracking, end-of-dungeon detection, pop-up button and window.
local World = require("world")
local item = World.item

local DUNGEON = { name = "Deadmines", id = 36, type = "party", mapID = 10, journalID = 63,
    encounters = { { id = 1, name = "Glubtok" }, { id = 2, name = "Cookie" } } }

local TEMPLE = { name = "Sunken Temple", id = 109, type = "party", mapID = 109, journalID = 237,
    encounters = { { id = 3584, name = "Shade of Eranikus" } } }

local function setup(w, summary, dungeon)
    local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = { summary = summary or "everyone" } })
    local b = w:addClient({ name = "Brakk", class = "WARRIOR" })
    local s = w:addClient({ name = "Seluna", class = "PRIEST" })
    w:formGroup({ me, b, s }, "instance")
    w:enterInstance({ me, b, s }, dungeon or DUNGEON)
    return me, b, s
end

local function kill(w, c, id, name)
    for _, x in ipairs(w.clients) do x.fire("ENCOUNTER_END", id, name, 1, 5, 1) end
end

return {
    { "wins are recorded and the pop-up button appears after the last boss", function(w, t)
        local me = setup(w)
        w:encounter(1, "Glubtok")
        w:drop(1, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):roll("Monra", "greed", 20):finish("Brakk")
        w:advance(6)
        w:encounter(2, "Cookie")
        w:drop(2, item(12640, "Lionheart Helm")):roll("Monra", "need", 90):finish("Monra")
        kill(w, me, 167, "Edwin VanCleef")
        w:advance(30)
        local screen = World.screen(me)
        t.ok(screen:find("Worn Shortsword", 1, true) or screen:find("Deadmines", 1, true)
            or screen:find("loot", 1, true), "something about the run must be on screen:\n" .. screen)
    end },

    { "last boss reported with fight ID 0: the book recognizes it by name", function(w, t)
        local me = setup(w)
        w:encounter(2, "Cookie")
        w:drop(2, item(12640, "Lionheart Helm")):roll("Monra", "need", 90):finish("Monra")
        kill(w, me, 0, "Edwin VanCleef")
        w:advance(30)
        t.has(World.screen(me), "Lionheart Helm")
    end },

    { "a middle boss with fight ID 0 does not end the dungeon", function(w, t)
        local me = setup(w)
        w:encounter(2, "Cookie")
        w:drop(2, item(12640, "Lionheart Helm")):roll("Monra", "need", 90):finish("Monra")
        kill(w, me, 0, "Gilnid")
        w:advance(30)
        t.eq(World.screen(me):find("Lionheart Helm", 1, true), nil)
    end },

    { "a known dungeon's side boss that the journal lists last does not end the dungeon", function(w, t)
        local me = setup(w)
        w:encounter(2, "Cookie")
        w:drop(2, item(12640, "Lionheart Helm")):roll("Monra", "need", 90):finish("Monra")
        kill(w, me, 2, "Cookie")
        w:advance(40)
        t.lacks(World.screen(me), "Deadmines")
    end },

    { "Ragefire Chasm ends only when all four bosses are down", function(w, t)
        local rfc = { name = "Ragefire Chasm", id = 389, type = "party", mapID = 213, journalID = 226,
            encounters = { { id = 430, name = "Oggleflint" } } }
        local me = setup(w, nil, rfc)
        w:encounter(433, "Bazzalan")
        w:drop(433, item(12640, "Lionheart Helm")):roll("Monra", "need", 90):finish("Monra")
        kill(w, me, 430, "Oggleflint")
        kill(w, me, 431, "Taragaman the Hungerer")
        kill(w, me, 432, "Jergosh the Invoker")
        w:advance(40)
        t.lacks(World.screen(me), "Ragefire")
        kill(w, me, 433, "Bazzalan")
        w:advance(30)
        t.has(World.screen(me), "Ragefire")
    end },

    { "no fight events: the combat message 'Edwin VanCleef dies.' ends the dungeon", function(w, t)
        local me = setup(w)
        w:encounter(2, "Cookie")
        w:drop(2, item(12640, "Lionheart Helm")):roll("Monra", "need", 90):finish("Monra")
        me.fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Edwin VanCleef dies.")
        w:advance(30)
        t.has(World.screen(me), "Lionheart Helm")
    end },

    { "/wwt test opens the sample summary without errors", function(w, t)
        local me = w:addClient({ name = "Monra", class = "MAGE" })
        me.slash("/wwt test")
        w:advance(2)
        t.has(World.chatText(me, 1), "TEST finished")
    end },

    { "summary off: nothing is shown at the end", function(w, t)
        local me = setup(w, "off")
        w:encounter(2, "Cookie")
        w:drop(2, item(25, "Worn Shortsword")):roll("Monra", "need", 90):finish("Monra")
        kill(w, me, 167, "Edwin VanCleef")
        w:advance(40)
        t.eq(World.screen(me):find("Worn Shortsword", 1, true), nil)
    end },

    { "leaving the dungeon mid-run does not error", function(w, t)
        local me, b, s = setup(w)
        w:encounter(1, "Glubtok")
        w:drop(1, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
        w:advance(6)
        w:enterInstance({ me, b, s }, nil)
        w:leaveGroup(me)
        w:advance(30)
    end },
}
