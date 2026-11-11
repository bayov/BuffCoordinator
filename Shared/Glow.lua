-- Glow -- the moving Pixel glow round an icon, in ForeverAuras' look.
--
-- Each line is a white square turned 45 degrees that travels around the
-- icon's edge, seen only through four thin strips along the edges. So a line
-- has slanted, soft ends, and it adds light to the icon under it (additive
-- blending) instead of covering it. That's how ForeverAuras draws the glow on
-- an Aura (Modern) icon (SecretAuraGlow.lua), and we liked it better than
-- LibCustomGlow's solid lines.
--
-- It also gets the thickness right. LibCustomGlow rounds where each line
-- starts to a whole UI unit, and on the beta one unit is 1.8 screen pixels. At
-- 2 pixels thick, its right line landed almost a pixel over the icon's border.
-- We round nothing to units. We round the thickness and inset to whole screen
-- pixels, so 2 pixels is 2 pixels on every side.
--
-- Glow.start takes the same settings as LibCustomGlow's PixelGlow_Start:
-- colour, lines, frequency, length, thickness and offsets.
--
-- This file is in bayovui/shared, so BayovCore and Buff Coordinator each load
-- their own copy of it. BayovCore's GlowHook.lua puts it on our auras too.

local ADDON, NS = ...
local CreateFrame = NS.Profiler and NS.Profiler.scope("glow") or CreateFrame

local WHITE = "Interface\\Buttons\\WHITE8X8"
local EDGES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
local ROOT2 = math.sqrt(2)
-- Where a frame keeps its glow, one per key. Each addon has its own, so the
-- two never take each other's glow down.
local FIELD = "_" .. ADDON .. "Glow"

local Glow = {}
NS.Glow = Glow

-- One screen pixel, in the frame's UI units.
local function pixel(frame)
    if not (PixelUtil and PixelUtil.GetPixelToUIUnitFactor) then return nil end
    return PixelUtil.GetPixelToUIUnitFactor() / frame:GetEffectiveScale()
end

-- A length in UI units, rounded to whole screen pixels. low is the fewest
-- pixels it may round to.
local function snap(frame, units, low)
    local p = pixel(frame)
    if not p then return units end
    local n = math.floor(math.abs(units) / p + 0.5)
    if n < low then n = low end
    return (units < 0 and -n or n) * p
end

local function rgba(color)
    if type(color) == "table" and color.GetRGBA then return color:GetRGBA() end
    if type(color) == "table" then return color[1], color[2], color[3], color[4] end
    return 0.95, 0.95, 0.32, 1
end

-- Where a point distance along the edge is, from the bottom left corner. It
-- goes up the left edge, then right along the top, then down and back.
-- Positive frequency runs that way, which is clockwise, like ForeverAuras.
local function along(distance, w, h)
    distance = distance % (2 * (w + h))
    if distance < h then return 0, distance end
    distance = distance - h
    if distance < w then return distance, h end
    distance = distance - w
    if distance < h then return w, h - distance end
    return w - (distance - h), 0
end

-- The stops of a line's trip round a gw x gh rectangle, starting `phase`
-- (0 to 1) of the way round: one move per straight stretch between corners,
-- each timed by its length, so the speed stays even. Answers where it starts
-- and the moves, as { delay, duration, dx, dy }.
local function trip(gw, gh, duration, phase, reverse)
    local perimeter = 2 * (gw + gh)
    local start = phase * perimeter
    local x0, y0 = along(start, gw, gh)
    local stops, seen = { perimeter }, { [perimeter] = true }
    for _, corner in ipairs({ 0, gh, gw + gh, gw + 2 * gh }) do
        local d = (reverse and (start - corner) or (corner - start)) % perimeter
        if d > 1e-6 and d < perimeter - 1e-6 and not seen[d] then
            stops[#stops + 1] = d
            seen[d] = true
        end
    end
    table.sort(stops)
    local moves, previous, px, py = {}, 0, x0, y0
    for i, d in ipairs(stops) do
        local x, y = along(start + (reverse and -d or d), gw, gh)
        if i == #stops then x, y = x0, y0 end
        moves[#moves + 1] = { delay = duration * previous / perimeter,
                              duration = duration * (d - previous) / perimeter,
                              dx = x - px, dy = y - py }
        previous, px, py = d, x, y
    end
    return x0, y0, moves
end

local function square(edge)
    local texture = edge:CreateTexture(nil, "OVERLAY")
    texture:SetTexture(WHITE)
    texture:SetBlendMode("ADD")
    texture:SetRotation(math.pi / 4)
    -- Let a line move by less than a pixel, so it glides instead of stepping.
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    return texture
end

-- A glow's frames: the holder round the glowed frame, and the four strips
-- along its edges that the lines show through. Each strip has one looping
-- animation group, which moves the strip's squares round the holder.
-- The test harnesses' stand-in frames have no animation groups. There the
-- glow gets this one, which does nothing, so it draws standing still.
local function nop() end
local STILL_MOVE = { SetTarget = nop, SetOrder = nop, SetStartDelay = nop, SetDuration = nop,
                     SetOffset = nop }
local STILL = { SetLooping = nop, Play = nop, Stop = nop, IsPlaying = nop,
                CreateAnimation = function() return STILL_MOVE end }

local function build(frame)
    local holder = CreateFrame("Frame", nil, frame)
    local g = { holder = holder, edges = {} }
    holder.glow = g
    for index in ipairs(EDGES) do
        local edge = CreateFrame("Frame", nil, holder)
        edge:SetClipsChildren(true)
        edge.squares, edge.moves = {}, {}
        edge.group = edge:CreateAnimationGroup() or STILL
        edge.group:SetLooping("REPEAT")
        g.edges[index] = edge
    end
    return g
end

-- Puts the strips at g.thickness, and gives every line a square in each
-- strip in the colour r, gr, b, a. The left and right strips stop at the top
-- and bottom ones, so a line turning a corner isn't drawn twice there, which
-- additive blending would show as a brighter corner.
local function dress(g, r, gr, b, a)
    local t = g.thickness
    for index, edge in ipairs(g.edges) do
        local point = EDGES[index]
        edge:ClearAllPoints()
        if point == "TOP" or point == "BOTTOM" then
            edge:SetPoint(point .. "LEFT", g.holder)
            edge:SetPoint(point .. "RIGHT", g.holder)
            edge:SetHeight(t)
        else
            edge:SetPoint("TOP" .. point, g.holder, "TOP" .. point, 0, -t)
            edge:SetPoint("BOTTOM" .. point, g.holder, "BOTTOM" .. point, 0, t)
            edge:SetWidth(t)
        end
        for line = 1, math.max(g.lines, #edge.squares) do
            local texture = edge.squares[line]
            if line <= g.lines then
                if not texture then
                    texture = square(edge)
                    edge.squares[line] = texture
                end
                texture:SetVertexColor(r, gr, b, a)
                texture:Show()
            elseif texture then
                texture:Hide()
            end
        end
    end
end

-- Sets every line's trip round a gw x gh holder, as Translation animations
-- the game runs on its own. It stops the groups, and play starts them again.
--
-- The animations are made once and set again on each layout, since the game
-- can't take one away. A line's trip has at most five moves. The moves a
-- line doesn't need, and every move of a line we no longer show, are set to
-- do nothing, so they don't make the loop longer.
local function layout(g, gw, gh)
    g.w, g.h = gw, gh
    local length = math.min(g.length or ((gw + gh) * (2 / g.lines - 0.1)), gw, gh)
    local side = math.max(g.thickness, length) / ROOT2
    for _, edge in ipairs(g.edges) do edge.group:Stop() end
    for line = 1, #g.edges[1].squares do
        local x0, y0, moves
        if line <= g.lines then
            x0, y0, moves = trip(gw, gh, g.duration, (line - 1) / g.lines, g.reverse)
        end
        for _, edge in ipairs(g.edges) do
            local texture = edge.squares[line]
            local pool = edge.moves[line] or {}
            edge.moves[line] = pool
            if moves then
                texture:SetSize(side, side)
                texture:ClearAllPoints()
                texture:SetPoint("CENTER", g.holder, "BOTTOMLEFT", x0, y0)
            end
            for i = 1, math.max(moves and #moves or 0, #pool) do
                local move = pool[i]
                if not move then
                    move = edge.group:CreateAnimation("Translation")
                    move:SetTarget(texture)
                    move:SetOrder(1)
                    pool[i] = move
                end
                local m = moves and moves[i]
                if m then
                    move:SetStartDelay(m.delay)
                    move:SetDuration(m.duration)
                    move:SetOffset(m.dx, m.dy)
                else
                    move:SetStartDelay(0)
                    move:SetDuration(0)
                    move:SetOffset(0, 0)
                end
            end
        end
    end
end

-- Starts the four groups together, so a line's squares in each strip stay in
-- step. A group that already plays is left alone, so the glow doesn't jump
-- back to its start.
local function play(g)
    local edges = g.edges
    if edges[1].group:IsPlaying() and edges[2].group:IsPlaying()
        and edges[3].group:IsPlaying() and edges[4].group:IsPlaying() then
        return
    end
    for _, edge in ipairs(edges) do edge.group:Stop() end
    for _, edge in ipairs(edges) do edge.group:Play() end
end

-- Lays the glow out again when its holder's size changes, and plays it. It
-- runs from Glow.start, and from the holder's OnSizeChanged and OnShow, so it
-- runs only when something changed, never every frame. OnShow is there in
-- case the game stops a group while its frame is hidden.
local function fit(holder)
    local g = holder.glow
    if not g.running then return end
    local w, h = holder:GetSize()
    if issecretvalue and issecretvalue(w) then return end
    if not (w and h and w > 0 and h > 0) then return end
    if w ~= g.w or h ~= g.h then layout(g, w, h) end
    play(g)
end

-- The glow on any frame of ours. It runs on the game's animations, so a
-- running glow costs us nothing a frame. The Lua glow it replaced moved its
-- lines in an OnUpdate, and was our most expensive script (about 10 calls a
-- frame, 13 s in a 28 minute session).
--
-- Calling it again with the same settings keeps the glow running where it
-- is, and only sets its colour.
function Glow.start(frame, color, lines, frequency, length, thickness,
                    xOffset, yOffset, key)
    local name = FIELD .. (key or "")
    local g = frame[name]
    if not g then
        g = build(frame)
        frame[name] = g
        g.holder:SetScript("OnSizeChanged", fit)
        g.holder:SetScript("OnShow", fit)
    end
    local holder = g.holder

    -- xOffset and yOffset are how far the glow reaches past the frame's
    -- edges, and a negative one moves it in, as in the library.
    xOffset = snap(holder, xOffset or 0, 0)
    yOffset = snap(holder, yOffset or 0, 0)
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", frame, "TOPLEFT", -xOffset, yOffset)
    holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", xOffset, -yOffset)
    holder:SetFrameLevel(frame:GetFrameLevel())

    lines = (lines and lines > 0) and math.floor(lines) or 8
    thickness = snap(holder, thickness or 1, 1)
    local duration = (frequency and frequency ~= 0) and math.max(0.1, math.abs(1 / frequency)) or 4
    local reverse = frequency and frequency < 0 or false
    if lines ~= g.lines or thickness ~= g.thickness or length ~= g.length
        or duration ~= g.duration or reverse ~= g.reverse then
        g.lines, g.thickness, g.length, g.duration, g.reverse = lines, thickness, length, duration, reverse
        g.w, g.h = nil, nil
    end
    dress(g, rgba(color))

    g.running = true
    holder:Show()
    fit(holder)
end

function Glow.stop(frame, key)
    local g = frame and frame[FIELD .. (key or "")]
    if not g then return end
    g.running = false
    for _, edge in ipairs(g.edges) do edge.group:Stop() end
    g.holder:Hide()
end

-- The same glow on one of the game's aura buttons, which plays it while its
-- aura shows.
--
-- The game marks its aura buttons secret, and no frame under one may run a
-- script, so Glow.start's OnSizeChanged and OnShow never run there. This
-- builds the glow once, at a safe time, from the same strips and animations.
-- The button plays them while its aura is shown (AddAuraShownAnimation), as
-- ForeverAuras does it (SecretAuraGlow.lua). The glow can't be changed
-- afterwards, so it takes the area's size `w` x `h` up front. `parent` is the
-- frame it sits in, usually the button. Like Glow.start, it sits at the
-- parent's own level, under the icon's swipe, which tints it into the icon.
--
-- `anchor` is the frame it goes round, the parent when it's nil. It differs
-- when the parent is a clip inside the button that only sometimes lets the
-- glow show (HUDMaintain's glow near the end). The groups still go to the
-- button, which plays them.
--
-- `button` may be nil, for a glow on a plain frame of ours. Then it just
-- plays, and Glow.play starts and stops it. That's how we glow a frame that
-- a clip shows only when the game says so, like a missing shield's icon:
-- Lua can't know when the clip is open, and an animation costs no Lua while
-- it plays, where Glow.start's mover runs every frame.
function Glow.native(button, parent, w, h, color, lines, frequency, length, thickness,
                     xOffset, yOffset, anchor)
    local g = build(parent)
    local holder = g.holder
    xOffset = snap(holder, xOffset or 0, 0)
    yOffset = snap(holder, yOffset or 0, 0)
    local gw, gh = math.max(2, w + 2 * xOffset), math.max(2, h + 2 * yOffset)
    holder:SetPoint("CENTER", anchor or parent, "CENTER")
    holder:SetSize(gw, gh)
    holder:SetFrameLevel(parent:GetFrameLevel())
    g.thickness = snap(holder, thickness or 1, 1)
    g.lines = (lines and lines > 0) and math.floor(lines) or 8
    g.duration = (frequency and frequency ~= 0) and math.max(0.1, math.abs(1 / frequency)) or 4
    g.reverse = frequency and frequency < 0
    g.length = length
    dress(g, rgba(color))
    layout(g, gw, gh)
    local groups = {}
    for i, edge in ipairs(g.edges) do groups[i] = edge.group end
    for _, group in ipairs(groups) do
        if button and button.AddAuraShownAnimation then
            pcall(button.AddAuraShownAnimation, button, group)
        end
        -- Registering doesn't start it on a button that already shows. On
        -- a hidden one it plays unseen until the aura shows.
        group:Play()
    end
    holder.glowGroups, holder.glowOn = groups, true
    return holder, groups
end

-- Starts or stops a glow that Glow.native made without a button. A stopped
-- one is hidden and runs nothing.
function Glow.play(holder, on)
    on = on and true or false
    if not (holder and holder.glowGroups) or holder.glowOn == on then return end
    holder.glowOn = on
    for _, group in ipairs(holder.glowGroups) do
        if on then group:Play() else group:Stop() end
    end
    holder:SetShown(on)
end

Glow.pixel = pixel
