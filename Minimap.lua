-- Our button on the minimap, and our line in the addon compartment.
--
-- A new player has no other way to find us while solo: the HUD waits for a
-- group, and /bbc is something they would have to be told. So the button
-- sits at the minimap's edge with our logo. A click opens the assignments
-- window, a right-click the settings, and a drag moves it around the edge.
-- The "Minimap button" setting hides it.
--
-- It's a LibDBIcon button (Shared/Minimap.lua), so EUI's minimap gathers it
-- into its button bar with the others. LibDBIcon keeps its place on the edge
-- in NS.db.minimap. Clients that have the addon compartment (the drawer
-- under the calendar) get our line there too.

local _, NS = ...
local O, T = NS.Options, NS.Theme

local M = {}
NS.Minimap = M

local icon

local function open(_, mouse)
    if not NS.Config then return end
    if mouse == "RightButton" then
        NS.Config.open("settings")
    else
        NS.Config.toggle()
    end
end

local function tooltip(owner)
    T.tip(owner, NS.BRAND, { "Who puts up which raid buff and debuff." }, {
        { "Click", "open or close the window" },
        { "Right-click", "settings" },
        { "Drag", "move this button" },
    })
end

function M.refresh()
    if icon then icon.refresh() end
end

NS.listen("login", function()
    local store = NS.db.minimap
    -- Our own button kept its angle on the edge in `angle`. LibDBIcon keeps
    -- the same angle in minimapPos, so the button stays where it was.
    if store.angle then
        store.minimapPos = store.minimapPos or tonumber(store.angle)
        store.angle = nil
    end
    icon = NS.MinimapIcon.new({
        name = "BuffCoordinator",
        label = NS.title,
        icon = NS.LOGO,
        onClick = open,
        onEnter = tooltip,
        store = store,
        shown = function() return O.get("minimap") end,
        compartment = NS.title,
    })
    M.button = icon.button
end)

NS.listen("option", function(key)
    if key == nil or key == "minimap" then M.refresh() end
end)
