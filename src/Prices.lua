-- Who Won That: item values for the loot summary. The prices come from the Auctionator addon's database, so a value
-- is only shown when Auctionator is installed and has scanned the item. Nothing is shown (and nothing breaks) otherwise.
local _, ns = ...

local CALLER_ID = "WhoWonThat" -- Auctionator wants every caller of its API to name itself

-- Auction house price of an item link in copper, or nil (option off, no Auctionator, item never scanned).
local function ItemPrice(link)
    if type(link) ~= "string" or (ns.db and ns.db.showValues == false) then
        return nil
    end
    local auctionator = _G.Auctionator
    local api = type(auctionator) == "table" and type(auctionator.API) == "table" and auctionator.API.v1
    if type(api) ~= "table" or type(api.GetAuctionPriceByItemLink) ~= "function" then
        return nil
    end
    local ok, price = pcall(api.GetAuctionPriceByItemLink, CALLER_ID, link)
    if ok and type(price) == "number" and price > 0 then
        return price
    end
    return nil
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
ns.ItemPrice, ns.FormatMoney, ns.RunValue = ItemPrice, FormatMoney, RunValue
