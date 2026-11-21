-- Who Won That: dungeon loot summary: pop-up button and opening rules.
local _, ns = ...

local ART, AddEdges, ClassColor, GOLD_B = ns.ART, ns.AddEdges, ns.ClassColor, ns.GOLD_B
local GOLD_G, GOLD_R, Gradient, MUTED_B = ns.GOLD_G, ns.GOLD_R, ns.Gradient, ns.MUTED_B
local MUTED_G, MUTED_R, OpenSummary, Print = ns.MUTED_G, ns.MUTED_R, ns.OpenSummary, ns.Print
local SUMMARY_DOT, TrySetFile, VisibleCount = ns.SUMMARY_DOT, ns.TrySetFile, ns.VisibleCount

-- ----- the pop-up button -----
-- At the end of a dungeon the window does not pop up by itself: a small pulsing button appears (like a toast),
-- a click opens the summary, right-click dismisses it. Draggable (position remembered), gone after 10 minutes.
local SUMMARY_BTN_W, SUMMARY_BTN_H = 290, 58
local SUMMARY_BTN_SHOW = 25 -- seconds the pop-up stays (longer while the mouse is on it)
local summaryBtnToken = 0
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_10"

local function StoreSummaryBtnPos(point, relPoint, x, y)
    if ns.db and type(point) == "string" and type(x) == "number" and type(y) == "number" then
        ns.db.summaryBtnPos = { point = point, relPoint = type(relPoint) == "string" and relPoint or point, x = x, y = y }
    end
end

local function SaveSummaryBtnPos(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    StoreSummaryBtnPos(point, relPoint, x, y)
end

local function PlaceSummaryButton(b)
    if b.moverOwned then
        return -- a UI addon's mover (ElvUI) keeps the anchor and the saved position
    end
    b:ClearAllPoints()
    local p = ns.db and ns.db.summaryBtnPos
    if type(p) == "table" and type(p.point) == "string" and type(p.relPoint) == "string"
        and type(p.x) == "number" and type(p.y) == "number" then
        if pcall(b.SetPoint, b, p.point, UIParent, p.relPoint, p.x, p.y) then
            return
        end
        b:ClearAllPoints()
    end
    b:SetPoint("TOP", UIParent, "TOP", 0, -12) -- right at the top edge, out of the way of the game view
end

local function BuildSummaryButton()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local ok, b = pcall(CreateFrame, "Button", "WhoWonThatSummaryButton", UIParent, template)
    if not ok or not b then
        b = CreateFrame("Button", "WhoWonThatSummaryButton", UIParent)
    end
    b:SetSize(SUMMARY_BTN_W, SUMMARY_BTN_H)
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    b:SetToplevel(true)
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- frame: the same dialog border + dark background as the window; flat gold edge if the art is missing
    local styled = false
    if b.SetBackdrop then
        styled = pcall(b.SetBackdrop, b, {
            bgFile = ART.dialogBg,
            edgeFile = ART.dialogEdge,
            tile = true, tileSize = 32, edgeSize = 18,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
    end
    if styled then
        pcall(b.SetBackdropColor, b, 1, 1, 1, 0.97)
        pcall(b.SetBackdropBorderColor, b, 1, 0.93, 0.8, 1)
    else
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.05, 0.04, 0.96)
        AddEdges(b, "BORDER", GOLD_R, GOLD_G, GOLD_B, 0.85)
    end
    local inset = styled and 5 or 1
    local sheen = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    sheen:SetPoint("TOPLEFT", inset, -inset)
    sheen:SetPoint("TOPRIGHT", -inset, -inset)
    sheen:SetHeight(SUMMARY_BTN_H / 2)
    Gradient(sheen, "VERTICAL", GOLD_R, GOLD_G, GOLD_B, 0, GOLD_R, GOLD_G, GOLD_B, 0.14)

    -- icon tile with a gold ring; a soft glow behind it pulses
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", 14, 0)
    if not TrySetFile(icon, BAG_ICON) then
        icon:SetColorTexture(0.3, 0.22, 0.08, 1)
    else
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    local ring = b:CreateTexture(nil, "OVERLAY")
    if TrySetFile(ring, ART.iconFrame) then
        ring:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
        ring:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
        ring:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)
    else
        ring:Hide()
    end
    local glow = b:CreateTexture(nil, "BACKGROUND", nil, 3)
    if TrySetFile(glow, ART.glow) then
        glow:SetPoint("CENTER", icon, "CENTER")
        glow:SetSize(72, 72)
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(1, 0.82, 0.3, 0.9)
        local pulse = glow:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local pa = pulse:CreateAnimation("Alpha")
        pa:SetFromAlpha(0.25)
        pa:SetToAlpha(0.95)
        pa:SetDuration(1)
        pa:SetSmoothing("IN_OUT")
        b.pulse = pulse
    else
        glow:Hide()
        b.pulse = b:CreateAnimationGroup()
    end

    -- text
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 1)
    b.text:SetJustifyH("LEFT")
    b.text:SetText(ns.L("loot_summary"))
    b.icon = icon
    b.text:SetTextColor(1, 0.86, 0.4)
    b.hint = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.hint:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -3)
    b.hint:SetJustifyH("LEFT")
    b.text:SetWidth(SUMMARY_BTN_W - 84)
    b.text:SetWordWrap(false)
    b.hint:SetWidth(SUMMARY_BTN_W - 84)
    b.hint:SetWordWrap(false)
    b.hint:SetTextColor(MUTED_R, MUTED_G, MUTED_B)

    -- hover highlight and a slow shine sweeping across
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", inset, -inset)
    hl:SetPoint("BOTTOMRIGHT", -inset, inset)
    hl:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.12)
    local holder = CreateFrame("Frame", nil, b)
    holder:SetPoint("TOPLEFT", inset, -inset)
    holder:SetPoint("BOTTOMRIGHT", -inset, inset)
    if holder.SetClipsChildren then
        holder:SetClipsChildren(true)
    end
    local shine = holder:CreateTexture(nil, "ARTWORK", nil, 2)
    shine:SetSize(34, SUMMARY_BTN_H)
    shine:SetPoint("RIGHT", holder, "LEFT", 0, 0)
    Gradient(shine, "HORIZONTAL", 1, 1, 1, 0, 1, 0.95, 0.8, 0.22)
    shine:SetBlendMode("ADD")
    local sg = shine:CreateAnimationGroup()
    sg:SetLooping("REPEAT")
    local sm = sg:CreateAnimation("Translation")
    sm:SetOffset(SUMMARY_BTN_W + 40, 0)
    sm:SetDuration(1)
    sm:SetStartDelay(2.5)
    b.shine = sg

    b:SetScript("OnDragStart", function(self)
        if not self.moverOwned then
            self:StartMoving()
        end
    end)
    b:SetScript("OnDragStop", SaveSummaryBtnPos)
    b:SetScript("OnClick", function(self, button)
        if GameTooltip then
            GameTooltip:Hide()
        end
        if self.placing then
            self.placing = false
            self:Hide() -- the position was already saved when the drag ended
            Print(ns.L("btn_pos_saved"))
            return
        end
        if button ~= "LeftButton" or not self.run then
            self:Hide() -- right-click dismisses
            return
        end
        local origin
        local l, r, t, bt = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
        if l and r and t and bt then
            local k = self:GetEffectiveScale() / UIParent:GetEffectiveScale() -- button units -> UIParent units
            origin = { left = l * k, right = r * k, top = t * k, bottom = bt * k }
        end
        OpenSummary(self.run, origin) -- hides the button, at once or at the end of the slide
    end)
    b:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Who Won That")
            if self.placing then
                GameTooltip:AddLine(ns.L("btn_tip_placing"), 1, 1, 1, true)
                GameTooltip:Show()
                return
            end
            GameTooltip:AddLine(ns.L("btn_tip_click"), 1, 1, 1, true)
            for i, e in ipairs(self.leaders or {}) do
                if i > 8 then
                    break
                end
                GameTooltip:AddDoubleLine(e.colored, ns.Count("items", e.count), 1, 1, 1, 0.8, 0.8, 0.8)
            end
            GameTooltip:AddLine(ns.L("btn_tip_dismiss"), 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    b:Hide()
    PlaceSummaryButton(b)
    return b
end

-- Builds the button on first use; nil if the client refuses it (the error is reported once).
local function EnsureSummaryButton()
    if not ns.summaryBtn then
        local ok, b = pcall(BuildSummaryButton)
        if not ok or not b then
            if geterrorhandler and not ok then
                geterrorhandler()(b)
            end
            return nil
        end
        ns.summaryBtn = b
    end
    return ns.summaryBtn
end

-- Winners of the run sorted by number of items: { name, colored (class-colored name), count }.
local function SummaryLeaders(run, mineOnly)
    local byPlayer, list = {}, {}
    for _, d in ipairs(run.drops) do
        local p = d.player
        if p and (not mineOnly or p.isSelf) then
            local e = byPlayer[p]
            if not e then
                local c = p.class and ClassColor(p.class)
                local colored = p.short
                if c then
                    colored = string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255 + 0.5),
                        math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), p.short)
                end
                e = { name = p.short, colored = colored, count = 0, order = p.order or 0 }
                byPlayer[p] = e
                list[#list + 1] = e
            end
            e.count = e.count + 1
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.order < b.order
    end)
    return list
end

-- Texture of an item for the icon tile; nil when the client does not know it yet.
local function ItemIcon(link)
    if not GetItemInfoInstant then
        return nil
    end
    local ok, _, _, _, _, icon = pcall(GetItemInfoInstant, link)
    return ok and icon or nil
end

-- What the button says: the dungeon as title and, under it, what matters to the player: the item they won
-- (its icon replaces the bag) or, when they won nothing, how much dropped in the run.
local function SetButtonInfo(b, run, count)
    b.text:SetText(run.name or ns.L("loot_summary"))
    local mine = {}
    for _, d in ipairs(run.drops) do
        if d.player.isSelf then
            mine[#mine + 1] = d
        end
    end
    local hint
    local icon = #mine > 0 and ItemIcon(mine[#mine].item) or nil
    if #mine > 0 then
        hint = ns.L("you_won", mine[#mine].item)
        if #mine > 1 then
            hint = hint .. SUMMARY_DOT .. ns.L("more_n", #mine - 1)
        end
    else
        hint = ns.Count("items", count) .. SUMMARY_DOT .. ns.Count("players", run.rosterCount)
    end
    b.hint:SetText(hint)
    if not (icon and TrySetFile(b.icon, icon)) then
        TrySetFile(b.icon, BAG_ICON)
    end
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

ns.ShowSummaryButton = function(run)
    if ns.summaryFrame and ns.summaryFrame:IsShown() then
        OpenSummary(run) -- the window is already open: show this run in it, no button needed
        return
    end
    if not EnsureSummaryButton() then
        OpenSummary(run) -- no button possible: fall back to opening the window
        return
    end
    ns.summaryBtn.placing = false
    ns.summaryBtn.run = run
    local mine = ns.db and ns.db.summary == "mine"
    local n = VisibleCount(run, mine)
    local leaders = SummaryLeaders(run, mine)
    SetButtonInfo(ns.summaryBtn, run, n)
    ns.summaryBtn.leaders, ns.summaryBtn.itemCount = leaders, n
    if ns.summaryBtn:IsShown() then
        return
    end
    ns.summaryBtn:Show()
    ns.summaryBtn:Raise()
    ns.summaryBtn.pulse:Play()
    ns.summaryBtn.shine:Play()
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST then
        pcall(PlaySound, SOUNDKIT.UI_EPICLOOT_TOAST)
    end
    summaryBtnToken = summaryBtnToken + 1
    local token = summaryBtnToken
    if C_Timer and C_Timer.After then
        local function Expire()
            if token ~= summaryBtnToken or not ns.summaryBtn:IsShown() then
                return
            end
            if ns.summaryBtn:IsMouseOver() then
                C_Timer.After(5, Expire) -- under the mouse: try again a bit later
                return
            end
            ns.summaryBtn:Hide()
        end
        C_Timer.After(SUMMARY_BTN_SHOW, Expire)
    end
end

-- Shows the button and keeps it until it is clicked (or the mover session ends), so it can be dragged
-- to its place without waiting for a dungeon to end.
local function ShowPlacementPreview()
    local b = EnsureSummaryButton()
    if not b or b.moverOwned then
        return nil
    end
    summaryBtnToken = summaryBtnToken + 1 -- cancels a pending auto-hide
    b.placing, b.run, b.leaders = true, nil, nil
    b.text:SetText(ns.L("loot_summary"))
    b.hint:SetText(ns.L("btn_placing_hint"))
    TrySetFile(b.icon, BAG_ICON)
    b:Show()
    b:Raise()
    b.pulse:Play()
    b.shine:Play()
    return b
end

-- Settings panel "Move pop-up button".
local function MoveSummaryButton()
    if ns.summaryBtn and ns.summaryBtn.moverOwned then
        Print(ns.L("mover_use_ui"))
        return
    end
    if not ShowPlacementPreview() then
        return
    end
    local panel = _G.SettingsPanel
    if panel and panel:IsShown() and HideUIPanel then
        pcall(HideUIPanel, panel) -- the panel would cover the screen the button is placed on
    end
end

local function ClearSummaryButtonPos()
    if ns.db then
        ns.db.summaryBtnPos = nil
    end
    if ns.summaryBtn then
        PlaceSummaryButton(ns.summaryBtn)
    end
end

local function ResetSummaryButtonPos()
    if ns.summaryBtn and ns.summaryBtn.moverOwned then
        Print(ns.L("mover_reset_ui"))
        return
    end
    ClearSummaryButtonPos()
    Print(ns.L("btn_pos_reset"))
end

local function InLockdown()
    return (InCombatLockdown and InCombatLockdown()) or (IsEncounterInProgress and IsEncounterInProgress()) or false
end

-- Opens the window now, or once combat / the encounter is over. auto = opened by the end of the dungeon
-- (respects the option and needs at least one item); otherwise asked for with /wwt summary.
local function ShowSummaryWhenSafe(run, auto)
    if not run or not ns.db then
        return
    end
    if auto and (ns.db.summary == "off" or VisibleCount(run, ns.db.summary == "mine") == 0) then
        return
    end
    if InLockdown() then
        local first = ns.summaryWaiting == nil
        ns.summaryWaiting, ns.summaryWaitingAuto = run, auto
        if first and C_Timer and C_Timer.After then
            local function Retry()
                if not ns.summaryWaiting then
                    return
                end
                if InLockdown() then
                    C_Timer.After(2, Retry)
                    return
                end
                local r, a = ns.summaryWaiting, ns.summaryWaitingAuto
                ns.summaryWaiting, ns.summaryWaitingAuto = nil, nil
                ShowSummaryWhenSafe(r, a)
            end
            C_Timer.After(2, Retry)
        end
        return
    end
    if auto then
        ns.ShowSummaryButton(run)
    else
        OpenSummary(run)
    end
end

local function ShowSummarySoon(run, delay)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function() ShowSummaryWhenSafe(run, true) end)
    else
        ShowSummaryWhenSafe(run, true)
    end
end

-- /wwt summary
local function SummaryCommand()
    local run = (ns.summaryRun and #ns.summaryRun.drops > 0) and ns.summaryRun or ns.summaryLast
    if not run then
        Print(ns.L("no_summary"))
        return
    end
    if InLockdown() then
        Print(ns.L("summary_after_combat"))
    end
    ShowSummaryWhenSafe(run, false)
end

-- ===== shared with the other files =====
ns.ShowSummarySoon, ns.ShowSummaryWhenSafe, ns.SummaryCommand = ShowSummarySoon, ShowSummaryWhenSafe, SummaryCommand
ns.MoveSummaryButton, ns.ResetSummaryButtonPos = MoveSummaryButton, ResetSummaryButtonPos
-- used by Movers.lua
ns.EnsureSummaryButton, ns.ShowPlacementPreview = EnsureSummaryButton, ShowPlacementPreview
ns.PlaceSummaryButton, ns.ClearSummaryButtonPos = PlaceSummaryButton, ClearSummaryButtonPos
ns.StoreSummaryBtnPos = StoreSummaryBtnPos
ns.SUMMARY_BTN_W, ns.SUMMARY_BTN_H = SUMMARY_BTN_W, SUMMARY_BTN_H
