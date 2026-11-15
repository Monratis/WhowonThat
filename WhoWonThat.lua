-- Who Won That - czesc startowa - laduje sie PIERWSZY (patrz WhoWonThat.toc).
-- 1) zapisuje slad, ze dodatek w ogole sie uruchomil (WhoWonThatDB.boot),
-- 2) przechwytuje KAZDY blad Lua (takze z innych dodatkow i z ladowania glownego pliku)
--    do WhoWonThatDB.errors, zeby mozna je bylo odczytac z pliku WTF po /reload.
-- Wylaczysz: /wwt debug off
WhoWonThatDB = WhoWonThatDB or {}
WhoWonThatDB.boot = "v4.0 " .. (date and date("%H:%M:%S") or "")

if seterrorhandler and geterrorhandler then
    local original = geterrorhandler()
    seterrorhandler(function(msg)
        local db = WhoWonThatDB
        if db and db.debug == true then
            local okStack, stack = pcall(debugstack, 3, 12, 0)
            local list = db.errors
            if not list then
                list = {}
                db.errors = list
            end
            local text = tostring(msg)
            local last = list[#list]
            if last and last.msg == text then
                last.count = (last.count or 1) + 1
            else
                list[#list + 1] = {
                    time = date and date("%H:%M:%S") or "",
                    msg = text,
                    stack = okStack and tostring(stack) or "",
                    count = 1,
                }
                if #list > 30 then
                    table.remove(list, 1)
                end
            end
        end
        if original then
            return original(msg)
        end
    end)
end

-- ===== koniec czesci diagnostycznej =====

-- Who Won That
-- W wybranym oknie czatu pokazuje rolle na przedmioty i wyniki. Domyslnie jako JEDNA czytelna
-- linia na przedmiot, po zakonczeniu rolla:
--   [Przedmiot]  >  Brakk wygral (Need 74)  |  Seluna Greed 55, Morvanna Pass
-- Tryb "raw" zostawia oryginalne linie Blizzarda (z filtrem typow). Inne okna czatu bez zmian.
-- Ustawienia: /wwt   (skrot: /wwt)

local ADDON = "WhoWonThat"

local DEFAULTS = {
    frame = 4,          -- numer okna czatu, w ktorym maja byc rolle i wyniki
    format = "summary", -- "summary" = jedna linia na przedmiot, "raw" = oryginalne linie Blizzarda
    rolls = true,       -- glowny przelacznik: pokazuj rolle innych graczy
    need = true,        -- pokazuj rolle Need
    greed = true,       -- pokazuj rolle Greed
    de = true,          -- (tylko tryb raw) rolle Disenchant, jesli gra je ma
    transmog = true,    -- pokazuj rolle Transmog
    pass = true,        -- pokazuj "spasowal"
    wins = true,        -- pokazuj, kto wygral / ze wszyscy spasowali
    hideOthers = true,  -- ukryj w tym oknie reszte lupow (podniesione przedmioty itp.)
    classColors = true, -- koloruj nicki wg klasy (kolory z EllesmereUI, jesli jest zainstalowany)
    debug = false,      -- zapisuj bledy Lua do pliku ustawien (WhoWonThatDB.errors) - tylko do diagnozy
}

local TYPE_LABEL = { need = "Need", greed = "Greed", de = "Disenchant", transmog = "Transmog", pass = "Pass" }
local PRIORITY = { win = 1, de = 2, transmog = 2, greed = 3, need = 4, pass = 5, other = 6 }
-- Forever (silnik Midnight) ma historie lootu z gotowymi danymi o rollach (C_LootHistory) - to glowne zrodlo.
-- Parsowanie tekstow czatu zostaje tylko do ukrywania surowych linii i jako rezerwa.
local HAS_HISTORY = (C_LootHistory ~= nil and C_LootHistory.GetSortedInfoForDrop ~= nil)
local STALE_SECONDS = 180

local db
local entries = {}  -- {pattern, kinds, kind, wonType, self, prio}
local items = {}    -- [itemLink] = { time = t, players = { [name] = { type, roll } } }

-- Wypisuje tekst w ramce czatu tak, jak robi to sam Blizzard: AddMessage(tekst, r, g, b, id).
-- Pelny zestaw argumentow jest wazny - dodatki podpiete pod AddMessage (np. EllesmereUIChat)
-- czytaja m.in. 5. argument (chatTypeID) i bez niego wywalaja "bad argument #5".
local function Emit(frame, text, chatType)
    local info = ChatTypeInfo and (ChatTypeInfo[chatType] or ChatTypeInfo.SYSTEM)
    if info then
        frame:AddMessage(text, info.r, info.g, info.b, info.id)
    else
        frame:AddMessage(text, 1, 1, 1, 0)
    end
end

local function Print(msg)
    Emit(DEFAULT_CHAT_FRAME, "|cff58c6faWho Won That:|r " .. msg, "SYSTEM")
end

-- Zamienia tekst formatu Blizzarda (np. "%s won: %s") na wzorzec Lua z grupami przechwytujacymi,
-- niezalezny od jezyka. Zwraca wzorzec oraz liste typow przechwytywanych pol ("s" albo "d").
local function Compile(fmt)
    local kinds = {}
    local p = fmt:gsub("%%%%", "\3")
    p = p:gsub("%%(%d*)%$?([sd])", function(_, t)
        kinds[#kinds + 1] = t
        return t == "s" and "\1" or "\2"
    end)
    p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("\1", "(.+)")
    p = p:gsub("\2", "(%%d+)")
    p = p:gsub("\3", "%%%%")
    return "^" .. p .. "$", kinds
end

-- Okresla na podstawie nazwy globalnej (np. LOOT_ROLL_ROLLED_NEED), czym jest dana wiadomosc.
local function ClassifyName(name)
    if name:find("WON") or name:find("ALL_PASSED") then
        return "win"
    end
    if name:find("TRANSMOG") then
        return "transmog"
    end
    if name:find("DISENCHANT") or name:find("_DE$") or name:find("_DE_") then
        return "de"
    end
    if name:find("GREED") then
        return "greed"
    end
    if name:find("NEED") then
        return "need"
    end
    if name:find("PASS") then
        return "pass"
    end
    return "other"
end

local function WonType(name)
    if name:find("DISENCHANT") or name:find("_DE$") or name:find("_DE_") then return "de" end
    if name:find("GREED") then return "greed" end
    if name:find("NEED") then return "need" end
    return nil
end

local function BuildEntries()
    wipe(entries)
    for name, text in pairs(_G) do
        if type(name) == "string" and type(text) == "string" and name:find("^LOOT_ROLL_") then
            local pattern, kinds = Compile(text)
            -- pomin wzorce, ktore pasowalyby do kazdej wiadomosci
            if pattern ~= "^(.+)$" and pattern ~= "^$" then
                local kind = ClassifyName(name)
                local literal = #(text:gsub("%%%d*%$?[sd]", ""))
                entries[#entries + 1] = {
                    literal = literal,
                    pattern = pattern,
                    kinds = kinds,
                    kind = kind,
                    name = name,
                    wonType = (kind == "win") and WonType(name) or nil,
                    allPassed = name:find("ALL_PASSED") ~= nil,
                    self = (name:find("_SELF") or name:find("YOU_")) and true or false,
                    prio = PRIORITY[kind],
                }
            end
        end
    end
    -- wygrane przed rollami ("wszyscy spasowali" pasuje tez do wzorca "X spasowal"),
    -- a w obrebie grupy najpierw wzorce o najwiekszej ilosci stalego tekstu, bo ogolny
    -- "%s won: %s" pasowalby tez do "You won: %s" i "%s won: %s (Need - 74)"
    table.sort(entries, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        if a.literal ~= b.literal then return a.literal > b.literal end
        return a.name < b.name
    end)
end

-- Zwraca pelna nazwe gracza ("Nick-Serwer", jesli klient ja podaje) oraz krotki nick.
-- Komunikaty Blizzarda zawieraja link |Hplayer:Nick-Serwer:...|h[Nick]|h, z niego bierzemy pelna nazwe.
local function PlayerInfo(raw)
    if not raw then return nil end
    local full = raw:match("|Hplayer:([^:|]+)")
    local short = raw:match("|h%[(.-)%]|h")
    if full then
        return full, short or (full:match("^([^%-]+)") or full)
    end
    return raw, (raw:match("^([^%-]+)") or raw)
end

local function SelfInfo()
    local name = UnitName("player")
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    if realm and realm ~= "" then
        realm = realm:gsub("%s", "")
        return name .. "-" .. realm, name
    end
    return name, name
end

-- Zwraca tabele {kind, item, player, roll, wonType, allPassed} albo nil, jesli to nie roll.
local function Parse(msg)
    for i = 1, #entries do
        local e = entries[i]
        local caps = { msg:match(e.pattern) }
        if caps[1] then
            local r = { kind = e.kind, wonType = e.wonType, allPassed = e.allPassed }
            for j = 1, #e.kinds do
                local c = caps[j]
                if c then
                    if e.kinds[j] == "d" then
                        r.roll = tonumber(c)
                    elseif c:find("|Hitem:") then
                        r.item = r.item or c
                    elseif not r.player then
                        r.player, r.short = PlayerInfo(c)
                    end
                end
            end
            if e.self then
                r.player, r.short = SelfInfo()
            end
            return r
        end
    end
    return nil
end

local function TargetFrame()
    return db and _G["ChatFrame" .. db.frame]
end

-- Zwrocenie true = ukryj wiadomosc w tym oknie czatu.
local function Filter(self, event, msg, ...)
    if not db or self ~= TargetFrame() then
        return false
    end
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then
        return false
    end
    local p = Parse(msg)
    if p then
        if db.format == "summary" then
            return true -- zastapimy jedna linia podsumowania
        end
        if p.kind == "win" then
            return not db.wins
        end
        if not db.rolls then
            return true
        end
        if p.kind == "other" then
            return false
        end
        return not db[p.kind]
    end
    return db.hideOthers
end

-- Gracz jako klikalny link z PELNA nazwa (Nick-Serwer). Dzieki temu dodatki do czatu
-- (kolorowanie nickow wg klasy itp.) rozpoznaja gracza tak samo jak w zwyklej wiadomosci.
-- Kolor klasy: najpierw paleta EllesmereUI (wlasne kolory uzytkownika), potem standardowy Blizzarda.
local function ClassColor(classFile)
    if not classFile then
        return nil
    end
    if type(EllesmereUI) == "table" and EllesmereUI.GetRawClassColor then
        local c = EllesmereUI.GetRawClassColor(classFile)
        if c then
            return c
        end
    end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
end

local function PlayerLink(full, short, classFile)
    -- w tekscie sam nick, a w linku pelna nazwa (Nick-Serwer)
    local link = "|Hplayer:" .. full .. "|h[" .. (short or full) .. "]|h"
    if db.classColors then
        local class = classFile
        if not class then
            _, class = UnitClass(full)
        end
        if not class and short then
            _, class = UnitClass(short)
        end
        local c = ClassColor(class)
        if c then
            return string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), link)
        end
    end
    return link
end

-- ===== Glowne zrodlo danych: historia lootu Blizzarda (zdarzenie LOOT_HISTORY_UPDATE_DROP) =====
local ROLL_STATE = (Enum and Enum.EncounterLootDropRollState)
    or { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
local STATE_INFO = {
    [ROLL_STATE.NeedMainSpec] = { kind = "need", label = "Need" },
    [ROLL_STATE.NeedOffSpec] = { kind = "need", label = "Need OS" },
    [ROLL_STATE.Transmog] = { kind = "transmog", label = "Transmog" },
    [ROLL_STATE.Greed] = { kind = "greed", label = "Greed" },
    [ROLL_STATE.Pass] = { kind = "pass", label = "Pass" },
    -- NoRoll: gracz jeszcze nie wybral - pomijamy
}
local printedDrops = {}
local printedCount = 0

local function ShortName(full)
    return (full:match("^([^%-]+)") or full)
end

-- nazwa gracza uzyteczna do wyswietlenia (zwykly tekst, nie "secret")
local function UsableName(v)
    return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v))
end

-- Ikony z klienta (te same sciezki uzywaja EllesmereUI i ForeverDungeonJournal)
local ICON_CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:16:16:0:0|t"
local KIND_ICON = {
    need = "|TInterface\\Buttons\\UI-GroupLoot-Dice-Up:14:14:0:0|t",
    greed = "|TInterface\\Buttons\\UI-GroupLoot-Coin-Up:14:14:0:0|t",
    pass = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14:0:0|t",
}

-- np. "[kostka] Need 74"
local function RollLabel(r, st)
    local icon = KIND_ICON[st.kind]
    return (icon and (icon .. " ") or "")
        .. "|cffaaaaaa" .. st.label .. "|r"
        .. (r.roll and (" |cffffffff" .. r.roll .. "|r") or "")
        .. (r.isSelf and "  |cffffd100(Ty)|r" or "")
end

-- Wypisuje podsumowanie jednego przedmiotu (dane z C_LootHistory) w kilku liniach:
--   [Przedmiot]
--      [korona] Zwyciezca  WYGRAL  [kostka] Need 74
--          Gracz2  [moneta] Greed 55
--          Gracz3  [kostka] Need OS 31
local function RenderDrop(info)
    local frame = TargetFrame()
    if not frame or type(info) ~= "table" then
        return
    end
    local item = info.itemHyperlink
    if type(item) ~= "string" or (issecretvalue and issecretvalue(item)) then
        return
    end
    if info.allPassed then
        if db.wins then
            Emit(frame, item, "LOOT")
            Emit(frame, "     |cffaaaaaanikt nie chcial (wszyscy spasowali)|r", "LOOT")
        end
        return
    end

    local winner = info.winner
    local list = {}
    if db.rolls then
        for _, r in ipairs(info.rollInfos or {}) do
            local st = STATE_INFO[r.state]
            -- zwyciezce wypisujemy osobno, chyba ze wygrane sa wylaczone
            if st and UsableName(r.playerName) and db[st.kind] and not (r.isWinner and db.wins) then
                list[#list + 1] = { r = r, st = st }
            end
        end
        table.sort(list, function(a, b)
            local ra, rb = a.r.roll or -1, b.r.roll or -1
            if ra ~= rb then return ra > rb end
            return a.r.playerName < b.r.playerName
        end)
    end

    local showWinner = db.wins and winner and UsableName(winner.playerName)
    if not showWinner and #list == 0 then
        return
    end

    Emit(frame, item, "LOOT")
    if showWinner then
        local line = "   " .. ICON_CROWN .. " "
            .. PlayerLink(winner.playerName, ShortName(winner.playerName), winner.playerClass)
            .. "  |cffffd100WYGRAL|r"
        local wst = STATE_INFO[winner.state]
        if wst then
            line = line .. "  " .. RollLabel(winner, wst)
        end
        Emit(frame, line, "LOOT")
    end
    for i = 1, #list do
        local r, st = list[i].r, list[i].st
        Emit(frame, "        " .. PlayerLink(r.playerName, ShortName(r.playerName), r.playerClass)
            .. "  " .. RollLabel(r, st), "LOOT")
    end
end

local function OnDropUpdate(encounterID, lootListKey)
    if not HAS_HISTORY or not db or db.format ~= "summary" then
        return
    end
    if issecretvalue and (issecretvalue(encounterID) or issecretvalue(lootListKey)) then
        return
    end
    local key = tostring(encounterID) .. ":" .. tostring(lootListKey)
    if printedDrops[key] then
        return
    end
    local info = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey)
    if type(info) ~= "table" or not (info.winner or info.allPassed) then
        return -- rzut jeszcze trwa
    end
    if printedCount > 400 then
        wipe(printedDrops)
        printedCount = 0
    end
    printedDrops[key] = true
    printedCount = printedCount + 1
    RenderDrop(info)
end

-- Po /reload (albo wejsciu do gry w trakcie dungeonu) historia lootu juz istnieje: oznacz rozstrzygniete
-- przedmioty jako wypisane, zeby ich podsumowania nie pojawily sie drugi raz.
local function MarkExistingDrops()
    if not HAS_HISTORY or not C_LootHistory.GetAllEncounterInfos or not C_LootHistory.GetSortedDropsForEncounter then
        return
    end
    local encounters = C_LootHistory.GetAllEncounterInfos()
    if type(encounters) ~= "table" then
        return
    end
    for _, enc in ipairs(encounters) do
        local id = enc.encounterID
        if id and not (issecretvalue and issecretvalue(id)) then
            local drops = C_LootHistory.GetSortedDropsForEncounter(id)
            if type(drops) == "table" then
                for _, d in ipairs(drops) do
                    if d.lootListKey and (d.winner or d.allPassed) then
                        local key = tostring(id) .. ":" .. tostring(d.lootListKey)
                        if not printedDrops[key] then
                            printedDrops[key] = true
                            printedCount = printedCount + 1
                        end
                    end
                end
            end
        end
    end
end


-- ===== Rezerwa: gdy gra nie ma historii lootu, rolle sa skladane z tekstow czatu =====
-- Dane trafiaja do tego samego RenderDrop, wiec wyglad jest identyczny.
local KIND_TO_STATE = {
    need = ROLL_STATE.NeedMainSpec, greed = ROLL_STATE.Greed, de = ROLL_STATE.Greed,
    transmog = ROLL_STATE.Transmog, pass = ROLL_STATE.Pass,
}

local function Prune(now)
    for key, rec in pairs(items) do
        if now - rec.time > STALE_SECONDS then
            items[key] = nil
        end
    end
end

local function Summarize(p)
    local rec = items[p.item]
    items[p.item] = nil
    local me = UnitName("player")
    local winnerKey = p.short or p.player
    local info = { itemHyperlink = p.item, allPassed = p.allPassed or false, rollInfos = {} }
    local winnerEntry
    if rec then
        for key, e in pairs(rec.players) do
            local state = KIND_TO_STATE[e.type]
            if state then
                local r = { playerName = e.full or key, state = state, roll = e.roll,
                    isWinner = (key == winnerKey), isSelf = (key == me) }
                info.rollInfos[#info.rollInfos + 1] = r
                if r.isWinner then
                    winnerEntry = r
                end
            end
        end
    end
    if not p.allPassed and p.player then
        if not winnerEntry then
            winnerEntry = { playerName = p.player, state = ROLL_STATE.NoRoll, isWinner = true, isSelf = (winnerKey == me) }
            info.rollInfos[#info.rollInfos + 1] = winnerEntry
        end
        if p.wonType and KIND_TO_STATE[p.wonType] then
            winnerEntry.state = KIND_TO_STATE[p.wonType]
        end
        winnerEntry.roll = winnerEntry.roll or p.roll
        info.winner = winnerEntry
    end
    RenderDrop(info)
end

local function OnLoot(msg)
    if HAS_HISTORY or not db or db.format ~= "summary" then
        return
    end
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then
        return
    end
    local p = Parse(msg)
    if not p or not p.item then
        return
    end
    local now = GetTime()
    Prune(now)
    if p.kind == "win" then
        Summarize(p)
        return
    end
    if not p.player then
        return
    end
    local rec = items[p.item]
    if not rec then
        rec = { time = now, players = {} }
        items[p.item] = rec
    end
    -- klucz = krotki nick (komunikaty raz podaja "Nick", raz "Nick-Serwer"); pelna nazwa trafia do linku
    local key = p.short or p.player
    local e = rec.players[key]
    if not e then
        e = {}
        rec.players[key] = e
    end
    e.type = p.kind
    e.short = key
    if not e.full or (p.player:find("-", 1, true) and not e.full:find("-", 1, true)) then
        e.full = p.player
    end
    if p.roll then
        e.roll = p.roll
    end
end

local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
local addGroup = ChatFrame_AddMessageGroup or (ChatFrameUtil and ChatFrameUtil.AddMessageGroup)

local function EnsureLootGroup()
    local frame = TargetFrame()
    if not frame then
        return
    end
    -- w Forever AddMessageGroup to metoda ramki czatu (ChatFrameMixin); zapamietuje sie sama
    if frame.ContainsMessageGroup and frame:ContainsMessageGroup("LOOT") then
        return
    end
    if frame.AddMessageGroup then
        frame:AddMessageGroup("LOOT")
    elseif addGroup then
        addGroup(frame, "LOOT")
    else
        Print("nie moge sam dodac grupy Loot - zaznacz Loot w tym oknie recznie (prawy klik na zakladke > Settings)")
    end
end

local function WindowName(i)
    local f = _G["ChatFrame" .. i]
    local name = f and f.name
    if (not name or name == "") and GetChatWindowInfo then
        name = GetChatWindowInfo(i)
    end
    return (name and name ~= "") and name or "-"
end

local function OnOff(v)
    return v and "|cff00ff00ON|r" or "|cffff4040OFF|r"
end

local function Status()
    Print(string.format("okno: %d (%s) | format: %s | rolle: %s | wygrane: %s | reszta lupow ukryta: %s",
        db.frame, WindowName(db.frame), db.format, OnOff(db.rolls), OnOff(db.wins), OnOff(db.hideOthers)))
    Print(string.format("typy rolli: Need %s, Greed %s, Transmog %s, Pass %s | kolory klas: %s",
        OnOff(db.need), OnOff(db.greed), OnOff(db.transmog), OnOff(db.pass), OnOff(db.classColors)))
end

local function Help()
    Status()
    Print("/wwt config - otworz panel ustawien (Esc > Options > AddOns > Who Won That)")
    Print("/wwt test - wyslij przykladowy roll do wybranego okna i sprawdz rozpoznawanie")
    Print("/wwt dump - zapisz teksty LOOT_ROLL_* z gry do pliku (diagnoza, potem /reload)")
    Print("/wwt list - lista okien czatu z numerami")
    Print("/wwt frame <numer lub nazwa> - gdzie pokazywac rolle i wygrane")
    Print("/wwt format summary / raw - jedna linia na przedmiot albo oryginalne linie")
    Print("/wwt rolls on/off - pokazuj rolle innych graczy")
    Print("/wwt need/greed/transmog/pass on/off - pojedyncze typy rolli")
    Print("/wwt only need  (albo greed, transmog, pass) - tylko ten typ rolla")
    Print("/wwt all - wszystkie typy rolli")
    Print("/wwt wins on/off - kto wygral / wszyscy spasowali")
    Print("/wwt others on/off - ukrywanie reszty lupow w tym oknie (takze rzeczy wytworzone, z questow, od mistrza lupow)")
    Print("/wwt colors on/off - kolory klas przy nickach (z EllesmereUI, jesli jest; link gracza ma zawsze pelna nazwe z serwerem)")
end

local function ParseBool(s)
    s = (s or ""):lower()
    if s == "on" or s == "1" or s == "yes" or s == "tak" then return true end
    if s == "off" or s == "0" or s == "no" or s == "nie" then return false end
    return nil
end

local function FindWindow(arg)
    local n = tonumber(arg)
    if n then
        n = math.floor(n)
        if n >= 1 and n <= (NUM_CHAT_WINDOWS or 10) and _G["ChatFrame" .. n] then
            return n
        end
        return nil
    end
    arg = (arg or ""):lower()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local name = WindowName(i)
        if name ~= "-" and name:lower() == arg then
            return i
        end
    end
    return nil
end

local settingsCategory -- kategoria w Esc > Options > AddOns

local TYPE_ALIASES = {
    need = "need", greed = "greed", transmog = "transmog", pass = "pass",
}

-- /wwt test: buduje przykladowe komunikaty z PRAWDZIWYCH tekstow gry (LOOT_ROLL_*), sprawdza,
-- czy dodatek je rozpoznaje, i (w trybie "summary") wysyla je przez ten sam kod co prawdziwe rolle.
local function RunTest()
    Print(string.format("TEST: okno %d (%s), format: %s, historia lootu (C_LootHistory): %s",
        db.frame, WindowName(db.frame), db.format, HAS_HISTORY and "TAK" or "NIE"))

    -- 1) czy rozpoznajemy teksty czatu z rolli (potrzebne do ukrywania surowych linii w tym oknie)
    local item = "|cffffffff|Hitem:25::::::::::::::|h[Worn Shortsword]|h|r"
    local function pl(n)
        return "|Hplayer:" .. n .. "-Testrealm:1|h[" .. n .. "]|h"
    end
    local cases = {
        { "LOOT_ROLL_NEED", { pl("Brakk"), item } },
        { "LOOT_ROLL_GREED", { pl("Seluna"), item } },
        { "LOOT_ROLL_PASSED", { pl("Morv"), item } },
        { "LOOT_ROLL_ROLLED_NEED", { 74, item, pl("Brakk") } },
        { "LOOT_ROLL_ROLLED_GREED", { 55, item, pl("Seluna") } },
        { "LOOT_ROLL_WON", { pl("Brakk"), item } },
    }
    local unpackFn = unpack or table.unpack
    local problems = 0
    for _, c in ipairs(cases) do
        local name, args = c[1], c[2]
        local fmt = _G[name]
        if type(fmt) ~= "string" then
            problems = problems + 1
            Print("|cffff4040BRAK|r globalnego tekstu " .. name .. " (w tej wersji gry ma inna nazwe?)")
        else
            -- w Forever teksty maja dodatkowe pola: dopelnij je ("1" pasuje do %s i %d)
            local needed = 0
            for idx in fmt:gmatch("%%(%d+)%$") do
                needed = math.max(needed, tonumber(idx))
            end
            needed = math.max(needed, (select(2, fmt:gsub("%%[sd]", ""))))
            local filled = {}
            for i = 1, math.max(needed, #args) do
                filled[i] = args[i] ~= nil and args[i] or "1"
            end
            local ok, msg = pcall(string.format, fmt, unpackFn(filled))
            if not ok then
                problems = problems + 1
                Print("|cffff4040BLAD|r formatowania " .. name .. ": " .. tostring(msg)
                    .. " | tekst: " .. fmt:gsub("|", "||"))
            else
                local parsed = Parse(msg)
                if parsed then
                    Print(string.format("|cff00ff00OK|r %s -> %s", name, parsed.kind))
                else
                    problems = problems + 1
                    Print("|cffff4040NIE ROZPOZNANO|r " .. name .. ": " .. msg:gsub("|", "||"))
                end
            end
        end
    end

    -- 2) podsumowanie: przykladowe dane w formacie historii lootu Blizzarda
    if db.format == "summary" then
        if TargetFrame() then
            local function roll(name, class, state, value, winner)
                return { playerName = name, playerGUID = name, playerClass = class, isSelf = false,
                    state = state, roll = value, isWinner = winner or false }
            end
            local win = roll("Brakk-Testrealm", "WARRIOR", ROLL_STATE.NeedMainSpec, 74, true)
            RenderDrop({
                itemHyperlink = item, allPassed = false, winner = win,
                rollInfos = {
                    win,
                    roll("Seluna-Testrealm", "PRIEST", ROLL_STATE.Greed, 55),
                    roll("Monra-Greytusk", "MAGE", ROLL_STATE.NeedOffSpec, 31),
                    roll("Rax-Testrealm", "ROGUE", ROLL_STATE.Transmog, 12),
                    roll("Morv-Testrealm", "HUNTER", ROLL_STATE.Pass),
                },
            })
            Print("Powinienes zobaczyc linie z przedmiotem [Worn Shortsword] w oknie " .. WindowName(db.frame) .. ".")
        else
            Print("Okno " .. db.frame .. " nie istnieje - zmien okno w ustawieniach.")
        end
    else
        Print("Tryb raw: test sprawdza tylko rozpoznawanie komunikatow (przelacz format na summary, zeby zobaczyc linie).")
    end
    Print(problems == 0 and "TEST zakonczony: wszystko rozpoznane." or ("TEST zakonczony: problemy: " .. problems))
end

local function HandleSlash(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    rest = rest or ""
    if cmd == "" or cmd == "help" or cmd == "status" then
        Help()
    elseif cmd == "test" then
        RunTest()
    elseif cmd == "dump" then
        -- zapisuje wszystkie teksty LOOT_ROLL_* z gry do pliku ustawien (po /reload), do diagnozy
        db.strings = {}
        local n = 0
        for gname, text in pairs(_G) do
            if type(gname) == "string" and type(text) == "string" and gname:find("^LOOT_ROLL_") then
                db.strings[gname] = text
                n = n + 1
            end
        end
        Print("zapisano " .. n .. " tekstow LOOT_ROLL_* - zrob /reload, zeby trafily do pliku")
    elseif cmd == "debug" then
        local v = ParseBool(rest)
        if v == nil then
            Print("Uzyj: /wwt debug on  albo  off  (zapisywanie bledow Lua do pliku ustawien)")
            return
        end
        db.debug = v
        Print("debug: " .. OnOff(v) .. " | zapisanych bledow: " .. #(db.errors or {}))
    elseif cmd == "errors" then
        if rest:lower() == "clear" then
            db.errors = nil
            Print("lista bledow wyczyszczona")
        else
            Print("zapisanych bledow: " .. #(db.errors or {}) .. " (zapisuja sie do pliku po /reload; /wwt errors clear = wyczysc)")
        end
    elseif cmd == "config" or cmd == "options" or cmd == "ui" then
        if settingsCategory and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(settingsCategory:GetID())
        else
            Print("panel ustawien jest niedostepny w tej wersji gry - uzyj komend z /wwt")
        end
    elseif cmd == "list" then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            if _G["ChatFrame" .. i] then
                Print(string.format("%d - %s%s", i, WindowName(i), i == db.frame and "  <- tutaj" or ""))
            end
        end
    elseif cmd == "frame" or cmd == "window" or cmd == "okno" then
        local n = FindWindow(rest)
        if not n then
            Print("Nie ma takiego okna. Wpisz /wwt list.")
            return
        end
        db.frame = n
        EnsureLootGroup()
        Status()
    elseif cmd == "format" then
        rest = rest:lower()
        if rest ~= "summary" and rest ~= "raw" then
            Print("Uzyj: /wwt format summary  albo  raw")
            return
        end
        db.format = rest
        wipe(items)
        Status()
    elseif cmd == "all" then
        db.rolls, db.need, db.greed, db.de, db.transmog, db.pass = true, true, true, true, true, true
        Status()
    elseif cmd == "only" then
        local t = TYPE_ALIASES[rest:lower()]
        if not t then
            Print("Uzyj: /wwt only need  (albo greed, transmog, pass)")
            return
        end
        db.rolls = true
        for _, key in ipairs({ "need", "greed", "transmog", "pass" }) do
            db[key] = (key == t)
        end
        Status()
    elseif TYPE_ALIASES[cmd] then
        local v = ParseBool(rest)
        if v == nil then
            Print("Uzyj: /wwt " .. cmd .. " on  albo  off")
            return
        end
        db[TYPE_ALIASES[cmd]] = v
        if v then
            db.rolls = true
        end
        Status()
    elseif cmd == "rolls" or cmd == "wins" or cmd == "others" or cmd == "colors" then
        local v = ParseBool(rest)
        if v == nil then
            Print("Uzyj: /wwt " .. cmd .. " on  albo  off")
            return
        end
        if cmd == "rolls" then db.rolls = v
        elseif cmd == "wins" then db.wins = v
        elseif cmd == "colors" then db.classColors = v
        else db.hideOthers = v end
        Status()
    else
        Help()
    end
end

-- Panel w Esc > Options > AddOns > Who Won That (API Settings z Blizzard_Settings_Shared).
-- Ustawienia zapisuja sie od razu w WhoWonThatDB; komendy /wwt dzialaja nadal.
local function RegisterPanel()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
        and Settings.CreateCheckbox and Settings.CreateDropdown and Settings.CreateControlTextContainer) then
        return
    end

    local category = Settings.RegisterVerticalLayoutCategory("Who Won That")
    settingsCategory = category

    local function AddBool(key, label, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "WWT_" .. key:upper(), key, db,
            Settings.VarType.Boolean, label, DEFAULTS[key])
        if onChange then
            setting:SetValueChangedCallback(onChange)
        end
        return Settings.CreateCheckbox(category, setting, tooltip)
    end

    -- Okno czatu: lista okien z numerami i nazwami
    local frameSetting = Settings.RegisterAddOnSetting(category, "WWT_FRAME", "frame", db,
        Settings.VarType.Number, "Okno czatu", DEFAULTS.frame)
    frameSetting:SetValueChangedCallback(function()
        EnsureLootGroup()
    end)
    local function WindowOptions()
        local container = Settings.CreateControlTextContainer()
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            if _G["ChatFrame" .. i] then
                container:Add(i, i .. " - " .. WindowName(i))
            end
        end
        return container:GetData()
    end
    Settings.CreateDropdown(category, frameSetting, WindowOptions,
        "Okno czatu, w ktorym pokazywane sa rolle i wygrane (np. Party/Dungs). Inne okna nie sa zmieniane.")

    -- Format
    local formatSetting = Settings.RegisterAddOnSetting(category, "WWT_FORMAT", "format", db,
        Settings.VarType.String, "Format", DEFAULTS.format)
    formatSetting:SetValueChangedCallback(function()
        wipe(items)
    end)
    local function FormatOptions()
        local container = Settings.CreateControlTextContainer()
        container:Add("summary", "Jedna linia na przedmiot",
            "Po zakonczeniu rolla: przedmiot, kto wygral i kto ile rzucil.")
        container:Add("raw", "Oryginalne linie",
            "Zostawia zwykle komunikaty Blizzarda (z filtrem typow rolli).")
        return container:GetData()
    end
    Settings.CreateDropdown(category, formatSetting, FormatOptions, "Jak pokazywac rolle w tym oknie.")

    -- Co pokazywac
    local rollsInit = AddBool("rolls", "Pokazuj rolle innych graczy",
        "Kto wybral Need/Greed/Transmog/Pass i ile rzucil.")
    local function Child(key, label, tooltip)
        local init = AddBool(key, label, tooltip)
        if init and init.SetParentInitializer and rollsInit then
            init:SetParentInitializer(rollsInit)
        end
    end
    Child("need", "Need", "Pokazuj rolle Need.")
    Child("greed", "Greed", "Pokazuj rolle Greed.")
    Child("transmog", "Transmog", "Pokazuj rolle Transmog.")
    Child("pass", "Pass", "Pokazuj osoby, ktore spasowaly.")
    AddBool("wins", "Pokazuj, kto wygral",
        "Zwyciezca rolla oraz informacja, ze wszyscy spasowali.")
    AddBool("hideOthers", "Ukryj reszte lupow w tym oknie",
        "Ukrywa komunikaty o podniesionych przedmiotach, wytworzonych, z questow, od mistrza lupow itp.")
    AddBool("classColors", "Kolory klas przy nickach",
        "Nicki w kolorach klas. Jesli masz EllesmereUI, uzywane sa jego kolory klas (takie same jak w reszcie interfejsu).")

    Settings.RegisterAddOnCategory(category)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        WhoWonThatDB = WhoWonThatDB or {}
        db = WhoWonThatDB
        db.mainLoaded = "v4.0 glowny plik dziala, historia lootu: " .. tostring(HAS_HISTORY)
        -- jednorazowe przeniesienie ustawien z poprzedniej nazwy dodatku (RollsOnly)
        if db.schema == nil and type(RollsOnlyDB) == "table" then
            for _, k in ipairs({ "frame", "format", "rolls", "need", "greed", "transmog", "pass",
                "wins", "hideOthers", "classColors" }) do
                if RollsOnlyDB[k] ~= nil and db[k] == nil then
                    db[k] = RollsOnlyDB[k]
                end
            end
        end
        if db.schema ~= 2 then
            -- porzadki po wersjach testowych: diagnostyka wylaczona, stare dane usuniete
            db.schema = 2
            db.debug = false
            db.errors = nil
            db.strings = nil
            db.colors = nil
        end
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then
                db[k] = v
            end
        end
        RegisterPanel()
    elseif event == "PLAYER_LOGIN" then
        BuildEntries()
        if addFilter then
            addFilter("CHAT_MSG_LOOT", Filter)
        end
        if HAS_HISTORY then
            MarkExistingDrops()
            if C_Timer and C_Timer.After then
                C_Timer.After(3, MarkExistingDrops) -- historia bywa gotowa dopiero chwile po wejsciu do gry
            end
            f:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
        else
            f:RegisterEvent("CHAT_MSG_LOOT") -- rezerwa: skladanie rolli z tekstow czatu
        end
        EnsureLootGroup()
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        OnDropUpdate(arg1, arg2)
    elseif event == "CHAT_MSG_LOOT" then
        OnLoot(arg1)
    end
end)

SLASH_WHOWONTHAT1 = "/wwt"
SLASH_WHOWONTHAT2 = "/whowonthat"
SlashCmdList["WHOWONTHAT"] = function(input)
    if db then
        HandleSlash(input)
    end
end
