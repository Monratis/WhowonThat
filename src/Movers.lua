-- Who Won That: lets the pop-up button be moved from the layout editors players already use.
-- Each editor is skipped quietly when it is not installed.
local _, ns = ...

local EnsureSummaryButton, ShowPlacementPreview = ns.EnsureSummaryButton, ns.ShowPlacementPreview
local PlaceSummaryButton, ClearSummaryButtonPos = ns.PlaceSummaryButton, ns.ClearSummaryButtonPos
local StoreSummaryBtnPos = ns.StoreSummaryBtnPos
local SUMMARY_BTN_W, SUMMARY_BTN_H = ns.SUMMARY_BTN_W, ns.SUMMARY_BTN_H

local MOVER_LABEL = "Who Won That loot pop-up"
local DEFAULT_POINT, DEFAULT_Y = "TOP", -12 -- the same spot PlaceSummaryButton falls back to

-- While a layout editor is open the button is only a placeholder; hide it again when the editor closes.
local function HidePlacementPreview()
    local b = ns.summaryBtn
    if b and b.placing then
        b.placing = false
        b:Hide()
    end
end

-- Blizzard's Edit Mode, through the embedded LibEditMode (src/libs): the button gets the usual selection box.
local function RegisterEditMode()
    local lib = ns.LibEditMode
    local b = lib and lib.AddFrame and lib.RegisterCallback and EnsureSummaryButton()
    if not b then
        return
    end
    local added = pcall(lib.AddFrame, lib, b, function(_, _, point, x, y)
        StoreSummaryBtnPos(point, point, x, y) -- the library anchors to UIParent with the same point on both sides
    end, { point = DEFAULT_POINT, x = 0, y = DEFAULT_Y }, MOVER_LABEL)
    if added then
        lib:RegisterCallback("enter", ShowPlacementPreview)
        lib:RegisterCallback("exit", HidePlacementPreview)
    end
end

-- EllesmereUI's Unlock Mode.
local function RegisterEllesmereUI()
    local E = _G.EllesmereUI
    if not (E and E.RegisterUnlockElements and E.MakeUnlockElement) then
        return
    end
    E:RegisterUnlockElements({
        E.MakeUnlockElement({
            key = "WWT_SummaryButton",
            label = "Loot summary pop-up",
            group = "Who Won That",
            order = 900,
            noResize = true,
            getFrame = EnsureSummaryButton,
            getSize = function() return SUMMARY_BTN_W, SUMMARY_BTN_H end,
            isHidden = function() return false end,
            savePos = function(_, point, relPoint, x, y)
                StoreSummaryBtnPos(point, relPoint, x, y)
            end,
            loadPos = function()
                local p = ns.db and ns.db.summaryBtnPos
                if type(p) == "table" and type(p.point) == "string" and type(p.relPoint) == "string"
                    and type(p.x) == "number" and type(p.y) == "number" then
                    return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
                end
                return nil
            end,
            clearPos = ClearSummaryButtonPos,
            applyPos = function()
                if ns.summaryBtn then
                    PlaceSummaryButton(ns.summaryBtn)
                end
            end,
        }),
    }, "WhoWonThat")
    if E.RegisterUnlockModeListener then
        E:RegisterUnlockModeListener("WhoWonThat", function(active)
            if active then
                ShowPlacementPreview()
            else
                HidePlacementPreview()
            end
        end)
    end
end

-- ElvUI (/moveui), TukUI (/moveui) and SpartanUI (move mode) take over the button's anchor and keep the position
-- in their own profile, so our own placing and dragging step aside (b.moverOwned, see PlaceSummaryButton).
local function RegisterElvUI()
    local registry = _G.ElvUI
    local E = type(registry) == "table" and registry[1]
    local b = E and E.CreateMover and EnsureSummaryButton()
    if not b then
        return false
    end
    b:ClearAllPoints()
    b:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, 0, DEFAULT_Y) -- the default spot the mover starts from
    if pcall(E.CreateMover, E, b, "WhoWonThatSummaryButtonMover", MOVER_LABEL, nil, nil, nil, "ALL,GENERAL") then
        b.moverOwned = true
        return true
    end
    return false
end

local function RegisterTukUI()
    local registry = _G.Tukui
    local T = type(registry) == "table" and registry[1]
    local movers = type(T) == "table" and T.Movers
    local b = movers and movers.RegisterFrame and EnsureSummaryButton()
    if not b then
        return false
    end
    b:ClearAllPoints()
    b:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, 0, DEFAULT_Y)
    if pcall(movers.RegisterFrame, movers, b, MOVER_LABEL) then -- TukUI needs the frame's global name: it has one
        b.moverOwned = true
        return true
    end
    return false
end

local function RegisterSpartanUI()
    local SUI = _G.SUI
    local moveIt = type(SUI) == "table" and SUI.GetModule and SUI:GetModule("MoveIt", true)
    local b = moveIt and moveIt.CreateMover and EnsureSummaryButton()
    if not b then
        return false
    end
    b:ClearAllPoints()
    b:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, 0, DEFAULT_Y)
    if pcall(moveIt.CreateMover, moveIt, b, "WhoWonThatSummaryButton", MOVER_LABEL, nil, "Who Won That") then
        b.moverOwned = true
        return true
    end
    return false
end

-- Called once after login, when every UI addon has loaded. Only one addon may own the position, so the
-- first full UI suite that takes the button wins; the position-free editors (Edit Mode, EllesmereUI) always join.
local function RegisterMovers()
    if not (RegisterElvUI() or RegisterTukUI()) then
        RegisterSpartanUI()
    end
    RegisterEllesmereUI()
    RegisterEditMode()
end

-- ===== shared with the other files =====
ns.RegisterMovers = RegisterMovers
