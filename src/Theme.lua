-- Who Won That: matches the roll window to the UI the player uses (EllesmereUI, ElvUI, TukUI or Blizzard's own look).
-- Every UI addon is optional and every call into one is protected: when an addon is missing, changed its API or
-- raises an error, the window keeps the Blizzard look instead of breaking.
local _, ns = ...

local AddEdges, GOLD_B, GOLD_G, GOLD_R = ns.AddEdges, ns.GOLD_B, ns.GOLD_G, ns.GOLD_R

local FLAT_BG = { 0.05, 0.05, 0.06, 0.92 }
local FLAT_EDGE = { 0, 0, 0, 1 }
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

-- EllesmereUI hands its skinning toolkit to a callback at login (only while the player has skinning enabled for us).
local euiSkin
local restyleHooks = {}

local function RunRestyleHooks()
    for _, fn in ipairs(restyleHooks) do
        local ok, err = pcall(fn)
        if not ok and geterrorhandler then
            geterrorhandler()(err)
        end
    end
end

if type(EllesmereUI) == "table" and type(EllesmereUI.RegisterSkin) == "function" then
    pcall(EllesmereUI.RegisterSkin, "WhoWonThat", function(S)
        euiSkin = S
        if type(S.OnLooksChanged) == "function" then
            pcall(S.OnLooksChanged, RunRestyleHooks) -- live accent / theme changes in EllesmereUI's options
        end
        RunRestyleHooks()
    end)
end

local function ElvEngine()
    local registry = _G.ElvUI
    local E = type(registry) == "table" and registry[1]
    return type(E) == "table" and E or nil
end

local function TukEngine()
    local registry = _G.Tukui
    local T = type(registry) == "table" and registry[1]
    if type(T) ~= "table" then
        return nil
    end
    return T, type(registry[2]) == "table" and registry[2] or nil
end

-- "eui", "elvui", "tukui" or "blizzard"
local function Kind()
    if euiSkin and (type(euiSkin.IsEnabled) ~= "function" or euiSkin.IsEnabled()) then
        return "eui"
    end
    if ElvEngine() then
        return "elvui"
    end
    if TukEngine() then
        return "tukui"
    end
    return "blizzard"
end

-- r, g, b of a color stored as { r = , g = , b = } or { 1, 2, 3 }
local function ColorOf(c)
    if type(c) ~= "table" then
        return nil
    end
    local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return r, g, b
    end
    return nil
end

-- The UI's highlight color: EllesmereUI's accent, ElvUI's value color, else the addon's gold.
local function Accent()
    local kind = Kind()
    if kind == "eui" and type(euiSkin.GetAccentColor) == "function" then
        local ok, r, g, b = pcall(euiSkin.GetAccentColor)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    elseif kind == "elvui" then
        local E = ElvEngine()
        local r, g, b = ColorOf(type(E.media) == "table" and E.media.rgbvaluecolor)
        if r then
            return r, g, b
        end
    end
    return GOLD_R, GOLD_G, GOLD_B
end

-- Font path and outline flags of the UI.
local function FontInfo()
    local kind = Kind()
    if kind == "eui" and type(euiSkin.GetFont) == "function" then
        local ok, path, flags = pcall(euiSkin.GetFont)
        if ok and type(path) == "string" and path ~= "" then
            return path, type(flags) == "string" and flags or ""
        end
    elseif kind == "elvui" then
        local E = ElvEngine()
        local path = type(E.media) == "table" and E.media.normFont
        if type(path) == "string" and path ~= "" then
            return path, ""
        end
    elseif kind == "tukui" then
        local _, C = TukEngine()
        local path = C and type(C.Medias) == "table" and C.Medias.Font
        if type(path) == "string" and path ~= "" then
            return path, ""
        end
    end
    return (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT) or DEFAULT_FONT, ""
end

-- Sets a font string in the UI's font. `outline` adds an outline (big numbers stay readable on any background).
local function SetFont(fs, size, outline)
    local path, flags = FontInfo()
    if outline and not flags:find("OUTLINE") then
        flags = (flags == "" and "OUTLINE") or (flags .. ", OUTLINE")
    end
    if not pcall(fs.SetFont, fs, path, size, flags) or not fs:GetFont() then
        pcall(fs.SetFont, fs, DEFAULT_FONT, size, outline and "OUTLINE" or "")
    end
    if fs.SetShadowOffset then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, outline and 0 or 0.8)
    end
end

local function FlatPanel(frame)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(FLAT_BG[1], FLAT_BG[2], FLAT_BG[3], FLAT_BG[4])
    AddEdges(frame, "BORDER", FLAT_EDGE[1], FLAT_EDGE[2], FLAT_EDGE[3], FLAT_EDGE[4])
end

-- Blizzard look: the slim tooltip border on a dark background (smaller and calmer than the dialog border).
local function BlizzardPanel(frame)
    if frame.SetBackdrop and pcall(frame.SetBackdrop, frame, {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    }) then
        pcall(frame.SetBackdropColor, frame, 0.04, 0.04, 0.05, 0.94)
        pcall(frame.SetBackdropBorderColor, frame, 0.62, 0.56, 0.44, 1)
        return true
    end
    FlatPanel(frame)
    return false
end

-- Gives a frame the window look of the UI. Returns the kind that was applied. Call once per frame.
local function Panel(frame)
    local kind = Kind()
    if kind == "eui" and type(euiSkin.Panel) == "function" and pcall(euiSkin.Panel, frame) then
        return kind
    elseif kind == "elvui" or kind == "tukui" then
        if frame.SetTemplate and pcall(frame.SetTemplate, frame, "Transparent") then
            return kind
        end
        if frame.CreateBackdrop and pcall(frame.CreateBackdrop, frame, "Transparent") then
            return kind
        end
        FlatPanel(frame)
        return kind
    end
    BlizzardPanel(frame)
    return "blizzard"
end

-- The close (X) button in the UI's style; the Blizzard one, or a plain "x" when the template is missing.
local function CloseButton(parent)
    local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelCloseButton")
    if not ok or not b then
        b = CreateFrame("Button", nil, parent)
        local x = b:CreateFontString(nil, "OVERLAY")
        SetFont(x, 14, true)
        x:SetPoint("CENTER")
        x:SetText("x")
        x:SetTextColor(0.8, 0.8, 0.8)
    end
    b:SetSize(20, 20)
    local kind = Kind()
    if kind == "eui" and type(euiSkin.CloseButton) == "function" then
        pcall(euiSkin.CloseButton, b)
    elseif kind == "elvui" then
        local E = ElvEngine()
        local skins = E.GetModule and select(2, pcall(E.GetModule, E, "Skins"))
        if type(skins) == "table" and type(skins.HandleCloseButton) == "function" then
            pcall(skins.HandleCloseButton, skins, b)
        end
    elseif kind == "tukui" and b.SkinCloseButton then
        pcall(b.SkinCloseButton, b)
    end
    return b
end

-- True for the flat looks (EllesmereUI, ElvUI, TukUI): item frames and edges are drawn as 1 pixel lines there.
local function IsFlat()
    return Kind() ~= "blizzard"
end

-- fn runs when the UI's looks change (EllesmereUI's live accent changes, or its skin arriving after our frames).
local function OnRestyle(fn)
    restyleHooks[#restyleHooks + 1] = fn
end

-- ===== shared with the other files =====
ns.Theme = {
    Kind = Kind, Accent = Accent, SetFont = SetFont, Panel = Panel, CloseButton = CloseButton,
    IsFlat = IsFlat, OnRestyle = OnRestyle,
}
