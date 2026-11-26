-- The roll window: live rolls, the winner, the board between rolls, and the chat staying quiet by default.
local World = require("world")
local item = World.item

local DUNGEON = { name = "Deadmines", id = 36, type = "party", mapID = 10, journalID = 63,
    encounters = { { id = 1, name = "Glubtok" }, { id = 2, name = "Cookie" } } }

local function group(w, sv, inside)
    sv = sv or {}
    local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = sv })
    local b = w:addClient({ name = "Brakk", class = "WARRIOR" })
    local s = w:addClient({ name = "Seluna", class = "PRIEST" })
    w:formGroup({ me, b, s }, inside and "instance" or nil)
    if inside then
        w:enterInstance({ me, b, s }, DUNGEON)
    end
    return me, b, s
end

local function window(c)
    return c.env.WhoWonThatRollWindow
end

local function shown(c)
    local f = window(c)
    return f ~= nil and f:IsShown()
end

return {
    { "by default a result goes to the roll window, not to the chat", function(w, t)
        local me = group(w)
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):roll("Seluna", "greed", 55)
            :roll("Monra", "pass"):finish("Brakk")
        w:advance(4)
        t.eq(World.chatText(me, 3), "", "nothing in the chat window")
        t.ok(shown(me), "the roll window must be open")
        local screen = World.screen(me)
        t.has(screen, "Worn Shortsword")
        t.has(screen, "Brakk wins!")
        t.has(screen, "74")
        t.lacks(screen, "55") -- Greed does not count once someone needs
    end },

    { "a roll in progress is shown live, the winner only after the numbers landed", function(w, t)
        local me = group(w)
        w:encounter(100, "Hogger")
        local d = w:drop(100, item(25, "Worn Shortsword"))
        d:roll("Brakk", "need", 74)
        w:advance(0.5)
        t.ok(shown(me), "opens as soon as the roll starts")
        t.has(World.screen(me), "Brakk")
        d:roll("Seluna", "need", 80):roll("Monra", "greed", 12)
        w:advance(0.3)
        d:finish("Seluna")
        w:advance(0.3)
        t.lacks(World.screen(me), "Seluna wins!") -- still spinning
        w:advance(4)
        t.has(World.screen(me), "Seluna wins!")
    end },

    { "in a dungeon the board lists the group with what they won", function(w, t)
        local me = group(w, nil, true)
        w:advance(1)
        t.ok(shown(me), "the board opens in a dungeon")
        t.has(World.screen(me), "No loot yet")
        w:encounter(1, "Glubtok")
        w:drop(1, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
        w:advance(15)
        local screen = World.screen(me)
        t.has(screen, "Who Won That")
        t.has(screen, "Seluna") -- members without loot are listed too
        t.has(screen, "Brakk")
        t.has(screen, "74")
        t.lacks(screen, "No loot yet")
    end },

    { "outside an instance the window fades away after the result", function(w, t)
        local me = group(w)
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
        w:advance(4)
        t.ok(shown(me), "shown for the result")
        w:advance(10)
        t.ok(not shown(me), "gone after the result was shown")
    end },

    { "several drops are shown one after the other", function(w, t)
        local me = group(w)
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
        w:drop(100, item(26, "Rusty Hatchet")):roll("Seluna", "greed", 40):finish("Seluna")
        w:advance(1)
        local screen = World.screen(me)
        t.has(screen, "Worn Shortsword")
        t.has(screen, "+1")
        w:advance(5)
        t.has(World.screen(me), "Seluna wins!")
    end },

    { "turned off: no window at all", function(w, t)
        local me = group(w, { rollWindow = false }, true)
        w:encounter(1, "Glubtok")
        w:drop(1, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
        w:advance(10)
        t.ok(not shown(me), "no roll window")
    end },

    { "closed in a dungeon it stays closed until the next roll", function(w, t)
        local me = group(w, nil, true)
        w:advance(1)
        window(me).close:GetScript("OnClick")(window(me).close)
        w:advance(1)
        t.ok(not shown(me), "closed")
        me.fire("ZONE_CHANGED_NEW_AREA")
        w:advance(1)
        t.ok(not shown(me), "a zone change does not bring the board back")
        w:encounter(1, "Glubtok")
        w:drop(1, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
        w:advance(2)
        t.ok(shown(me), "the next roll opens it again")
        w:advance(10)
        t.ok(not shown(me), "and after the roll the closed board stays away")
    end },

    { "/wwt demo plays a made-up roll to the end: the ninja wins", function(w, t)
        local me = group(w)
        me.env.SlashCmdList.WHOWONTHAT("demo")
        w:advance(1)
        t.ok(shown(me), "the demo opens the window")
        t.has(World.screen(me), "Lionheart Helm")
        w:advance(7)
        t.has(World.screen(me), "Seluna wins!") -- three Need, two Greed, and the priest ninjas the plate helm
        w:advance(10)
        t.ok(not shown(me), "the demo ends outside an instance")
    end },

    { "/wwt window toggles the board and reset keeps it working", function(w, t)
        local me = group(w)
        me.env.SlashCmdList.WHOWONTHAT("window")
        w:advance(1)
        t.ok(shown(me), "opened by the command")
        me.env.SlashCmdList.WHOWONTHAT("window reset")
        me.env.SlashCmdList.WHOWONTHAT("window")
        w:advance(1)
        t.ok(not shown(me), "closed by the command")
    end },

    { "your place is shown while the numbers land, and a near miss after", function(w, t)
        local me = group(w)
        w:encounter(100, "Hogger")
        local d = w:drop(100, item(25, "Worn Shortsword"))
        d:roll("Brakk", "need", 74):roll("Monra", "need", 72):roll("Seluna", "pass")
        w:advance(3)
        t.has(World.screen(me), "You: #2 of 2")
        d:finish("Brakk")
        w:advance(2)
        t.has(World.screen(me), "Missed by 2")
    end },

    { "leading shows 'You lead!'", function(w, t)
        local me = group(w)
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 10):roll("Monra", "need", 90)
            :roll("Seluna", "pass")
        w:advance(3)
        t.has(World.screen(me), "You lead!")
    end },

    { "the board keeps everyone's luck over the run", function(w, t)
        local me = group(w, nil, true)
        w:encounter(1, "Glubtok")
        local rolls = { { 80, 20 }, { 60, 30 }, { 70, 10 } }
        for i, r in ipairs(rolls) do
            w:drop(1, item(30 + i, "Thing " .. i)):roll("Brakk", "need", r[1]):roll("Monra", "need", r[2])
                :roll("Seluna", "pass"):finish("Brakk")
            w:advance(15)
        end
        local screen = World.screen(me)
        t.has(screen, "avg 70 · best 80") -- Brakk
        t.has(screen, "avg 20 · best 30") -- Monra
    end },

    { "an epic item gets the longer finale", function(w, t)
        local me = group(w)
        me.items[40] = { quality = 4 }
        w:encounter(100, "Hogger")
        w:drop(100, item(40, "Shiny Epic", "a335ee")):roll("Brakk", "need", 74):roll("Monra", "need", 20)
            :roll("Seluna", "pass"):finish("Brakk")
        w:advance(9)
        t.ok(shown(me), "still on screen thanks to the longer hold")
        t.has(World.screen(me), "Brakk wins!")
        t.eq(#me.errors, 0)
    end },

    { "announcing to the group and the roll window work together", function(w, t)
        local me = group(w, { announce = "all" })
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):roll("Monra", "need", 20)
            :roll("Seluna", "pass"):finish("Monra")
        w:advance(4)
        t.ok(shown(me), "the roll window shows the roll")
        t.has(World.screen(me), "You won it!")
        w:advance(10)
        local said = table.concat(World.said(me), " ")
        t.has(said, "Worn Shortsword") -- and the result went to party chat
        t.eq(World.chatText(me, 1), "", "nothing of my own in chat")
    end },

    { "greed players drop out as soon as someone needs", function(w, t)
        local me = group(w)
        w:encounter(100, "Hogger")
        local d = w:drop(100, item(25, "Worn Shortsword"))
        d:roll("Seluna", "greed"):roll("Brakk", "need", 74):roll("Monra", "need", 30)
        w:advance(4)
        local screen = World.screen(me)
        t.lacks(screen, "Choosing") -- nobody is left to wait for
        t.has(screen, "You: #2 of 2") -- the race is between the two Need rolls only
        d:finish("Brakk")
        w:advance(3)
        t.has(World.screen(me), "Brakk wins!")
    end },

    { "an item that is not loaded yet keeps its quality, and the window redraws when it loads", function(w, t)
        local me = group(w)
        me.slash("/wwt demo")
        w:advance(1)
        me.fire("GET_ITEM_INFO_RECEIVED", 12640, true)
        me.fire("GET_ITEM_INFO_RECEIVED", 12640, true)
        w:advance(1)
        t.has(World.screen(me), "Lionheart Helm")
    end },
}
