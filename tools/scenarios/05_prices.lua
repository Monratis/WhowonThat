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
            env.TSM_API = { GetCustomPriceValue = function(source, item) return item == "i:12640" and 20000 or nil end }
        end)
        t.has(World.screen(me), "2g")
    end },

    { "Booty Bay Broker only: its price call is used, by item ID when the link has no figure", function(w, t)
        local me = run(w, nil, nil, function(env)
            env.BootyBayBrokerAPI = { VERSION = 1, GetItemPrice = function(item)
                if item == 12640 then return 30000, "scan", 60 end
                return nil
            end }
        end)
        t.has(World.screen(me), "3g")
    end },

    { "Auctionator: a price stored under the item-level key is found like in its tooltip", function(w, t)
        local me = run(w, nil, nil, function(env)
            env.Auctionator = {
                API = { v1 = { GetAuctionPriceByItemLink = function() return nil end } },
                Utilities = { DBKeyFromLink = function(link, cb) cb(link:find("12640", 1, true) and { "g:12640:30", "12640" } or { "25" }) end },
                Database = { GetFirstPrice = function(_, keys) return keys[1] == "g:12640:30" and 50000 or nil end },
            }
        end)
        t.has(World.screen(me), "5g")
    end },

    { "Naowh Forever only: its auction price is used", function(w, t)
        local me = run(w, nil, nil, function(env)
            env.NaowhForever = { AuctionPrice = function(id) return id == 12640 and 40000 or nil end }
        end)
        t.has(World.screen(me), "4g")
    end },

    { "Forever Ledger only: its price is used", function(w, t)
        local me = run(w, nil, nil, function(env)
            env.ForeverLedgerAPI = { version = 1, GetPrice = function(id) return id == 12640 and 60000 or nil end }
        end)
        t.has(World.screen(me), "6g")
    end },

    { "AuctionDB only: its last price is used", function(w, t)
        local me = run(w, nil, nil, function(env)
            env.AuctionDB = { ViewHouse = function() return "house" end,
                LastPrice = function(_, id) return id == 12640 and { 1, 70000 } or nil end }
        end)
        t.has(World.screen(me), "7g")
    end },
}
