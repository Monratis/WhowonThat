-- Rarity effects, the roll shown from its very start, the addon's own roll buttons and loot toast, and the sounds.
local World = require("world")
local item = World.item

local DUNGEON = { name = "Deadmines", id = 36, type = "party", mapID = 10, journalID = 63,
    encounters = { { id = 1, name = "Glubtok" }, { id = 2, name = "Cookie" } } }

local EPIC = item(40, "Shiny Epic", "a335ee")

local function group(w, sv)
    local me = w:addClient({ name = "Monra", class = "MAGE", savedVariables = sv or {} })
    local b = w:addClient({ name = "Brakk", class = "WARRIOR" })
    local s = w:addClient({ name = "Seluna", class = "PRIEST" })
    w:formGroup({ me, b, s }, "instance")
    w:enterInstance({ me, b, s }, DUNGEON)
    return me, b, s
end

-- advances time and runs the roll window's and the toast's OnUpdate, the way the game draws frames
local function frames(w, me, n)
    for _ = 1, n do
        w:advance(0.05)
        for _, name in ipairs({ "WhoWonThatRollWindow", "WhoWonThatLootToast", "WhoWonThatRollButtons" }) do
            local f = me.env[name]
            local tick = f and f:IsShown() and f:GetScript("OnUpdate")
            if tick then tick(f, 0.05) end
        end
    end
end

local function shown(me, name)
    local f = me.env[name]
    return f ~= nil and f:IsVisible()
end

local function button(me, rollType)
    for _, f in ipairs(me.frames) do
        if f.def and f.def.type == rollType and f.entry then return f end
    end
end

-- SOUNDKIT names the addon played, in order
local function recordSounds(me)
    local names, played = {}, {}
    me.env.SOUNDKIT = setmetatable({}, { __index = function(tbl, k)
        local id = #names + 1
        names[id] = k
        rawset(tbl, k, id)
        return id
    end })
    me.env.PlaySound = function(id) played[#played + 1] = names[id] end
    return played
end

local function has(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

return {
    { "every quality plays its finale frame by frame without errors", function(w, t)
        local me = group(w)
        for _, q in ipairs({ "poor", "common", "uncommon", "rare", "epic", "legendary" }) do
            me.slash("/wwt demo " .. q .. " win")
            frames(w, me, 320)
        end
        t.eq(#me.errors, 0)
    end },

    { "a legendary you win: the window says so and the addon's toast shows it", function(w, t)
        local me = group(w)
        me.slash("/wwt demo legendary win")
        frames(w, me, 200)
        local screen = World.screen(me)
        t.has(screen, "Thunderfury")
        t.has(screen, "Legendary")
        t.has(screen, "You won it!")
        t.ok(shown(me, "WhoWonThatLootToast"), "the toast is up")
        t.has(screen, "You won |", "the toast's title")
        t.eq(#me.errors, 0)
    end },

    { "the toast can be turned off", function(w, t)
        local me = group(w, { wonToast = false })
        me.slash("/wwt demo epic win")
        frames(w, me, 160)
        t.has(World.screen(me), "You won it!")
        t.ok(not shown(me, "WhoWonThatLootToast"))
    end },

    { "the window opens when the roll starts, with the group waiting, and joins the loot history's drop", function(w, t)
        local me = group(w)
        w:encounter(100, "Hogger")
        me.startRoll(7, EPIC, 60)
        w:advance(0.3)
        local screen = World.screen(me)
        t.has(screen, "Shiny Epic", "shown before anyone chose")
        t.has(screen, "Brakk")
        t.has(screen, "Seluna")
        local d = w:drop(100, EPIC)
        d:roll("Brakk", "need", 74):roll("Seluna", "greed"):roll("Monra", "need", 20)
        w:advance(0.5)
        t.lacks(World.screen(me), "+1", "one drop on screen, not two")
        d:finish("Brakk")
        me.endRoll(7)
        frames(w, me, 140)
        t.has(World.screen(me), "Brakk wins!")
        t.eq(#me.errors, 0)
    end },

    { "a roll the loot history never reports is given up", function(w, t)
        local me = group(w)
        me.startRoll(8, EPIC, 60)
        w:advance(0.5)
        t.has(World.screen(me), "Shiny Epic")
        me.endRoll(8)
        w:advance(10)
        t.lacks(World.screen(me), "Shiny Epic")
    end },

    { "the addon's roll buttons replace the game's roll popups", function(w, t)
        local me = group(w)
        w:advance(0.1)
        t.ok(me.closedEvents.START_LOOT_ROLL, "the game's popup route is closed")
        me.startRoll(9, EPIC, 60)
        t.ok(shown(me, "WhoWonThatRollButtons"), "the addon's buttons are up")
        local need = button(me, 1)
        t.ok(need ~= nil, "a Need button")
        need:GetScript("OnClick")(need)
        t.eq(me.rolledOn[1] and me.rolledOn[1].id, 9)
        t.eq(me.rolledOn[1] and me.rolledOn[1].kind, 1)
        frames(w, me, 30)
        t.ok(not shown(me, "WhoWonThatRollButtons"), "the row leaves after you chose")
        t.eq(#me.errors, 0)
    end },

    { "Need is refused when the game says this character cannot need", function(w, t)
        local me = group(w)
        w:advance(0.1)
        me.startRoll(10, EPIC, 60, { canNeed = false })
        local need = button(me, 1)
        need:GetScript("OnClick")(need)
        t.eq(#me.rolledOn, 0)
        local greed = button(me, 2)
        greed:GetScript("OnClick")(greed)
        t.eq(me.rolledOn[1] and me.rolledOn[1].kind, 2)
    end },

    { "a bind on pickup pick counts once it is confirmed", function(w, t)
        local me = group(w)
        w:advance(0.1)
        me.startRoll(12, EPIC, 60, { bop = true })
        local need = button(me, 1)
        need:GetScript("OnClick")(need)
        frames(w, me, 30)
        t.ok(shown(me, "WhoWonThatRollButtons"), "still there while the game asks to confirm")
        me.env.ConfirmLootRoll(12, 1)
        frames(w, me, 30)
        t.ok(not shown(me, "WhoWonThatRollButtons"))
    end },

    { "with the roll buttons off the game's popups stay", function(w, t)
        local me = group(w, { rollButtons = false })
        w:advance(0.1)
        t.ok(not me.closedEvents.START_LOOT_ROLL)
        me.startRoll(11, EPIC, 60)
        t.ok(not shown(me, "WhoWonThatRollButtons"))
    end },

    { "the game's toast for a won roll is put away, an item the window skips keeps it", function(w, t)
        local me = group(w)
        local active = {}
        local system = { alertFramePool = { EnumerateActive = function()
            local i = 0
            return function() i = i + 1; return active[i] end
        end } }
        function system:ShowAlert(link)
            local f = me.makeFrame("Frame", nil, me.env.UIParent)
            f.hyperlink = link
            active[#active + 1] = f
        end
        me.env.LootAlertSystem = system
        w:advance(0.1)
        me.fire("LOOT_ITEM_ROLL_WON", EPIC, 1, 1, 80)
        me.env.LootAlertSystem:ShowAlert(EPIC, 1, 1, 80)
        t.ok(not active[1]:IsShown(), "our toast shows this win")
        local diamond = item(11754, "Black Diamond")
        me.fire("LOOT_ITEM_ROLL_WON", diamond, 1, 2, 40)
        me.env.LootAlertSystem:ShowAlert(diamond, 1, 2, 40)
        t.ok(active[2]:IsShown(), "an ignored item keeps the game's toast")
        me.env.LootAlertSystem:ShowAlert(EPIC, 1)
        t.ok(active[3]:IsShown(), "a toast that is not a roll win stays")
    end },

    { "the win sound when you win, another one when you rolled and lost, the coin when you passed", function(w, t)
        local me = group(w)
        local played = recordSounds(me)
        w:encounter(100, "Hogger")
        w:drop(100, item(25, "Worn Shortsword")):roll("Brakk", "need", 30):roll("Monra", "need", 80)
            :roll("Seluna", "pass"):finish("Monra")
        frames(w, me, 120)
        t.ok(has(played, "UI_EPICLOOT_TOAST"), "your win")
        for i = #played, 1, -1 do played[i] = nil end
        w:drop(100, item(26, "Worn Axe")):roll("Brakk", "need", 90):roll("Monra", "need", 10)
            :roll("Seluna", "pass"):finish("Brakk")
        frames(w, me, 300)
        t.ok(has(played, "IG_QUEST_LOG_ABANDON_QUEST"), "your loss")
        t.ok(not has(played, "UI_EPICLOOT_TOAST"))
        for i = #played, 1, -1 do played[i] = nil end
        w:drop(100, item(27, "Worn Mace")):roll("Brakk", "need", 90):roll("Monra", "pass")
            :roll("Seluna", "pass"):finish("Brakk")
        frames(w, me, 300)
        t.ok(has(played, "LOOT_WINDOW_COIN_SOUND"), "not yours")
        t.ok(not has(played, "IG_QUEST_LOG_ABANDON_QUEST"))
    end },

    { "an expensive item shows its value and counts it up after the win", function(w, t)
        local me = group(w)
        me.env.ForeverLedgerAPI = { version = 1, GetPrice = function(id) return id == 41 and 3000000 or nil end }
        w:encounter(100, "Hogger")
        w:drop(100, item(41, "Pricey Green", "1eff00")):roll("Brakk", "need", 30):roll("Monra", "need", 80)
            :roll("Seluna", "pass"):finish("Monra")
        frames(w, me, 160)
        t.has(World.screen(me), "300g")
        t.eq(#me.errors, 0)
    end },
}
