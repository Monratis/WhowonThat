-- Who Won That: item values for the loot summary. The prices come from a price addon (Auctionator, TradeSkillMaster
-- or Booty Bay Broker), so a value is only shown when one is installed and knows the item. Nothing is shown (and
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
local PROVIDERS = {
    { -- Auctionator: the last seen auction house listing
        name = "Auctionator",
        present = function()
            local auctionator = _G.Auctionator
            local api = type(auctionator) == "table" and type(auctionator.API) == "table" and auctionator.API.v1
            return type(api) == "table" and type(api.GetAuctionPriceByItemLink) == "function" and api or nil
        end,
        price = function(api, link)
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
    { -- TradeSkillMaster: the market value of its auction database
        name = "TSM",
        present = function()
            local tsm = _G.TSM_API
            return type(tsm) == "table" and type(tsm.ToItemString) == "function"
                and type(tsm.GetCustomPriceValue) == "function" and tsm or nil
        end,
        price = function(tsm, link)
            local token = tsm.ToItemString(link)
            return token and tsm.GetCustomPriceValue("DBMarket", token)
        end,
    },
    { -- Booty Bay Broker: its value of one item
        name = "Booty Bay Broker",
        present = function()
            local ace = _G.LibStub and _G.LibStub("AceAddon-3.0", true)
            local broker = ace and ace:GetAddon("BootyBayBroker", true)
            return broker and type(broker.ItemUnitValue) == "function" and broker or nil
        end,
        price = function(broker, link)
            local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
            local itemID = getInfo and getInfo(link)
            return itemID and broker:ItemUnitValue(itemID)
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
