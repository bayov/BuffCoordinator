-- Minimap -- our button on the minimap's edge, and our line in the addon
-- compartment.
--
-- The button is LibDBIcon's (Shared/Libs), not a frame of our own. EUI's
-- minimap gathers LibDBIcon buttons into its own button bar, and other
-- minimap skins reshape them, so ours goes along with the rest. LibDBIcon
-- keeps the button's place on the edge (minimapPos, in degrees) and whether
-- it's hidden (hide) in the saved table we hand it.
--
-- NS.MinimapIcon.new(spec) makes it, once the saved variables are loaded:
--
--   name         the name LibDBIcon knows it by, like "BuffCoordinator"
--   label, icon  its name and texture
--   onClick      function(owner, mouse), with mouse "LeftButton" or "RightButton"
--   tooltip      function(tip), fills LibDBIcon's tooltip. Or:
--   onEnter      function(owner), shows a tooltip of our own on `owner`
--   store        the saved table LibDBIcon reads and writes
--   shown        function() -> whether the button shows (a setting)
--   compartment  the line's text in the addon compartment, or nil for no line
--
-- It returns a table with refresh(), to call when `shown` changed, and the
-- LibDBIcon button as .button. A client without the libraries (the test
-- harnesses) gets no button, and nothing else changes.
--
-- This file is in bayovui/shared, so BayovCore and Buff Coordinator each load
-- their own copy of it.

local _, NS = ...

local MI = {}
NS.MinimapIcon = MI

local function libs()
    local stub = _G.LibStub
    if not stub then return nil, nil end
    return stub("LibDataBroker-1.1", true), stub("LibDBIcon-1.0", true)
end

-- The addon compartment calls our function with the mouse button somewhere
-- among its arguments: as a string on older clients, inside a table on
-- newer ones.
local function rightClicked(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v == "RightButton" or (type(v) == "table" and v.buttonName == "RightButton") then
            return true
        end
    end
    return false
end

local function hideTip()
    if GameTooltip then GameTooltip:Hide() end
end

-- Our line in the addon compartment (the drawer under the calendar), on the
-- clients that have one.
local function compartment(spec)
    local drawer = _G.AddonCompartmentFrame
    if not (drawer and drawer.RegisterAddon) then return end
    pcall(drawer.RegisterAddon, drawer, {
        text = spec.compartment,
        icon = spec.icon,
        notCheckable = true,
        func = function(...)
            spec.onClick(nil, rightClicked(...) and "RightButton" or "LeftButton")
        end,
        funcOnEnter = function(owner) if spec.onEnter then spec.onEnter(owner) end end,
        funcOnLeave = hideTip,
    })
end

function MI.new(spec)
    local icon = { spec = spec }
    local function shown() return spec.shown == nil or spec.shown() end

    function icon.refresh()
        local _, lib = libs()
        if not (lib and lib:IsRegistered(spec.name)) then return end
        spec.store.hide = not shown()
        lib:Refresh(spec.name, spec.store)
    end

    local ldb, lib = libs()
    if ldb and lib and not lib:IsRegistered(spec.name) then
        local object = ldb:NewDataObject(spec.name, {
            type = "launcher",
            label = spec.label,
            icon = spec.icon,
            OnClick = function(owner, mouse) spec.onClick(owner, mouse) end,
            OnTooltipShow = spec.tooltip,
            OnEnter = not spec.tooltip and spec.onEnter or nil,
            OnLeave = not spec.tooltip and spec.onEnter and hideTip or nil,
        })
        spec.store.hide = not shown()
        lib:Register(spec.name, object, spec.store)
        icon.button = lib.GetMinimapButton and lib:GetMinimapButton(spec.name) or nil
    end
    if spec.compartment then compartment(spec) end
    return icon
end
