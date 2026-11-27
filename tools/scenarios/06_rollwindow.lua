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
        w:advance(15)
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
        w:advance(20)
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

    { "a character's surname from the loot history does not list the player twice on the board", function(w, t)
        local me = w:addClient({ name = "Monra", surname = "Greytusk", class = "MAGE" })
        local b = w:addClient({ name = "Anton", surname = "Paladin", class = "PALADIN" })
        w:formGroup({ me, b }, "instance")
        w:enterInstance({ me, b }, DUNGEON)
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Anton", "need", 77):roll("Monra", "need", 20):finish("Anton")
        w:advance(30)
        local screen = World.screen(me)
        t.has(screen, "Anton")
        t.lacks(screen, "Paladin", "the surname is left out")
        t.lacks(screen, "Greytusk")
        t.eq(select(2, screen:gsub("Anton", "")), 1, "one row for Anton")
        t.eq(select(2, screen:gsub("Monra", "")), 1, "one row for Monra")
        t.has(screen, "avg 77")
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
        t.lacks(World.chatText(me, 1), "won by", "my own line names me, not a third person")
        t.has(World.chatText(me, 1), "You won")
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

    { "the animations (class bars and every class effect) run frame by frame without errors", function(w, t)
        local classes = { "MAGE", "WARRIOR", "ROGUE", "HUNTER", "PRIEST", "PALADIN", "DRUID", "SHAMAN", "WARLOCK" }
        local list = {}
        for i, cls in ipairs(classes) do
            list[i] = w:addClient({ name = "P" .. cls:sub(1, 1) .. cls:sub(2):lower(), class = cls })
        end
        w:formGroup(list)
        local me = list[1]
        local function frames(n)
            local f = me.env.WhoWonThatRollWindow
            for _ = 1, n do
                w:advance(0.05)
                local tick = f and f:GetScript("OnUpdate")
                if tick then tick(f, 0.05) end
            end
        end
        w:encounter(100, "Hogger")
        local d = w:drop(100, item(25, "Worn Shortsword"))
        for i, c in ipairs(list) do d:roll(c.name, "need", 100 - i * 7) end
        frames(40)
        d:finish(list[1].name)
        frames(300) -- every number spins and lands, each with its class effect, then the winner
        me.slash("/wwt demo")
        frames(240)
        t.eq(#me.errors, 0)
        t.has(World.screen(me), "wins!")
    end },
    { "one result line in your own chat, only once the winner is shown", function(w, t)
        local me = group(w)
        w:encounter(100, "Hogger")
        local d = w:drop(100, item(25, "Worn Shortsword"))
        d:roll("Brakk", "need", 74):roll("Seluna", "greed", 55):roll("Monra", "pass")
        w:advance(0.3)
        d:finish("Brakk")
        w:advance(0.3)
        t.eq(World.chatText(me, 1), "", "the chat does not give the result away while the numbers spin")
        w:advance(4)
        local chat = World.chatText(me, 1)
        t.has(chat, "[Worn Shortsword] won by Brakk (Need 74)")
        t.eq(select(2, chat:gsub("Worn Shortsword", "")), 1, "one line")
        t.eq(#World.said(me), 0, "nothing goes to the group")
    end },

    { "the result line can be turned off", function(w, t)
        local me = group(w, { chatLine = false })
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
        w:advance(15)
        t.eq(World.chatText(me, 1), "")
    end },

    { "clicking the item of a result line replays the roll", function(w, t)
        local me = group(w)
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):roll("Monra", "need", 30)
            :roll("Seluna", "pass"):finish("Brakk")
        w:advance(20)
        t.ok(not shown(me), "faded away after the result")
        me.env.SetItemRef("item:26::::::::::::::", "[Rusty Hatchet]", "LeftButton")
        w:advance(1)
        t.ok(not shown(me), "an item without a result line does nothing")
        me.env.IsShiftKeyDown = function() return true end
        me.env.SetItemRef("item:25::::::::::::::", "[Worn Shortsword]", "LeftButton")
        w:advance(1)
        t.ok(not shown(me), "shift-click only links the item")
        me.env.IsShiftKeyDown = function() return false end
        me.env.SetItemRef("item:25::::::::::::::", "[Worn Shortsword]", "LeftButton")
        me.env.SetItemRef("item:25::::::::::::::", "[Worn Shortsword]", "LeftButton")
        w:advance(0.5)
        t.ok(shown(me), "the click opens the window again")
        t.has(World.screen(me), "Worn Shortsword")
        t.lacks(World.screen(me), "+1", "a double click does not queue the replay twice")
        w:advance(4)
        t.has(World.screen(me), "Brakk wins!")
        t.eq(select(2, World.chatText(me, 1):gsub("Worn Shortsword", "")), 1, "a replay writes no second line")
        w:advance(15)
        t.ok(not shown(me), "and fades again")
        t.eq(#me.errors, 0)
    end },

    { "the fade time follows the setting", function(w, t)
        local me = group(w, { rollWinFade = 20 })
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
        w:advance(18)
        t.ok(shown(me), "still there before the set time")
        w:advance(8)
        t.ok(not shown(me), "gone after it")
    end },

    { "with fading off the window stays open until closed", function(w, t)
        local me = group(w, { rollWinFade = 0 })
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
        w:advance(60)
        t.ok(shown(me), "still open long after the result")
        t.has(World.screen(me), "Brakk") -- the board took over
        me.fire("ZONE_CHANGED_NEW_AREA")
        w:advance(1)
        t.ok(shown(me), "a zone change keeps it open")
        window(me).close:GetScript("OnClick")(window(me).close)
        w:advance(1)
        t.ok(not shown(me), "the X closes it")
    end },
}
