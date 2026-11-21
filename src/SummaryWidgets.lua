-- Who Won That: dungeon loot summary: game art helpers and reusable widgets.
local _, ns = ...

local ClassColor, PlainNumber, UsableName = ns.ClassColor, ns.PlainNumber, ns.UsableName

local SUMMARY_FRAME_NAME = "WhoWonThatSummaryFrame"
-- Layout on an 8 pixel rhythm. The list panel sits SUMMARY_PAD from the sides, SUMMARY_TOP below the top edge
-- and SUMMARY_FOOT above the bottom edge; its content is 4 pixels inside it (content width = width - 32).
local SUMMARY_WIDTH, SUMMARY_DETAILS_WIDTH = 336, 480
local SUMMARY_MAX_BODY = 384      -- tallest the list gets before it scrolls (mouse wheel)
local SUMMARY_NAME_COL, SUMMARY_TILE, SUMMARY_TILE_GAP, SUMMARY_ROW_PAD = 96, 30, 4, 5 -- name col incl. class icon
local SUMMARY_SIDE = 8 -- inner left / right padding of a board row
local SUMMARY_HEADER = 26      -- height of the title band (flat fallback look)
local SUMMARY_PAD, SUMMARY_TOP, SUMMARY_FOOT, SUMMARY_SUB_Y = 12, 56, 44, -36
local DETAIL_ROW, DETAIL_HEAD = 24, 20 -- details view: row height, column header strip height
local SUMMARY_DOT = " \194\183 "  -- " · "
local GOLD_R, GOLD_G, GOLD_B = 0.89, 0.72, 0.29
local MUTED_R, MUTED_G, MUTED_B = 0.62, 0.60, 0.55
ns.summaryDetails = false -- window in "details" (list) view
-- ----- the window -----
-- Look: a Blizzard dialog (dialog border, dark background, title plate on the top edge), a sunken list panel,
-- item slots with quality-tinted icon frames, class icons, the standard red panel buttons and the corner X.
-- Every piece of game art is optional: without the backdrop API the window keeps the flat look (dark
-- rectangle, thin gold edge), an unknown atlas falls back to a file or leaves its icon out, and without the
-- gradient API a gradient becomes flat color.
local ART = {
    dialogBg = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    dialogEdge = "Interface\\DialogFrame\\UI-DialogBox-Border",
    header = "Interface\\DialogFrame\\UI-DialogBox-Header",
    iconFrame = "Interface\\Common\\WhiteIconFrame",
    glow = "Interface\\Buttons\\UI-ActionButton-Border",
    hilight = "Interface\\Buttons\\ButtonHilight-Square",
    classes = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
    starAtlas = "auctionhouse-icon-favorite",
    star = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
}
ns.summaryStyled = false -- the frame got the dialog look (backdrop API available)

local function HasAtlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then
        return false
    end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and type(info) == "table"
end

local function TrySetAtlas(tex, name)
    if not (tex.SetAtlas and HasAtlas(name)) then
        return false
    end
    return (pcall(tex.SetAtlas, tex, name))
end

local function TrySetFile(tex, path)
    local ok, res = pcall(tex.SetTexture, tex, path)
    return ok and res ~= false
end

-- Two-color gradient on a plain texture; color 1 is the left / bottom end. Falls back to the flat average.
local function Gradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    if CreateColor and tex.SetGradient
        and pcall(tex.SetGradient, tex, orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then
        return
    end
    if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, orient, r1, g1, b1, a1, r2, g2, b2, a2) then
        return
    end
    tex:SetColorTexture((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
end

-- class icon: the client's class atlas, else the character creation sheet, else nothing
local function SetClassIcon(tex, class)
    if UsableName(class) then
        if TrySetAtlas(tex, "classicon-" .. class:lower()) then
            tex:Show()
            return
        end
        local c = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[class]
        if type(c) == "table" and type(c[4]) == "number" and TrySetFile(tex, ART.classes) then
            local i = 0.015 -- trims the outer rim a little
            tex:SetTexCoord(c[1] + i, c[2] - i, c[3] + i, c[4] - i)
            tex:Show()
            return
        end
    end
    tex:Hide()
end

local function ItemTexture(link)
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if getInfo then
        local ok, _, _, _, _, icon = pcall(getInfo, link)
        if ok and (PlainNumber(icon) or UsableName(icon)) then
            return icon
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- r, g, b of the item's quality, and the quality number when the client knows it
local function ItemQualityColorRaw(link)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local quality
    if getInfo then
        local ok, _, _, q = pcall(getInfo, link)
        if ok and PlainNumber(q) then
            quality = q
        end
    end
    if quality then
        local c = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[quality]
        if type(c) == "table" and type(c.r) == "number" then
            return c.r, c.g, c.b, quality
        end
        local getColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
        if getColor then
            local ok, r, g, b = pcall(getColor, quality)
            if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b, quality
            end
        end
    end
    -- the link's own color: |cffRRGGBB
    local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
    if hex then
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    end
    return 0.62, 0.62, 0.62
end

-- Item borders are the quality color, toned down so they do not glow: a flat edge at 55 % (flat look), or the
-- game's icon frame tinted at 75 %. Common items get a neutral grey frame; epic and better a faint glow.
local BORDER_DIM, FRAME_DIM = 0.55, 0.75
local function StyleItemBorder(w, link)
    local r, g, b, q = ItemQualityColorRaw(link)
    if not w.styled then
        w.border:SetColorTexture(r * BORDER_DIM, g * BORDER_DIM, b * BORDER_DIM, 0.95)
        return
    end
    if (q and q <= 1) or (not q and r > 0.9 and g > 0.9 and b > 0.9) then
        w.border:SetVertexColor(0.42, 0.42, 0.42, 0.85)
    else
        w.border:SetVertexColor(r * FRAME_DIM, g * FRAME_DIM, b * FRAME_DIM, 0.9)
    end
    if w.glow then
        if q and q >= 4 then
            w.glow:SetVertexColor(r, g, b, 0.18)
            w.glow:Show()
        else
            w.glow:Hide()
        end
    end
end

-- Red warning on a slot: a Need win of an item the winner's class cannot use. A soft pulsing glow behind the
-- icon and a red frame; the glow is created on first use. Call it after StyleItemBorder, which sets the frame.
local WARN_R, WARN_G, WARN_B = 1, 0.25, 0.2
local function MarkCantUse(w, on)
    w.cantUse = on
    if not w.warn and on then
        local g = w:CreateTexture(nil, "OVERLAY", nil, 2)
        local size = w.border:GetWidth() * 1.9
        if TrySetFile(g, ART.glow) then
            g:SetBlendMode("ADD")
            g:SetPoint("CENTER", w.border, "CENTER")
            g:SetSize(size, size)
        else
            g:SetAllPoints(w.border)
            g:SetColorTexture(1, 1, 1, 0.3)
        end
        g:SetVertexColor(WARN_R, WARN_G, WARN_B, 1)
        w.warn = g
        w.warnPulse = g:CreateAnimationGroup()
        w.warnPulse:SetLooping("BOUNCE")
        local a = w.warnPulse:CreateAnimation("Alpha")
        a:SetFromAlpha(0.45)
        a:SetToAlpha(1)
        a:SetDuration(0.9)
        a:SetSmoothing("IN_OUT")
    end
    if not w.warn then
        return
    end
    if on then
        if not w.ninja then
            -- the ninja icon sits on the slot's lower right corner
            w.ninja = w:CreateTexture(nil, "OVERLAY", nil, 4)
            local size = w.border:GetWidth() >= 24 and 15 or 12
            w.ninja:SetSize(size, size)
            w.ninja:SetPoint("BOTTOMRIGHT", w.border, "BOTTOMRIGHT", 3, -3)
            if TrySetFile(w.ninja, ns.NINJA_ICON_PATH) then
                w.ninja:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                w.ninja:SetColorTexture(WARN_R, WARN_G, WARN_B, 1)
            end
        end
        w.ninja:Show()
        if w.glow then
            w.glow:Hide() -- the quality glow would mix with the red one
        end
        if w.styled then
            w.border:SetVertexColor(WARN_R, WARN_G, WARN_B, 1)
        else
            w.border:SetColorTexture(WARN_R, WARN_G, WARN_B, 0.95)
        end
        w.warn:Show()
        w.warnPulse:Play()
    else
        w.warnPulse:Stop()
        w.warn:Hide()
        if w.ninja then
            w.ninja:Hide()
        end
    end
end

-- Icon slot on a widget: dark rim (depth), icon, quality frame. Returns true with the game's icon frame art,
-- false for the flat look (a colored square behind a slightly smaller icon). size = edge length of the slot.
local function MakeSlot(w, anchor, size)
    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    w.border = w:CreateTexture(nil, "OVERLAY")
    w.border:SetSize(size, size)
    anchor(w.border)
    w.styled = ns.summaryStyled and TrySetFile(w.border, ART.iconFrame)
    if w.styled then
        w.icon:SetAllPoints(w.border)
        local rim = w:CreateTexture(nil, "BACKGROUND", nil, 1)
        rim:SetPoint("TOPLEFT", w.border, "TOPLEFT", -1, 1)
        rim:SetPoint("BOTTOMRIGHT", w.border, "BOTTOMRIGHT", 1, -1)
        rim:SetColorTexture(0, 0, 0, 0.8)
    else
        w.border:SetDrawLayer("BACKGROUND", 1)
        local inset = size >= 24 and 2 or 1.5
        w.icon:SetPoint("TOPLEFT", w.border, "TOPLEFT", inset, -inset)
        w.icon:SetPoint("BOTTOMRIGHT", w.border, "BOTTOMRIGHT", -inset, inset)
    end
    return w.styled
end

local function FormatDuration(sec)
    sec = math.max(0, math.floor((sec or 0) + 0.5))
    local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
end

local function SetClassColor(fs, class)
    local c = ClassColor(class)
    if c and type(c.r) == "number" then
        fs:SetTextColor(c.r, c.g, c.b)
    else
        fs:SetTextColor(1, 1, 1)
    end
end

-- tooltip, shift-click (link into chat), ctrl-click (dressing room) for an item tile or a details row
local function ItemButtonEnter(self)
    if not self.link or not GameTooltip then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
    if self.cantUse then
        GameTooltip:AddLine(ns.L("ninja_tip"), WARN_R, 0.35, 0.3, true)
    end
    GameTooltip:Show()
end

local function ItemButtonLeave()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function ItemButtonClick(self)
    local link = self.link
    if not link then
        return
    end
    if HandleModifiedItemClick then
        pcall(HandleModifiedItemClick, link)
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
        if insert then
            pcall(insert, link)
        end
    end
end

-- click on a player name: whisper
local function NameClick(self)
    local name = self.full
    if not name or self.isSelf then
        return
    end
    if ChatFrame_SendTell then
        pcall(ChatFrame_SendTell, name)
    elseif ChatFrameUtil and ChatFrameUtil.SendTell then
        pcall(ChatFrameUtil.SendTell, name)
    end
end

-- Reused widgets: each kind has a list; a render hides them all and takes what it needs from the front.
local pools = {}
local function Acquire(kind, make)
    local p = pools[kind]
    if not p then
        p = { list = {}, used = 0 }
        pools[kind] = p
    end
    p.used = p.used + 1
    local w = p.list[p.used]
    if not w then
        w = make()
        p.list[p.used] = w
    end
    w:ClearAllPoints()
    w:Show()
    return w
end

local function ReleaseAll()
    for _, p in pairs(pools) do
        for i = 1, #p.list do
            p.list[i]:Hide()
        end
        p.used = 0
    end
end

-- full-width background of one row: zebra stripe, your own row (gold gradient + edge), or a column header strip
local function MakeBand()
    local f = CreateFrame("Frame", nil, ns.summaryContent)
    f:SetFrameLevel(ns.summaryContent:GetFrameLevel()) -- below the tiles and names
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.glow:SetAllPoints()
    f.edge = f:CreateTexture(nil, "BORDER")
    f.edge:SetWidth(2)
    f.edge:SetPoint("TOPLEFT")
    f.edge:SetPoint("BOTTOMLEFT")
    f.line = f:CreateTexture(nil, "BORDER")
    f.line:SetHeight(1)
    f.line:SetPoint("BOTTOMLEFT")
    f.line:SetPoint("BOTTOMRIGHT")
    return f
end

local function PlaceBand(y, h, kind)
    local band = Acquire("band", MakeBand)
    band:SetPoint("TOPLEFT", ns.summaryContent, "TOPLEFT", 0, -y)
    band:SetPoint("TOPRIGHT", ns.summaryContent, "TOPRIGHT", 0, -y)
    band:SetHeight(h)
    band.glow:Hide()
    band.edge:Hide()
    band.line:Hide()
    if kind == "self" then
        band.bg:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.035)
        Gradient(band.glow, "HORIZONTAL", GOLD_R, GOLD_G, GOLD_B, 0.20, GOLD_R, GOLD_G, GOLD_B, 0)
        band.glow:Show()
        band.edge:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.85)
        band.edge:Show()
    elseif kind == "bad" then
        band.bg:SetColorTexture(WARN_R, WARN_G, WARN_B, 0.05)
        Gradient(band.glow, "HORIZONTAL", WARN_R, WARN_G, WARN_B, 0.30, WARN_R, WARN_G, WARN_B, 0)
        band.glow:Show()
        band.edge:SetColorTexture(WARN_R, WARN_G, WARN_B, 0.9)
        band.edge:Show()
    elseif kind == "head" then
        band.bg:SetColorTexture(0, 0, 0, 0.4)
        band.line:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.3)
        band.line:Show()
    else
        band.bg:SetColorTexture(1, 1, 1, 0.03)
    end
    return band
end

local function MakeTile()
    local b = CreateFrame("Button", nil, ns.summaryContent)
    b:SetSize(SUMMARY_TILE, SUMMARY_TILE)
    if MakeSlot(b, function(t) t:SetPoint("CENTER") end, SUMMARY_TILE) then
        b.glow = b:CreateTexture(nil, "OVERLAY", nil, 1)
        b.glow:SetSize(SUMMARY_TILE * 1.8, SUMMARY_TILE * 1.8)
        b.glow:SetPoint("CENTER")
        if TrySetFile(b.glow, ART.glow) then
            b.glow:SetBlendMode("ADD")
        else
            b.glow = nil
        end
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if TrySetFile(hl, ART.hilight) then
        hl:SetBlendMode("ADD")
    else
        hl:SetColorTexture(1, 1, 1, 0.15)
    end
    b:SetScript("OnEnter", ItemButtonEnter)
    b:SetScript("OnLeave", ItemButtonLeave)
    b:SetScript("OnClick", ItemButtonClick)
    return b
end

-- player name with the class icon in front of it
local function MakeName()
    local b = CreateFrame("Button", nil, ns.summaryContent)
    b.cls = b:CreateTexture(nil, "ARTWORK")
    b.cls:SetSize(16, 16)
    b.cls:SetPoint("LEFT", 0, 0)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("LEFT", 22, 0)
    b.text:SetPoint("RIGHT", 0, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", NameClick)
    return b
end

local function MakeText()
    local fs = ns.summaryContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWordWrap(false)
    return fs
end

-- marker of the run's top looter (strictly the most items, at least two)
local function MakeStar()
    local t = ns.summaryContent:CreateTexture(nil, "OVERLAY")
    t:SetSize(12, 12)
    if not TrySetAtlas(t, ART.starAtlas) then
        TrySetFile(t, ART.star)
    end
    return t
end

local function MakeDetailRow()
    local b = CreateFrame("Button", nil, ns.summaryContent)
    b:SetHeight(DETAIL_ROW)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.08)
    MakeSlot(b, function(t) t:SetPoint("LEFT", 4, 0) end, 20)
    b.item = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.item:SetPoint("LEFT", 32, 0)
    b.item:SetWidth(204)
    b.item:SetJustifyH("LEFT")
    b.item:SetWordWrap(false)
    b.cls = b:CreateTexture(nil, "ARTWORK")
    b.cls:SetSize(14, 14)
    b.cls:SetPoint("LEFT", 244, 0)
    b.winner = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.winner:SetPoint("LEFT", 262, 0)
    b.winner:SetWidth(100)
    b.winner:SetJustifyH("LEFT")
    b.winner:SetWordWrap(false)
    b.roll = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.roll:SetPoint("RIGHT", -6, 0)
    b.roll:SetJustifyH("RIGHT")
    b.roll:SetWordWrap(false)
    b:SetScript("OnEnter", ItemButtonEnter)
    b:SetScript("OnLeave", ItemButtonLeave)
    b:SetScript("OnClick", ItemButtonClick)
    return b
end

-- ===== shared with the other files =====
ns.ART, ns.Acquire, ns.DETAIL_HEAD, ns.DETAIL_ROW = ART, Acquire, DETAIL_HEAD, DETAIL_ROW
ns.FormatDuration, ns.GOLD_B, ns.GOLD_G, ns.GOLD_R = FormatDuration, GOLD_B, GOLD_G, GOLD_R
ns.Gradient, ns.ItemTexture, ns.MUTED_B, ns.MUTED_G = Gradient, ItemTexture, MUTED_B, MUTED_G
ns.MUTED_R, ns.MakeDetailRow, ns.MakeName, ns.MakeStar = MUTED_R, MakeDetailRow, MakeName, MakeStar
ns.MakeText, ns.MakeTile, ns.PlaceBand, ns.ReleaseAll = MakeText, MakeTile, PlaceBand, ReleaseAll
ns.SUMMARY_DETAILS_WIDTH, ns.SUMMARY_DOT, ns.SUMMARY_FOOT, ns.SUMMARY_FRAME_NAME = SUMMARY_DETAILS_WIDTH, SUMMARY_DOT, SUMMARY_FOOT, SUMMARY_FRAME_NAME
ns.SUMMARY_HEADER, ns.SUMMARY_MAX_BODY, ns.SUMMARY_NAME_COL, ns.SUMMARY_PAD = SUMMARY_HEADER, SUMMARY_MAX_BODY, SUMMARY_NAME_COL, SUMMARY_PAD
ns.SUMMARY_ROW_PAD, ns.SUMMARY_SIDE, ns.SUMMARY_SUB_Y, ns.SUMMARY_TILE = SUMMARY_ROW_PAD, SUMMARY_SIDE, SUMMARY_SUB_Y, SUMMARY_TILE
ns.SUMMARY_TILE_GAP, ns.SUMMARY_TOP, ns.SUMMARY_WIDTH, ns.SetClassColor = SUMMARY_TILE_GAP, SUMMARY_TOP, SUMMARY_WIDTH, SetClassColor
ns.SetClassIcon, ns.StyleItemBorder, ns.TrySetFile = SetClassIcon, StyleItemBorder, TrySetFile
ns.MarkCantUse = MarkCantUse
