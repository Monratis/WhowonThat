-- Who Won That: dungeon loot summary: board / details views and the window.
local _, ns = ...

local ART, Acquire, DETAIL_HEAD, DETAIL_ROW = ns.ART, ns.Acquire, ns.DETAIL_HEAD, ns.DETAIL_ROW
local FormatDuration, GOLD_B, GOLD_G, GOLD_R = ns.FormatDuration, ns.GOLD_B, ns.GOLD_G, ns.GOLD_R
local Gradient, ItemTexture, KIND_ICON, LABEL_COLOR = ns.Gradient, ns.ItemTexture, ns.KIND_ICON, ns.LABEL_COLOR
local MUTED_B, MUTED_G, MUTED_R, MakeDetailRow = ns.MUTED_B, ns.MUTED_G, ns.MUTED_R, ns.MakeDetailRow
local MakeName, MakeStar, MakeText, MakeTile = ns.MakeName, ns.MakeStar, ns.MakeText, ns.MakeTile
local PlaceBand, ReleaseAll, SUMMARY_DETAILS_WIDTH, SUMMARY_DOT = ns.PlaceBand, ns.ReleaseAll, ns.SUMMARY_DETAILS_WIDTH, ns.SUMMARY_DOT
local SUMMARY_FOOT, SUMMARY_FRAME_NAME, SUMMARY_HEADER, SUMMARY_MAX_BODY = ns.SUMMARY_FOOT, ns.SUMMARY_FRAME_NAME, ns.SUMMARY_HEADER, ns.SUMMARY_MAX_BODY
local SUMMARY_NAME_COL, SUMMARY_PAD, SUMMARY_ROW_PAD, SUMMARY_SIDE = ns.SUMMARY_NAME_COL, ns.SUMMARY_PAD, ns.SUMMARY_ROW_PAD, ns.SUMMARY_SIDE
local SUMMARY_SUB_Y, SUMMARY_TILE, SUMMARY_TILE_GAP, SUMMARY_TOP = ns.SUMMARY_SUB_Y, ns.SUMMARY_TILE, ns.SUMMARY_TILE_GAP, ns.SUMMARY_TOP
local SUMMARY_WIDTH, SetClassColor, SetClassIcon, StyleItemBorder = ns.SUMMARY_WIDTH, ns.SetClassColor, ns.SetClassIcon, ns.StyleItemBorder
local TrySetFile, VisibleCount = ns.TrySetFile, ns.VisibleCount
local CanClassUse, MarkCantUse = ns.CanClassUse, ns.MarkCantUse

-- A Need win of an item that is not for the winner's class (cannot wear it, wrong primary stat): ninja loot, red.
local function CantUse(d)
    return ns.db and ns.db.flagUnusable and d.kind == "need" and not CanClassUse(d.player.class, d.item) or false
end

-- Players of the run with the items they won: winners first (most items), then the others in join order.
local function SummaryPlayers(run, mineOnly)
    local list, byPlayer = {}, {}
    for _, p in pairs(run.roster) do
        if not mineOnly or p.isSelf then
            local e = { p = p, drops = {} }
            byPlayer[p] = e
            list[#list + 1] = e
        end
    end
    for _, d in ipairs(run.drops) do
        local e = byPlayer[d.player]
        if e then
            e.drops[#e.drops + 1] = d
        end
    end
    table.sort(list, function(a, b)
        if #a.drops ~= #b.drops then return #a.drops > #b.drops end
        return a.p.order < b.p.order
    end)
    return list
end

-- Board view: [class icon] name | item tiles (wrapping) | [star] count. Returns the content height.
local function RenderBoard(run, mineOnly, width)
    local tilesX = SUMMARY_SIDE + SUMMARY_NAME_COL + 8
    local step = SUMMARY_TILE + SUMMARY_TILE_GAP
    local perLine = math.max(1, math.floor((width - tilesX - SUMMARY_SIDE - 36 + SUMMARY_TILE_GAP) / step))
    local y = 0
    local players = SummaryPlayers(run, mineOnly)
    local first, second = players[1], players[2]
    local leader = first and #first.drops >= 2 and (not second or #second.drops < #first.drops) and first
    for idx, e in ipairs(players) do
        local lines = math.max(1, math.ceil(#e.drops / perLine))
        local rowH = lines * SUMMARY_TILE + (lines - 1) * SUMMARY_TILE_GAP + 2 * SUMMARY_ROW_PAD
        local top = -y - SUMMARY_ROW_PAD
        if e.p.isSelf then
            PlaceBand(y, rowH, "self")
        elseif idx % 2 == 0 then
            PlaceBand(y, rowH, "zebra")
        end
        local name = Acquire("name", MakeName)
        name:SetSize(SUMMARY_NAME_COL, SUMMARY_TILE)
        name:SetPoint("TOPLEFT", ns.summaryContent, "TOPLEFT", SUMMARY_SIDE, top)
        name.text:SetText(e.p.short)
        SetClassColor(name.text, e.p.class)
        SetClassIcon(name.cls, e.p.class)
        name.full, name.isSelf = e.p.full, e.p.isSelf
        if #e.drops == 0 then
            local none = Acquire("text", MakeText)
            none:SetPoint("LEFT", ns.summaryContent, "TOPLEFT", tilesX, top - SUMMARY_TILE / 2)
            none:SetText("-")
            none:SetTextColor(0.42, 0.41, 0.37)
        else
            for i, d in ipairs(e.drops) do
                local tile = Acquire("tile", MakeTile)
                local line, col = math.floor((i - 1) / perLine), (i - 1) % perLine
                tile:SetPoint("TOPLEFT", ns.summaryContent, "TOPLEFT", tilesX + col * step, top - line * step)
                tile.link = d.item
                tile.icon:SetTexture(ItemTexture(d.item))
                StyleItemBorder(tile, d.item)
                MarkCantUse(tile, CantUse(d))
            end
            local count = Acquire("text", MakeText)
            count:SetPoint("RIGHT", ns.summaryContent, "TOPRIGHT", -SUMMARY_SIDE, top - SUMMARY_TILE / 2)
            count:SetText("\195\151" .. #e.drops) -- multiplication sign + number
            count:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
            if e == leader then
                local star = Acquire("star", MakeStar)
                star:SetPoint("RIGHT", count, "LEFT", -3, 0)
            end
        end
        y = y + rowH
    end
    return y
end

-- Details view: a column header strip, then one row per item: [icon] item, [class icon] winner, roll icon
-- (+ "OS") and number. Returns the height.
local function RenderDetails(run, mineOnly, width)
    PlaceBand(0, DETAIL_HEAD, "head")
    local heads = { { "Item", "LEFT", 32 }, { "Winner", "LEFT", 244 }, { "Roll", "RIGHT", -6 } }
    for _, h in ipairs(heads) do
        local fs = Acquire("text", MakeText)
        fs:SetPoint(h[2], ns.summaryContent, "TOP" .. h[2], h[3], -DETAIL_HEAD / 2)
        fs:SetText(h[1])
        fs:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    end
    local y, n = DETAIL_HEAD + 2, 0
    for _, d in ipairs(run.drops) do
        if not mineOnly or d.player.isSelf then
            n = n + 1
            local bad = CantUse(d)
            if bad then
                PlaceBand(y, DETAIL_ROW, "bad")
            elseif d.player.isSelf then
                PlaceBand(y, DETAIL_ROW, "self")
            elseif n % 2 == 0 then
                PlaceBand(y, DETAIL_ROW, "zebra")
            end
            local row = Acquire("detail", MakeDetailRow)
            row:SetPoint("TOPLEFT", ns.summaryContent, "TOPLEFT", 0, -y)
            row:SetWidth(width)
            row.link = d.item
            row.icon:SetTexture(ItemTexture(d.item))
            StyleItemBorder(row, d.item)
            MarkCantUse(row, bad)
            row.item:SetText(d.item)
            row.winner:SetText(d.player.short)
            SetClassColor(row.winner, d.player.class)
            SetClassIcon(row.cls, d.player.class)
            local roll = (d.kind and KIND_ICON[d.kind] or "")
                .. (d.tag and (" |cff" .. (LABEL_COLOR[d.kind] or "aaaaaa") .. d.tag .. "|r") or "")
                .. (d.roll and (" " .. d.roll) or "")
            if bad then
                roll = "|cffff5040ninja loot|r " .. roll
            end
            row.roll:SetText(roll ~= "" and roll or "|cff6c695f-|r")
            y = y + DETAIL_ROW
        end
    end
    return y
end

function ns.RenderSummary()
    local fr, run = ns.summaryFrame, ns.summaryShowing
    if not fr or not run then
        return
    end
    ReleaseAll()
    local mineOnly = ns.db and ns.db.summary == "mine"
    local count = VisibleCount(run, mineOnly)
    fr.sub:SetText(run.name .. SUMMARY_DOT .. run.rosterCount .. (run.rosterCount == 1 and " player" or " players"))
    fr.dur:SetText(FormatDuration((run.endTime or GetTime()) - run.startTime))
    local width = ns.summaryDetails and SUMMARY_DETAILS_WIDTH or SUMMARY_WIDTH
    fr:SetWidth(width)
    local inner = width - 2 * SUMMARY_PAD - 8
    ns.summaryContent:SetWidth(inner)
    local h
    if ns.summaryDetails then
        h = RenderDetails(run, mineOnly, inner)
    else
        h = RenderBoard(run, mineOnly, inner)
    end
    ns.summaryContent:SetHeight(math.max(h, 1))
    fr:SetHeight(SUMMARY_TOP + 8 + math.min(math.max(h, 20), SUMMARY_MAX_BODY) + SUMMARY_FOOT)
    fr.scroll:SetVerticalScroll(0)
    local unusable = 0
    for _, d in ipairs(run.drops) do
        if (not mineOnly or d.player.isSelf) and CantUse(d) then
            unusable = unusable + 1
        end
    end
    fr.count:SetText((count == 1 and "1 item" or (count .. " items")) .. (mineOnly and " (yours)" or "")
        .. (unusable > 0 and (SUMMARY_DOT .. "|cffff5040" .. unusable .. " ninja|r") or ""))
    fr.detailsBtn:SetText(ns.summaryDetails and "Board" or "Details")
end

-- 1 pixel frame of four textures (flat look; no template needed)
local function AddEdges(parent, layer, r, g, b, a)
    local edges = {
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }
    for _, e in ipairs(edges) do
        local t = parent:CreateTexture(nil, layer)
        t:SetColorTexture(r, g, b, a)
        t:SetPoint(e[1])
        t:SetPoint(e[2])
        if e[3] then t:SetWidth(e[3]) end
        if e[4] then t:SetHeight(e[4]) end
    end
end

-- The game's red panel button with the dialog look; otherwise a flat dark button with a gold edge.
local function MakeButton(parent, text, width)
    if ns.summaryStyled then
        local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
        if ok and b then
            b:SetSize(width, 22)
            b:SetText(text)
            return b
        end
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.13, 0.115, 0.08, 1)
    AddEdges(b, "BORDER", GOLD_R, GOLD_G, GOLD_B, 0.55)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.16)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b:SetText(text)
    return b
end

local function SaveSummaryPos(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    if ns.db and type(point) == "string" and type(x) == "number" and type(y) == "number" then
        ns.db.summaryPos = { point = point, relPoint = type(relPoint) == "string" and relPoint or point, x = x, y = y }
    end
end

local function PlaceSummaryFrame(fr)
    fr:ClearAllPoints()
    local p = ns.db and ns.db.summaryPos
    if type(p) == "table" and type(p.point) == "string" and type(p.relPoint) == "string"
        and type(p.x) == "number" and type(p.y) == "number" then
        if pcall(fr.SetPoint, fr, p.point, UIParent, p.relPoint, p.x, p.y) then
            return
        end
        fr:ClearAllPoints()
    end
    fr:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
end

-- Dialog look: dialog border + dark background, a warm sheen under the title and a shade at the bottom,
-- and the title plate (3 slices of the dialog header art) over the top edge. Returns the title font string.
local function DecorateDialog(fr)
    local ok = pcall(fr.SetBackdrop, fr, {
        bgFile = ART.dialogBg,
        edgeFile = ART.dialogEdge,
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 7, right = 7, top = 7, bottom = 7 },
    })
    if not ok then
        return nil
    end
    pcall(fr.SetBackdropColor, fr, 1, 1, 1, 0.96)
    pcall(fr.SetBackdropBorderColor, fr, 1, 0.93, 0.8, 1) -- a touch warmer than the stock grey
    local sheen = fr:CreateTexture(nil, "BACKGROUND", nil, 2)
    sheen:SetPoint("TOPLEFT", 7, -7)
    sheen:SetPoint("TOPRIGHT", -7, -7)
    sheen:SetHeight(72)
    Gradient(sheen, "VERTICAL", GOLD_R, GOLD_G, GOLD_B, 0, GOLD_R, GOLD_G, GOLD_B, 0.08)
    local shade = fr:CreateTexture(nil, "BACKGROUND", nil, 2)
    shade:SetPoint("BOTTOMLEFT", 7, 7)
    shade:SetPoint("BOTTOMRIGHT", -7, 7)
    shade:SetHeight(56)
    Gradient(shade, "VERTICAL", 0, 0, 0, 0.4, 0, 0, 0, 0)

    local title = fr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetText("WHO WON THAT")
    local plate = fr:CreateTexture(nil, "ARTWORK")
    if TrySetFile(plate, ART.header) then
        plate:SetTexCoord(0.31, 0.67, 0, 0.63)
        plate:SetPoint("TOP", 0, 12)
        plate:SetSize(math.max((title:GetStringWidth() or 0) + 24, 110), 40)
        local left = fr:CreateTexture(nil, "ARTWORK")
        TrySetFile(left, ART.header)
        left:SetTexCoord(0.21, 0.31, 0, 0.63)
        left:SetSize(30, 40)
        left:SetPoint("RIGHT", plate, "LEFT")
        local right = fr:CreateTexture(nil, "ARTWORK")
        TrySetFile(right, ART.header)
        right:SetTexCoord(0.67, 0.77, 0, 0.63)
        right:SetSize(30, 40)
        right:SetPoint("LEFT", plate, "RIGHT")
        title:SetPoint("TOP", plate, "TOP", 0, -14)
    else
        plate:Hide()
        title:SetPoint("TOP", 0, -16)
    end
    return title
end

-- Flat look: dark rectangle with a thin gold edge and a header band with the centered title.
local function DecorateFlat(fr)
    local bg = fr:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.07, 0.09, 0.95)
    AddEdges(fr, "BORDER", GOLD_R, GOLD_G, GOLD_B, 0.8)
    local headBg = fr:CreateTexture(nil, "BORDER")
    headBg:SetColorTexture(0.15, 0.115, 0.05, 1)
    headBg:SetPoint("TOPLEFT", 1, -1)
    headBg:SetPoint("TOPRIGHT", -1, -1)
    headBg:SetHeight(SUMMARY_HEADER)
    local headLine = fr:CreateTexture(nil, "BORDER")
    headLine:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.6)
    headLine:SetPoint("TOPLEFT", 1, -(SUMMARY_HEADER + 1))
    headLine:SetPoint("TOPRIGHT", -1, -(SUMMARY_HEADER + 1))
    headLine:SetHeight(1)
    local title = fr:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER", fr, "TOP", 0, -(SUMMARY_HEADER / 2) - 1)
    title:SetText("WHO WON THAT")
    title:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
end

-- Sunken list panel: darker fill, an inner shadow under the top edge, dark top / sides and a faint light
-- bottom edge. Returns the scroll frame inside it.
local function MakeListPanel(fr)
    local panel = CreateFrame("Frame", nil, fr)
    panel:SetPoint("TOPLEFT", SUMMARY_PAD, -SUMMARY_TOP)
    panel:SetPoint("BOTTOMRIGHT", -SUMMARY_PAD, SUMMARY_FOOT)
    local fill = panel:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0, 0, 0, ns.summaryStyled and 0.42 or 0.22)
    local shadow = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    shadow:SetPoint("TOPLEFT")
    shadow:SetPoint("TOPRIGHT")
    shadow:SetHeight(10)
    Gradient(shadow, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0.45)
    local edges = {
        { "TOPLEFT", "TOPRIGHT", nil, 1, 0, 0, 0, 0.7 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1, 1, 1, 1, 0.07 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil, 0, 0, 0, 0.45 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil, 0, 0, 0, 0.45 },
    }
    for _, e in ipairs(edges) do
        local t = panel:CreateTexture(nil, "BORDER")
        t:SetColorTexture(e[5], e[6], e[7], e[8])
        t:SetPoint(e[1])
        t:SetPoint(e[2])
        if e[3] then t:SetWidth(e[3]) end
        if e[4] then t:SetHeight(e[4]) end
    end
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    return scroll
end

-- ----- slide-out from the pop-up button -----
-- The window slides out from under the button's edge like a drawer: downwards if there is room under it,
-- otherwise upwards. A clipping frame covers the screen from the button's edge outwards, so the window
-- starts fully hidden behind that edge and travels its full height. The button stays on top (higher
-- strata) and fades out during the slide. Without clipping support, or with no room to rest fully past
-- the edge, it falls back to a short fade-and-nudge.
local SLIDE_TIME = 0.32 -- long enough to read as a slide, short enough not to delay the user
local SLIDE_GAP = 14 -- room between the button and the window; above 12 so the title plate is never cut off
local SLIDE_NUDGE = 36 -- travel of the fallback fade-in
local slideClip -- clipping frame; false once we know the client cannot clip

local function SlideClip()
    if slideClip == nil then
        local f = CreateFrame("Frame", nil, UIParent)
        if f.SetClipsChildren then
            f:SetFrameStrata("HIGH")
            f:SetClipsChildren(true)
            f:Hide()
            slideClip = f
        else
            slideClip = false
        end
    end
    return slideClip or nil
end

-- Ends a running slide at once: final spot, back under UIParent, screen clamping and full alpha restored,
-- and the pop-up button (which was fading out) hidden and reset for its next appearance.
local function StopSlide(fr)
    local s = fr.slide
    if not s then
        return
    end
    fr.slide = nil
    fr:SetScript("OnUpdate", nil)
    if s.clip then
        fr:SetParent(UIParent) -- reparent before hiding the clip frame, or the window would hide with it
        fr:SetFrameStrata("HIGH")
        s.clip:Hide()
    end
    fr:SetClampedToScreen(true)
    fr:SetAlpha(1)
    s.place(0)
    local b = ns.summaryBtn
    if b then
        b:Hide()
        b:SetAlpha(1)
        b:EnableMouse(true)
    end
end

local function CreateSummaryFrame()
    local fr
    if BackdropTemplateMixin then
        local ok, f = pcall(CreateFrame, "Frame", SUMMARY_FRAME_NAME, UIParent, "BackdropTemplate")
        if ok then
            fr = f
        end
    end
    fr = fr or CreateFrame("Frame", SUMMARY_FRAME_NAME, UIParent)
    fr:SetSize(SUMMARY_WIDTH, 200)
    fr:SetFrameStrata("HIGH")
    fr:SetClampedToScreen(true)
    fr:SetMovable(true)
    fr:EnableMouse(true)
    fr:RegisterForDrag("LeftButton")
    fr:SetScript("OnDragStart", function(self)
        StopSlide(self)
        self:StartMoving()
    end)
    fr:SetScript("OnDragStop", SaveSummaryPos)
    fr:SetScript("OnHide", function(self)
        StopSlide(self)
        if not self:IsShown() then
            PlaceSummaryFrame(self) -- closed (not just hidden with the UI): the next plain open uses the remembered spot
        end
    end)
    fr:Hide()

    ns.summaryStyled = fr.SetBackdrop ~= nil and DecorateDialog(fr) ~= nil
    if not ns.summaryStyled then
        DecorateFlat(fr)
    end

    fr.dur = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fr.dur:SetPoint("TOPRIGHT", -(SUMMARY_PAD + 4), SUMMARY_SUB_Y)
    fr.dur:SetTextColor(MUTED_R, MUTED_G, MUTED_B)

    fr.sub = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fr.sub:SetPoint("TOPLEFT", SUMMARY_PAD + 4, SUMMARY_SUB_Y)
    fr.sub:SetPoint("RIGHT", fr.dur, "LEFT", -8, 0)
    fr.sub:SetJustifyH("LEFT")
    fr.sub:SetWordWrap(false)
    fr.sub:SetTextColor(MUTED_R, MUTED_G, MUTED_B)

    local scroll = MakeListPanel(fr)
    ns.summaryContent = CreateFrame("Frame", nil, scroll)
    ns.summaryContent:SetSize(SUMMARY_WIDTH - 2 * SUMMARY_PAD - 8, 1)
    scroll:SetScrollChild(ns.summaryContent)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, (ns.summaryContent:GetHeight() or 0) - (self:GetHeight() or 0))
        local v = (self:GetVerticalScroll() or 0) - delta * 30
        self:SetVerticalScroll(math.min(math.max(v, 0), max))
    end)
    fr.scroll = scroll

    fr.count = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fr.count:SetPoint("BOTTOMLEFT", SUMMARY_PAD + 4, 19)
    fr.count:SetTextColor(MUTED_R, MUTED_G, MUTED_B)

    local function Close()
        fr:Hide()
    end
    local close = MakeButton(fr, "Close", 80)
    close:SetPoint("BOTTOMRIGHT", -(SUMMARY_PAD + 2), 13)
    close:SetScript("OnClick", Close)
    fr.detailsBtn = MakeButton(fr, "Details", 80)
    fr.detailsBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)
    fr.detailsBtn:SetScript("OnClick", function()
        ns.summaryDetails = not ns.summaryDetails
        ns.RenderSummary()
    end)
    if ns.summaryStyled then
        local ok, x = pcall(CreateFrame, "Button", nil, fr, "UIPanelCloseButton")
        if ok and x then
            x:SetPoint("TOPRIGHT", -2, -2)
            x:SetScript("OnClick", Close)
        end
    end

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, SUMMARY_FRAME_NAME) -- Esc closes it
    end
    PlaceSummaryFrame(fr)
    return fr
end

-- origin = { left, right, top, bottom } of the button, already in UIParent units.
local function SlideOutFrom(fr, origin)
    local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
    local w, h = fr:GetWidth(), fr:GetHeight()
    local roomBelow, roomAbove = origin.bottom - SLIDE_GAP, uiH - origin.top - SLIDE_GAP
    local down
    if roomBelow >= h then
        down = true
    elseif roomAbove >= h then
        down = false
    else
        down = roomBelow >= roomAbove -- cramped both ways: use the larger side
    end
    -- Clip only when the window can rest fully past the edge; otherwise screen clamping would keep part of it
    -- behind the edge and that part would pop in when the clip ends.
    local clip = (down and roomBelow or roomAbove) >= h and SlideClip()
    local left = math.min(math.max((origin.left + origin.right) / 2 - w / 2, 0), math.max(uiW - w, 0))
    local anchor = down and "TOPLEFT" or "BOTTOMLEFT"
    local edge = down and origin.bottom or origin.top
    local endY = down and (edge - SLIDE_GAP) or (edge + SLIDE_GAP)
    local dist = clip and (h + SLIDE_GAP) or SLIDE_NUDGE -- with the clip it starts fully behind the edge
    local dir = down and 1 or -1 -- the window starts shifted towards the button, i.e. against its travel
    local function Place(offset)
        fr:ClearAllPoints()
        fr:SetPoint(anchor, UIParent, "BOTTOMLEFT", left, endY + dir * offset)
    end
    if clip then
        clip:ClearAllPoints()
        clip:SetPoint(anchor, UIParent, "BOTTOMLEFT", 0, edge)
        clip:SetPoint(down and "BOTTOMRIGHT" or "TOPRIGHT", UIParent)
        clip:Show()
        fr:SetParent(clip)
        fr:SetFrameStrata("HIGH") -- reparenting may change the strata
        fr:SetClampedToScreen(false) -- the hidden start position may be off screen
    end
    local btn = ns.summaryBtn
    if btn then
        btn:EnableMouse(false) -- no second click or drag while it fades
    end
    fr.slide = { clip = clip, place = Place }
    Place(dist)
    fr:SetAlpha(clip and 1 or 0)
    local elapsed = 0
    fr:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + math.min(dt, 0.05) -- a long first frame (building the rows) must not skip the slide
        local t = math.min(elapsed / SLIDE_TIME, 1)
        local ease = 1 - (1 - t) ^ 4 -- quick start, soft landing
        Place(dist * (1 - ease))
        if not clip then
            self:SetAlpha(ease)
        end
        if btn then
            btn:SetAlpha(1 - t)
        end
        if t >= 1 then
            StopSlide(self)
        end
    end)
end

-- origin: the pop-up button's rect when opened from it; the window then slides out of it.
local function OpenSummary(run, origin)
    if not ns.summaryFrame then
        local ok, fr = pcall(CreateSummaryFrame)
        if not ok or not fr then
            if geterrorhandler and not ok then
                geterrorhandler()(fr)
            end
            return
        end
        ns.summaryFrame = fr
    end
    local fr = ns.summaryFrame
    ns.summaryShowing = run
    if run.id ~= "sample" then
        ns.summaryLast = run -- the /wwt test sample never replaces the last real dungeon
    end
    StopSlide(fr)
    ns.RenderSummary()
    if origin and not fr:IsShown() then
        SlideOutFrom(fr, origin) -- the button stays up and fades out during the slide
    elseif ns.summaryBtn then
        ns.summaryBtn:Hide()
    end
    fr:Show()
end

-- ===== shared with the other files =====
ns.AddEdges, ns.OpenSummary = AddEdges, OpenSummary
