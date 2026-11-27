-- Who Won That: the roll window. A small movable window that replaces the game's roll lines in chat:
--  * board mode (no roll running): everyone in the group with the items they won and the roll that won them,
--  * roll mode (an item is being rolled for): who chose Need / Greed / Pass, then the numbers land one after another
--    like a slot machine (spinning digits, the best roll lands last), and the winner gets a crown, a flash and sparks.
-- It opens inside dungeons and raids and whenever a roll starts; outside it fades away after the result (after the
-- time set in the options, or never). Each result also gets one short line in your own chat; clicking its item
-- replays the roll in the window.
-- Game logic (reveals, the winner, switching drops) runs on timers; OnUpdate only animates what is on screen.
local _, ns = ...

local L = ns.L
local ART, CanClassUse, ClassColor, MarkCantUse = ns.ART, ns.CanClassUse, ns.ClassColor, ns.MarkCantUse
local PlainNumber, ROLL_STATE, STATE_INFO, SetClassColor = ns.PlainNumber, ns.ROLL_STATE, ns.STATE_INFO, ns.SetClassColor
local SetClassIcon, StyleItemBorder, Theme = ns.SetClassIcon, ns.StyleItemBorder, ns.Theme
local TrySetFile, UsableName, Gradient = ns.TrySetFile, ns.UsableName, ns.Gradient
local RollFX = ns.RollFX

local WINDOW_NAME = "WhoWonThatRollWindow"
local PAD = 8
local DEFAULT_W, MIN_W, MAX_W = 300, 220, 600 -- the width can be dragged at the lower right corner
local FOOT = 12             -- bottom margin: room for the resize grip under the last row
local MIN_SCALE, MAX_SCALE = 0.6, 1.8         -- Ctrl + mouse wheel
local W = DEFAULT_W
local INNER = W - 2 * PAD
local ROLL_HEAD = 70        -- item icon, item name, item details, status line and the timer bar
local ICON = 40
local BOARD_HEAD = 30
local ROW_H = 22
local BOARD_ROW_H = 34       -- name over the luck line, item icons beside them
local TILE, TILE_GAP = 20, 4
local NAME_COL_MIN, NAME_COL_MAX = 104, 160 -- class icon + name column of the board (grows with the width)
local MAX_BOARD_ROWS = 12
local SPIN = 0.8            -- seconds a number spins before it lands (it has been spinning since the player chose)
-- the deciding (last) number spins longer, its row pulsing: how long depends on the item (src/RollFX.lua)
local MISSED_BY = 5         -- you lost by this many points or less: the window tells you
local LUCK_MIN_ROLLS = 3    -- rolls a player needs before the lucky / unlucky badge can go to them
local PHOTO_FINISH = 3      -- a win by this many points or less is called a photo finish
local REVEAL_GAP = 0.4      -- seconds between two numbers landing (weakest first, the best one last)
local FAST_GAP = 0.25       -- the same while more drops are waiting
local CELEBRATE_DELAY = 0.25
local HOLD_BUSY = 2.5      -- seconds a result stays while more drops are waiting (otherwise the fade setting)
local HOLD_NO_FADE = 10     -- with fading turned off: seconds the result stays before the board takes over
local STALE_DROP = 300      -- a roll that never finishes is given up after this many seconds
local MAX_QUEUE, MAX_ROLLERS, MAX_RESULTS, MAX_KNOWN = 12, 40, 120, 300
local MAX_HISTORY = 50      -- finished drops kept so a click on their chat line can replay them
local CHAT_GAP_ABOVE, CHAT_GAP_BELOW = 36, -40 -- clear of the chat tabs above and the edit box below

local KIND_RGB = { need = { 1, 0.62, 0.30 }, greed = { 0.44, 0.72, 1 }, pass = { 0.6, 0.6, 0.6 } }
local KIND_TEXTURE = {
    need = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    pass = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}
local CROWN = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local SPARK = "Interface\\Cooldown\\star4"
local DOTS = { ".", "..", "..." }
local MUTED = "|cff9d9d9d"
local LUCKY_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"   -- star
local UNLUCKY_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" -- skull

-- ===== state =====
local known = {}        -- [dropKey] = drop table, or false for an item that is not shown (ignored / cheap)
local knownCount = 0
local queue = {}        -- drops waiting to be shown, oldest first; queue[1] is the one on screen
local current           -- the drop on screen in roll mode
local results = {}      -- finished wins for the board: { item, full, short, class, isSelf, kind, tag, roll }
local luck = {}         -- [short name] = { n = rolls, sum = total, best = highest } over the run
local resultsRun        -- ns.summaryRun the results belong to
local rollTimers = {}   -- [itemID] = { endsAt, duration } from START_LOOT_ROLL (only items we may roll on)
local win               -- the window (built on first use)
local mode              -- "roll" or "board"
local userClosed        -- run the player closed the window for: the board stays away until the next run
local pinned = false    -- opened with /wwt window: the board stays even outside an instance
local animating = false
local chatSeq, demoSeq, replaySeq = 0, 0, 0
local history = {}      -- finished drops the chat lines point to, oldest first
local fonts = {}        -- { fontString, size, outline } so a later UI skin can re-font everything

local Advance, Idle, RenderRoll, RenderBoard, Retire, StartAnimating
local Rarity = {} -- rarity effects of the drop on screen (src/RollFX.lua decides which ones an item gets)
local Early = {}  -- a roll shown from its very start: the window opens at START_LOOT_ROLL, reels spin at once

local function Enabled()
    return ns.db ~= nil and ns.db.rollWindow ~= false
end

-- Seconds a result stays on screen; 0 means the window never fades away on its own.
local function FadeAfter()
    local s = ns.db and ns.db.rollWinFade
    if type(s) ~= "number" then
        return ns.DEFAULTS.rollWinFade
    end
    return math.max(0, s)
end

local function RunKey()
    local run = ns.summaryRun
    return run and (tostring(run.id) .. ":" .. tostring(run.startTime)) or "world"
end

-- A new dungeon run starts a new board.
local function CheckRun()
    local run = ns.summaryRun
    if run and run ~= resultsRun then
        resultsRun = run
        wipe(results)
        wipe(luck)
        userClosed = nil
    end
end

local function After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(math.max(delay, 0), fn)
    else
        fn()
    end
end

local function Sound(name)
    local id = SOUNDKIT and SOUNDKIT[name]
    if id and PlaySound then
        pcall(PlaySound, id)
    end
end

-- One player, one name: WoW Forever characters carry a surname that the loot history adds ("Monra Greytusk") but
-- UnitName leaves out ("Monra"), and other realms add "-Realm". The first word is the name shown and the key that
-- joins the group, the rolls, the wins and the luck of one player.
local function ShortName(full)
    local name = ns.ShortName(full)
    return name:match("^(%S+)") or name
end

local function Hex(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function ClassText(name, class)
    local c = ClassColor(class)
    if c and type(c.r) == "number" then
        return Hex(c.r, c.g, c.b) .. name .. "|r"
    end
    return name
end

-- "[Item]" in its quality color, without the hyperlink markup (a font string would print it as text)
local function ItemLabel(link)
    local color, name = link:match("^(|c.-)|H.-|h%[(.-)%]|h")
    if color and name then
        return color .. name .. "|r"
    end
    return link:match("%[(.-)%]") or link
end

-- "Plate · Head · Item Level 45" from the client's own (translated) names; empty while the item is not cached yet
local function ItemDetails(link)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then
        return ""
    end
    local ok, _, _, _, ilvl, _, _, subType, _, equipLoc = pcall(getInfo, link)
    if not ok then
        return ""
    end
    local parts = {}
    if UsableName(subType) then
        parts[#parts + 1] = subType
    end
    local slot = UsableName(equipLoc) and _G[equipLoc]
    if UsableName(slot) and slot ~= subType then
        parts[#parts + 1] = slot
    end
    if PlainNumber(ilvl) and ilvl > 1 then
        local fmt = _G.ITEM_LEVEL
        parts[#parts + 1] = (type(fmt) == "string" and fmt:find("%%d")) and fmt:format(ilvl) or ("ilvl " .. ilvl)
    end
    return table.concat(parts, ns.SUMMARY_DOT)
end

-- ===== animation helpers (src/RollFX.lua) =====
local NewAnim, AddAnim, MakePop, MakeFlash, Play = ns.Anim.New, ns.Anim.Add, ns.Anim.MakePop, ns.Anim.MakeFlash, ns.Anim.Play

-- ===== widgets =====
local function Text(parent, size, outline)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.SetFont(fs, size, outline)
    fs:SetWordWrap(false)
    fonts[#fonts + 1] = { fs, size, outline }
    return fs
end

-- item icon with a quality frame: the game's icon frame on the Blizzard look, a 1 pixel edge on flat UIs
local function MakeSlot(w, size)
    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    w.border = w:CreateTexture(nil, "OVERLAY")
    w.border:SetSize(size, size)
    w.border:SetPoint("CENTER")
    w.styled = not Theme.IsFlat() and TrySetFile(w.border, ART.iconFrame)
    if w.styled then
        w.icon:SetAllPoints(w.border)
    else
        w.border:SetDrawLayer("BACKGROUND", 1)
        w.icon:SetPoint("TOPLEFT", w.border, "TOPLEFT", 1, -1)
        w.icon:SetPoint("BOTTOMRIGHT", w.border, "BOTTOMRIGHT", -1, 1)
    end
end

local function SetSlotItem(w, link)
    w.link = link
    TrySetFile(w.icon, ns.ItemTexture(link))
    StyleItemBorder(w, link)
end

local function Pool(make)
    return { list = {}, used = 0, make = make }
end

local function Take(p)
    p.used = p.used + 1
    local w = p.list[p.used]
    if not w then
        w = p.make()
        p.list[p.used] = w
    end
    w:ClearAllPoints()
    w:Show()
    return w
end

local function Release(p)
    for i = 1, #p.list do
        p.list[i]:Hide()
    end
    p.used = 0
end

local rollRows, boardRows, tiles

local function MakeRollRow()
    local row = CreateFrame("Frame", nil, win.rollPane)
    row:SetSize(INNER, ROW_H - 2)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.fill = row:CreateTexture(nil, "BORDER")
    row.fill:SetPoint("TOPLEFT")
    row.fill:SetPoint("BOTTOMLEFT")
    row.fill:SetWidth(1)
    row.glow = row:CreateTexture(nil, "BORDER", nil, 1)
    row.glow:SetAllPoints()
    row.fx = row:CreateTexture(nil, "BORDER", nil, 2) -- the class effect that plays over a bar when it lands
    row.fx:SetBlendMode("ADD")
    row.fx:Hide()
    row.sweep = row:CreateTexture(nil, "BORDER", nil, 3) -- light running once over the winner's row (uncommon and up)
    row.sweep:SetBlendMode("ADD")
    row.sweep:Hide()
    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetWidth(2)
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.flash = row:CreateTexture(nil, "OVERLAY", nil, 3)
    row.flash:SetAllPoints()
    row.flash:SetColorTexture(1, 1, 1, 1)
    row.flash:SetBlendMode("ADD")
    row.flashAnim = MakeFlash(row.flash, 0.5, 0.8)
    row.cls = row:CreateTexture(nil, "ARTWORK")
    row.cls:SetSize(14, 14)
    row.cls:SetPoint("LEFT", 6, 0)
    row.crown = row:CreateTexture(nil, "OVERLAY")
    row.crown:SetSize(18, 18)
    row.crown:SetPoint("CENTER", row.cls, "CENTER", 0, 1)
    if not TrySetFile(row.crown, CROWN) then
        row.crown:SetColorTexture(1, 0.82, 0, 1)
    end
    row.crownPop = MakePop(row.crown, 2.6, 0.45)
    row.name = Text(row, 12)
    row.name:SetPoint("LEFT", 26, 0)
    row.name:SetWidth(132)
    row.name:SetJustifyH("LEFT")
    row.ninja = row:CreateTexture(nil, "OVERLAY")
    row.ninja:SetSize(12, 12)
    row.ninja:SetPoint("LEFT", 162, 0)
    if TrySetFile(row.ninja, ns.NINJA_ICON_PATH) then
        row.ninja:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    row.choice = row:CreateTexture(nil, "ARTWORK")
    row.choice:SetSize(16, 16)
    row.choice:SetPoint("RIGHT", -48, 0)
    row.choicePop = MakePop(row.choice, 1.8, 0.3)
    row.tag = Text(row, 9, true)
    row.tag:SetPoint("RIGHT", row.choice, "LEFT", -1, 0)
    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(40, ROW_H)
    row.box:SetPoint("RIGHT", -4, 0)
    row.num = Text(row.box, 16, true)
    row.num:SetPoint("RIGHT")
    row.num:SetJustifyH("RIGHT")
    row.numPop = MakePop(row.box, 1.9, 0.35)
    return row
end

-- lucky / unlucky badge: what it means, with the average that earned it
local function BadgeEnter(self)
    if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L(self.lucky and "rw_lucky" or "rw_unlucky"),
            self.lucky and 0.4 or 1, self.lucky and 1 or 0.35, self.lucky and 0.55 or 0.3)
        GameTooltip:AddLine(L(self.lucky and "rw_lucky_tip" or "rw_unlucky_tip", self.avg), 1, 1, 1, true)
        GameTooltip:Show()
    end
end

local function MakeBoardRow()
    local row = CreateFrame("Frame", nil, win.boardPane)
    row:SetSize(INNER, BOARD_ROW_H - 2)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetWidth(2)
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.cls = row:CreateTexture(nil, "ARTWORK")
    row.cls:SetSize(14, 14)
    row.cls:SetPoint("LEFT", 6, 0)
    row.name = Text(row, 12)
    row.name:SetJustifyH("LEFT")
    row.stats = Text(row, 10)
    row.stats:SetPoint("LEFT", 26, -7)
    row.stats:SetJustifyH("LEFT")
    row.badge = CreateFrame("Button", nil, row)
    row.badge:SetSize(12, 12)
    row.badge.tex = row.badge:CreateTexture(nil, "ARTWORK")
    row.badge.tex:SetAllPoints()
    row.badge:SetScript("OnEnter", BadgeEnter)
    row.badge:SetScript("OnLeave", ns.ItemButtonLeave)
    row.none = Text(row, 12)
    row.none:SetText(MUTED .. "-|r")
    row.more = Text(row, 10)
    row.value = Text(row, 10)
    row.value:SetPoint("RIGHT", -6, 0)
    row.value:SetJustifyH("RIGHT")
    return row
end

local function TileEnter(self)
    ns.ItemButtonEnter(self)
    local res = self.res
    if res and GameTooltip then
        local st = res.kind and KIND_RGB[res.kind]
        GameTooltip:AddLine(ClassText(res.short, res.class) .. (res.roll and ("  " .. res.roll) or ""),
            st and st[1] or 1, st and st[2] or 1, st and st[3] or 1)
        GameTooltip:Show()
    end
end

local function MakeTile()
    local b = CreateFrame("Button", nil, win.boardPane)
    b:SetSize(TILE, TILE)
    MakeSlot(b, TILE)
    b.num = Text(b, 10, true)
    b.num:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1) -- inside the icon, like a stack count
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.18)
    b:SetScript("OnEnter", TileEnter)
    b:SetScript("OnLeave", ns.ItemButtonLeave)
    b:SetScript("OnClick", ns.ItemButtonClick)
    return b
end

local function MakeSparks(parent)
    local list = {}
    for i = 1, 12 do
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 5)
        t:SetSize(14, 14)
        if not TrySetFile(t, SPARK) then
            t:SetColorTexture(1, 1, 1, 1)
        end
        t:SetBlendMode("ADD")
        t:SetAlpha(0)
        local g = NewAnim(t)
        if g then
            t.move = AddAnim(g, "Translation", 0.9)
            local a = AddAnim(g, "Alpha", 0.9)
            if a then
                a:SetFromAlpha(1)
                a:SetToAlpha(0)
            end
            local r = AddAnim(g, "Rotation", 0.9)
            if r and r.SetDegrees then
                r:SetDegrees(i % 2 == 0 and 160 or -160)
            end
            t.anim = g
        end
        list[i] = t
    end
    return list
end

-- ===== position =====
local function StorePos(point, relPoint, x, y)
    if ns.db and type(point) == "string" and type(x) == "number" and type(y) == "number" then
        ns.db.rollWinPos = { point = point, relPoint = type(relPoint) == "string" and relPoint or point, x = x, y = y }
    end
end

local function Place(f)
    if f.moverOwned then
        return -- a UI addon's mover (ElvUI, TukUI, SpartanUI) keeps the anchor and the saved position
    end
    f:ClearAllPoints()
    local p = ns.db and ns.db.rollWinPos
    if type(p) == "table" and type(p.point) == "string" and type(p.relPoint) == "string"
        and type(p.x) == "number" and type(p.y) == "number" then
        if pcall(f.SetPoint, f, p.point, UIParent, p.relPoint, p.x, p.y) then
            return
        end
        f:ClearAllPoints()
    end
    -- not placed yet: right above the chat window (below it when the chat sits high on the screen), so it grows
    -- away from the chat. Anchored to the chat frame itself, so it follows a chat that is moved.
    local chat = DEFAULT_CHAT_FRAME
    local top, screen = chat and chat:GetTop(), UIParent:GetTop()
    if type(top) == "number" and type(screen) == "number" then
        local placed
        if top + 220 < screen then
            placed = pcall(f.SetPoint, f, "BOTTOMLEFT", chat, "TOPLEFT", -4, CHAT_GAP_ABOVE)
        else
            placed = pcall(f.SetPoint, f, "TOPLEFT", chat, "BOTTOMLEFT", -4, CHAT_GAP_BELOW)
        end
        if placed then
            return
        end
        f:ClearAllPoints()
    end
    f:SetPoint("CENTER", UIParent, "CENTER", 380, 160)
end

-- Remembers where the window is now, in screen coordinates. In the upper half of the screen it is anchored by its
-- top edge (it grows downwards), in the lower half by its bottom edge (it grows upwards, like above the chat).
local function SaveCurrentPos()
    if not win or win.moverOwned then
        return
    end
    local l, b, t = win:GetLeft(), win:GetBottom(), win:GetTop()
    local screen = UIParent:GetTop()
    if not (l and b and t and screen) then
        return
    end
    local k = UIParent:GetEffectiveScale() / win:GetEffectiveScale() -- UIParent units -> window units
    if (b + t) / 2 > screen * k / 2 then
        StorePos("TOPLEFT", "BOTTOMLEFT", l, t)
    else
        StorePos("BOTTOMLEFT", "BOTTOMLEFT", l, b)
    end
    Place(win)
end

local function ApplyWidth(w)
    W = math.max(MIN_W, math.min(MAX_W, math.floor(w + 0.5)))
    INNER = W - 2 * PAD
    if not win then
        return
    end
    win:SetWidth(W)
    local rp, bp = win.rollPane, win.boardPane
    rp.name:SetWidth(INNER - ICON - 8 - 44)
    rp.details:SetWidth(INNER - ICON - 8 - 50)
    rp.status:SetWidth(INNER - ICON - 8 - 8)
    rp.qglow:SetWidth(math.floor(W * 0.8))
    rp.timerBg:SetWidth(INNER)
    rp.shine.move:SetOffset(INNER + 60, 0)
    bp.line:SetWidth(INNER)
    bp.hint:SetWidth(INNER - 8)
end

-- Scales the window around its current place (the saved offsets are in the window's own units).
local function ApplyScale(s)
    s = math.max(MIN_SCALE, math.min(MAX_SCALE, math.floor(s * 20 + 0.5) / 20))
    local old = win:GetScale()
    local l, b, t = win:GetLeft(), win:GetBottom(), win:GetTop()
    win:SetScale(s)
    if ns.db then
        ns.db.rollWinScale = s
    end
    if l and b and t and old and old > 0 and not win.moverOwned then
        local k = old / s
        local screen = UIParent:GetTop()
        if screen and (b + t) / 2 * old > screen / 2 then
            StorePos("TOPLEFT", "BOTTOMLEFT", l * k, t * k)
        else
            StorePos("BOTTOMLEFT", "BOTTOMLEFT", l * k, b * k)
        end
        Place(win)
    end
end

-- Not resized yet: as wide as the chat window it sits on.
local function DefaultWidth()
    local chat = DEFAULT_CHAT_FRAME
    local w = chat and chat:GetWidth()
    if type(w) == "number" and w > 0 then
        return w + 8
    end
    return DEFAULT_W
end

local function ClearPos()
    if ns.db then
        ns.db.rollWinPos, ns.db.rollWinWidth, ns.db.rollWinScale = nil, nil, nil
    end
    if win then
        win:SetScale(1)
        ApplyWidth(DefaultWidth())
        Place(win)
    end
end

-- ===== the window =====
local hideToken = 0

local function ShowWindow()
    if not win then
        return
    end
    hideToken = hideToken + 1 -- cancels a fade-out that is still running
    if win.fadeOut then
        win.fadeOut:Stop()
    end
    win:SetAlpha(1)
    if not win:IsShown() then
        win:Show()
        Play(win.fadeIn)
    end
end

local function HideWindow(fade)
    if not win or not win:IsShown() then
        return
    end
    hideToken = hideToken + 1
    local token = hideToken
    if fade and win.fadeOut then
        Play(win.fadeOut)
        After(0.3, function()
            if token == hideToken then
                win:Hide()
            end
        end)
    else
        win:Hide()
    end
end

local function SetMode(m)
    if mode == m then
        return
    end
    mode = m
    win.rollPane:SetShown(m == "roll")
    win.boardPane:SetShown(m == "board")
    Play(m == "roll" and win.rollPane.fadeIn or win.boardPane.fadeIn)
end

local function Close()
    userClosed = RunKey()
    pinned = false
    for _, d in ipairs(queue) do
        d.dismissed = true -- the rolls already running stay away; the next new roll opens the window again
    end
    if win then
        win.placing = false
    end
    HideWindow(true)
end

local function BuildRollPane(rp)
    -- a wash of the item's quality color behind the header (it breathes for epic and better items)
    rp.qglow = rp:CreateTexture(nil, "BACKGROUND", nil, 2)
    rp.qglow:SetPoint("TOPLEFT", 2, -2)
    rp.qglow:SetHeight(ROLL_HEAD - 10)
    rp.item = CreateFrame("Button", nil, rp)
    rp.item:SetSize(ICON, ICON)
    rp.item:SetPoint("TOPLEFT", PAD, -PAD)
    MakeSlot(rp.item, ICON)
    rp.item:SetScript("OnEnter", ns.ItemButtonEnter)
    rp.item:SetScript("OnLeave", ns.ItemButtonLeave)
    rp.item:SetScript("OnClick", ns.ItemButtonClick)
    rp.burst = rp:CreateTexture(nil, "ARTWORK")
    rp.burst:SetSize(ICON * 1.6, ICON * 1.6)
    rp.burst:SetPoint("CENTER", rp.item, "CENTER")
    if TrySetFile(rp.burst, ART.glow) then
        rp.burst:SetBlendMode("ADD")
    else
        rp.burst:SetColorTexture(1, 1, 1, 0.4)
    end
    rp.burstAnim = MakeFlash(rp.burst, 1, 0.9, 0.6, 1.2) -- stays around the icon, never over the window
    -- rare and up: the icon glows softly in its quality color; legendary: slow rays behind it after the win
    rp.iconGlow = rp:CreateTexture(nil, "ARTWORK", nil, -1)
    rp.iconGlow:SetSize(ICON * 1.9, ICON * 1.9)
    rp.iconGlow:SetPoint("CENTER", rp.item, "CENTER")
    rp.iconGlow.ok = TrySetFile(rp.iconGlow, ART.glow)
    if rp.iconGlow.ok then
        rp.iconGlow:SetBlendMode("ADD")
    end
    rp.iconGlow:Hide()
    rp.rays = RollFX.NewRays(rp, rp.item, ICON * 2.2)
    rp.name = Text(rp, 13)
    rp.name:SetPoint("TOPLEFT", rp.item, "TOPRIGHT", 8, -1)
    rp.name:SetJustifyH("LEFT")
    rp.details = Text(rp, 10)
    rp.details:SetPoint("TOPLEFT", rp.name, "BOTTOMLEFT", 0, -3)
    rp.details:SetJustifyH("LEFT")
    rp.status = Text(rp, 11)
    rp.status:SetPoint("TOPLEFT", rp.details, "BOTTOMLEFT", 0, -4)
    rp.status:SetJustifyH("LEFT")
    rp.queue = Text(rp, 10)
    rp.queue:SetPoint("TOPRIGHT", rp, "TOPRIGHT", -28, -11)
    rp.value = Text(rp, 10) -- the auction house value, when a price addon knows the item
    rp.value:SetPoint("TOPRIGHT", rp, "TOPRIGHT", -10, -26)
    rp.value:SetJustifyH("RIGHT")
    rp.timerBg = rp:CreateTexture(nil, "ARTWORK")
    rp.timerBg:SetPoint("TOPLEFT", PAD, -(ROLL_HEAD - 7))
    rp.timerBg:SetSize(INNER, 3)
    rp.timerBg:SetColorTexture(1, 1, 1, 0.07)
    rp.timer = rp:CreateTexture(nil, "ARTWORK", nil, 1)
    rp.timer:SetPoint("LEFT", rp.timerBg, "LEFT")
    rp.timer:SetSize(INNER, 3)
    rp.timer:SetColorTexture(1, 1, 1, 1)
    -- a light sweeping over the header every few seconds while the roll is open (like a slot machine's glass)
    local clip = CreateFrame("Frame", nil, rp)
    clip:SetPoint("TOPLEFT", 2, -2)
    clip:SetPoint("TOPRIGHT", -2, -2)
    clip:SetHeight(ROLL_HEAD - 8)
    if clip.SetClipsChildren then
        clip:SetClipsChildren(true)
    end
    local shine = clip:CreateTexture(nil, "OVERLAY")
    shine:SetSize(48, ROLL_HEAD)
    shine:SetPoint("RIGHT", clip, "LEFT", 0, 0)
    Gradient(shine, "HORIZONTAL", 1, 1, 1, 0, 1, 0.95, 0.8, 0.16)
    shine:SetBlendMode("ADD")
    rp.shine = NewAnim(shine) or { Play = function() end, Stop = function() end }
    if rp.shine.SetLooping then
        rp.shine:SetLooping("REPEAT")
        rp.shine.move = AddAnim(rp.shine, "Translation", 1.1)
        if rp.shine.move and rp.shine.move.SetStartDelay then
            rp.shine.move:SetStartDelay(1.6)
        end
    end
    rp.shine.move = rp.shine.move or { SetOffset = function() end }
    rp.fadeIn = MakePop(rp, 1, 0.2)
end

-- The grip at the lower right corner drags the width (the height always follows the content).
local function BuildGrip(f)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(11, 11)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    local tex = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
    pcall(grip.SetNormalTexture, grip, tex .. "Up")
    pcall(grip.SetHighlightTexture, grip, tex .. "Highlight")
    pcall(grip.SetPushedTexture, grip, tex .. "Down")
    grip:SetAlpha(0) -- shows only while the mouse is on the window
    grip:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Who Won That")
            GameTooltip:AddLine(L("rw_tip"), 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    grip:SetScript("OnLeave", function(self)
        ns.ItemButtonLeave()
        self:SetAlpha(f:IsMouseOver() and 0.6 or 0)
    end)
    grip:SetScript("OnMouseDown", function(self)
        if not GetCursorPosition then
            return
        end
        SaveCurrentPos() -- anchored by the left edge now, so the width grows to the right
        self.startX, self.startW = GetCursorPosition() / f:GetEffectiveScale(), W
        self:SetScript("OnUpdate", function()
            local x = GetCursorPosition() / f:GetEffectiveScale()
            local before = W
            ApplyWidth(self.startW + x - self.startX)
            if W ~= before then
                if mode == "roll" then
                    RenderRoll()
                elseif mode == "board" then
                    RenderBoard()
                end
            end
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if ns.db then
            ns.db.rollWinWidth = W
        end
        SaveCurrentPos()
    end)
    return grip
end

local function BuildBoardPane(bp)
    bp.title = Text(bp, 13)
    bp.title:SetPoint("TOPLEFT", PAD + 2, -9)
    bp.title:SetText("Who Won That")
    bp.sub = Text(bp, 10)
    bp.sub:SetPoint("LEFT", bp.title, "RIGHT", 8, -1)
    bp.sub:SetPoint("RIGHT", bp, "RIGHT", -28, 0)
    bp.sub:SetJustifyH("LEFT")
    bp.line = bp:CreateTexture(nil, "ARTWORK")
    bp.line:SetPoint("TOPLEFT", PAD, -(BOARD_HEAD - 3))
    bp.line:SetSize(INNER, 1)
    bp.hint = Text(bp, 11)
    bp.hint:SetJustifyH("LEFT")
    bp.hint:SetWidth(INNER - 8)
    bp.fadeIn = MakePop(bp, 1, 0.2)
end

local function SaveDraggedPos(self)
    self:StopMovingOrSizing()
    SaveCurrentPos()
end

-- Ctrl + mouse wheel scales the window
local function OnWheel(self, delta)
    if IsControlKeyDown and IsControlKeyDown() then
        ApplyScale(self:GetScale() + (delta > 0 and 0.05 or -0.05))
    end
end

local function Restyle()
    if not win then
        return
    end
    if win.themeKind ~= Theme.Kind() then
        if win.SetBackdrop then
            pcall(win.SetBackdrop, win, nil)
        end
        win.themeKind = Theme.Panel(win)
    end
    for _, f in ipairs(fonts) do
        Theme.SetFont(f[1], f[2], f[3])
    end
    if mode == "roll" then
        RenderRoll()
    elseif mode == "board" then
        RenderBoard()
    end
end

local function BuildWindow()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local ok, f = pcall(CreateFrame, "Frame", WINDOW_NAME, UIParent, template)
    if not ok or not f then
        f = CreateFrame("Frame", WINDOW_NAME, UIParent)
    end
    win = f
    f:SetSize(W, 120)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not self.moverOwned then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", SaveDraggedPos)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            Close()
        end
    end)
    -- no tooltip on the window itself (it would cover the game on every pass); the grip carries the hint
    f:SetScript("OnEnter", function(self)
        if self.grip then
            self.grip:SetAlpha(0.6)
        end
    end)
    f:SetScript("OnLeave", function(self)
        if self.grip and not self:IsMouseOver() then
            self.grip:SetAlpha(0)
        end
    end)
    f.themeKind = Theme.Panel(f)

    f.rollPane = CreateFrame("Frame", nil, f)
    f.rollPane:SetAllPoints()
    f.boardPane = CreateFrame("Frame", nil, f)
    f.boardPane:SetAllPoints()
    BuildRollPane(f.rollPane)
    BuildBoardPane(f.boardPane)
    f.sparks = MakeSparks(f.rollPane)
    f.motes = RollFX.NewEmitter(f.rollPane, 32)
    f.edge = RollFX.NewEdge(f)
    f.rollPane:Hide()
    f.boardPane:Hide()

    f.close = Theme.CloseButton(f)
    f.close:SetPoint("TOPRIGHT", -3, -3)
    f.close:SetFrameLevel(f:GetFrameLevel() + 10)
    f.close:SetScript("OnClick", Close)
    f.grip = BuildGrip(f)
    if f.EnableMouseWheel then
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", OnWheel)
    end
    local saved = ns.db and ns.db.rollWinScale
    if type(saved) == "number" and saved >= MIN_SCALE and saved <= MAX_SCALE then
        f:SetScale(saved)
    end
    ApplyWidth(type(ns.db and ns.db.rollWinWidth) == "number" and ns.db.rollWinWidth or DefaultWidth())

    f.fadeIn = MakePop(f, 1, 0.25)
    f.fadeOut = MakeFlash(f, 1, 0.25)
    if f.fadeOut and f.fadeOut.SetToFinalAlpha then
        f.fadeOut:SetToFinalAlpha(true) -- stays invisible until it is hidden (ShowWindow restores the alpha)
    end
    f:SetAlpha(1) -- MakeFlash rests its region at 0; the window itself must stay visible
    rollRows, boardRows, tiles = Pool(MakeRollRow), Pool(MakeBoardRow), Pool(MakeTile)
    f:Hide()
    Place(f)
    Theme.OnRestyle(Restyle)
    return f
end

local buildFailed = false
-- Right after login the client has not loaded most items yet: once their data arrives, draw the window again so
-- the item type, slot and level show up. Several items often arrive together, so one redraw covers them all.
local itemInfoPending = false
local function OnItemInfo()
    if itemInfoPending or not (win and win:IsShown()) then
        return
    end
    itemInfoPending = true
    C_Timer.After(0.1, function()
        itemInfoPending = false
        if win and win:IsShown() then
            Restyle()
        end
    end)
end

local function EnsureWindow()
    if win or buildFailed then
        return win
    end
    local ok, err = pcall(BuildWindow)
    if not ok then
        buildFailed = true
        win = nil
        if geterrorhandler then
            geterrorhandler()(err)
        end
    elseif win.RegisterEvent and pcall(win.RegisterEvent, win, "GET_ITEM_INFO_RECEIVED") then
        win:SetScript("OnEvent", OnItemInfo)
    end
    return win
end

-- ===== roll mode =====
local function StateOf(state)
    if not PlainNumber(state) or state == ROLL_STATE.NoRoll then
        return nil
    end
    if state == ROLL_STATE.Transmog then
        return STATE_INFO[ROLL_STATE.Greed] -- shown like Greed (WoW Forever has no transmog rolls anyway)
    end
    return STATE_INFO[state]
end

-- in the race for the item: chose Need or Greed, has a number, and is not out (see Merge)
local function Rolls(p)
    return p.st ~= nil and p.st.kind ~= "pass" and not p.out and p.roll ~= nil
end

-- best roll first: Need before Need OS before Greed, then the higher number (how the game picks the winner)
local function Better(a, b)
    if a.st.rank ~= b.st.rank then
        return a.st.rank < b.st.rank
    end
    if a.roll ~= b.roll then
        return a.roll > b.roll
    end
    return a.order < b.order
end

local function Leader(d)
    local best
    for _, p in ipairs(d.list) do
        if p.shown and Rolls(p) and (not best or Better(p, best)) then
            best = p
        end
    end
    return best
end

-- landed numbers on top (best first), then those still to land, then players still choosing, passes last
local function Group(p)
    if p.shown and Rolls(p) then
        return 1
    elseif p.st and (p.st.kind == "pass" or p.out) then
        return 4
    elseif p.st then
        return 2
    end
    return 3
end

local function DisplayOrder(a, b)
    local ga, gb = Group(a), Group(b)
    if ga ~= gb then
        return ga < gb
    end
    if ga == 1 then
        return Better(a, b)
    end
    return a.order < b.order
end

local function FillWidth(roll)
    return math.max(1, INNER * math.min(roll, 100) / 100)
end

-- A bar in a deep shade of the player's class color: the name on top is drawn in the full class color, so it
-- always stands out against its own bar. The winner's bar is a little brighter.
local function BarColor(p)
    local c = ClassColor(p.class)
    if c and type(c.r) == "number" then
        return c.r, c.g, c.b
    end
    local k = KIND_RGB[p.st.kind]
    return k[1], k[2], k[3]
end

local function PaintFill(row, p, width, winner)
    local r, g, b = BarColor(p)
    local s = winner and 0.6 or 0.42
    Gradient(row.fill, "HORIZONTAL", r * s, g * s, b * s, 0.95, r * s * 0.55, g * s * 0.55, b * s * 0.55, 0.8)
    row.fill:SetWidth(math.max(1, width))
    row.fill:Show()
end

local function PlaceRow(row)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", win.rollPane, "TOPLEFT", PAD + (row.dx or 0), -row.y)
end

-- ===== class effects: each of WoW Forever's classes lands its bar in its own way =====
local FX_TIME = 0.9

-- a soft band of light over part of a bar, x and width in pixels from the bar's left end
local function Band(row, x, width, r, g, b, a, hard)
    x = math.max(0, x)
    width = math.max(1, width)
    row.fx:ClearAllPoints()
    row.fx:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
    row.fx:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
    row.fx:SetWidth(width)
    if hard then
        row.fx:SetColorTexture(r, g, b, a)
    else
        Gradient(row.fx, "HORIZONTAL", r, g, b, 0, r, g, b, a)
    end
    row.fx:Show()
end

-- Each effect gets the progress t (0 to 1), the bar's full width w and the class color, draws its light and
-- returns the bar width for this frame (some classes bend the bar itself).
local FX = {}
function FX.WARRIOR(row, t, w, r, g, b) -- slam: the bar overshoots, the row shakes, a hard flash
    row.dx = math.sin(t * 40) * 3 * (1 - t) ^ 2
    Band(row, 0, w, r, g, b, 0.5 * (1 - t) ^ 3, true)
    return w * (1 + 0.1 * math.sin(t * math.pi * 3) * (1 - t))
end
function FX.ROGUE(row, t, w, r, g, b) -- two quick dashes run along the bar
    local phase = (t * 2) % 1
    Band(row, phase * w - 34, 34, math.min(1, r + 0.4), math.min(1, g + 0.4), math.min(1, b + 0.4), 0.8 * (1 - t))
    return w
end
function FX.HUNTER(row, t, w, r, g, b) -- an arrow flies to the end of the bar and hits
    if t < 0.55 then
        Band(row, w * t / 0.55 - 44, 44, 1, 1, 0.85, 0.85)
    else
        Band(row, w - 16, 16, r, g, b, 0.9 * (1 - (t - 0.55) / 0.45), true)
    end
    return w
end
function FX.MAGE(row, t, w) -- a frosty shimmer drifts across
    Band(row, t * (w + 60) - 60, 60, 0.65, 0.9, 1, 0.6 * math.sin(math.pi * t))
    return w
end
function FX.PRIEST(row, t, w) -- the whole bar glows with holy light
    Band(row, 0, w, 1, 0.97, 0.85, 0.45 * math.sin(math.pi * t), true)
    return w
end
function FX.PALADIN(row, t, w) -- golden radiance spreads from the left
    Band(row, 0, w * math.min(1, t * 1.6), 1, 0.82, 0.35, 0.55 * (1 - t))
    return w
end
function FX.DRUID(row, t, w, r, g, b) -- the bar grows like a plant, with a little sway
    Band(row, 0, w, r * 0.6, g, b * 0.6, 0.3 * (1 - t), true)
    return w * (1 + 0.14 * math.sin(t * 13) * (1 - t))
end
function FX.SHAMAN(row, t, w) -- lightning strobes over the bar
    if math.floor(t * 14) % 3 == 0 then
        Band(row, 0, w, 0.55, 0.75, 1, 0.65 * (1 - t), true)
    else
        row.fx:Hide()
    end
    return w
end
function FX.WARLOCK(row, t, w) -- fel fire flickers
    Band(row, 0, w, 0.45, 1, 0.3, math.random() * 0.45 * (1 - t), true)
    return w
end
local function DefaultFX(row, t, w, r, g, b) -- an unknown class: a sweep in its own color
    Band(row, t * (w + 50) - 50, 50, r, g, b, 0.7 * math.sin(math.pi * t))
    return w
end

-- One frame of a landed bar's effect; false once it is over (the bar is then left as PaintRollRow drew it).
local function ClassFX(row, p, now, winner)
    local t = (now - row.fxStart) / FX_TIME
    local w = FillWidth(p.roll)
    if t >= 1 then
        row.fxStart = nil
        row.fx:Hide()
        row.dx = 0
        PlaceRow(row)
        PaintFill(row, p, w, winner)
        return false
    end
    local r, g, b = BarColor(p)
    local fx = (type(p.class) == "string" and FX[p.class]) or DefaultFX
    PaintFill(row, p, fx(row, t, w, r, g, b), winner)
    if row.dx and row.dx ~= 0 then
        PlaceRow(row)
    end
    return true
end

local function Me(d)
    for _, p in ipairs(d.list) do
        if p.isSelf then
            return p
        end
    end
    return nil
end

-- " · You lead!" / " · You: #2 of 4" while the numbers land (only once your own number is in)
local function MyPosition(d)
    local me = Me(d)
    if not (me and me.shown and Rolls(me)) then
        return ""
    end
    local pos, total = 1, 0
    for _, p in ipairs(d.list) do
        if p.shown and Rolls(p) then
            total = total + 1
            if p ~= me and Better(p, me) then
                pos = pos + 1
            end
        end
    end
    if total < 2 then
        return ""
    end
    if pos == 1 then
        local r, g, b = Theme.Accent()
        return MUTED .. ns.SUMMARY_DOT .. "|r" .. Hex(r, g, b) .. L("rw_you_lead") .. "|r"
    end
    return MUTED .. ns.SUMMARY_DOT .. L("rw_you_pos", pos, total) .. "|r"
end

-- " Missed by 2" when you lost to a roll of the same kind by a hair
local function MissedBy(d)
    local me, w = Me(d), d.winner
    if not (me and w and me ~= w and Rolls(me) and Rolls(w) and me.st.rank == w.st.rank) then
        return ""
    end
    local diff = w.roll - me.roll
    if diff > MISSED_BY then
        return ""
    end
    return "  |cffff5a4a" .. L("rw_missed", diff) .. "|r"
end

local function StatusText(d)
    if d.celebrated then
        if d.allPassed or not d.winner then
            return MUTED .. L("rw_all_passed") .. "|r"
        end
        local text = L("rw_wins", ClassText(d.winner.short, d.winner.class))
        if d.winner.isSelf then
            local r, g, b = Theme.Accent()
            text = Hex(r, g, b) .. L("rw_you_won") .. "|r"
        end
        local missed = MissedBy(d)
        if missed ~= "" then
            return text .. missed
        end
        if d.photoFinish then
            text = text .. "  |cffff7b5c" .. L("rw_close") .. "|r"
        end
        return text
    end
    local chosen = 0
    for _, p in ipairs(d.list) do
        if p.st then
            chosen = chosen + 1
        end
    end
    if not d.done and chosen < #d.list then
        return MUTED .. L("rw_choosing", chosen, #d.list) .. "|r"
    end
    return "|cffffffff" .. L("rw_rolling") .. "|r " .. MyPosition(d)
end

-- A player who chose Need or Greed but whose number the game has not given yet: the reel already spins (dimmed),
-- so the roll is under way from the first pick instead of waiting for the end.
function Early.IdleSpin(p, d)
    return not d.done and p.st ~= nil and p.st.kind ~= "pass" and not p.out and not p.roll and not p.revealAt
end

-- The auction house value in the header; `frac` < 1 while it counts up after the win.
function Rarity.ValueText(look, frac)
    if not look.price then
        return ""
    end
    local color = look.band >= 1 and "|cffd9b56a" or MUTED
    return color .. ns.FormatMoney(math.floor(look.price * frac / 100) * 100) .. "|r"
end

local function PaintRollRow(row, p, d, leader, index)
    local st = p.st
    local passed = st and (st.kind == "pass" or p.out) -- a pass, or a Greed that cannot win against a Need
    local isWinner = d.celebrated and d.winner == p and not d.allPassed
    local ar, ag, ab = Theme.Accent()
    local dimmed = d.suspenseOn and d.look and d.look.tier.dim and not (p.suspense and not p.shown)
    row:SetAlpha(passed and 0.45 or (dimmed and 0.5) or 1)
    if p.isSelf then
        row.bg:SetColorTexture(ar, ag, ab, 0.07)
    else
        row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.035 or 0.012)
    end
    row:SetWidth(INNER)
    local nameW = INNER - 132
    row.name:SetWidth(nameW)
    row.name:SetText(p.short)
    SetClassColor(row.name, p.class)
    if isWinner then
        row.cls:Hide()
        row.crown:Show()
    else
        SetClassIcon(row.cls, p.class)
        row.crown:Hide()
    end
    local ninja = st ~= nil and st.kind == "need" and not CanClassUse(p.class, d.item)
    row.ninja:SetShown(ninja)
    if ninja then
        row.ninja:ClearAllPoints()
        row.ninja:SetPoint("LEFT", row.name, "LEFT", math.min(row.name:GetStringWidth() or 0, nameW) + 4, 0)
    end
    if st then
        TrySetFile(row.choice, KIND_TEXTURE[st.kind])
        row.choice:Show()
        if row.shownSt ~= st then
            row.shownSt = st
            Play(row.choicePop)
        end
    else
        row.choice:Hide()
        row.shownSt = nil
    end
    local tagColor = st and KIND_RGB[st.kind]
    row.tag:SetText(st and st.tag or "")
    if tagColor then
        row.tag:SetTextColor(tagColor[1], tagColor[2], tagColor[3])
    end
    row.fill:Hide()
    if not row.fxStart then
        row.fx:Hide()
    end
    if passed then
        row.num:SetText(p.out and "-" or "")
        row.num:SetTextColor(0.55, 0.55, 0.55)
    elseif p.shown and Rolls(p) then
        row.num:SetText(p.roll)
        if isWinner then
            row.num:SetTextColor(0.3, 1, 0.35)
        elseif leader == p then
            row.num:SetTextColor(ar, ag, ab)
        else
            row.num:SetTextColor(1, 1, 1)
        end
        if not row.fxStart then
            PaintFill(row, p, FillWidth(p.roll), isWinner)
        end
    elseif p.revealAt then
        row.num:SetText("?") -- the spin itself is drawn by the OnUpdate animation
        row.num:SetTextColor(0.85, 0.85, 0.85)
        row.fill:SetWidth(1)
    elseif Early.IdleSpin(p, d) then
        row.num:SetText(math.random(1, 100)) -- the OnUpdate animation keeps it turning
        row.num:SetTextColor(0.5, 0.5, 0.5)
    elseif st then
        row.num:SetText(d.done and "-" or "?")
        row.num:SetTextColor(0.55, 0.55, 0.55)
    else
        row.num:SetText(DOTS[3])
        row.num:SetTextColor(0.55, 0.55, 0.55)
    end
    local mr, mg, mb = ar, ag, ab
    if isWinner and d.look and d.look.tier.mark then
        mr, mg, mb = d.look.fr, d.look.fg, d.look.fb -- rare and up: the winner is marked in the quality color
    end
    row.edge:SetShown(isWinner or (leader == p and not d.celebrated))
    row.edge:SetColorTexture(mr, mg, mb, 0.9)
    if isWinner then
        Gradient(row.glow, "HORIZONTAL", mr, mg, mb, 0.35, mr, mg, mb, 0)
        row.glow:Show()
    else
        row.glow:Hide()
    end
end

function RenderRoll()
    local d = current
    if not (win and d) then
        return
    end
    local rp = win.rollPane
    SetSlotItem(rp.item, d.item)
    rp.name:SetText(ItemLabel(d.item))
    local look = RollFX.Look(d.item)
    d.look = look
    local tier = look.tier
    local quality = ""
    if look.quality >= 5 then -- a legendary says so above everything else
        local word = _G.ITEM_QUALITY5_DESC
        quality = Hex(look.r, look.g, look.b) .. (type(word) == "string" and word or "Legendary") .. "|r  "
    end
    rp.details:SetText(quality .. MUTED .. ItemDetails(d.item) .. "|r")
    rp.status:SetText(StatusText(d))
    Gradient(rp.qglow, "HORIZONTAL", look.r, look.g, look.b, tier.wash, look.r, look.g, look.b, 0)
    rp.iconGlow:SetShown(rp.iconGlow.ok and tier.iconGlow == true)
    rp.iconGlow:SetVertexColor(look.r, look.g, look.b, 0.45)
    if tier.reveal and not d.nameFadeAt and not d.celebrated then
        d.nameFadeAt = GetTime() -- the name of a legendary fades in slowly
    elseif not d.nameFadeAt then
        rp.name:SetAlpha(1)
    end
    if not d.countAt then
        rp.value:SetText(Rarity.ValueText(look, 1))
    end
    rp.queue:SetText(#queue > 1 and (MUTED .. "+" .. (#queue - 1) .. "|r") or "")
    local ar, ag, ab = Theme.Accent()
    rp.timer:SetColorTexture(ar, ag, ab, 0.9)
    rp.timerBg:SetShown(not d.done)
    rp.timer:SetShown(not d.done)
    if d.done then
        rp.shine:Stop()
    elseif not (rp.shine.IsPlaying and rp.shine:IsPlaying()) then
        rp.shine:Play()
    end
    local order = {}
    for i, p in ipairs(d.list) do
        order[i] = p
    end
    table.sort(order, DisplayOrder)
    local leader = Leader(d)
    for i, p in ipairs(order) do
        local row = p.row
        if not row then
            row = Take(rollRows)
            row.shownSt, row.y, row.fxStart, row.dx = nil, nil, nil, 0
            p.row = row
        end
        row.ty = ROLL_HEAD + (i - 1) * ROW_H
        if not row.y then
            row.y = row.ty
            PlaceRow(row)
        end
        PaintRollRow(row, p, d, leader, i)
    end
    win:SetHeight(ROLL_HEAD + math.max(#order, 1) * ROW_H + FOOT)
    StartAnimating()
end

-- ===== board mode =====
local function GroupUnits()
    local units = { "player" }
    if IsInRaid and IsInRaid() and GetNumGroupMembers then
        for i = 1, math.min(GetNumGroupMembers() or 0, 40) do
            units[#units + 1] = "raid" .. i
        end
    else
        for i = 1, 4 do
            units[#units + 1] = "party" .. i
        end
    end
    return units
end

-- Everyone in the group (you first) plus anyone who won something and left, each with their wins.
-- In a raid only players with loot are listed (and you), the most loot first.
local function BoardPlayers()
    local list, by = {}, {}
    local function Add(full, class, isSelf)
        if not UsableName(full) or #full > 64 then
            return nil
        end
        local short = ShortName(full)
        local e = by[short]
        if not e then
            e = { short = short, items = {}, order = #list + 1 }
            by[short] = e
            list[#list + 1] = e
        end
        if not e.class and UsableName(class) then
            e.class = class
        end
        if isSelf then
            e.isSelf = true
        end
        return e
    end
    for _, unit in ipairs(GroupUnits()) do
        if not UnitExists or UnitExists(unit) then
            local ok, name, realm = pcall(UnitName, unit)
            if ok and UsableName(name) then
                local okc, _, class = pcall(UnitClass, unit)
                local full = UsableName(realm) and (name .. "-" .. realm) or name
                Add(full, okc and class or nil, unit == "player")
            end
        end
    end
    for _, res in ipairs(results) do
        local e = Add(res.full, res.class, res.isSelf)
        if e then
            e.items[#e.items + 1] = res
        end
    end
    if IsInRaid and IsInRaid() then
        local keep = {}
        for _, e in ipairs(list) do
            if e.isSelf or #e.items > 0 then
                keep[#keep + 1] = e
            end
        end
        table.sort(keep, function(a, b)
            if #a.items ~= #b.items then
                return #a.items > #b.items
            end
            return a.order < b.order
        end)
        list = keep
    end
    local hidden = math.max(0, #list - MAX_BOARD_ROWS)
    for i = #list, MAX_BOARD_ROWS + 1, -1 do
        list[i] = nil
    end
    return list, hidden
end

-- Every number rolled in the run counts, not only the winning ones.
local function RecordLuck(d)
    for _, p in ipairs(d.list) do
        if Rolls(p) then
            local e = luck[p.short]
            if not e then
                e = { n = 0, sum = 0, best = 0 }
                luck[p.short] = e
            end
            e.n, e.sum, e.best = e.n + 1, e.sum + p.roll, math.max(e.best, p.roll)
        end
    end
end

-- The players with the highest and the lowest average roll (at least LUCK_MIN_ROLLS rolls, two players needed).
local function LuckBadges()
    local hi, lo, count
    count = 0
    for short, e in pairs(luck) do
        if e.n >= LUCK_MIN_ROLLS then
            count = count + 1
            local avg = e.sum / e.n
            if not hi or avg > hi.avg then
                hi = { short = short, avg = avg }
            end
            if not lo or avg < lo.avg then
                lo = { short = short, avg = avg }
            end
        end
    end
    if count < 2 or hi.avg == lo.avg then
        return nil, nil
    end
    return hi, lo
end

local function PlayerValue(e)
    if not (ns.db and ns.db.showValues and ns.ItemPrice) then
        return nil
    end
    local sum = 0
    for _, res in ipairs(e.items) do
        local ok, price = pcall(ns.ItemPrice, res.item)
        if ok and PlainNumber(price) then
            sum = sum + price
        end
    end
    return sum > 0 and sum or nil
end

function RenderBoard()
    if not win then
        return
    end
    CheckRun()
    local bp = win.boardPane
    Release(boardRows)
    Release(tiles)
    local ar, ag, ab = Theme.Accent()
    bp.title:SetTextColor(ar, ag, ab)
    bp.line:SetColorTexture(ar, ag, ab, 0.35)
    local run = ns.summaryRun
    local sub = ns.Count("items", #results)
    if run and UsableName(run.name) then
        sub = run.name .. ns.SUMMARY_DOT .. sub
    end
    bp.sub:SetText(MUTED .. sub .. "|r")
    local players, hidden = BoardPlayers()
    local nameCol = math.max(NAME_COL_MIN, math.min(NAME_COL_MAX, math.floor(INNER * 0.38)))
    local lucky, unlucky = LuckBadges()
    local y = BOARD_HEAD
    for i, e in ipairs(players) do
        local row = Take(boardRows)
        row:SetPoint("TOPLEFT", bp, "TOPLEFT", PAD, -y)
        row:SetWidth(INNER)
        if e.isSelf then
            row.bg:SetColorTexture(ar, ag, ab, 0.07)
            row.edge:SetColorTexture(ar, ag, ab, 0.85)
            row.edge:Show()
        else
            row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.035 or 0.012)
            row.edge:Hide()
        end
        SetClassIcon(row.cls, e.class)
        row.name:SetWidth(nameCol - 30)
        row.none:ClearAllPoints()
        row.none:SetPoint("LEFT", nameCol + 2, 0)
        row.name:SetText(e.short)
        SetClassColor(row.name, e.class)
        local stats = luck[e.short]
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 26, stats and 6 or 0)
        row.stats:SetWidth(nameCol - 30)
        row.stats:SetText(stats and (MUTED .. L("rw_stats", math.floor(stats.sum / stats.n + 0.5), stats.best) .. "|r") or "")
        local badge = (lucky and lucky.short == e.short and lucky) or (unlucky and unlucky.short == e.short and unlucky)
        row.badge:SetShown(badge ~= nil and badge ~= false)
        if badge then
            row.badge.lucky = badge == lucky
            row.badge.avg = math.floor(badge.avg + 0.5)
            TrySetFile(row.badge.tex, row.badge.lucky and LUCKY_ICON or UNLUCKY_ICON)
            row.badge:ClearAllPoints()
            row.badge:SetPoint("LEFT", row.name, "LEFT", math.min(row.name:GetStringWidth() or 0, nameCol - 44) + 4, 0)
        end
        local value = PlayerValue(e)
        row.value:SetText(value and ns.FormatMoney(value) or "")
        local valueW = value and ((row.value:GetStringWidth() or 0) + 10) or 0
        local fit = math.max(1, math.floor((INNER - nameCol - 4 - valueW + TILE_GAP) / (TILE + TILE_GAP)))
        local n = #e.items
        local show = n > fit and fit - 1 or n
        row.none:SetShown(n == 0)
        for k = 1, show do
            local res = e.items[n - k + 1] -- newest first
            local t = Take(tiles)
            t:SetPoint("LEFT", row, "LEFT", nameCol + (k - 1) * (TILE + TILE_GAP), 0)
            t:SetFrameLevel(row:GetFrameLevel() + 2)
            SetSlotItem(t, res.item)
            t.res = res
            local c = res.kind and KIND_RGB[res.kind]
            t.num:SetText(res.roll or "")
            if c then
                t.num:SetTextColor(c[1], c[2], c[3])
            end
            MarkCantUse(t, res.kind == "need" and not CanClassUse(e.class, res.item))
        end
        row.more:SetText(n > show and (MUTED .. "+" .. (n - show) .. "|r") or "")
        row.more:ClearAllPoints()
        row.more:SetPoint("LEFT", row, "LEFT", nameCol + show * (TILE + TILE_GAP) + 2, 0)
        y = y + BOARD_ROW_H
    end
    local hint
    if hidden > 0 then
        hint = L("more_n", hidden)
    elseif #results == 0 then
        hint = L("rw_no_loot")
    end
    bp.hint:SetShown(hint ~= nil)
    if hint then
        bp.hint:ClearAllPoints()
        bp.hint:SetPoint("TOPLEFT", bp, "TOPLEFT", PAD + 4, -(y + 4))
        bp.hint:SetText(MUTED .. hint .. "|r")
        y = y + 20
    end
    win:SetHeight(y + FOOT)
end

-- ===== animation (OnUpdate, only while something moves) =====
local function Tick(self, elapsed)
    local now = GetTime()
    local busy = false
    local d = current
    if mode == "roll" and d then
        local rp = self.rollPane
        if not d.done then
            busy = true
            local look = d.look
            if look and look.tier.breathe then
                -- the epic wash breathes slowly. Redrawn here rather than with an alpha animation: on this client
                -- an animated gradient texture loses its colors and flashes white.
                local a = look.tier.wash * (0.6 + 0.2 * (math.sin(now * 1.75) + 1))
                Gradient(rp.qglow, "HORIZONTAL", look.r, look.g, look.b, a, look.r, look.g, look.b, 0)
            end
            local t = rollTimers[d.itemID]
            if t and t.endsAt > now then
                local frac = math.min(1, (t.endsAt - now) / t.duration)
                rp.timer:ClearAllPoints()
                rp.timer:SetPoint("LEFT", rp.timerBg, "LEFT")
                rp.timer:SetWidth(math.max(1, INNER * frac))
                if frac < 0.25 then
                    rp.timer:SetColorTexture(1, 0.3, 0.25, 0.6 + 0.4 * math.abs(math.sin(now * 6)))
                end
            else
                -- no countdown known: a short light sweeps back and forth while the group decides
                local seg = 46
                rp.timer:SetWidth(seg)
                rp.timer:ClearAllPoints()
                rp.timer:SetPoint("LEFT", rp.timerBg, "LEFT", (math.sin(now * 2.4) + 1) / 2 * (INNER - seg), 0)
            end
        end
        for _, p in ipairs(d.list) do
            local row = p.row
            if row then
                if row.y ~= row.ty then
                    busy = true
                    row.y = row.y + (row.ty - row.y) * math.min(1, elapsed * 12)
                    if math.abs(row.ty - row.y) < 0.5 then
                        row.y = row.ty
                    end
                    PlaceRow(row)
                end
                if p.revealAt and not p.shown then
                    busy = true
                    if now >= p.revealAt then
                        local prog = math.min(1, (now - p.revealAt) / p.spin)
                        if now >= (row.nextSpin or 0) then
                            row.num:SetText(math.random(1, 100))
                            local flicker = math.random()
                            row.num:SetTextColor(1, 0.8 + 0.2 * flicker, 0.45 + 0.55 * flicker)
                            row.nextSpin = now + 0.03 + 0.2 * prog * prog -- slows down like a slot machine reel
                        end
                        if p.suspense then
                            -- the deciding number: its row breathes (one breath in 1.4 s) until it lands, in the
                            -- item's color from uncommon up
                            Rarity.SuspenseOn(d, true)
                            local r, g, b = Theme.Accent()
                            if d.look and d.look.quality >= 2 then
                                r, g, b = d.look.fr, d.look.fg, d.look.fb
                            end
                            row.bg:SetColorTexture(r, g, b, 0.06 + 0.06 * (math.sin(now * 4.5) + 1))
                        end
                        PaintFill(row, p, FillWidth(p.roll) * (1 - (1 - prog) ^ 3))
                    end
                elseif p.shown and row.fxStart then
                    busy = ClassFX(row, p, now, d.celebrated and d.winner == p) or busy
                elseif Early.IdleSpin(p, d) then
                    busy = true
                    if now >= (row.nextSpin or 0) then
                        row.num:SetText(math.random(1, 100))
                        row.nextSpin = now + 0.09
                    end
                elseif not p.st and not d.done then
                    busy = true
                    row.num:SetText(DOTS[math.floor(now * 3) % 3 + 1])
                end
            end
        end
        busy = Rarity.Effects(d, now, elapsed) or busy
    end
    if not busy then
        animating = false
        self:SetScript("OnUpdate", nil)
    end
end

function StartAnimating()
    if win and not animating then
        animating = true
        win:SetScript("OnUpdate", Tick)
    end
end

-- ===== rarity effects (src/RollFX.lua decides which ones an item gets) =====
-- y of a row's middle, counted from the bottom of the window (the particles are placed from its lower left corner)
function Rarity.RowY(row)
    return win:GetHeight() - (row.y or row.ty or 0) - (ROW_H - 2) / 2
end

-- The deciding number starts or stops spinning: epic and up dim the other rows and tint the window's edge.
function Rarity.SuspenseOn(d, on)
    if d.suspenseOn == on or not d.look then
        return
    end
    d.suspenseOn = on
    local tier, look = d.look.tier, d.look
    if tier.edge and on then
        RollFX.ShowEdge(win.edge, true, look.fr, look.fg, look.fb)
    end
    if tier.dim and d == current then
        RenderRoll()
    end
end

-- light running once over the winner's row, its bright edge in front
function Rarity.StepSweep(row, now, r, g, b)
    local k = (now - row.sweepStart) / 1.3
    if k >= 1 then
        row.sweepStart = nil
        row.sweep:Hide()
        return false
    end
    if k >= 0 then
        local band = INNER * 0.4
        local right = (INNER + band) * (1 - (1 - k) ^ 3)
        local left = math.max(0, right - band)
        right = math.min(INNER, right)
        if right - left >= 1 then
            row.sweep:ClearAllPoints()
            row.sweep:SetPoint("TOPLEFT", row, "TOPLEFT", left, 0)
            row.sweep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, 0)
            row.sweep:SetWidth(right - left)
            Gradient(row.sweep, "HORIZONTAL", r, g, b, 0, r, g, b, 0.45)
            row.sweep:Show()
        end
    end
    return true
end

-- One frame of the effects that move: the legendary name fading in, embers, rays, the light over the winner's row,
-- the value counting up and every particle. True while something still moves.
function Rarity.Effects(d, now, dt)
    local look = d.look
    if not look then
        return false
    end
    local rp, tier, busy = win.rollPane, look.tier, false
    if d.nameFadeAt then
        local k = (now - d.nameFadeAt) / 1.4
        rp.name:SetAlpha(math.max(0.05, math.min(1, k)))
        if k < 1 then
            busy = true
        else
            d.nameFadeAt = nil
        end
    end
    if tier.embers and (not d.celebratedAt or now - d.celebratedAt < 3) then
        busy = true -- a few embers drift up from the bottom of the window for the whole roll
        d.emberAcc = (d.emberAcc or 0) + dt * tier.embers
        while d.emberAcc >= 1 do
            d.emberAcc = d.emberAcc - 1
            RollFX.Emit(win.motes, PAD + math.random() * INNER, 4, look.fr, look.fg * (0.7 + 0.3 * math.random()),
                look.fb * 0.6, { vy = 12 + math.random() * 12, life = 2.2 + math.random(), size = 4 + math.random() * 2,
                    flicker = true })
        end
    end
    if d.celebratedAt and tier.rays then
        busy = RollFX.StepRays(rp.rays, now - d.celebratedAt, look.fr, look.fg, look.fb) or busy
    end
    local row = d.winner and d.winner.row
    if row and row.sweepStart then
        busy = Rarity.StepSweep(row, now, look.fr, look.fg, look.fb) or busy
    end
    if d.countAt and now >= d.countAt then
        local k = math.min(1, (now - d.countAt) / 1.4)
        rp.value:SetText(Rarity.ValueText(look, 1 - (1 - k) ^ 3))
        if k < 1 then
            busy = true
        else
            d.countAt = nil
        end
    elseif d.countAt then
        busy = true
    end
    return RollFX.Step(win.motes, dt) or busy
end

-- motes rise from the winner's row (and, for a legendary, embers burst out of the icon)
function Rarity.Motes(d, row)
    local look, tier = d.look, d.look.tier
    local y = Rarity.RowY(row)
    for i = 1, tier.motes do
        RollFX.Emit(win.motes, PAD + 12 + math.random() * (INNER - 24), y + math.random(-4, 4), look.fr, look.fg, look.fb,
            { delay = 0.35 + i * 0.07 })
    end
    if tier.embers then
        local x, iy = PAD + ICON / 2, win:GetHeight() - PAD - ICON / 2
        for _ = 1, 16 do
            RollFX.Emit(win.motes, x, iy, look.fr, look.fg * (0.7 + 0.3 * math.random()), look.fb * 0.6,
                { vx = math.random(-55, 55), vy = math.random(10, 60), life = 1.2 + math.random() * 1.2,
                    size = 4 + math.random() * 2, flicker = true, delay = math.random() * 0.3 })
        end
    end
end

-- The game's win sound when you won it, a softer one when you rolled and lost, the coin when you were not in it.
function Rarity.ResultSound(d)
    local w = d.winner
    if w.isSelf then
        if d.look.tier.power >= 5 then
            RollFX.SoundAny("UI_LEGENDARY_LOOT_TOAST", "UI_EPICLOOT_TOAST")
        else
            Sound("UI_EPICLOOT_TOAST")
        end
        return
    end
    local me = Me(d)
    if me and me.st and me.st.kind ~= "pass" then
        RollFX.SoundAny("IG_QUEST_LOG_ABANDON_QUEST", "IG_MAINMENU_CLOSE")
    else
        Sound("LOOT_WINDOW_COIN_SOUND")
    end
end

-- Effects that belong to the drop on screen end with it.
function Rarity.ClearEffects(d)
    d.suspenseOn = nil
    RollFX.ShowEdge(win.edge, false)
    RollFX.ClearEmitter(win.motes)
    if win.rollPane.rays then
        win.rollPane.rays:SetAlpha(0)
    end
    win.rollPane.name:SetAlpha(1)
end

-- ===== the flow of one drop =====
local function FlashRow(row, r, g, b)
    row.flash:SetVertexColor(r, g, b)
    Play(row.flashAnim)
end

-- sparks fly up from a row, in the UI's accent color with a few white ones
local function Sparkle(row, count)
    local r, g, b = Theme.Accent()
    for i, t in ipairs(win.sparks) do
        if i <= count and t.anim and t.move then
            t:ClearAllPoints()
            t:SetPoint("CENTER", row, "LEFT", 14 + math.random() * (INNER - 28), 0)
            if i % 3 == 0 then
                t:SetVertexColor(1, 1, 1)
            else
                t:SetVertexColor(r, g, b)
            end
            t.move:SetOffset(math.random(-40, 40), math.random(14, 46))
            Play(t.anim)
        end
    end
end

local function ItemLinkBody(link)
    return type(link) == "string" and link:match("|H(item:[^|]+)|h") or nil
end

-- One short line in your own chat: the item, who won it and with which roll. Written once the winner is shown in
-- the window, so the chat never gives the result away before the numbers land.
local function ChatLine(d)
    if d.replay or not (ns.db and ns.db.chatLine ~= false) or not DEFAULT_CHAT_FRAME then
        return
    end
    local w = d.winner
    local text
    if d.allPassed or not w then
        text = L("chat_passed", d.item)
    else
        text = w.isSelf and L("chat_you_won", d.item) or L("chat_won", d.item, ClassText(w.short, w.class))
        if w.st and w.roll then
            local kind = w.st.kind == "greed" and L("chat_greed") or (w.st.tag and L("chat_need_os") or L("chat_need"))
            text = text .. " " .. MUTED .. "(" .. kind .. " " .. w.roll .. ")|r"
        end
    end
    ns.Emit(DEFAULT_CHAT_FRAME, "|cff58c6faWWT|r " .. text, "SYSTEM")
    if #history >= MAX_HISTORY then
        table.remove(history, 1)
    end
    history[#history + 1] = d
end

local function Celebrate(d)
    if d.retired then
        return
    end
    d.celebrated = true
    ChatLine(d)
    local w = d.winner
    if w and not d.allPassed and Rolls(w) then
        for _, p in ipairs(d.list) do
            if p ~= w and Rolls(p) and p.st.rank == w.st.rank and w.roll - p.roll <= PHOTO_FINISH then
                d.photoFinish = true
            end
        end
    end
    d.look = d.look or RollFX.Look(d.item)
    local look, tier = d.look, d.look.tier
    local p = d.winner
    if d == current then
        RenderRoll()
        if p and not d.allPassed then
            local rp = win.rollPane
            d.celebratedAt = GetTime()
            if tier.burst > 0 then
                rp.burst:SetVertexColor(look.fr, look.fg, look.fb, tier.burst)
                Play(rp.burstAnim)
            end
            if p.row then
                if tier.power > 0 then
                    FlashRow(p.row, look.fr, look.fg, look.fb)
                end
                Play(p.row.crownPop)
                if tier.sparks > 0 then
                    Sparkle(p.row, tier.sparks)
                end
                Rarity.Motes(d, p.row)
                if tier.sweep then
                    p.row.sweepStart = d.celebratedAt + 0.1
                end
            end
            if look.price and look.band >= 1 then
                d.countAt = d.celebratedAt + 0.3
            end
            if tier.edge then
                After(2.6, function()
                    if current == d then
                        RollFX.ShowEdge(win.edge, false)
                    end
                end)
            end
            StartAnimating()
            Rarity.ResultSound(d)
        end
    end
    if p and p.isSelf and not d.allPassed and not d.replay and ns.LootFrames then
        ns.LootFrames.Toast(d.item, look, p.st, p.roll)
    end
    local fade = FadeAfter()
    local hold = fade > 0 and fade or HOLD_NO_FADE
    if #queue > 1 then
        hold = math.min(hold, HOLD_BUSY)
    end
    hold = hold + tier.hold
    After(hold, function()
        Retire(d)
    end)
end

local function Settle(d, p)
    if d.retired then
        return
    end
    p.shown = true
    if p.suspense then
        Rarity.SuspenseOn(d, false)
    end
    local leader = Leader(d)
    local before = d.leader
    local newLeader = leader == p and before ~= nil and before ~= p
    d.leader = leader
    if d == current and win then
        RenderRoll()
        if p.row then
            Play(p.row.numPop)
            if Rolls(p) then
                p.row.fxStart = GetTime()
                StartAnimating()
            end
            if newLeader then
                FlashRow(p.row, 1, 1, 1) -- overtaken: the new leader lights up
            end
        end
        if newLeader and before.isSelf and before.row then
            FlashRow(before.row, 1, 0.2, 0.15) -- you lost the lead: your row flashes red
        end
        if #d.list <= 10 then
            Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        end
    end
end

-- Numbers that arrived since the last call get their turn: weakest first, so the best number lands last.
local function ScheduleReveals(d)
    local fresh = {}
    for _, p in ipairs(d.list) do
        if Rolls(p) and not p.revealAt then
            fresh[#fresh + 1] = p
        end
    end
    if #fresh == 0 then
        return
    end
    table.sort(fresh, function(a, b) return Better(b, a) end)
    local gap = #queue > 2 and FAST_GAP or REVEAL_GAP
    local now = GetTime()
    local t = math.max(now, d.nextReveal or 0)
    -- when nobody is left to choose, the last number of this batch decides the roll: it gets the long spin
    local allIn = d.done
    if not allIn then
        allIn = true
        for _, p in ipairs(d.list) do
            if not p.st or (p.st.kind ~= "pass" and not p.out and not p.roll) then
                allIn = false
            end
        end
    end
    for i, p in ipairs(fresh) do
        p.revealAt = t
        p.suspense = allIn and i == #fresh and #fresh > 1 and #queue <= 2
        p.spin = p.suspense and d.look.tier.spin or SPIN
        local landAt = t + p.spin
        d.lastLanding = math.max(d.lastLanding or 0, landAt)
        After(landAt - now, function()
            Settle(d, p)
        end)
        t = t + gap
    end
    d.nextReveal = t
end

local function Present(d)
    ScheduleReveals(d)
    if d.done and not d.celebrateAt then
        local now = GetTime()
        d.celebrateAt = math.max(now, d.lastLanding or 0) + CELEBRATE_DELAY
        After(d.celebrateAt - now, function()
            Celebrate(d)
        end)
    end
    RenderRoll()
end

function Retire(d)
    if d.retired then
        return
    end
    d.retired = true
    for i = #queue, 1, -1 do
        if queue[i] == d then
            table.remove(queue, i)
        end
    end
    if current == d then
        current = nil
        Rarity.ClearEffects(d)
        Release(rollRows)
        for _, p in ipairs(d.list) do
            p.row = nil
        end
        Advance()
    elseif current then
        RenderRoll() -- the "+N" counter
    end
end

local function ShouldShowBoard()
    if not Enabled() then
        return false
    end
    if pinned then
        return true
    end
    return ns.InstanceRunInfo() ~= nil and userClosed ~= RunKey()
end

function Idle()
    if not win then
        if not ShouldShowBoard() or not EnsureWindow() then
            return
        end
    end
    -- with fading turned off the window stays where it is once a roll opened it (the X still closes it)
    if win.placing or ShouldShowBoard() or (FadeAfter() == 0 and win:IsShown()) then
        SetMode("board")
        RenderBoard()
        ShowWindow()
    else
        HideWindow(true)
    end
end

function Advance()
    local d = queue[1]
    if not d then
        Idle()
        return
    end
    if current == d or not EnsureWindow() then
        return
    end
    current = d
    SetMode("roll")
    Present(d)
    if not d.dismissed then
        ShowWindow()
    end
    After(STALE_DROP, function()
        if not d.done then
            Retire(d) -- the loot history never reported a result for it
        end
    end)
end

local function AddResult(d)
    local p = d.winner
    if d.demo then
        return
    end
    CheckRun()
    RecordLuck(d)
    if d.allPassed or not p then
        return
    end
    if #results >= MAX_RESULTS then
        table.remove(results, 1)
    end
    results[#results + 1] = { item = d.item, full = p.full, short = p.short, class = p.class, isSelf = p.isSelf,
        kind = p.st and p.st.kind, tag = p.st and p.st.tag, roll = p.roll }
    if mode == "board" and not current then
        RenderBoard()
    end
end

local function Skipped(link)
    return (ns.IsIgnoredItem and ns.IsIgnoredItem(link)) or (ns.IsCheapItem and ns.IsCheapItem(link)) or false
end

local function Remember(key, value)
    if known[key] == nil then
        knownCount = knownCount + 1
        if knownCount > MAX_KNOWN then
            for k, v in pairs(known) do
                if v == false or v.retired then
                    known[k] = nil
                    knownCount = knownCount - 1
                end
            end
        end
    end
    known[key] = value
end

local function NewDrop(key, item, demo)
    local d = { key = key, item = item, itemID = ns.ItemIDOf(item), players = {}, list = {}, demo = demo }
    d.look = RollFX.Look(item)
    if #queue >= MAX_QUEUE then
        Retire(queue[#queue] ~= current and queue[#queue] or queue[1]) -- a flood: the newest waiting one goes
    end
    queue[#queue + 1] = d
    Remember(key, d)
    return d
end

local function Merge(d, info, finished)
    for _, r in ipairs(type(info.rollInfos) == "table" and info.rollInfos or {}) do
        if type(r) == "table" and UsableName(r.playerName) and #r.playerName <= 64 then
            local short = ShortName(r.playerName)
            local p = d.players[short]
            if not p and #d.list < MAX_ROLLERS then
                p = { full = r.playerName, short = short, order = #d.list + 1 }
                d.players[short] = p
                d.list[#d.list + 1] = p
            end
            if p then
                p.guess = nil
                if not p.class and UsableName(r.playerClass) then
                    p.class = r.playerClass
                end
                if r.isSelf == true then
                    p.isSelf = true
                end
                local st = StateOf(r.state)
                if st then
                    p.st = st
                end
                if PlainNumber(r.roll) and not p.roll then
                    p.roll = r.roll
                end
                if r.isWinner == true then
                    d.winner = p
                end
            end
        end
    end
    if finished then
        d.done = true
        d.allPassed = info.allPassed == true
        local w = info.winner
        if not d.winner and type(w) == "table" and UsableName(w.playerName) then
            d.winner = d.players[ShortName(w.playerName)]
        end
    end
    -- Once anyone chose Need, the game does not roll for Greed at all: those players are out of the race at once
    -- (dimmed like a pass), instead of waiting for a number that never comes.
    local anyNeed = false
    for _, p in ipairs(d.list) do
        if p.st and p.st.kind == "need" then
            anyNeed = true
        end
    end
    for _, p in ipairs(d.list) do
        p.out = anyNeed and p.st ~= nil and p.st.kind == "greed" and p ~= d.winner
    end
end

-- A drop opened from START_LOOT_ROLL (before the loot history knew it) waiting for its loot history drop.
function Early.Adopt(key, item)
    local id = ns.ItemIDOf(item)
    for _, d in ipairs(queue) do
        if d.provisional and not d.retired and d.itemID == id then
            d.provisional = nil
            d.key = key
            Remember(key, d)
            return d
        end
    end
    return nil
end

-- The group members shown while the roll waits for its first pick leave once the loot history names the players.
function Early.DropGuesses(d)
    local keep = {}
    for _, p in ipairs(d.list) do
        if p.guess then
            d.players[p.short] = nil
        else
            keep[#keep + 1] = p
        end
    end
    if #keep == #d.list then
        return
    end
    d.list = keep
    if current == d and win then
        Release(rollRows)
        for _, p in ipairs(d.list) do
            p.row = nil
        end
    end
end

-- Every change of a drop comes through here (loot history updates while rolling, and the final result).
local function Update(key, info, finished, demo)
    if not (demo or Enabled()) or type(info) ~= "table" then
        return
    end
    local item = info.itemHyperlink
    if not UsableName(item) or #item > 512 or not ns.ItemIDOf(item) then
        return
    end
    local d = known[key]
    if d == false or (d and d.done) then
        return
    end
    if not d and not demo then
        d = Early.Adopt(key, item)
    end
    if not d then
        if not demo and Skipped(item) then
            Remember(key, false)
            return
        end
        d = NewDrop(key, item, demo)
    end
    Merge(d, info, finished)
    Early.DropGuesses(d)
    if finished then
        AddResult(d)
    end
    if current == d then
        Present(d)
    elseif current then
        RenderRoll()
    else
        Advance()
    end
end

-- Plays a finished drop again from the start (a click on its chat line): a copy, so the board and the luck
-- numbers do not count it twice.
local function Replay(old)
    if old.replaying and not old.replaying.retired then
        return -- already on screen or waiting
    end
    replaySeq = replaySeq + 1
    local d = NewDrop("replay:" .. replaySeq, old.item, true)
    d.replay = true
    for _, o in ipairs(old.list) do
        local p = { full = o.full, short = o.short, order = o.order, class = o.class, isSelf = o.isSelf,
            st = o.st, roll = o.roll, out = o.out }
        d.players[p.short] = p
        d.list[#d.list + 1] = p
        if o == old.winner then
            d.winner = p
        end
    end
    d.done, d.allPassed = true, old.allPassed
    old.replaying = d
    if current then
        RenderRoll() -- the "+N" counter; it comes after the roll on screen
    else
        Advance()
    end
end

-- A plain click on an item link anywhere in chat: if one of our result lines named that item, its roll is played
-- again. The game still opens its item tooltip as usual (a hook, not a replacement).
local function OnItemRef(link, _, button)
    if type(link) ~= "string" or not link:find("^item:") or (button and button ~= "LeftButton") then
        return
    end
    if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown())
        or (IsAltKeyDown and IsAltKeyDown()) then
        return -- linking, the dressing room and the like
    end
    if not Enabled() or not EnsureWindow() then
        return
    end
    for i = #history, 1, -1 do
        if ItemLinkBody(history[i].item) == link then
            Replay(history[i])
            return
        end
    end
end

if hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", OnItemRef)
end

-- ===== events and commands =====
local function OnProgress(encounterID, lootListKey, info)
    local key = ns.DropKey(encounterID, lootListKey)
    if key then
        Update(key, info, false)
    end
end

local function OnFinished(info, encounterID, lootListKey)
    local key = ns.DropKey(encounterID, lootListKey)
    if not key then
        chatSeq = chatSeq + 1
        key = "chat:" .. chatSeq -- the chat fallback has no drop key
    end
    Update(key, info, true)
end

-- A roll we may roll on opens the window at once, before anyone has chosen: the drop is shown from the roll's own
-- item link with the group waiting, and joined to the loot history's drop for the same item as soon as it reports.
function Early.OpenFromRoll(rollID, link)
    local key = "roll:" .. rollID
    if not Enabled() or known[key] ~= nil or Skipped(link) then
        return
    end
    local d = NewDrop(key, link)
    d.provisional = true
    for _, unit in ipairs(GroupUnits()) do
        local okn, name = pcall(UnitName, unit)
        local okc, _, class = pcall(UnitClass, unit)
        if okn and UsableName(name) and not d.players[name] and #d.list < MAX_ROLLERS then
            local p = { full = name, short = name, order = #d.list + 1, guess = true,
                class = okc and UsableName(class) and class or nil, isSelf = unit == "player" }
            d.players[name] = p
            d.list[#d.list + 1] = p
        end
    end
    if current then
        RenderRoll() -- the "+N" counter
    else
        Advance()
    end
end

-- START_LOOT_ROLL: the game's own countdown for an item we may roll on (rollTime in milliseconds).
local function OnStartRoll(rollID, rollTime)
    if not (PlainNumber(rollID) and PlainNumber(rollTime) and rollTime > 0 and GetLootRollItemLink) then
        return
    end
    local ok, link = pcall(GetLootRollItemLink, rollID)
    local id = ok and UsableName(link) and ns.ItemIDOf(link)
    if not id then
        return
    end
    local now = GetTime()
    for k, t in pairs(rollTimers) do
        if t.endsAt < now then
            rollTimers[k] = nil
        end
    end
    local seconds = rollTime > 1000 and rollTime / 1000 or rollTime
    rollTimers[id] = { endsAt = now + seconds, duration = seconds }
    Early.OpenFromRoll(rollID, link)
end

-- The roll ended (CANCEL_LOOT_ROLL). A drop opened from it that the loot history never reported is given up after
-- a moment, so it cannot hold up the window.
local function OnRollGone(rollID)
    local d = PlainNumber(rollID) and known["roll:" .. rollID]
    if d and d.provisional then
        After(8, function()
            if d.provisional then
                Retire(d)
            end
        end)
    end
end

local function OnZone()
    CheckRun()
    if not current then
        Idle()
    end
end

local function SetEnabled(on)
    if on then
        OnZone()
    else
        for i = #queue, 1, -1 do
            Retire(queue[i])
        end
        HideWindow(false)
    end
end

-- Brings the window up and keeps it up (the board between rolls): /wwt and the minimap button in a dungeon or raid.
local function Open()
    if not EnsureWindow() then
        return
    end
    userClosed, pinned = nil, true
    for _, d in ipairs(queue) do
        d.dismissed = false
    end
    if current then
        SetMode("roll")
        RenderRoll()
    else
        SetMode("board")
        RenderBoard()
    end
    ShowWindow()
end

-- /wwt window
local function Toggle()
    if EnsureWindow() and win:IsShown() and not win.placing then
        Close()
    else
        Open()
    end
end

local function ResetPos()
    if win and win.moverOwned then
        ns.Print(L("mover_reset_ui"))
        return
    end
    ClearPos()
    ns.Print(L("rw_pos_reset"))
end

-- Layout editors: show the window while they are open so it can be placed.
local function Preview(on)
    if not EnsureWindow() then
        return nil
    end
    if on then
        win.placing = true
        if not current then
            SetMode("board")
            RenderBoard()
        end
        ShowWindow()
    else
        win.placing = false
        if not current and not ShouldShowBoard() then
            HideWindow(false)
        end
    end
    return win
end

-- /wwt demo [quality] [win]: a made-up roll with you and four others, so the window can be seen (and placed) any
-- time. The quality (poor .. legendary, or 0 .. 5) picks the sample item; "win" lets you win it.
local DEMO_ITEMS = { -- [quality] = sample item
    [0] = "|cff9d9d9d|Hitem:4865::::::::::::::|h[Ruined Pelt]|h|r",
    [1] = "|cffffffff|Hitem:2589::::::::::::::|h[Linen Cloth]|h|r",
    [2] = "|cff1eff00|Hitem:10400::::::::::::::|h[Blackened Defias Leggings]|h|r",
    [3] = "|cff0070dd|Hitem:10399::::::::::::::|h[Blackened Defias Armor]|h|r",
    [4] = "|cffa335ee|Hitem:12640::::::::::::::|h[Lionheart Helm]|h|r",
    [5] = "|cffff8000|Hitem:19019::::::::::::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r",
}
DEMO_ITEMS.words = { poor = 0, grey = 0, gray = 0, common = 1, white = 1, uncommon = 2, green = 2, rare = 3,
    blue = 3, epic = 4, purple = 4, legendary = 5, orange = 5 }
local function Demo(args)
    local quality, youWin = 4, false
    for word in tostring(args or ""):lower():gmatch("%S+") do
        if word == "win" then
            youWin = true
        elseif DEMO_ITEMS.words[word] or (tonumber(word) and DEMO_ITEMS[tonumber(word)]) then
            quality = DEMO_ITEMS.words[word] or tonumber(word)
        end
    end
    local item = DEMO_ITEMS[quality]
    if not EnsureWindow() then
        return
    end
    demoSeq = demoSeq + 1
    local key = "demo:" .. demoSeq
    local me, myClass = ns.L("sample_you"), "MAGE"
    if UnitName then
        local ok, n = pcall(UnitName, "player")
        if ok and UsableName(n) then
            me = n
        end
        local okc, _, c = pcall(UnitClass, "player")
        if okc and UsableName(c) then
            myClass = c
        end
    end
    local S = ROLL_STATE
    -- Three Need, two Greed (they drop out, so the game gives them no number), and the priest wins it on Need, so
    -- the ninja loot flag shows on plate. You greed, so your own class never adds a second ninja; with "win" you
    -- need and win it instead.
    local ninja = { "Seluna", "PRIEST", S.NeedMainSpec }
    local mine = { me, myClass, youWin and S.NeedMainSpec or S.Greed, true }
    local cast = {
        { "Brakk", "WARRIOR", S.NeedMainSpec }, mine, ninja,
        { "Rax", "ROGUE", S.Greed }, { "Thorgrim", "PALADIN", S.NeedMainSpec },
    }
    local best = youWin and mine or ninja
    local used = {}
    for _, c in ipairs(cast) do
        if c[3] == S.NeedMainSpec and c ~= best then
            local n
            repeat
                n = math.random(15, 90)
            until not used[n]
            used[n] = true
            c.roll = n
        end
    end
    local top = 0
    for n in pairs(used) do
        top = math.max(top, n)
    end
    best.roll = math.random(top + 1, 100) -- the ninja (or you, with "win") always wins the demo
    local function Info(chosen, rolled, finished)
        local list = {}
        for i, c in ipairs(cast) do
            list[i] = { playerName = c[1], playerClass = c[2], isSelf = c[4] == true,
                state = i <= chosen and c[3] or S.NoRoll, roll = rolled and c.roll or nil,
                isWinner = finished and c == best }
        end
        return { itemHyperlink = item, rollInfos = list }
    end
    userClosed = nil
    Update(key, Info(0), false, true)
    local d = known[key]
    if d then
        d.demo = true
        rollTimers[ns.ItemIDOf(item)] = { endsAt = GetTime() + 8, duration = 8 }
    end
    for step = 1, #cast do
        After(0.5 * step, function()
            Update(key, Info(step), false, true)
        end)
    end
    After(0.5 * #cast + 0.8, function()
        Update(key, Info(#cast, true, true), true, true)
    end)
end

-- ===== shared with the other files =====
ns.RollWindow = {
    OnProgress = OnProgress, OnFinished = OnFinished, OnStartRoll = OnStartRoll, OnRollGone = OnRollGone, OnZone = OnZone,
    SetEnabled = SetEnabled, Open = Open, Toggle = Toggle, ResetPos = ResetPos, Demo = Demo,
}
-- used by Movers.lua
ns.EnsureRollWindow, ns.RollWindowPreview, ns.PlaceRollWindow = EnsureWindow, Preview, Place
ns.StoreRollWinPos, ns.ClearRollWinPos = StorePos, ClearPos
ns.ItemLabel = ItemLabel -- used by LootFrames.lua
ns.ROLL_WINDOW_W = W
