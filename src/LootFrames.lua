-- Who Won That: the addon's own roll buttons and loot toast, in place of the game's.
--  * Roll buttons: every roll you may roll on gets a row where the game shows its roll popups - the item, its
--    countdown and Need / Greed / Disenchant / Pass. The game builds its roll popups (GroupLootFrame1..N inside GroupLootContainer)
--    from START_LOOT_ROLL through its internal game event router. While our buttons are on, that one route is closed
--    (GameEvent.UnregisterInternalEvent), so no popup is ever built and GroupLootContainer - a frame of the managed
--    bottom column - is never touched by addon code. Opening the route again from here would run the game's popup
--    code under our taint, so turning the buttons off takes a /reload; until then the buttons keep showing rolls.
--    When EllesmereUI's or ElvUI's own roll list is on, or under WoW Forever's Gamepad interface style (it has its
--    own roll frame, which the closed route does not reach), the addon stays out of the way.
--  * Loot toast: when you win a roll, the addon's own toast shows it once the numbers have landed in the roll window,
--    in the item's rarity look. The game's "you won" toast for that item is put away as it shows (LootAlertSystem);
--    items the roll window does not show (ignored or below the minimum value) keep the game's toast.
local _, ns = ...

local L = ns.L
local Anim, RollFX, Theme = ns.Anim, ns.RollFX, ns.Theme
local ART, Gradient, PlainNumber, StyleItemBorder = ns.ART, ns.Gradient, ns.PlainNumber, ns.StyleItemBorder
local TrySetFile, UsableName, ItemLabel = ns.TrySetFile, ns.UsableName, ns.ItemLabel

local ROW_H, ROW_GAP, SLOT, BTN = 40, 3, 34, 30
local MAX_ROWS = 8
local PROMPT_W = 300            -- a little wider than the game's 277 pixel roll popup
local CHOSEN_HOLD = 0.9         -- seconds a row stays after you chose, showing your choice
local TOAST_W, TOAST_H, TOAST_ICON = 290, 60, 40
local TOAST_TIME = 5            -- seconds a toast stays (plus the item's extra hold)
local MUTED = "|cff9d9d9d"
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- right to left: Pass on the far right, Need nearest the item (the order of the game's own frame, mirrored)
local BUTTONS = {
    { type = 0, tex = "Interface\\Buttons\\UI-GroupLoot-Pass", label = "PASS", fallback = "Pass" },
    { type = 3, tex = "Interface\\Buttons\\UI-GroupLoot-DE", label = "ROLL_DISENCHANT", fallback = "Disenchant",
        can = 8, reason = 11 },
    { type = 2, tex = "Interface\\Buttons\\UI-GroupLoot-Coin", label = "GREED", fallback = "Greed", can = 7, reason = 10 },
    { type = 1, tex = "Interface\\Buttons\\UI-GroupLoot-Dice", label = "NEED", fallback = "Need", can = 6, reason = 9 },
}

local function Label(b)
    local text = _G[b.label]
    return type(text) == "string" and text or b.fallback
end

local function Enabled(key)
    return ns.db ~= nil and ns.db.rollWindow ~= false and ns.db[key] ~= false
end

-- EllesmereUI's or ElvUI's own roll list is on: two sets of buttons would only confuse.
local function OtherRollFrames()
    local eui = type(_G.EllesmereUI) == "table" and _G.EllesmereUI._LootRolls
    if type(eui) == "table" and type(eui.Suppressed) == "function" then
        local ok, on = pcall(eui.Suppressed)
        if ok and on then
            return true
        end
    end
    local engine = type(_G.ElvUI) == "table" and _G.ElvUI[1]
    if type(engine) ~= "table" then
        return false
    end
    local ok, on = pcall(function() return engine.private.general.lootRoll end)
    return ok and on == true
end

-- WoW Forever's Gamepad interface style drives its own roll frame with the controller.
local function GamepadStyle()
    local style, types = _G.C_InputInterfaceStyle, _G.Enum and _G.Enum.InputDeviceInterfaceType
    if type(style) ~= "table" or type(style.GetCurrentStyle) ~= "function" or type(types) ~= "table" then
        return false
    end
    local ok, current = pcall(style.GetCurrentStyle)
    return ok and current ~= nil and current == types.Gamepad
end

-- ===== the roll buttons =====
local prompt               -- the container of the rows, in the game's own roll popup spot
local entries = {}         -- { id = rollID, link, duration, row, chosenAt }, oldest first
local durations = {}       -- [rollID] = seconds the roll lasts (from START_LOOT_ROLL)
local rowPool = {}
local suppressed = false   -- the game's popup route is closed (for the rest of the session)

-- Closes the game's popup route. A client that cannot close it keeps its popups and gets no buttons: never both.
local function Suppress()
    if suppressed or OtherRollFrames() or GamepadStyle() then
        return
    end
    local ge = _G.GameEvent
    if type(ge) == "table" and type(ge.UnregisterInternalEvent) == "function"
        and pcall(ge.UnregisterInternalEvent, "START_LOOT_ROLL") then
        suppressed = true
    end
end

-- Our buttons stand in for the game's popups (once the route is closed they show every roll, even after the option
-- was turned off, until the next /reload).
local function ButtonsOn()
    return suppressed and not GamepadStyle()
end

local function RollInfo(id)
    if not GetLootRollItemInfo then
        return nil
    end
    local info = { pcall(GetLootRollItemInfo, id) }
    if not info[1] then
        return nil
    end
    table.remove(info, 1)
    return info
end

local function TimeLeft(id)
    if not GetLootRollTimeLeft then
        return nil
    end
    local ok, ms = pcall(GetLootRollTimeLeft, id)
    return ok and PlainNumber(ms) and ms / 1000 or nil
end

local Layout, Remove, Chosen

local function SlotEnter(self)
    if not GameTooltip or not self.rollID then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not (GameTooltip.SetLootRollItem and pcall(GameTooltip.SetLootRollItem, GameTooltip, self.rollID)) and self.link then
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
    end
    GameTooltip:Show()
end

local function ButtonEnter(self)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(Label(self.def), 1, 1, 1)
    if self.why then
        GameTooltip:AddLine(self.why, 1, 0.35, 0.3, true)
    end
    GameTooltip:Show()
end

local function ButtonClick(self)
    local e = self.entry
    if not e or not self.usable or not RollOnLoot then
        return
    end
    if not pcall(RollOnLoot, e.id, self.def.type) then
        return
    end
    if e.bop and self.def.type ~= 0 then
        return -- bind on pickup: the game asks first, the pick counts once confirmed (ConfirmLootRoll)
    end
    Chosen(e, self.def.type)
end

-- you picked (or confirmed a bind on pickup pick): the row shows your choice for a moment, then leaves
function Chosen(e, rollType)
    if e.chosenAt then
        return
    end
    local def
    for _, b in ipairs(BUTTONS) do
        if b.type == rollType then
            def = b
        end
    end
    e.chosenAt = GetTime()
    local row = e.row
    for _, b in ipairs(row.buttons) do
        b:Hide()
    end
    row.chosen:SetText(def and (MUTED .. Label(def) .. "|r") or "")
    row.chosen:Show()
end

local function SlotFor(parent, size)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(size, size)
    s.border = s:CreateTexture(nil, "BACKGROUND", nil, 1)
    s.border:SetAllPoints()
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.styled = false -- the flat 1 pixel quality edge
    return s
end

local function MakeRow()
    local row = CreateFrame("Frame", nil, prompt, TEMPLATE)
    row:SetHeight(ROW_H)
    Theme.Panel(row)
    row.wash = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.wash:SetPoint("TOPLEFT", 2, -2)
    row.wash:SetPoint("BOTTOMLEFT", 2, 2)
    row.slot = SlotFor(row, SLOT)
    row.slot:SetPoint("LEFT", 3, 0)
    row.slot:SetScript("OnEnter", SlotEnter)
    row.slot:SetScript("OnLeave", ns.ItemButtonLeave)
    row.slot:SetScript("OnClick", ns.ItemButtonClick)
    row.buttons = {}
    for i, def in ipairs(BUTTONS) do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(BTN, BTN)
        pcall(b.SetNormalTexture, b, def.tex .. "-Up")
        pcall(b.SetPushedTexture, b, def.tex .. "-Down")
        pcall(b.SetHighlightTexture, b, def.tex .. "-Highlight")
        b.def = def
        b:SetScript("OnEnter", ButtonEnter)
        b:SetScript("OnLeave", ns.ItemButtonLeave)
        b:SetScript("OnClick", ButtonClick)
        row.buttons[i] = b
    end
    row.name = row:CreateFontString(nil, "OVERLAY")
    Theme.SetFont(row.name, 13)
    row.name:SetWordWrap(false)
    row.name:SetJustifyH("LEFT")
    row.name:SetPoint("TOPLEFT", row.slot, "TOPRIGHT", 8, -3)
    row.chosen = row:CreateFontString(nil, "OVERLAY")
    Theme.SetFont(row.chosen, 12)
    row.chosen:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.barBg = row:CreateTexture(nil, "ARTWORK")
    row.barBg:SetHeight(3)
    row.barBg:SetPoint("BOTTOMLEFT", row.slot, "BOTTOMRIGHT", 8, 3)
    row.barBg:SetColorTexture(1, 1, 1, 0.07)
    row.bar = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.bar:SetHeight(3)
    row.bar:SetPoint("LEFT", row.barBg, "LEFT")
    return row
end

-- the item, its rarity wash and which buttons this character may use (with the game's reason when not)
local function Fill(e)
    local row, info = e.row, RollInfo(e.id) or {}
    local look = RollFX.Look(e.link)
    e.bop = info[5] == true
    row.slot.rollID, row.slot.link = e.id, e.link
    TrySetFile(row.slot.icon, info[1] or ns.ItemTexture(e.link))
    StyleItemBorder(row.slot, e.link)
    local count = PlainNumber(info[3]) and info[3] > 1 and (" x" .. info[3]) or ""
    row.name:SetText(ItemLabel(e.link) .. count)
    Gradient(row.wash, "HORIZONTAL", look.r, look.g, look.b, look.tier.wash + 0.04, look.r, look.g, look.b, 0)
    for _, b in ipairs(row.buttons) do
        local def = b.def
        local usable = def.can == nil or info[def.can] == true
        local reason = def.reason and info[def.reason]
        local why = not usable and PlainNumber(reason) and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason] or nil
        b.entry, b.usable, b.why = e, usable, type(why) == "string" and why or nil
        b:SetShown(not e.chosenAt and (usable or def.type ~= 3)) -- no Disenchant button when nobody can
        b:SetAlpha(usable and 1 or 0.3)
        local normal = b.GetNormalTexture and b:GetNormalTexture()
        if normal and normal.SetDesaturated then
            normal:SetDesaturated(not usable)
        end
    end
    -- the shown buttons line up from the right edge; the name and the countdown end where they begin
    local right = -5
    for _, b in ipairs(row.buttons) do
        if b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("RIGHT", row, "RIGHT", right, 0)
            right = right - BTN - 4
        end
    end
    row.textRight = right - 6
    row.name:SetPoint("RIGHT", row, "RIGHT", row.textRight, 0)
    row.barBg:SetPoint("RIGHT", row, "RIGHT", row.textRight, 0)
    row.chosen:SetShown(e.chosenAt ~= nil)
end

local function TakeRow()
    local row = table.remove(rowPool) or MakeRow()
    row:Show()
    return row
end

-- Nothing secret among the values (a frame fed secret data hands back secret values from its getters).
local function Readable(...)
    for i = 1, select("#", ...) do
        if issecretvalue and issecretvalue((select(i, ...))) then
            return false
        end
    end
    return true
end

-- Our rows go where the game's own roll popups would be, as the player's UI has them. The game hangs its popups
-- from GroupLootContainer, which sits on top of the bottom managed column (BottomManagedFrameContainer, above the
-- action bars) unless a mover or an unlock mode of the player's UI has placed it elsewhere. Placed elsewhere: our
-- rows grow up from its spot. In the column (or never laid out): from the top of the column. Both frames are only
-- read, never changed; the place is looked up again for every roll, so a move in the UI is followed.
local function Place()
    prompt:ClearAllPoints()
    local loot, col = _G.GroupLootContainer, _G.BottomManagedFrameContainer
    if type(loot) == "table" and loot.GetPoint and loot.GetBottom then
        local ok, point, rel = pcall(loot.GetPoint, loot, 1)
        local okb, bottom = pcall(loot.GetBottom, loot)
        if ok and okb and point and Readable(point, rel) and PlainNumber(bottom) and (col == nil or rel ~= col) then
            prompt:SetPoint("BOTTOM", loot, "BOTTOM", 0, 0)
            return
        end
    end
    if type(col) == "table" and col.GetTop then
        local ok, top = pcall(col.GetTop, col)
        if ok and PlainNumber(top) then
            prompt:SetPoint("BOTTOM", col, "TOP", 0, 4)
            return
        end
    end
    prompt:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
end

function Layout()
    if not prompt then
        return
    end
    if #entries == 0 then
        prompt:Hide()
        return
    end
    local y = 0
    for i, e in ipairs(entries) do
        local row = e.row
        row:ClearAllPoints()
        row:SetPoint("LEFT", prompt, "LEFT")
        row:SetPoint("RIGHT", prompt, "RIGHT")
        row:SetPoint("BOTTOM", prompt, "BOTTOM", 0, y)
        y = y + ROW_H + (i < #entries and ROW_GAP or 0)
    end
    prompt:SetHeight(math.max(1, y))
    Place()
    prompt:Show()
end

function Remove(id)
    for i, e in ipairs(entries) do
        if e.id == id then
            e.row:Hide()
            rowPool[#rowPool + 1] = e.row
            table.remove(entries, i)
            Layout()
            return
        end
    end
end

-- countdown bars; a row leaves once its roll is over or shortly after you chose
local function PromptTick()
    local now = GetTime()
    for i = #entries, 1, -1 do
        local e = entries[i]
        local left = TimeLeft(e.id)
        if (e.chosenAt and now - e.chosenAt >= CHOSEN_HOLD) or (left and left <= 0) then
            Remove(e.id)
        elseif left then
            local frac = math.max(0, math.min(1, left / e.duration))
            local w = e.row.barBg:GetWidth() or 0
            e.row.bar:SetWidth(math.max(1, w * frac))
            if frac < 0.25 then
                e.row.bar:SetColorTexture(1, 0.3, 0.25, 0.9)
            else
                local r, g, b = Theme.Accent()
                e.row.bar:SetColorTexture(r, g, b, 0.85)
            end
        end
    end
end

local function BuildPrompt()
    if prompt or not CreateFrame then
        return
    end
    prompt = CreateFrame("Frame", "WhoWonThatRollButtons", UIParent)
    prompt:SetFrameStrata("HIGH")
    prompt:SetSize(PROMPT_W, 1)
    prompt:SetClampedToScreen(true)
    prompt:SetScript("OnUpdate", PromptTick)
    prompt:Hide()
end

local function Add(id)
    if not PlainNumber(id) or not GetLootRollItemLink then
        return
    end
    BuildPrompt()
    if not ButtonsOn() then
        return
    end
    for _, e in ipairs(entries) do
        if e.id == id then
            return
        end
    end
    local ok, link = pcall(GetLootRollItemLink, id)
    if not ok or not UsableName(link) or #entries >= MAX_ROWS then
        return
    end
    local e = { id = id, link = link, duration = durations[id] or TimeLeft(id) or 60 }
    e.duration = math.max(1, e.duration)
    e.row = TakeRow()
    entries[#entries + 1] = e
    Fill(e)
    Layout()
end

local function EntryOf(id)
    for _, e in ipairs(entries) do
        if e.id == id then
            return e
        end
    end
    return nil
end

-- ===== the loot toast =====
local toast
local toastQueue = {}
local claimed = {}         -- [item link] = time: wins whose game toast we put away (our toast shows them)
local alertHooked = false

local function KindText(st)
    if not st then
        return ""
    end
    if st.kind == "greed" then
        return L("chat_greed")
    end
    return st.tag and L("chat_need_os") or L("chat_need")
end

local ShowNextToast

local function ToastTick(self, elapsed)
    local now = GetTime()
    local look = self.look
    if not look then
        return
    end
    local tier = look.tier
    if tier.embers and now - self.shownAt < 3 then
        self.emberAcc = (self.emberAcc or 0) + elapsed * tier.embers * 1.5
        while self.emberAcc >= 1 do
            self.emberAcc = self.emberAcc - 1
            RollFX.Emit(self.motes, 8 + math.random() * (TOAST_W - 16), 3, look.fr, look.fg * (0.7 + 0.3 * math.random()),
                look.fb * 0.6, { vy = 10 + math.random() * 10, life = 1.8 + math.random(), size = 4 + math.random() * 2,
                    flicker = true })
        end
    end
    if tier.rays then
        RollFX.StepRays(self.rays, now - self.shownAt, look.fr, look.fg, look.fb)
    end
    RollFX.Step(self.motes, elapsed)
    if now >= self.hideAt then
        local a = 1 - (now - self.hideAt) / 0.4
        if a <= 0 then
            self:Hide()
            ShowNextToast()
        else
            self:SetAlpha(a)
        end
    end
end

local function Dismiss(self, button)
    if button == "RightButton" then
        self.hideAt = math.min(self.hideAt, GetTime())
    end
end

local function BuildToast()
    local f = CreateFrame("Frame", "WhoWonThatLootToast", UIParent, TEMPLATE)
    f:SetSize(TOAST_W, TOAST_H)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", Dismiss)
    Theme.Panel(f)
    f.wash = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    f.wash:SetPoint("TOPLEFT", 2, -2)
    f.wash:SetPoint("BOTTOMLEFT", 2, 2)
    f.wash:SetWidth(TOAST_W * 0.8)
    f.slot = SlotFor(f, TOAST_ICON)
    f.slot:SetPoint("LEFT", 10, 0)
    f.slot:SetScript("OnEnter", ns.ItemButtonEnter)
    f.slot:SetScript("OnLeave", ns.ItemButtonLeave)
    f.slot:SetScript("OnClick", ns.ItemButtonClick)
    f.glow = f:CreateTexture(nil, "ARTWORK", nil, -1)
    f.glow:SetSize(TOAST_ICON * 1.9, TOAST_ICON * 1.9)
    f.glow:SetPoint("CENTER", f.slot, "CENTER")
    f.glow.ok = TrySetFile(f.glow, ART.glow)
    if f.glow.ok then
        f.glow:SetBlendMode("ADD")
    end
    f.glow:Hide()
    f.burst = f:CreateTexture(nil, "ARTWORK")
    f.burst:SetSize(96, 96)
    f.burst:SetPoint("CENTER", f.slot, "CENTER")
    if TrySetFile(f.burst, ART.glow) then
        f.burst:SetBlendMode("ADD")
        f.burstAnim = Anim.MakeFlash(f.burst, 1, 0.9, 0.5, 1.6)
    else
        f.burst:Hide()
    end
    f.rings = RollFX.NewRings(f, f.slot, 3, TOAST_ICON * 1.5)
    f.rays = RollFX.NewRays(f, f.slot, 130)
    f.motes = RollFX.NewEmitter(f, 24)
    f.title = f:CreateFontString(nil, "OVERLAY")
    Theme.SetFont(f.title, 10)
    f.title:SetPoint("TOPLEFT", f.slot, "TOPRIGHT", 10, 0)
    f.name = f:CreateFontString(nil, "OVERLAY")
    Theme.SetFont(f.name, 13)
    f.name:SetWordWrap(false)
    f.name:SetJustifyH("LEFT")
    f.name:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.name:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.sub = f:CreateFontString(nil, "OVERLAY")
    Theme.SetFont(f.sub, 10)
    f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
    f.pop = Anim.MakePop(f, 0.94, 0.3)
    f:SetScript("OnUpdate", ToastTick)
    f:Hide()
    return f
end

-- where the game's own alerts appear (so a moved AlertFrame moves the toast too)
local function PlaceToast(f)
    f:ClearAllPoints()
    local alert = _G.AlertFrame
    if type(alert) == "table" and alert.GetBottom and alert:GetBottom() then
        f:SetPoint("BOTTOM", alert, "BOTTOM", 0, 0)
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
    end
end

local function PlayToast(t)
    toast = toast or BuildToast()
    local f, look = toast, t.look
    local tier = look.tier
    f.look, f.shownAt, f.emberAcc = look, GetTime(), 0
    f.hideAt = f.shownAt + TOAST_TIME + tier.hold
    PlaceToast(f)
    f.slot.link = t.item
    TrySetFile(f.slot.icon, ns.ItemTexture(t.item))
    StyleItemBorder(f.slot, t.item)
    local ar, ag, ab = Theme.Accent()
    f.title:SetText(string.format("|cff%02x%02x%02x%s|r", math.floor(ar * 255 + 0.5), math.floor(ag * 255 + 0.5),
        math.floor(ab * 255 + 0.5), L("toast_won")))
    f.name:SetText(ItemLabel(t.item))
    local parts = {}
    if t.st and PlainNumber(t.roll) then
        parts[#parts + 1] = KindText(t.st) .. " " .. t.roll
    end
    if look.price then
        parts[#parts + 1] = ns.FormatMoney(look.price)
    end
    f.sub:SetText(MUTED .. table.concat(parts, ns.SUMMARY_DOT or " - ") .. "|r")
    Gradient(f.wash, "HORIZONTAL", look.r, look.g, look.b, tier.wash + 0.06, look.r, look.g, look.b, 0)
    f.glow:SetShown(f.glow.ok and tier.iconGlow == true)
    f.glow:SetVertexColor(look.r, look.g, look.b, 0.45)
    if f.rays then
        f.rays:SetAlpha(0)
    end
    RollFX.ClearEmitter(f.motes)
    f:SetAlpha(1)
    f:Show()
    Anim.Play(f.pop)
    if tier.burst > 0 and f.burstAnim then
        f.burst:SetVertexColor(look.fr, look.fg, look.fb, tier.burst)
        Anim.Play(f.burstAnim)
    end
    RollFX.PlayRings(f.rings, tier.rings, look.fr, look.fg, look.fb)
    for i = 1, tier.motes do
        RollFX.Emit(f.motes, 60 + math.random() * (TOAST_W - 80), 14 + math.random() * 10, look.fr, look.fg, look.fb,
            { delay = 0.2 + i * 0.07 })
    end
end

function ShowNextToast()
    local t = table.remove(toastQueue, 1)
    if t then
        PlayToast(t)
    end
end

-- Called by the roll window when you won a roll and its numbers have landed.
local function Toast(item, look, st, roll)
    if not (Enabled("wonToast") and CreateFrame) or type(item) ~= "string" then
        return
    end
    toastQueue[#toastQueue + 1] = { item = item, look = look or RollFX.Look(item), st = st, roll = roll }
    if #toastQueue > 5 then
        table.remove(toastQueue, 1)
    end
    if not (toast and toast:IsShown()) then
        ShowNextToast()
    end
end

-- A won item that gets our toast: shown by the roll window (not ignored, not below the minimum value).
local function OursToShow(link)
    return Enabled("wonToast") and UsableName(link)
        and not ((ns.IsIgnoredItem and ns.IsIgnoredItem(link)) or (ns.IsCheapItem and ns.IsCheapItem(link)))
end

local function Claim(link)
    local now = GetTime()
    for k, t in pairs(claimed) do
        if now - t > 30 then
            claimed[k] = nil
        end
    end
    claimed[link] = now
end

-- The game shows a roll win as LootAlertSystem:ShowAlert(link, quantity, rollType, roll, ...). Our toast shows that
-- win, so the game's toast for the same item is put away as it appears (the way EllesmereUI hides toasts).
local function OnGameToast(system, link, _, rollType)
    if rollType == nil or type(link) ~= "string" or not (claimed[link] or OursToShow(link)) then
        return
    end
    claimed[link] = nil
    local pool = system.alertFramePool
    if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then
        return
    end
    local ok, iter, state, first = pcall(pool.EnumerateActive, pool)
    if not ok or not iter then
        return
    end
    for frame in iter, state, first do
        if frame.hyperlink == link and frame:IsShown() then
            frame:Hide()
        end
    end
end

local function HookGameToast()
    local system = _G.LootAlertSystem
    if alertHooked or type(system) ~= "table" or type(system.ShowAlert) ~= "function" or not hooksecurefunc then
        return
    end
    alertHooked = true
    hooksecurefunc(system, "ShowAlert", OnGameToast)
end

local function OnRollWon(link)
    HookGameToast() -- in case the alert system was not there yet at login
    if OursToShow(link) then
        Claim(link)
    end
end

-- ===== events =====
local function Apply()
    HookGameToast()
    if Enabled("rollButtons") then
        Suppress()
    elseif suppressed then
        ns.Print(L("rb_reload")) -- the game's popups come back with the next /reload
    end
    if not ButtonsOn() then
        return
    end
    -- rolls already open (after /reload or logging in during a roll)
    local ok, ids = pcall(GetActiveLootRollIDs or function() return {} end)
    if ok and type(ids) == "table" then
        for _, id in ipairs(ids) do
            Add(id)
        end
    end
end

local events = CreateFrame and CreateFrame("Frame")
if events then
    for _, ev in ipairs({ "PLAYER_LOGIN", "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS",
        "LOOT_ITEM_ROLL_WON" }) do
        pcall(events.RegisterEvent, events, ev) -- events this client does not know are skipped
    end
    events:SetScript("OnEvent", function(_, event, a1, a2)
        if not ns.db then
            return
        elseif event == "PLAYER_LOGIN" then
            -- a bind on pickup pick counts once it is confirmed
            if type(ConfirmLootRoll) == "function" and hooksecurefunc then
                hooksecurefunc("ConfirmLootRoll", function(rollID, rollType)
                    local e = EntryOf(rollID)
                    if e then
                        Chosen(e, rollType)
                    end
                end)
            end
            -- after EllesmereUI's own login, so its roll list has made up its mind
            if C_Timer and C_Timer.After then
                C_Timer.After(0, Apply)
            else
                Apply()
            end
        elseif event == "START_LOOT_ROLL" then
            if PlainNumber(a1) and PlainNumber(a2) and a2 > 0 then
                durations[a1] = a2 > 1000 and a2 / 1000 or a2
            end
            Add(a1)
        elseif event == "CANCEL_LOOT_ROLL" then
            Remove(a1)
            durations[a1] = nil
            ns.SummaryCall(ns.RollWindow.OnRollGone, a1)
        elseif event == "CANCEL_ALL_LOOT_ROLLS" then
            for i = #entries, 1, -1 do
                Remove(entries[i].id)
            end
        elseif event == "LOOT_ITEM_ROLL_WON" then
            OnRollWon(a1)
        end
    end)
end

-- ===== shared with the other files =====
ns.LootFrames = { Toast = Toast, Apply = Apply }
