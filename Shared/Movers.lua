-- Movers -- moving the parts of a HUD that sit at a fixed spot on the screen,
-- with a box over each part.
--
-- Drag a box to move what it covers, and it lands on a whole pixel when it's
-- let go. A click picks it for the arrow keys, which move it a pixel of the
-- screen at a time (Shift for ten) and repeat while held. Enter, Escape or a
-- right-click finish, and so does combat.
--
-- This file is in bayovui/shared, so BayovCore and Buff Coordinator each load
-- their own copy of it. It only draws the boxes. Each addon puts what's only
-- its own on top, through Movers.host (below): BayovCore moves its HUD
-- through EllesmereUI's unlock mode when EUI is there and shows its features
-- on the game screen (BayovCore/Movers.lua), and Buff Coordinator lays its
-- HUD out for moving (HUD.lua).
--
-- A thing to move is added with Movers.add:
--
--   key      unique among the addon's, like "consumes" or "raidbuffs.self"
--   label    what the box says, like "Consumes"
--   frame    returns its frame, building it when it isn't there yet
--   point    the frame's point that X and Y place: "CENTER" (the default) or
--            "TOP" for a card that grows down from its top edge
--   get      returns X and Y: where `point` sits from the middle of the
--            screen, in UIParent's units
--   set      writes a new X and Y into the addon's settings
--   place    puts the frame where the settings say
--   hidden   optional, true when there's nothing to move (the feature is off,
--            or its frame isn't on show)
--   moving   optional, called with true when moving starts and false when it
--            ends, so it can show made-up content to drag around
--   feature  optional, what it belongs to, for moving one feature's parts by
--            themselves (Movers.moveOnly). It defaults to the key up to its
--            first dot, so "raidbuffs.self" belongs to "raidbuffs".
--   xKey     optional, the setting key of its X, so moveOnly can pick it first
--
-- And optionally, for a part that keeps its spot its own way:
--
--   nudge    moves it by dx and dy screen pixels and keeps the spot, instead
--            of the nudge here that goes through get and set
--   save     keeps the spot a drag left it at, instead of set with where it is
--   fit      fit(box) puts the box where the part's content is, when that's
--            smaller than its frame (a row of icons in a bigger holder)
--   hint     a line of help under the box while it's the picked one

local ADDON, NS = ...
local CreateFrame = NS.Profiler and NS.Profiler.scope("move") or CreateFrame

local Movers = {}
NS.Movers = Movers

local floor = math.floor
local format = string.format

-- What an addon adds on top. Each field is optional:
--   say(fmt, ...)  prints a line to the player
--   before()       runs before any moving starts (BayovCore stops its demos)
--   start()        starts moving everything another way, and returns true
--                  when it did (BayovCore opens EUI's unlock mode)
--   stop()         ends that other way, and returns true when it did
--   started()      runs once our boxes are up for everything
--   combat()       runs as combat starts while we move, and returns true when
--                  it took care of it (BayovCore pauses EUI's mode)
--   changed()      runs when moving one feature by itself starts or stops
--   added(d)       runs for each part added
--   busy           what moveOnly says while the other way is still open
Movers.host = {}

local list = {}     -- everything to move, in the order it was added
local byKey = {}
local active = false
local boxes = {}    -- our boxes, by key
local only          -- the feature we move by itself (Movers.moveOnly), or nil
local selected      -- the part the arrow keys move

local function say(...)
    if Movers.host.say then Movers.host.say(...) end
end

-- How big one of the frame's units is in UIParent's units. A card with a
-- scale of its own has a different one.
local function ratio(f)
    return f:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Puts `point` of frame `f` at x and y from the middle of the screen, in
-- UIParent's units. A SetPoint offset is in the frame's own units, so a card
-- at size 1.5 needs offsets 1.5 times smaller to land on the same spot.
function Movers.place(f, point, x, y)
    local r = ratio(f)
    f:ClearAllPoints()
    f:SetPoint(point, UIParent, "CENTER", x / r, y / r)
end

-- Which way `point` is from a frame's centre: -1, 0 or 1 across and up, as
-- in TOPLEFT's (-1, 1).
local function side(point)
    local dx = point:find("LEFT") and -1 or point:find("RIGHT") and 1 or 0
    local dy = point:find("TOP") and 1 or point:find("BOTTOM") and -1 or 0
    return dx, dy
end

-- Where `point` of frame `f` is now, as Movers.place takes it. Rounded to a
-- whole unit unless `exact`.
local function spotOf(f, point, exact)
    local r = ratio(f)
    local ux, uy = UIParent:GetCenter()
    local x, y = f:GetCenter()
    local dx, dy = side(point or "CENTER")
    x, y = x + dx * f:GetWidth() / 2, y + dy * f:GetHeight() / 2
    x, y = x * r - ux, y * r - uy
    if exact then return x, y end
    return floor(x + 0.5), floor(y + 0.5)
end

-- The same for a widget that moves itself, like Training's rotation list,
-- which is dragged on its own and writes where it ended up.
Movers.spot = spotOf
Movers.side = side
Movers.ratio = ratio

-- How many of UIParent's units one pixel of the screen is. UIParent covers
-- the whole screen, so it's its height over the screen's height in pixels.
local function pixelUnits()
    local _, ph = 0, 0
    if GetPhysicalScreenSize then _, ph = GetPhysicalScreenSize() end
    local uh = UIParent:GetHeight()
    if not (ph and ph > 0 and uh and uh > 0) then return 1 end
    return uh / ph
end

-- A position kept to a thousandth of a unit, so the saved variables don't
-- fill with long fractions. A thousandth is far less than a pixel.
local function tidy(v) return floor(v * 1000 + 0.5) / 1000 end
Movers.tidy = tidy

local movedListeners = {}
local stopListeners = {}

-- Moves part `d` by `dx` and `dy` whole pixels of the screen, and writes its
-- new X and Y. Right and up are positive.
--
-- We count the pixels from its top left corner, rounded to the nearest
-- pixel first. So a part that sat between two pixels lands on one with the
-- first press, and its edges stay sharp after that. One pixel is rarely one
-- of UIParent's units (at a UI scale of 0.71 on a 1440p screen it's 0.53 of
-- one), so the X and Y this writes are often fractions. A settings page
-- rounds them for show.
local function nudge(d, dx, dy)
    if d.nudge then
        d.nudge(dx, dy)
    else
        local f = d.frame()
        local l, t = f:GetLeft(), f:GetTop()
        if not (l and t) then return end
        local r, px = ratio(f), pixelUnits()
        l, t = l * r, t * r
        local x, y = d.get()
        local nl = (floor(l / px + 0.5) + dx) * px
        local nt = (floor(t / px + 0.5) + dy) * px
        d.set(tidy(x + nl - l), tidy(y + nt - t))
        d.place()
    end
    for _, fn in ipairs(movedListeners) do pcall(fn, d) end
end

local function hidden(d) return d.hidden ~= nil and d.hidden() and true or false end

local function ofFeature(d, feature) return feature == nil or d.feature == feature end

local function startMoving(d, on)
    if d.moving then d.moving(on) end
end

-- =============================================================
-- The boxes
-- =============================================================
local ARROWS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
-- A held arrow key moves once, waits this long, then moves every REPEAT.
local HOLD, REPEAT = 0.35, 0.04

-- Whether a box keeps key `key` from the game.
local function ours(key)
    return ARROWS[key] ~= nil or key == "ENTER" or key == "ESCAPE"
end

-- Lets key `key` go on to the game or not, out of combat (the game blocks it
-- in combat). Every key but the arrows, Enter and Escape goes on, so we can
-- still type and use our keybinds. That counts for a key coming up too. Say
-- we start moving while walking with W held down. When W comes up the box
-- has the keyboard, and the game has to hear it or we keep walking.
local function passOn(f, key)
    if f.SetPropagateKeyboardInput and not InCombatLockdown() then
        f:SetPropagateKeyboardInput(not ours(key))
    end
end

-- Four small corner marks just outside `owner`, which sits over a part. They
-- are one pixel thin, a few pixels long and kept off the part, so every pixel
-- of the part stays in view while we line it up. A fill or a full outline
-- over it hid the very edges we were aligning.
local MARK_LEN, MARK_GAP = 6, 2   -- in screen pixels

local function corners(owner)
    local T = NS.Theme
    local marks = {}
    for i = 1, 8 do
        local t = owner:CreateTexture(nil, "OVERLAY")
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
        if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        t:SetColorTexture(1, 1, 1, 1)
        marks[i] = t
    end
    -- Each corner is a short line along the top or bottom, and one down or
    -- up the side, meeting just outside the part's corner.
    local SPOTS = { { "TOPLEFT", -1, 1 }, { "TOPRIGHT", 1, 1 },
                    { "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", 1, -1 } }
    local function fit()
        local px = T and T.pixel(owner) or 1
        local out = (MARK_GAP + 1) * px
        for i, spot in ipairs(SPOTS) do
            local h, v = marks[2 * i - 1], marks[2 * i]
            for _, m in ipairs({ h, v }) do
                m:ClearAllPoints()
                m:SetPoint(spot[1], owner, spot[1], spot[2] * out, spot[3] * out)
            end
            h:SetSize(MARK_LEN * px, px)
            v:SetSize(px, MARK_LEN * px)
        end
    end
    fit()
    owner:HookScript("OnShow", fit)
    function owner:paintMarks(color, alpha)
        for _, m in ipairs(marks) do m:SetVertexColor(color[1], color[2], color[3], alpha) end
    end
    -- Where a label goes: above the top left mark.
    owner.markOut = function() return (MARK_GAP + 1) * (T and T.pixel(owner) or 1) end
    return marks
end

-- BayovCore's Tickets picker outlines frames the same way.
Movers.corners = corners

-- A position as we show it: whole, or to two places.
local function num(v)
    if v == floor(v) then return format("%d", v) end
    return format("%.2f", v)
end

-- The picked box has accent corners, a small label with its X and Y, and its
-- hint under it. The others have faint white corners, and their name only
-- under the mouse.
local function paintBox(d)
    local b = boxes[d.key]
    if not (b and b.label) then return end
    local T = NS.Theme
    local on, over = selected == d, b.over
    b:paintMarks(on and T.ACCENT or { 1, 1, 1 }, on and 0.9 or over and 0.7 or 0.35)
    local text = d.label
    if on then
        local x, y = d.get()
        text = format("%s  |cffffffff%s, %s|r", d.label, num(x), num(y))
    end
    b.label:SetText(text)
    b.label:SetShown(on or over)
    if b.hint then b.hint:SetShown(on) end
end

-- Puts box `b` over part `d`, or over its content (d.fit).
local function fitBox(d, b)
    if d.fit then
        d.fit(b)
    else
        b:ClearAllPoints()
        b:SetAllPoints(d.frame())
    end
end

local function pick(d)
    local was = selected
    selected = d
    if was then paintBox(was) end
    if d then paintBox(d) end
    for key, b in pairs(boxes) do
        if b.EnableKeyboard then b:EnableKeyboard(d ~= nil and key == d.key and b:IsShown()) end
        if b.SetPropagateKeyboardInput and not InCombatLockdown() then b:SetPropagateKeyboardInput(true) end
    end
end

-- Ends a drag of part `d`'s box, and keeps the spot. Not in combat, where
-- moving a frame with secure buttons in it is blocked. A box that hides while
-- it's dragged (combat starts, or a right-click on another) ends its drag
-- here too, or the part would stay stuck to the mouse.
local function endDrag(d, b)
    if InCombatLockdown() then return end
    b.dragging = nil
    local f = d.frame()
    f:StopMovingOrSizing()
    -- A named frame we moved would be saved in the game's layout cache too,
    -- and we place it ourselves.
    if f.SetUserPlaced then f:SetUserPlaced(false) end
    if d.save then
        d.save()
    else
        d.set(spotOf(f, d.point, true))
        d.place()
        nudge(d, 0, 0)
    end
    fitBox(d, b)
    paintBox(d)
end

local function newBox(d)
    local T = NS.Theme
    local b = CreateFrame("Frame", nil, UIParent)
    b:SetFrameStrata("DIALOG")
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    if T then
        corners(b)
        b.label = T.text(b, 10, false, 0.8)
        b.label:SetPoint("BOTTOMLEFT", b, "TOPLEFT", -b.markOut(), b.markOut() + 3)
        b.label:SetText(d.label)
        if d.hint then
            b.hint = T.text(b, 10, false, 0.5)
            b.hint:SetPoint("TOPLEFT", b, "BOTTOMLEFT", -b.markOut(), -b.markOut() - 3)
            b.hint:SetText(d.hint)
            b.hint:Hide()
        end
    end
    b:SetScript("OnEnter", function()
        b.over = true
        paintBox(d)
    end)
    b:SetScript("OnLeave", function()
        b.over = false
        paintBox(d)
    end)
    if T and T.dragCursor then T.dragCursor(b, function() return not InCombatLockdown() end) end
    b:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        pick(d)
        local f = d.frame()
        f:SetMovable(true)
        b.dragging = true
        f:StartMoving()
    end)
    b:SetScript("OnDragStop", function() endDrag(d, b) end)
    b:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then pick(d) end
    end)
    b:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Movers.stop() end
    end)

    -- The arrow keys, while this box is the picked one.
    local held
    local function step(dir)
        local n = IsShiftKeyDown and IsShiftKeyDown() and 10 or 1
        nudge(d, dir[1] * n, dir[2] * n)
        if d.fit then fitBox(d, b) end
        paintBox(d)
    end
    b:SetScript("OnKeyDown", function(self, key)
        local dir = ARROWS[key]
        passOn(self, key)
        if not ours(key) then return end
        if not dir then return Movers.stop() end
        step(dir)
        held = { key = key, dir = dir, at = GetTime() + HOLD }
        self:SetScript("OnUpdate", function()
            if not held or GetTime() < held.at then return end
            held.at = GetTime() + REPEAT
            step(held.dir)
        end)
    end)
    b:SetScript("OnKeyUp", function(self, key)
        passOn(self, key)
        if held and held.key == key then
            held = nil
            self:SetScript("OnUpdate", nil)
        end
    end)
    b:SetScript("OnHide", function(self)
        held = nil
        self:SetScript("OnUpdate", nil)
        if self.dragging then endDrag(d, self) end
    end)
    b:Hide()
    return b
end

-- The strata of the boxes. Moving one feature from a config window, its
-- boxes go over the window, so a part under it can still be dragged.
local function strata() return only and "FULLSCREEN" or "DIALOG" end

-- Shows a box over every part of `feature` (every part when it's nil) that
-- has something to move, or hides them all. It returns the first part with a
-- box.
local function showBoxes(on, feature)
    local first
    for _, d in ipairs(list) do
        local b = boxes[d.key]
        if on and ofFeature(d, feature) then
            b = b or newBox(d)
            boxes[d.key] = b
            if hidden(d) then
                b:Hide()
            else
                b:SetFrameStrata(strata())
                fitBox(d, b)
                b:Show()
                paintBox(d)
                first = first or d
            end
        elseif b then
            b:Hide()
        end
    end
    return first
end

-- Fits each box to what it moves now, after the parts were laid out again
-- while we move them (a setting changed the icons, say). A box whose part
-- has nothing to show hides, and when that was the picked one, the next
-- one with a box is picked.
function Movers.fit()
    if not active then return end
    for _, d in ipairs(list) do
        local b = boxes[d.key]
        if b and ofFeature(d, only) then
            local show = not hidden(d)
            if show and not b.dragging then fitBox(d, b) end
            if show ~= b:IsShown() then
                if show then b:SetFrameStrata(strata()) end
                b:SetShown(show)
            end
            paintBox(d)
        end
    end
    if selected and not (boxes[selected.key] and boxes[selected.key]:IsShown()) then
        for _, d in ipairs(list) do
            local b = boxes[d.key]
            if b and b:IsShown() then return pick(d) end
        end
    end
end

-- =============================================================
-- Moving
-- =============================================================
function Movers.add(d)
    assert(d.key and not byKey[d.key], "Movers.add: a new key is required")
    d.point = d.point or "CENTER"
    d.feature = d.feature or d.key:match("^[^.]+")
    d.order = #list + 1
    list[#list + 1] = d
    byKey[d.key] = d
    if Movers.host.added then Movers.host.added(d) end
    return d
end

-- `fn(d)` hears when one of our boxes moved part `d`, by a drag or a key, so
-- a settings page can show its new X and Y.
function Movers.onMoved(fn) movedListeners[#movedListeners + 1] = fn end

-- `fn(combat)` hears when our boxes went, by any way out (a right-click,
-- Enter, Escape, combat), with `combat` true when combat ended it.
function Movers.onStop(fn) stopListeners[#stopListeners + 1] = fn end

-- Whether we're moving right now, with our boxes or another way.
function Movers.active() return active end

-- Says we're moving, or not, another way (EUI's unlock mode in BayovCore).
function Movers.setActive(on) active = on and true or false end

-- The feature we're moving by itself, or nil.
function Movers.movingOnly() return only end

-- Whether `feature` has anything to move.
function Movers.has(feature)
    for _, d in ipairs(list) do
        if d.feature == feature then return true end
    end
    return false
end

-- Everything to move, in the order it was added, and the box of part `key`.
function Movers.list() return list end
function Movers.box(key) return boxes[key] end

-- Starts moving everything. With `pickFirst` the first part with a box is
-- picked, so the arrow keys move it at once. It returns true when moving
-- started.
function Movers.start(pickFirst)
    if only then Movers.stop() end
    if active then return false end
    if InCombatLockdown() then
        say("not in combat")
        return false
    end
    local host = Movers.host
    if host.before then host.before() end
    if host.start and host.start() then return true end
    active = true
    for _, d in ipairs(list) do startMoving(d, true) end
    local first = showBoxes(true)
    if pickFirst and first then pick(first) end
    if host.started then host.started() end
    return true
end

-- Ends moving. `combat` says combat is starting, which ends it too.
function Movers.stop(combat)
    if not active then return end
    local host = Movers.host
    if not only and host.stop and host.stop() then return end
    local feature = only
    active, only = false, nil
    pick(nil)
    showBoxes(false)
    for _, d in ipairs(list) do
        if ofFeature(d, feature) then
            startMoving(d, false)
            d.place()
        end
    end
    if feature and host.changed then host.changed() end
    for _, fn in ipairs(stopListeners) do pcall(fn, combat == true) end
end

-- Moves only `feature`'s parts, always with our boxes. `xKey` picks the part
-- whose X is that setting for the arrow keys, rather than the first one.
function Movers.moveOnly(feature, xKey)
    if only == feature then return end
    if active then Movers.stop() end
    if active then return say(Movers.host.busy or "finish moving first") end
    if InCombatLockdown() then return say("not in combat") end
    if not Movers.has(feature) then return end
    local host = Movers.host
    if host.before then host.before() end
    active, only = true, feature
    for _, d in ipairs(list) do
        if ofFeature(d, feature) then startMoving(d, true) end
    end
    local first = showBoxes(true, feature)
    for _, d in ipairs(list) do
        if xKey and d.feature == feature and d.xKey == xKey and boxes[d.key]
           and boxes[d.key]:IsShown() then
            first = d
        end
    end
    if not first then
        Movers.stop()
        return say("there's nothing of it on the screen to move (is it off?)")
    end
    pick(first)
    if host.changed then host.changed() end
end

function Movers.toggle()
    if active then Movers.stop() else Movers.start() end
end

-- Combat ends our boxes, while the game still lets us put each part back.
-- The addon's own combat() goes first, and can take care of it instead.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function()
    if not active then return end
    if Movers.host.combat and Movers.host.combat() then return end
    Movers.stop(true)
end)

Movers._test = { list = list, boxes = boxes, spotOf = spotOf, nudge = nudge, pixelUnits = pixelUnits }
