-- Group announcements and addon-to-addon coordination: several clients, all running the addon.
local World = require("world")
local item = World.item

local function group(w, announceFlags)
    local names = { { "Monra", "MAGE" }, { "Brakk", "WARRIOR" }, { "Seluna", "PRIEST" } }
    local list = {}
    for i, n in ipairs(names) do
        list[i] = w:addClient({ name = n[1], class = n[2],
            savedVariables = { announce = announceFlags[i] and "all" or "off" } })
    end
    w:formGroup(list)
    w:encounter(100, "Hogger")
    return list[1], list[2], list[3]
end

local function lootBlock(w, winner)
    local d = w:drop(100, item(25, "Worn Shortsword"))
    d:roll("Brakk", "need", 74):roll("Seluna", "greed", 55):roll("Monra", "pass")
    d:finish(winner)
    return d
end

local function itemLines(c)
    local n = 0
    for _, m in ipairs(c.sent) do if m.text:find("Worn Shortsword", 1, true) then n = n + 1 end end
    return n
end

return {
    { "announce off: nothing is sent to the group", function(w, t)
        local me, brakk = group(w, { false, false, false })
        lootBlock(w, "Brakk")
        w:advance(20)
        t.count(me.sent, 0)
        t.count(brakk.sent, 0)
        t.has(World.chatText(me, 3), "Brakk]  WON")
    end },

    { "Auctionator: an item worth under 20 silver is not announced, but still shown locally", function(w, t)
        local me, brakk = group(w, { true, true, true })
        brakk.env.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 1999 end } } }
        lootBlock(w, "Brakk")
        w:advance(20)
        t.eq(itemLines(brakk), 0, "cheap item stays out of the group chat")
        t.has(World.chatText(brakk, 3), "Worn Shortsword")
    end },

    { "Auctionator: an item worth 20 silver or more is announced", function(w, t)
        local _, brakk = group(w, { true, true, true })
        brakk.env.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 2000 end } } }
        lootBlock(w, "Brakk")
        w:advance(20)
        t.eq(itemLines(brakk), 1)
    end },

    { "only the winner's addon announces when everyone has it on", function(w, t)
        local me, brakk, seluna = group(w, { true, true, true })
        lootBlock(w, "Brakk")
        w:advance(20)
        t.eq(itemLines(brakk), 1, "winner announces once")
        t.eq(itemLines(me), 0, "others stay quiet")
        t.eq(itemLines(seluna), 0, "others stay quiet")
        t.has(brakk.sent[1].text, "Worn Shortsword")
        t.eq(brakk.sent[1].channel, "PARTY")
    end },

    { "the claim message cancels the others at once", function(w, t)
        local me, brakk = group(w, { true, true, false })
        lootBlock(w, "Brakk")
        w:advance(3)
        local claims = 0
        for _, m in ipairs(brakk.addonMessages) do if m.text:match("^A:100:%d+:25$") then claims = claims + 1 end end
        t.eq(claims, 1, "claim sent by the winner")
        w:advance(20)
        t.eq(itemLines(me), 0, "Monra does not announce a drop that was claimed")
    end },

    { "winner without the addon: another member's addon steps in", function(w, t)
        local me, _, seluna = group(w, { true, false, true })
        lootBlock(w, "Brakk")
        w:advance(30)
        t.eq(itemLines(me) + itemLines(seluna), 1, "exactly one of them announces")
    end },

    { "a block announced by another player is not printed twice", function(w, t)
        local me, _, _ = group(w, { true, true, false })
        World.clearChat(me)
        lootBlock(w, "Brakk")
        w:advance(30)
        local n = 0
        for _, l in ipairs(World.chat(me, 3)) do if World.plain(l):find("Worn Shortsword", 1, true) then n = n + 1 end end
        t.eq(n, 0, "own block hidden when the result was announced (hideWhenAnnounced)")
    end },

    { "chat lockdown (encounter): nothing is sent, own block still appears", function(w, t)
        local me, brakk = group(w, { true, true, false })
        for _, c in ipairs({ me, brakk }) do c.locked = true end
        lootBlock(w, "Brakk")
        w:advance(30)
        t.count(brakk.sent, 0)
        t.has(World.chatText(me, 3), "Worn Shortsword")
    end },

    { "everyone passed is announced once", function(w, t)
        local me, brakk, seluna = group(w, { true, true, true })
        local d = w:drop(100, item(25, "Worn Shortsword"))
        d:roll("Brakk", "pass"):roll("Seluna", "pass"):roll("Monra", "pass"):allPassed()
        w:advance(30)
        t.eq(itemLines(me) + itemLines(brakk) + itemLines(seluna), 1)
    end },

    { "leaving the group stops announcements", function(w, t)
        local me, brakk = group(w, { true, true, false })
        w:leaveGroup(brakk)
        lootBlock(w, "Brakk")
        w:advance(30)
        t.count(brakk.sent, 0)
    end },

    { "version notice: an older copy hears about a newer one once", function(w, t)
        local a = w:addClient({ name = "Monra", class = "MAGE" })
        local b = w:addClient({ name = "Brakk", class = "WARRIOR" })
        b.toc.Version = "9.9.9" -- Brakk "runs" a newer version
        w:formGroup({ a, b })
        a.fire("CHAT_MSG_ADDON", "WWT", "V:9.9.9", "PARTY", "Brakk-Testrealm")
        a.fire("CHAT_MSG_ADDON", "WWT", "V:9.9.9", "PARTY", "Brakk-Testrealm")
        w:advance(1)
        local text = World.chatText(a, 1)
        t.has(text, "A newer version (9.9.9)")
        local n = select(2, text:gsub("A newer version", ""))
        t.eq(n, 1, "notice printed once")
    end },
}
