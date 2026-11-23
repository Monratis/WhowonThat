-- Item values in the loot summary window, from Auctionator's price database when it is installed.
local World = require("world")
local item = World.item

local DUNGEON = { name = "Deadmines", id = 36, type = "party", mapID = 10, journalID = 63,
    encounters = { { id = 1, name = "Glubtok" }, { id = 2, name = "Cookie" } } }

local function run(w, savedVariables, auctionator, setup)
    local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = savedVariables or {} })
    local b = w:addClient({ name = "Brakk", class = "WARRIOR" })
    w:formGroup({ me, b }, "instance")
    w:enterInstance({ me, b }, DUNGEON)
    if auctionator then
        me.env.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = auctionator } } }
    end
    if setup then
        setup(me.env)
    end
    w:encounter(2, "Cookie")
    w:drop(2, item(12640, "Lionheart Helm")):roll("Monra", "need", 90):finish("Monra")
    w:drop(2, item(25, "Worn Shortsword")):roll("Brakk", "need", 74):finish("Brakk")
    w:advance(10) -- the wins are recorded a moment after the rolls end
    me.slash("/wwt summary")
    w:advance(2)
    return me
end

local function price(callerID, link)
    if link:find("12640", 1, true) then return 12345 end -- 1g 23s 45c
    return nil                                         -- the sword was never scanned
end

return {
    { "Auctionator installed: the window shows the total of the scanned items", function(w, t)
        local me = run(w, nil, price)
        t.has(World.screen(me), "1g 23s 45c")
    end },

    { "the Auctionator API is called with the addon's own caller ID", function(w, t)
        local seen
        local me = run(w, nil, function(callerID, link) seen = callerID return 100 end)
        t.eq(seen, "WhoWonThat")
        t.has(World.screen(me), "Total value")
    end },

    { "no Auctionator: no value line and no error", function(w, t)
        local me = run(w)
        t.has(World.screen(me), "2 items")
        t.lacks(World.screen(me), "Total value")
    end },

    { "Auctionator without a scanned price shows nothing", function(w, t)
        local me = run(w, nil, function() return nil end)
        t.has(World.screen(me), "2 items")
        t.lacks(World.screen(me), "Total value")
    end },

    { "the option 'show item values' off hides the total", function(w, t)
        local me = run(w, { showValues = false }, price)
        t.has(World.screen(me), "2 items")
        t.lacks(World.screen(me), "Total value")
    end },

    { "values follow the language of the addon", function(w, t)
        local me = run(w, { language = "deDE" }, price)
        t.has(World.screen(me), "Gesamtwert")
    end },

    { "TSM only: the market value is used", function(w, t)
        local me = run(w, nil, nil, function(env)
            env.TSM_API = { ToItemString = function(link) return link end,
                GetCustomPriceValue = function(source, link) return link:find("12640", 1, true) and 20000 or nil end }
        end)
        t.has(World.screen(me), "2g")
    end },

    { "Booty Bay Broker only: its unit value is used", function(w, t)
        local me = run(w, nil, nil, function(env)
            local broker = { ItemUnitValue = function(_, id) return id == 12640 and 30000 or nil end }
            env.LibStub = function() return { GetAddon = function() return broker end } end
        end)
        t.has(World.screen(me), "3g")
    end },
}
