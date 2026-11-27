-- Who Won That: rarity effects shared by the roll window, the roll buttons and the loot toast.
-- The rarer (or the more valuable on the auction house) an item, the more its roll shows - but always quietly and in
-- the item's own quality color: every step keeps what the step below has and adds one visible thing.
--   poor: a crown only          common: a few sparks         uncommon: light sweeps the winner, motes rise
--   rare: a thin ring, the winner is marked                  epic: the rest dims, a soft bloom behind the icon
--   legendary: the name fades in, embers drift up, slow rays behind the icon
-- A price from a price addon raises the step: 100 gold or more by one, 500 gold or more to at least epic.
-- Nothing here shakes or strobes; a pulse is never faster than 1.4 seconds, and every effect ends in a calm state.
local _, ns = ...

local ART, PlainNumber, TrySetFile = ns.ART, ns.PlainNumber, ns.TrySetFile

local SPARK = "Interface\\Cooldown\\star4"
local RAYS = "Interface\\Cooldown\\starburst"
local VIGNETTE = "Interface\\FullScreenTextures\\LowHealth"
local GOLD = 10000 -- copper
local WORTH_GOLD, RICH_GOLD, TREASURE_GOLD = 20, 100, 500

-- One table per step (index = power 0 .. 5).
--   spin: seconds the deciding number spins     hold: extra seconds the result stays on screen
--   wash: alpha of the quality wash in the header (breathe: it slowly breathes)
--   burst: peak alpha of the light behind the icon at the win, rings: thin rings from the icon
--   sparks / motes: particles at the winner, embers: embers per second rising during the roll
local TIERS = {
    [0] = { power = 0, spin = 1.4, hold = 0, wash = 0.06, burst = 0, rings = 0, sparks = 0, motes = 0 },
    [1] = { power = 1, spin = 1.6, hold = 0, wash = 0.10, burst = 0.5, rings = 0, sparks = 5, motes = 0, tint = true },
    [2] = { power = 2, spin = 1.8, hold = 0, wash = 0.14, burst = 0.5, rings = 0, sparks = 0, motes = 7, tint = true,
        sweep = true },
    [3] = { power = 3, spin = 2.1, hold = 1, wash = 0.18, burst = 0.65, rings = 1, sparks = 0, motes = 9, tint = true,
        sweep = true, mark = true, iconGlow = true },
    [4] = { power = 4, spin = 2.8, hold = 2, wash = 0.26, breathe = true, burst = 0.85, rings = 2, sparks = 0, motes = 12,
        tint = true, sweep = true, mark = true, iconGlow = true, dim = true, edge = true },
    [5] = { power = 5, spin = 3.8, hold = 4, wash = 0.30, breathe = true, burst = 1, rings = 3, sparks = 0, motes = 16,
        tint = true, sweep = true, mark = true, iconGlow = true, dim = true, edge = true, vignette = true,
        embers = 2.5, rays = true, reveal = true },
}

-- value band of a price in copper: 0 none / cheap, 1 worth a look, 2 rich, 3 a treasure
local function ValueBand(copper)
    if not PlainNumber(copper) then
        return 0
    elseif copper >= TREASURE_GOLD * GOLD then
        return 3
    elseif copper >= RICH_GOLD * GOLD then
        return 2
    elseif copper >= WORTH_GOLD * GOLD then
        return 1
    end
    return 0
end

local function PriceOf(link)
    if not ns.ItemPrice then
        return nil
    end
    local ok, price = pcall(ns.ItemPrice, link)
    return ok and PlainNumber(price) and price or nil
end

-- The look of an item's roll: the step (TIERS entry), the quality color, the effect color (the quality color made
-- bright enough to glow; white items use the UI's accent), the price and its band.
local function Look(link)
    local r, g, b, q = ns.ItemQualityColorRaw(link)
    q = PlainNumber(q) and math.max(0, math.min(5, q)) or 1
    local price = PriceOf(link)
    local band = ValueBand(price)
    local power = q
    if band >= 2 then
        power = math.min(5, power + 1)
    end
    if band >= 3 then
        power = math.max(power, 4)
    end
    local fr, fg, fb = r + (1 - r) * 0.25, g + (1 - g) * 0.25, b + (1 - b) * 0.25
    if q == 1 then
        fr, fg, fb = ns.Theme.Accent()
    end
    return { tier = TIERS[power], quality = q, r = r, g = g, b = b, fr = fr, fg = fg, fb = fb,
        price = price, band = band }
end

-- ===== animation helpers (every one is optional: a client without an animation type just skips it) =====
local function NewAnim(region)
    if not region.CreateAnimationGroup then
        return nil
    end
    local ok, g = pcall(region.CreateAnimationGroup, region)
    return ok and g or nil
end

local function AddAnim(g, kind, duration)
    local ok, a = pcall(g.CreateAnimation, g, kind)
    if not ok or not a then
        return nil
    end
    a:SetDuration(duration)
    if a.SetSmoothing then
        pcall(a.SetSmoothing, a, "OUT")
    end
    return a
end

local function ScaleBetween(a, from, to)
    if a and a.SetScaleFrom and a.SetScaleTo then
        a:SetScaleFrom(from, from)
        a:SetScaleTo(to, to)
    end
end

-- grows in from `from` times its size while fading in
local function MakePop(region, from, duration)
    local g = NewAnim(region)
    if not g then
        return nil
    end
    ScaleBetween(AddAnim(g, "Scale", duration), from, 1)
    local a = AddAnim(g, "Alpha", duration * 0.6)
    if a then
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
    end
    return g
end

-- a region resting invisible that lights up and fades out
local function MakeFlash(region, peak, duration, scaleFrom, scaleTo)
    region:SetAlpha(0)
    local g = NewAnim(region)
    if not g then
        return nil
    end
    local a = AddAnim(g, "Alpha", duration)
    if a then
        a:SetFromAlpha(peak)
        a:SetToAlpha(0)
    end
    if scaleFrom then
        ScaleBetween(AddAnim(g, "Scale", duration), scaleFrom, scaleTo)
    end
    return g
end

local function Play(g)
    if g then
        g:Stop()
        g:Play()
    end
end

-- ===== particles: a small pool of soft stars on one frame, moved by the caller's OnUpdate =====
local function NewEmitter(parent, size)
    local e = { parent = parent, free = {}, live = {} }
    for i = 1, size do
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 6)
        if not TrySetFile(t, SPARK) then
            t:SetColorTexture(1, 1, 1, 1)
        end
        t:SetBlendMode("ADD")
        t:Hide()
        e.free[i] = t
    end
    return e
end

-- One particle at x, y (from the frame's lower left corner). o: vx, vy (pixels per second), life, size, delay,
-- flicker (embers)
local function Emit(e, x, y, r, g, b, o)
    local t = table.remove(e.free)
    if not t then
        return
    end
    o = o or {}
    e.live[#e.live + 1] = { tex = t, x = x, y = y, r = r, g = g, b = b,
        vx = o.vx or (math.random() * 16 - 8), vy = o.vy or (14 + math.random() * 16),
        age = -(o.delay or 0), life = o.life or (1.4 + math.random() * 0.8), size = o.size or (5 + math.random() * 3),
        flicker = o.flicker, sway = math.random() * 6.28 }
end

-- Moves every particle one frame on; true while any is alive.
local function Step(e, dt)
    for i = #e.live, 1, -1 do
        local p = e.live[i]
        p.age = p.age + dt
        local k = p.age / p.life
        if k >= 1 then
            p.tex:Hide()
            e.free[#e.free + 1] = p.tex
            table.remove(e.live, i)
        elseif p.age >= 0 then
            p.vx, p.vy = p.vx * 0.985, p.vy * 0.985
            p.x = p.x + p.vx * dt + math.sin(p.age * 2.2 + p.sway) * 0.2
            p.y = p.y + p.vy * dt
            local a = math.sin(math.pi * k) * 0.8
            if p.flicker then
                a = a * (0.75 + 0.25 * math.sin(p.age * 9 + p.sway))
            end
            local t = p.tex
            t:ClearAllPoints()
            t:SetPoint("CENTER", e.parent, "BOTTOMLEFT", p.x, p.y)
            t:SetSize(p.size, p.size)
            t:SetVertexColor(p.r, p.g, p.b)
            t:SetAlpha(a)
            t:Show()
        end
    end
    return #e.live > 0
end

local function ClearEmitter(e)
    for _, p in ipairs(e.live) do
        p.tex:Hide()
        e.free[#e.free + 1] = p.tex
    end
    wipe(e.live)
end

-- ===== thin rings: the game's soft square glow, growing out of an icon one after another =====
local function NewRings(parent, anchor, count, size)
    local list = {}
    for i = 1, count do
        local t = parent:CreateTexture(nil, "ARTWORK", nil, 2)
        if TrySetFile(t, ART.glow) then
            t:SetBlendMode("ADD")
            t:SetSize(size, size)
            t:SetPoint("CENTER", anchor, "CENTER")
            t.anim = MakeFlash(t, 0.55 - (i - 1) * 0.12, 1.1, 0.7, 2.6 + i * 0.5)
            if t.anim then
                for _, a in ipairs({ t.anim:GetAnimations() }) do
                    if a.SetStartDelay then
                        a:SetStartDelay((i - 1) * 0.22)
                    end
                end
            end
        else
            t:Hide()
        end
        list[i] = t
    end
    return list
end

local function PlayRings(list, count, r, g, b)
    for i = 1, math.min(count, #list) do
        local t = list[i]
        if t.anim then
            t:SetVertexColor(r, g, b)
            Play(t.anim)
        end
    end
end

-- ===== slow rays behind an icon (legendary): turned and faded by the caller's OnUpdate =====
local function NewRays(parent, anchor, size)
    local t = parent:CreateTexture(nil, "BACKGROUND", nil, 3)
    if not TrySetFile(t, RAYS) then
        return nil
    end
    t:SetBlendMode("ADD")
    t:SetSize(size, size)
    t:SetPoint("CENTER", anchor, "CENTER")
    t:SetAlpha(0)
    return t
end

-- t seconds after the win: fades in, turns slowly, fades out; false once it is over
local function StepRays(t, since, r, g, b)
    if not t then
        return false
    end
    local a = 0.32 * math.min(1, since / 0.8) * math.max(0, 1 - math.max(0, since - 2.5) / 3.5)
    t:SetVertexColor(r, g, b)
    t:SetAlpha(a)
    if t.SetRotation then
        pcall(t.SetRotation, t, since * 0.12)
    end
    return a > 0
end

-- ===== a thin edge in the quality color around a frame =====
local function NewEdge(frame)
    local edge = {}
    for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[3] then
            t:SetHeight(1)
        else
            t:SetWidth(1)
        end
        t:Hide()
        edge[i] = t
    end
    return edge
end

local function ShowEdge(edge, on, r, g, b)
    for _, t in ipairs(edge) do
        if on then
            t:SetColorTexture(r, g, b, 0.5)
        end
        t:SetShown(on)
    end
end

-- ===== the world around the window darkens a little (legendary, while the deciding number spins) =====
local vignette
local function Vignette(on)
    if not vignette then
        if not on or not CreateFrame then
            return
        end
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetAllPoints(UIParent)
        f:SetFrameStrata("BACKGROUND")
        f:EnableMouse(false)
        local t = f:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints()
        if not TrySetFile(t, VIGNETTE) then
            return
        end
        t:SetVertexColor(0, 0, 0)
        f.alpha, f.target = 0, 0
        f:SetAlpha(0)
        f:SetScript("OnUpdate", function(self, elapsed)
            local step = elapsed / 1.2 -- fades over 1.2 seconds
            if self.alpha < self.target then
                self.alpha = math.min(self.target, self.alpha + step)
            else
                self.alpha = math.max(self.target, self.alpha - step)
            end
            self:SetAlpha(self.alpha)
            if self.alpha == self.target and self.target == 0 then
                self:Hide()
            end
        end)
        vignette = f
    end
    vignette.target = on and 0.55 or 0
    if on then
        vignette:Show()
    end
end

-- ===== sounds =====
local function SoundAny(...)
    if not (SOUNDKIT and PlaySound) then
        return
    end
    for i = 1, select("#", ...) do
        local id = SOUNDKIT[select(i, ...)]
        if id then
            pcall(PlaySound, id)
            return
        end
    end
end

-- ===== shared with the other files =====
ns.RollFX = {
    Look = Look, ValueBand = ValueBand, TIERS = TIERS,
    NewEmitter = NewEmitter, Emit = Emit, Step = Step, ClearEmitter = ClearEmitter,
    NewRings = NewRings, PlayRings = PlayRings, NewRays = NewRays, StepRays = StepRays,
    NewEdge = NewEdge, ShowEdge = ShowEdge, Vignette = Vignette, SoundAny = SoundAny,
}
ns.Anim = { New = NewAnim, Add = AddAnim, ScaleBetween = ScaleBetween, MakePop = MakePop, MakeFlash = MakeFlash,
    Play = Play }
