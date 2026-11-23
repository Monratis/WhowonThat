-- Who Won That: item values for the loot summary. The prices come from a price addon (Auctionator, TradeSkillMaster,
-- AuctionDB, Naowh, Forever Ledger or Booty Bay Broker), so a value is only shown when one is installed and knows the item. Nothing is shown (and
-- nothing breaks) otherwise.
local _, ns = ...

local CALLER_ID = "WhoWonThat" -- Auctionator wants every caller of its API to name itself

local function Positive(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return type(value) == "number" and value > 0 and value < math.huge and value or nil
end

-- Price sources, tried in this order; the first one that knows the item wins. Each one is looked up when asked
-- (not at load), because the price addons may load after this one.
-- TSM price source expression (checked against TSM's own source list): the latest AuctionDB snapshot value, then
-- its minimum buyout, then the 14-day market value
local TSM_PRICE = "first(DBRecent, DBMinBuyout, DBMarket)"

local function ItemIDOf(link)
    return tonumber(link:match("item:(%d+)"))
end

local dbKeysByLink, dbKeyCount = {}, 0 -- Auctionator database keys by item link
local PROVIDERS = {
    { -- Auctionator: the last seen auction house listing
        name = "Auctionator",
        present = function()
            local auctionator = _G.Auctionator
            local api = type(auctionator) == "table" and type(auctionator.API) == "table" and auctionator.API.v1
            return type(api) == "table" and type(api.GetAuctionPriceByItemLink) == "function" and api or nil
        end,
        price = function(api, link)
            -- The way Auctionator's own tooltip does it: its database keys for the item (gear and bags can be stored
            -- under a key with the item level) and the first one that has a price. Its public API only manages that
            -- when the item data is already loaded, so the keys are kept from the first lookup that finished.
            local auctionator = _G.Auctionator
            local keyFor = type(auctionator.Utilities) == "table" and auctionator.Utilities.DBKeyFromLink
            local db = auctionator.Database
            if type(keyFor) == "function" and type(db) == "table" and type(db.GetFirstPrice) == "function" then
                if not dbKeysByLink[link] then
                    if dbKeyCount > 300 then
                        dbKeysByLink, dbKeyCount = {}, 0
                    end
                    keyFor(link, function(keys)
                        if type(keys) == "table" and #keys > 0 then
                            dbKeysByLink[link] = keys
                            dbKeyCount = dbKeyCount + 1
                        end
                    end)
                end
                local keys = dbKeysByLink[link]
                local found = keys and Positive(db:GetFirstPrice(keys))
                if found then
                    return found
                end
            end
            local price = api.GetAuctionPriceByItemLink(CALLER_ID, link)
            if Positive(price) then
                return price
            end
            -- the link lookup can come back empty (e.g. while item data is still loading) although the plain
            -- item is in the database, so ask by item ID too
            local id = tonumber(link:match("item:(%d+)"))
            return id and type(api.GetAuctionPriceByItemID) == "function" and api.GetAuctionPriceByItemID(CALLER_ID, id)
        end,
    },
    { -- TradeSkillMaster: the latest AuctionDB snapshot (the way SkillUp Forever reads it), asked by item ID
        name = "TSM",
        present = function()
            local tsm = _G.TSM_API
            return type(tsm) == "table" and type(tsm.GetCustomPriceValue) == "function" and tsm or nil
        end,
        price = function(tsm, link)
            -- TSM wants its own item string (it keeps gear versions apart); the plain "i:<id>" is the fallback.
            -- It raises an error for a string it cannot use, which the caller's pcall absorbs.
            local id = ItemIDOf(link)
            local itemString = type(tsm.ToItemString) == "function" and tsm.ToItemString(link) or nil
            local value = itemString and tsm.GetCustomPriceValue(TSM_PRICE, itemString)
            if not Positive(value) and id then
                value = tsm.GetCustomPriceValue(TSM_PRICE, "i:" .. id)
            end
            return value
        end,
    },
    { -- AuctionDB: the last price it recorded on the current auction house
        name = "AuctionDB",
        present = function()
            local db = _G.AuctionDB
            return type(db) == "table" and type(db.LastPrice) == "function" and type(db.ViewHouse) == "function" and db or nil
        end,
        price = function(db, link)
            local id = ItemIDOf(link)
            local point = id and db:LastPrice(id, db:ViewHouse())
            return type(point) == "table" and point[2] or nil
        end,
    },
    { -- Naowh Forever
        name = "Naowh",
        present = function()
            local naowh = _G.NaowhForever
            return type(naowh) == "table" and type(naowh.AuctionPrice) == "function" and naowh or nil
        end,
        price = function(naowh, link)
            local id = ItemIDOf(link)
            return id and naowh.AuctionPrice(id)
        end,
    },
    { -- Forever Ledger
        name = "Forever Ledger",
        present = function()
            local ledger = _G.ForeverLedgerAPI
            return type(ledger) == "table" and ledger.version == 1 and type(ledger.GetPrice) == "function" and ledger or nil
        end,
        price = function(ledger, link)
            local id = ItemIDOf(link)
            return id and (ledger.GetPrice(id))
        end,
    },
    { -- Booty Bay Broker: its documented price call (BootyBayBrokerAPI, API.md) - copper first, nil when it holds none
        name = "Booty Bay Broker",
        present = function()
            local api = _G.BootyBayBrokerAPI
            return type(api) == "table" and type(api.GetItemPrice) == "function" and api or nil
        end,
        price = function(api, link)
            -- a link naming one version of a piece of gear answers only that version's own figure,
            -- so ask by item ID when the link has none
            local copper = api.GetItemPrice(link)
            if not Positive(copper) then
                local id = ItemIDOf(link)
                copper = id and api.GetItemPrice(id)
            end
            return copper
        end,
    },
}

-- True when at least one supported price addon is loaded.
local function HasPriceSource()
    for _, provider in ipairs(PROVIDERS) do
        local ok, source = pcall(provider.present)
        if ok and source then
            return true
        end
    end
    return false
end

-- Price of an item link in copper from the first price addon that has one, or nil (option off, no price addon,
-- item never scanned).
local function ItemPrice(link)
    if type(link) ~= "string" or (ns.db and ns.db.showValues == false) then
        return nil
    end
    for _, provider in ipairs(PROVIDERS) do
        local ok, source = pcall(provider.present)
        if ok and source then
            local done, price = pcall(provider.price, source, link)
            price = done and Positive(price)
            if price then
                return price
            end
        end
    end
    return nil
end

-- What every price addon says about one item: { { name = "Auctionator", price = copper or nil }, ... } for the
-- addons that are loaded. Used by /wwt price to explain why an item was or was not skipped.
local function PriceReport(link)
    local report = {}
    for _, provider in ipairs(PROVIDERS) do
        local ok, source = pcall(provider.present)
        if ok and source then
            local done, price = pcall(provider.price, source, link)
            report[#report + 1] = { name = provider.name, price = done and Positive(price) or nil }
        end
    end
    return report
end

-- Copper as gold / silver / copper with the game's coin icons, or plain letters where the game has no such call.
local function FormatMoney(copper)
    local coins = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if coins then
        local ok, text = pcall(coins, copper)
        if ok and type(text) == "string" then
            return text
        end
    end
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if rest > 0 or #parts == 0 then
        parts[#parts + 1] = rest .. "c"
    end
    return table.concat(parts, " ")
end

-- Total value of the items of a run that the window shows, and how many of them had a price.
local function RunValue(run, mineOnly)
    local total, priced = 0, 0
    for _, d in ipairs(run.drops) do
        if not mineOnly or d.player.isSelf then
            local price = ItemPrice(d.item)
            if price then
                total, priced = total + price, priced + 1
            end
        end
    end
    return total, priced
end

-- ===== shared with the other files =====
ns.FormatMoney, ns.HasPriceSource, ns.ItemPrice, ns.PriceReport, ns.RunValue = FormatMoney, HasPriceSource, ItemPrice, PriceReport, RunValue
