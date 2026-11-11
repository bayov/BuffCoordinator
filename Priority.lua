-- The blessing orders: the blessings each spec or player wants, most
-- wanted first. Buffs by Spec (BuffsBySpec.lua) shows them as its top
-- section, a column of icons under each spec's or player's head
-- (Pr.column). Auto gives each paladin's blessing in these orders: one
-- paladin gives the 1st, two give the first two, and so on.
--
-- Each column shows every blessing, top down: the ones it wants in order,
-- then the ones it doesn't, faded. A click turns one on or off (Pr.flip),
-- and a drag moves it to another place (Pr.move). The orders live in the
-- blessings job's `order` (Duties.lua), so they sync and go into a draft
-- like every edit.
--
-- The You page shows our own order the same way, as a row left to right
-- (Pr.ownRow). Anyone may change their own, so it saves through
-- Du.setOwnBlessOrder, which goes to the group at once and never into a
-- draft.

local _, NS = ...
local D, R, Du, T, Tr = NS.Data, NS.Roster, NS.Duties, NS.Theme, NS.Tracking

local format = string.format
local max = math.max

local Pr = {}
NS.Priority = Pr

local ICON, GAP = 20, 4
-- A blessing a place, an icon tall.
local COL = ICON + GAP
local PLACES = 4
local PLACE = { "1st", "2nd", "3rd", "4th" }
Pr.PLACES, Pr.COL = PLACES, COL

-- The frame the last columns were drawn in, and the picture of a dragged
-- icon that follows the mouse.
local panel, ghostFrame

local function canChange() return NS.Config.canChange() end

-- The order `key` wants now, and whether it's its own.
local function orderOf(key)
    local own = Du.blessOrderOf(key)
    return own or Du.baseOrder(key), own ~= nil
end

-- Every blessing for `key`, as { id, on }: the ones it wants in order, then
-- the rest, off.
function Pr.shownOrder(key)
    local t, seen = {}, {}
    for _, id in ipairs((orderOf(key))) do
        if not seen[id] then
            seen[id] = true
            t[#t + 1] = { id = id, on = true }
        end
    end
    for _, id in ipairs(D.JOB.blessings.options) do
        if not seen[id] then t[#t + 1] = { id = id, on = false } end
    end
    return t
end

local function wanted(list)
    local t = {}
    for _, x in ipairs(list) do
        if x.on then t[#t + 1] = x.id end
    end
    return t
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- Keeps `list` as `key`'s order. Nothing happens when it's the order it has
-- now, so a drag that changes nothing leaves no override or draft change.
-- The order auto would give puts it back to auto. With `mine`, it's our own
-- order from the You page.
local function save(key, list, mine)
    local now, own = orderOf(key)
    if same(list, now) then return end
    local set = Du.setBlessOrder
    if mine then set = function(_, l) Du.setOwnBlessOrder(l) end end
    if same(list, Du.baseOrder(key)) then
        if own then set(key, nil) end
        return
    end
    set(key, list)
end

-- Turns blessing `id` on or off for `key`. One turned on goes last.
function Pr.flip(key, id, mine)
    local list = Pr.shownOrder(key)
    local t = wanted(list)
    local at
    for i, x in ipairs(t) do
        if x == id then at = i end
    end
    if at then table.remove(t, at) else t[#t + 1] = id end
    save(key, t, mine)
end

-- Moves blessing `id` to place `pos` of what the row shows. One that's off
-- turns on when it lands among the ones that are on, and one that's on and
-- lands among the ones that are off goes last of those on.
function Pr.move(key, id, pos, mine)
    local list = Pr.shownOrder(key)
    local from, on
    for i, x in ipairs(list) do
        if x.id == id then from, on = i, x.on end
    end
    if not from or from == pos then return end
    local count = #wanted(list)
    table.remove(list, from)
    if not on and pos <= count then on = true end
    if on then
        count = #wanted(list)
        pos = math.min(pos, count + 1)
    end
    table.insert(list, math.max(1, math.min(pos, #list + 1)), { id = id, on = on })
    save(key, wanted(list), mine)
end

-- =============================================================
-- Columns
-- =============================================================
-- The icon being dragged, and the picture of it that follows the mouse.
local drag

local function ghost()
    if ghostFrame then return ghostFrame end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("TOOLTIP")
    g:SetSize(ICON, ICON)
    g.icon = T.icon(g, nil, ICON)
    g.icon:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
    g:SetAlpha(0.8)
    g:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local s = self:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    end)
    g:Hide()
    ghostFrame = g
    return g
end

-- How far along its column (down) or row (across) an icon at place `i`
-- sits.
local function slot(c, i)
    return (i - 1) * (c.size + GAP)
end

local function setPos(c, b, v)
    T.unglide(b)
    b:ClearAllPoints()
    if c.across then
        b:SetPoint("LEFT", c, "LEFT", v, 0)
    else
        b:SetPoint("TOP", c, "TOP", 0, -v)
    end
end

-- While an icon is dragged, the others make way so there's a gap where it
-- would land (T.makeWay), and the ghost carries it.
local function makeWay(c, from)
    local shown = {}
    for _, b in ipairs(c.icons) do
        if b:IsShown() then shown[#shown + 1] = b end
    end
    local step = c.size + GAP
    return T.makeWay({ frames = shown, from = from, gap = GAP, axis = c.across and "x" or "y", inside = function()
        local top, bottom, left, right = c:GetTop(), c:GetBottom(), c:GetLeft(), c:GetRight()
        if not (top and bottom and left and right) then return false end
        local x, y = GetCursorPosition()
        local s = c:GetEffectiveScale()
        x, y = x / s, y / s
        return x >= left - step and x <= right + step and y <= top + step and y >= bottom - step
    end })
end

-- A column of blessing icons, or with `across` a row of them, `size` big.
-- With `mine` it's our own order, which we may always change.
local function newColumn(parent, size, across, mine)
    local c = CreateFrame("Frame", nil, parent)
    c:EnableMouse(false)
    c.size, c.across, c.mine = size, across, mine
    -- A row is as long as the blessings there are, so what's beside it sits
    -- right after the last.
    local n = across and math.min(PLACES, #D.JOB.blessings.options) or PLACES
    local long = n * (size + GAP) - GAP
    if across then c:SetSize(long, size) else c:SetSize(size, long) end
    c.icons = {}
    local function editable() return c.mine or canChange() end
    for i = 1, PLACES do
        local b = CreateFrame("Button", nil, c)
        b:SetSize(size, size)
        b.icon = T.icon(b, nil, size)
        b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.pos = i
        setPos(c, b, slot(c, i))
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnEnter", function(self) if c.tip then c.tip(self) end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local function movable(self) return self.id ~= nil and editable() end
        T.hoverEdge(b, movable)
        T.dragCursor(b, movable)
        b:SetScript("OnClick", function(self)
            if c.key and self.id and editable() then Pr.flip(c.key, self.id, c.mine) end
        end)
        b:SetScript("OnDragStart", function(self)
            if not (c.key and self.id and editable()) then return end
            drag = { col = c, id = self.id, from = self.pos, way = makeWay(c, self.pos) }
            local g = ghost()
            g:SetSize(c.size, c.size)
            g.icon:SetSize(c.size, c.size)
            g.icon:SetTexture(Tr.icon(D.BY_ID[self.id]))
            g.icon:SetDesaturated(not self.on)
            g:Show()
            -- The icon leaves its place, and the ghost carries it.
            self:SetAlpha(0)
            c:SetScript("OnUpdate", function(_, elapsed) drag.way:update(elapsed) end)
            GameTooltip:Hide()
        end)
        b:SetScript("OnDragStop", function(self)
            if ghostFrame then ghostFrame:Hide() end
            c:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
            local d = drag
            drag = nil
            -- The place it lands, among the icons once it's out of its own.
            local at = d and d.way:stop()
            if at then
                if at > d.from then at = at - 1 end
                Pr.move(c.key, d.id, math.min(at, PLACES), c.mine)
            end
            -- Everything back in its place, which is the new order's when
            -- it moved.
            NS.Config.refresh()
        end)
        c.icons[i] = b
    end
    return c
end

-- Whether order `key` ("WARRIOR:1" or "name:Grom") is set by hand, and
-- whether that's the class's order ("WARRIOR"), which a spec without one
-- of its own takes. The class's is an override of all three specs at once.
function Pr.own(key)
    local _, own = orderOf(key)
    local class = not own and key:match("^(%u+):%d$")
    return own, class and Du.blessOrderOf(class) ~= nil and class or nil
end

-- Order `key` back to auto: its own, else its class's.
function Pr.clear(key)
    local own, class = Pr.own(key)
    if own then Du.setBlessOrder(key, nil) elseif class then Du.setBlessOrder(class, nil) end
end

-- Whether the draft changed order `key`, or its class's.
function Pr.changed(key)
    local _, class = Pr.own(key)
    return NS.Config.changedWhere(function(it)
        return it.kind == "order" and (it.a == key or class ~= nil and it.a == class)
    end)
end

-- Shows order `key` in column or row `c`. `name` is what its tooltips call
-- it.
local function fill(c, key, name)
    c:Show()
    c.key = key
    c.changed = not c.mine and Pr.changed(key)
    local list = Pr.shownOrder(key)
    for j, b in ipairs(c.icons) do
        local x = list[j]
        b.id, b.on = x and x.id, x and x.on
        b.icon:SetTexture(x and Tr.icon(D.BY_ID[x.id]) or nil)
        b.icon:SetDesaturated(x and not x.on or false)
        b.icon:SetAlpha(x and not x.on and 0.35 or 1)
        b:SetShown(x ~= nil)
        b:SetAlpha(1)
        setPos(c, b, slot(c, j))
    end
    c.tip = function(owner)
        if not owner.id then return end
        local lines = { owner.on and format("%s for %s.", PLACE[owner.pos], name) or format("Off for %s.", name) }
        local own, class = Pr.own(key)
        local player = key:match("^name:(.+)$")
        if own and not player then lines[#lines + 1] = T.line("Override.", "hand") end
        if own and player and not c.mine then
            if Du.selfOrder(player) then
                lines[#lines + 1] = T.line(format("%s set it themselves.", player), "up")
            end
        elseif own and player and not Du.selfOrder(player) then
            lines[#lines + 1] = T.line("Set by the Assignments Leader.", "hand")
        end
        if class then lines[#lines + 1] = T.line(format("Override for all %s.", NS.classWord(class)), "hand") end
        if c.changed then lines[#lines + 1] = T.line("Changed in the draft.", "changed") end
        -- Our own order is ours to change even when nothing else is.
        local list = { { "Click", "turn it on or off" }, { "Drag", "change its place" } }
        local hints = c.mine and list or NS.Config.hints(lines, list)
        T.spellTip(owner, D.BY_ID[owner.id], NS.buffText(D.BY_ID[owner.id]), lines, hints)
    end
    return c
end

-- Column `i` of `parent`, for order `key`, a spec's ("WARRIOR:1") or a
-- player's ("name:Grom"). `name` is what its tooltips call it. Returns the
-- column, for the caller to place.
function Pr.column(parent, i, key, name)
    panel = parent
    parent.blessCols = parent.blessCols or {}
    local c = parent.blessCols[i]
    if not c then
        c = newColumn(parent, ICON)
        parent.blessCols[i] = c
    end
    return fill(c, key, name)
end

-- Our own blessing order on the You page: a row of `size` icons, left to
-- right, in `parent`. Returns the row, for the caller to place.
function Pr.ownRow(parent, size)
    local me = R.me()
    local c = parent.ownBlessRow
    if not c then
        c = newColumn(parent, size, true, true)
        parent.ownBlessRow = c
    end
    if not me then
        c:Hide()
        return c
    end
    return fill(c, "name:" .. me.name, "you")
end

-- Hides `parent`'s columns from `i` on.
function Pr.hideFrom(parent, i)
    for j = i, #(parent.blessCols or {}) do parent.blessCols[j]:Hide() end
end

-- Whether order `key` is set for a player here or remembered.
local function playerOrders()
    local t = {}
    for _, m in ipairs(R.list()) do
        if Du.blessOrderOf("name:" .. m.name) then t[m.name] = true end
    end
    return t
end
Pr.playerOrders = playerOrders

-- Whether a spec, the class or a player of `class` has an order set by
-- hand.
function Pr.marked(class)
    if Du.blessOrderOf(class) then return true end
    for tree = 1, 3 do
        if Du.blessOrderOf(class .. ":" .. tree) then return true end
    end
    for name in pairs(playerOrders()) do
        local m = R.byName(name)
        if m and m.class == class then return true end
    end
    return false
end

-- The columns that show, for the tests.
function Pr.columns()
    local t = {}
    for _, c in ipairs(panel and panel.blessCols or {}) do
        if c:IsVisible() then t[#t + 1] = c end
    end
    return t
end
