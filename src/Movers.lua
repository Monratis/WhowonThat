-- Who Won That: lets the pop-up button and the roll window be moved from the layout editors players already use.
-- Each editor is skipped quietly when it is not installed.
local _, ns = ...

local EnsureSummaryButton, ShowPlacementPreview = ns.EnsureSummaryButton, ns.ShowPlacementPreview
local PlaceSummaryButton, ClearSummaryButtonPos = ns.PlaceSummaryButton, ns.ClearSummaryButtonPos
local StoreSummaryBtnPos = ns.StoreSummaryBtnPos
local SUMMARY_BTN_W, SUMMARY_BTN_H = ns.SUMMARY_BTN_W, ns.SUMMARY_BTN_H
local EnsureRollWindow, RollWindowPreview, PlaceRollWindow = ns.EnsureRollWindow, ns.RollWindowPreview, ns.PlaceRollWindow
local StoreRollWinPos, ClearRollWinPos = ns.StoreRollWinPos, ns.ClearRollWinPos

local function ValidPos(p)
    if type(p) == "table" and type(p.point) == "string" and type(p.relPoint) == "string"
        and type(p.x) == "number" and type(p.y) == "number" then
        return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
    end
    return nil
end

-- While a layout editor is open the button is only a placeholder; hide it again when the editor closes.
local function HideButtonPreview()
    local b = ns.summaryBtn
    if b and b.placing then
        b.placing = false
        b:Hide()
    end
end

-- What every editor needs to know about one movable frame.
local MOVABLES = {
    {
        key = "WWT_SummaryButton", owner = "WhoWonThat", moverName = "WhoWonThatSummaryButton", label = "Who Won That loot pop-up",
        euiLabel = function() return ns.L("popup_label") end, order = 900,
        ensure = EnsureSummaryButton, preview = ShowPlacementPreview, unpreview = HideButtonPreview,
        size = function() return SUMMARY_BTN_W, SUMMARY_BTN_H end,
        store = StoreSummaryBtnPos, saved = function() return ns.db and ns.db.summaryBtnPos end,
        clear = ClearSummaryButtonPos,
        apply = function()
            if ns.summaryBtn then
                PlaceSummaryButton(ns.summaryBtn)
            end
        end,
        default = { point = "TOP", x = 0, y = -12 }, -- the same spot PlaceSummaryButton falls back to
    },
    {
        key = "WWT_RollWindow", owner = "WhoWonThatRollWindow", moverName = "WhoWonThatRollWindow", label = "Who Won That roll window",
        euiLabel = function() return ns.L("rw_mover_label") end, order = 901,
        ensure = EnsureRollWindow,
        preview = function() return RollWindowPreview(true) end,
        unpreview = function() RollWindowPreview(false) end,
        size = function()
            local f = EnsureRollWindow()
            if f then
                return f:GetWidth(), f:GetHeight()
            end
            return ns.ROLL_WINDOW_W, 120
        end,
        store = StoreRollWinPos, saved = function() return ns.db and ns.db.rollWinPos end,
        clear = ClearRollWinPos,
        apply = function()
            local f = EnsureRollWindow()
            if f then
                PlaceRollWindow(f)
            end
        end,
        default = { point = "CENTER", x = 380, y = 160 },
    },
}

-- Blizzard's Edit Mode, through the embedded LibEditMode (src/libs): the frame gets the usual selection box.
local function RegisterEditMode(m)
    local lib = ns.LibEditMode
    local f = lib and lib.AddFrame and lib.RegisterCallback and m.ensure()
    if not f then
        return
    end
    local added = pcall(lib.AddFrame, lib, f, function(_, _, point, x, y)
        m.store(point, point, x, y) -- the library anchors to UIParent with the same point on both sides
    end, { point = m.default.point, x = m.default.x, y = m.default.y }, m.label)
    if added then
        lib:RegisterCallback("enter", m.preview)
        lib:RegisterCallback("exit", m.unpreview)
    end
end

-- EllesmereUI's Unlock Mode.
local function RegisterEllesmereUI(m)
    local E = _G.EllesmereUI
    if not (E and E.RegisterUnlockElements and E.MakeUnlockElement) then
        return
    end
    E:RegisterUnlockElements({
        E.MakeUnlockElement({
            key = m.key,
            label = m.euiLabel(),
            group = "Who Won That",
            order = m.order,
            noResize = true,
            getFrame = m.ensure,
            getSize = m.size,
            isHidden = function() return false end,
            savePos = function(_, point, relPoint, x, y)
                m.store(point, relPoint, x, y)
            end,
            loadPos = function() return ValidPos(m.saved()) end,
            clearPos = m.clear,
            applyPos = m.apply,
        }),
    }, m.owner)
    if E.RegisterUnlockModeListener then
        E:RegisterUnlockModeListener(m.owner, function(active)
            if active then
                m.preview()
            else
                m.unpreview()
            end
        end)
    end
end

-- ElvUI (/moveui), TukUI (/moveui) and SpartanUI (move mode) take over the frame's anchor and keep the position
-- in their own profile, so our own placing and dragging step aside (frame.moverOwned).
local function TakeOver(f, m, register)
    f:ClearAllPoints()
    f:SetPoint(m.default.point, UIParent, m.default.point, m.default.x, m.default.y) -- where the mover starts
    if register() then
        f.moverOwned = true
        return true
    end
    m.apply() -- refused: back to our own position
    return false
end

local function RegisterElvUI(m)
    local registry = _G.ElvUI
    local E = type(registry) == "table" and registry[1]
    local f = E and E.CreateMover and m.ensure()
    if not f then
        return false
    end
    return TakeOver(f, m, function()
        return pcall(E.CreateMover, E, f, m.moverName .. "Mover", m.label, nil, nil, nil, "ALL,GENERAL")
    end)
end

local function RegisterTukUI(m)
    local registry = _G.Tukui
    local T = type(registry) == "table" and registry[1]
    local movers = type(T) == "table" and T.Movers
    local f = movers and movers.RegisterFrame and m.ensure()
    if not f then
        return false
    end
    return TakeOver(f, m, function()
        return pcall(movers.RegisterFrame, movers, f, m.label) -- TukUI needs the frame's global name: it has one
    end)
end

local function RegisterSpartanUI(m)
    local SUI = _G.SUI
    local moveIt = type(SUI) == "table" and SUI.GetModule and SUI:GetModule("MoveIt", true)
    local f = moveIt and moveIt.CreateMover and m.ensure()
    if not f then
        return false
    end
    return TakeOver(f, m, function()
        return pcall(moveIt.CreateMover, moveIt, f, m.moverName, m.label, nil, "Who Won That")
    end)
end

-- Called once after login, when every UI addon has loaded. Only one addon may own a frame's position, so the
-- first full UI suite that takes it wins; the position-free editors (Edit Mode, EllesmereUI) always join.
local function RegisterMovers()
    for _, m in ipairs(MOVABLES) do
        if not (RegisterElvUI(m) or RegisterTukUI(m)) then
            RegisterSpartanUI(m)
        end
        RegisterEllesmereUI(m)
        RegisterEditMode(m)
    end
end

-- ===== shared with the other files =====
ns.RegisterMovers = RegisterMovers
