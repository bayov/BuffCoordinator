-- Theme -- how our windows look: colours, fonts and the controls.
--
-- It follows EllesmereUI's config window, because that is the window BayovCore
-- sits next to on the beta. Flat dark panels, text that is white at different
-- alphas rather than in different colours, one accent colour for whatever is
-- selected or on, and 1 pixel borders. EUI paints most of its window from one
-- big image. We draw ours from solid textures, so it needs no art and looks
-- the same where EUI isn't installed.
--
-- The accent is the blue the /bayov console prints module names in, so the
-- window and the chat lines read as the same thing. It means selected, on, or
-- the one main action, and nothing else.
--
-- Every control here is a plain frame of the kind the client would give us
-- anyway (a CheckButton for a toggle, an EditBox for a number, a Button per
-- choice), with our own textures on it. So what a page does with a control
-- doesn't depend on how it looks.
--
-- This file is in bayovui/shared, so BayovCore and Buff Coordinator each load
-- their own copy of it, from their own Shared folder. Each addon's own
-- Theme.lua loads right after it and makes it theirs:
--
--   T.SIZE, T.CONTROL    the type scale and the sizes of the controls. Buff
--                        Coordinator's are a little smaller, because its
--                        window is small and holds a long list.
--   T.FONT, T.BOLD       the fonts. BayovCore takes EUI's Avant Garde when
--                        EUI is there, Buff Coordinator the player's pick.
--   T.PANEL_TEX,         the panel art, and whether it's drawn upside down.
--   T.GRAIN_TEX,         BayovCore's are copies of EUI's files, which Buff
--   T.PANEL_FLIP         Coordinator can't ship, so it has its own.
--   T.MENU_NAME          the global name of the menu, for Escape.
--   T.GREY_HOVER         menus light a row grey under the mouse, and only the
--                        pick in the accent (Buff Coordinator's menus).
--
-- We read all of these when a control is made or painted, not when this file
-- loads, so the addon's Theme.lua can set them after it. Art comes from the
-- addon's own Media folder (T.media), so neither addon reaches into the other.
-- Nothing here needs BayovCore, EUI or FojjiCore.
--
-- The accent can change while we play (Buff Coordinator has a setting for it,
-- and for the font). T.ACCENT is one table we change in place, and T.restyle
-- puts a new accent and font on everything already made.

local ADDON, NS = ...
-- BayovCore times what its windows cost. Buff Coordinator has no Profiler.
local CreateFrame = NS.Profiler and NS.Profiler.scope("config") or CreateFrame

local T = {}
NS.Theme = T

local max, min, floor = math.max, math.min, math.floor

-- Our art, in the addon's own Media folder: T.media("Dot").
local MEDIA = [[Interface\AddOns\]] .. ADDON .. [[\Media\]]
function T.media(name) return MEDIA .. name end

-- PT Sans Narrow, which both addons ship. The addon's Theme.lua may pick
-- another font.
T.PT      = [[Interface\AddOns\]] .. ADDON .. [[\Fonts\PTSansNarrow-Regular.ttf]]
T.PT_BOLD = [[Interface\AddOns\]] .. ADDON .. [[\Fonts\PTSansNarrow-Bold.ttf]]
T.FONT, T.BOLD = T.PT, T.PT_BOLD
T.WHITE8 = [[Interface\Buttons\WHITE8X8]]

-- Our logo, drawn by bayovui/build/logo.py.
T.LOGO = MEDIA .. "Logo"

T.ACCENT = { 0.30, 0.72, 1.00 }
T.BG     = { 0.055, 0.060, 0.072 }
T.INPUT  = { 0.020, 0.022, 0.028 }

T.GOOD   = { 0.36, 0.86, 0.56 }
T.WARN   = { 1.00, 0.45, 0.30 }
T.GOLD   = { 1.00, 0.82, 0.00 }
T.ORANGE = { 1.00, 0.58, 0.15 }

-- Text alphas, from EUI: a label is full white, a description about half, a
-- section heading less, and anything disabled barely there.
T.A_TEXT  = 0.92
-- The line under a row or a number on a Ledger page (T.SIZE.sub). Dimmer
-- than the row, but still easy to read at 12 pt.
T.A_SUB   = 0.70
T.A_DIM   = 0.55
T.A_FAINT = 0.38
T.A_OFF   = 0.22

-- A list's row under the mouse is white at T.LIST_HOVER, and the picked row
-- the accent at T.LIST_SELECTED, in every list and table.
T.LIST_HOVER    = 0.05
T.LIST_SELECTED = 0.18

-- A colour lifted toward white until it reads on our dark panels.
--
-- The game's class colours are made for its own frames, and some are too dark
-- for text on ours: on Forever a Shaman is a deep blue (0, 0.44, 0.87) that
-- barely shows against the near-black background. We measure how light a
-- colour looks (the usual weights for red, green and blue), and when it's
-- under T.READABLE we mix in white until it reaches it. Light colours, like a
-- Priest's white or a Rogue's yellow, come back as they were.
T.READABLE = 0.55

function T.readable(r, g, b)
    local light = 0.299 * r + 0.587 * g + 0.114 * b
    if light >= T.READABLE then return r, g, b end
    local t = (T.READABLE - light) / (1 - light)
    return r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
end

-- A class's colour for our text: { r, g, b, colorStr = "ffrrggbb" }, from
-- the game's RAID_CLASS_COLORS (or C_ClassColor), lifted by T.readable. Nil
-- for a class the game doesn't know. Every name we colour by class reads
-- through here, so a Shaman reads the same everywhere.
--
-- In combat the game can hide a class from us (a secret value), like the
-- class of our cast's target. Comparing one is an error, so we give nil for
-- it, and a caller that wants the colour anyway asks C_ClassColor itself.
local classColors = {}

-- The class colours for a client that gives us none (the tests' doesn't), as
-- the game has them.
T.CLASS_HEX = { WARRIOR = "ffc69b6d", PALADIN = "fff48cba", HUNTER = "ffaad372", ROGUE = "fffff468",
                PRIEST = "ffffffff", SHAMAN = "ff0070dd", MAGE = "ff3fc7eb", WARLOCK = "ff8788ee",
                DRUID = "ffff7c0a", DEATHKNIGHT = "ffc41e3a", MONK = "ff00ff98", DEMONHUNTER = "ffa330c9",
                EVOKER = "ff33937f" }

function T.classColor(class)
    if _G.issecretvalue and _G.issecretvalue(class) then return nil end
    if type(class) ~= "string" or class == "" then return nil end
    local c = classColors[class]
    if c then return c end
    -- A colour may come as r, g, b, as GetRGB, or only as "ffrrggbb".
    local function rgb(x)
        if type(x) ~= "table" then return nil end
        if x.r then return x.r, x.g, x.b end
        if x.GetRGB then return x:GetRGB() end
        local hex = type(x.colorStr) == "string" and x.colorStr
        if hex and #hex == 8 then
            return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255,
                   tonumber(hex:sub(7, 8), 16) / 255
        end
    end
    local r, g, b = rgb(_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class])
    local api = _G.C_ClassColor
    if not r and api and api.GetClassColor then
        local ok, x = pcall(api.GetClassColor, class)
        if ok then r, g, b = rgb(x) end
    end
    if not r then r, g, b = rgb({ colorStr = T.CLASS_HEX[class] }) end
    if not r then return nil end
    r, g, b = T.readable(r, g, b)
    c = { r = r, g = g, b = b,
          colorStr = string.format("ff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)) }
    function c:GetRGB() return self.r, self.g, self.b end
    classColors[class] = c
    return c
end

-- "You changed this": a small gold dot (Media/Dot.tga, drawn by
-- build/glyphs.py and tinted gold here). A settings page puts it beside
-- anything changed, with a revert button next to it. One mark, learned once.
-- BayovCore's console `list` still prints a gold `*`, since chat is text.
T.MARK = "|T" .. MEDIA .. "Dot:7:7:0:0:64:64:0:64:0:64:255:209:0|t"

-- The down arrow on anything that opens a list (Media/Chevron.tga, also drawn
-- by build/glyphs.py). T.chevron is a texture to place, T.DOWN goes in text.
T.CHEVRON = MEDIA .. "Chevron"
T.DOWN = "|T" .. T.CHEVRON .. ":10:10:0:0:64:64:0:64:0:64:170:174:180|t"

function T.chevron(parent, size, alpha)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(T.CHEVRON)
    t:SetSize(size or 10, size or 10)
    t:SetVertexColor(1, 1, 1, alpha or 0.6)
    return t
end

-- Makes edit box `e` read as plain text until the mouse is on it or it has
-- focus, for numbers that are mostly read and only sometimes changed. Call
-- it after the box's own OnEnter and OnLeave are set, since SetScript drops
-- hooks.
function T.quietEdit(e)
    local function look()
        local focus = e:HasFocus()
        local on = focus or e.hover
        e.bg:SetShown(on and true or false)
        if not focus then T.paint(e, { 1, 1, 1 }, on and 0.12 or 0) end
    end
    e.quietLook = look
    e:HookScript("OnEnter", function()
        e.hover = true
        look()
    end)
    e:HookScript("OnLeave", function()
        e.hover = nil
        look()
    end)
    e:HookScript("OnEditFocusGained", look)
    e:HookScript("OnEditFocusLost", look)
    look()
end

-- A dim up and down arrow inside an edit box's left end, on a box the mouse
-- wheel changes, like a count. The text keeps clear of them.
function T.wheelHint(edit)
    local up = T.chevron(edit, 8, 0.35)
    up:SetTexCoord(0, 1, 1, 0)
    up:SetPoint("BOTTOM", edit, "LEFT", 9, -1)
    local down = T.chevron(edit, 8, 0.35)
    down:SetPoint("TOP", edit, "LEFT", 9, 1)
    if edit.SetTextInsets then edit:SetTextInsets(16, 6, 0, 0) end
    edit.wheelUp, edit.wheelDown = up, down
    return up, down
end

-- Shows that a wheel turn on `edit` hit its limit, like a count under 1 or
-- over what there is. The border and the arrow that way (T.wheelHint) flash
-- red for a moment.
T.LIMIT_FLASH = 0.35
function T.wheelLimit(edit, up)
    local arrow = up and edit.wheelUp or edit.wheelDown
    local c = T.WARN
    if arrow then arrow:SetVertexColor(c[1], c[2], c[3], 1) end
    edit.bg:Show()
    T.paint(edit, c, 0.9)
    edit.limitN = (edit.limitN or 0) + 1
    local n = edit.limitN
    C_Timer.After(T.LIMIT_FLASH, function()
        if edit.limitN ~= n then return end
        if arrow then arrow:SetVertexColor(1, 1, 1, 0.35) end
        if edit:HasFocus() then
            T.paint(edit, T.ACCENT, 0.9)
        else
            T.paint(edit, edit.restEdge or { 1, 1, 1 }, edit.restAlpha or 0.12)
        end
        if edit.quietLook then edit.quietLook() end
    end)
end

-- The type scale. Every text in a window is one of these sizes, so a page
-- can't pick a size of its own and the window reads as one thing.
--
-- `title` is a page's name, `tab` a tab in a page's strip and the sidebar's
-- features, `label` a setting's name, `body` a description, a summary or a
-- status, and `caption` the small print, like the version line.
T.SIZE = { title = 22, tab = 14, label = 14, body = 13, caption = 11 }

-- A Ledger page's own steps, the Session page and the Sessions window's list
-- first. A page has more small print than a settings page, so it needs more
-- steps between the title and the axis times:
--
--   page      the page's own title (the Session page's title block)
--   value     a tile's number, the biggest thing after the title
--   section   a section or card heading, in capitals at T.A_DIM
--   row       a row's words, a line of facts, a list entry's name
--   sub       the line under a row or a number, at T.A_SUB
--   tiny      axis times, a lane's name, a hint, the dim words beside a
--             heading, at T.A_DIM
--   bar       words drawn inside a 10 to 12 px bar or lane
--
-- Text under 12 pt is only for labels a player glances at, never for what
-- they read: at the Sessions window's 0.8 scale, 11 pt is under 9 px.
T.SIZE.page, T.SIZE.value, T.SIZE.section = 18, 20, 12
T.SIZE.row, T.SIZE.sub, T.SIZE.tiny, T.SIZE.bar = 12, 12, 11, 10

-- The sizes of the controls, in the same spirit. `w` and `h` are what a
-- control is made at when its caller gives no size, and `size` its text.
T.CONTROL = {
    button   = { w = 120, h = 26, size = 14 },
    toggle   = { w = 36, h = 18, knob = 12 },
    range    = { h = 18, knobW = 10, knobH = 16 },
    heading  = { h = 30, size = 12, y = 7 },
    chip     = { h = 20, size = 12, pad = 16 },
    segment  = { h = 22, size = 13 },
    dropdown = { w = 160, h = 22, row = 22, size = 13 },
    edit     = { w = 76, h = 22, size = 14 },
    revert   = 20,
    -- A menu row's words, and the dim words at its right.
    menu     = { size = 13, right = 12 },
}

-- The global name of the menu, which Escape closes by. The addon's Theme.lua
-- may set another.
T.MENU_NAME = ADDON .. "Menu"
T.GREY_HOVER = false

-- =============================================================
-- Regions
-- =============================================================

-- What T.text and T.fill made, so a new font or accent reaches frames that
-- already exist (T.restyle). Before, Buff Coordinator made its window again
-- for a new font or accent, and the old one stayed behind, since the game
-- never frees a frame. The tables are weak, so they don't keep anything
-- alive.
local texts = setmetatable({}, { __mode = "k" })
local accentFills = setmetatable({}, { __mode = "k" })
local accentEdges = setmetatable({}, { __mode = "k" })

-- The game may hand a font's path back with other slashes or case.
local function samePath(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    return (a:lower():gsub("/", "\\")) == (b:lower():gsub("/", "\\"))
end

-- Puts the font and accent the addon just set (T.FONT, T.BOLD, T.ACCENT) on
-- everything already made. `oldFont` and `oldBold` are the fonts from before.
-- Only a text still in the old window font changes, so one that was given a
-- font of its own keeps it. A text keeps its own size and outline, and stays
-- bold or regular as it is now.
function T.restyle(oldFont, oldBold)
    for fs, t in pairs(texts) do
        local path, size, flags = fs:GetFont()
        if path == nil or samePath(path, oldFont) or samePath(path, oldBold) then
            local bold = t.bold
            if oldFont ~= oldBold and path ~= nil then bold = samePath(path, oldBold) end
            fs:SetFont(bold and T.BOLD or T.FONT, size or t.size, flags or "")
        end
    end
    for tex, alpha in pairs(accentFills) do tex:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], alpha) end
    for frame, alpha in pairs(accentEdges) do T.paint(frame, T.ACCENT, alpha) end
end

-- A font string in our font. It starts from a Blizzard font object, so when
-- the font file can't be read the text still shows in the game's own face.
function T.text(parent, size, bold, alpha, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlight")
    fs:SetFont(bold and T.BOLD or T.FONT, size or 14, "")
    fs:SetShadowColor(0, 0, 0, 0.6)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(1, 1, 1, alpha or T.A_TEXT)
    fs:SetJustifyH("LEFT")
    texts[fs] = { bold = bold and true or false, size = size or 14 }
    return fs
end

-- What goes between the fragments of a status or a line: "22 categories ·
-- 3 hidden".
T.SEP = " \194\183 "

-- The fragments joined by T.SEP, the empty ones (nil, false, "") left out:
-- T.join("22 categories", hidden > 0 and hidden .. " hidden"). One table of
-- fragments works too.
function T.join(...)
    local n = select("#", ...)
    local parts = { ... }
    if n == 1 and type(parts[1]) == "table" then
        parts = parts[1]
        n = #parts
    end
    local out = {}
    for i = 1, n do
        local p = parts[i]
        if p ~= nil and p ~= false and p ~= "" then out[#out + 1] = tostring(p) end
    end
    return table.concat(out, T.SEP)
end

-- The one look of a list or page with nothing in it: what's missing as a
-- sentence (14, dim) in the middle of `parent`, and a hint under it (12,
-- faint) that says how to get some.
--
--   opts.hint   the hint
--   opts.area   what it sits over, `parent` when not given
--   opts.cover  true: a solid back that hides what's under it and takes the
--               mouse, above the parent's rows (the Ledger's views)
--   opts.pad    room at its sides before the text wraps (10)
--
-- It answers the frame, shown when `text` is given. e:set(text, hint) changes
-- it, and e:set(nil) hides it. e.text and e.hint are its two lines.
function T.empty(parent, text, opts)
    opts = opts or {}
    local area = opts.area or parent
    local pad = opts.pad or 10
    local e = CreateFrame("Frame", nil, parent)
    e:SetAllPoints(area)
    if opts.cover then
        e:SetFrameLevel((parent:GetFrameLevel() or 1) + 50)
        e.bg = T.fill(e, T.BG, 0.97)
        e.bg:SetAllPoints(e)
        e:EnableMouse(true)
    end
    e.text = T.text(e, 14, false, T.A_DIM)
    e.text:SetJustifyH("CENTER")
    e.hint = T.text(e, 12, false, T.A_FAINT)
    e.hint:SetJustifyH("CENTER")
    e.hint:SetPoint("TOPLEFT", e.text, "BOTTOMLEFT", 0, -6)
    e.hint:SetPoint("TOPRIGHT", e.text, "BOTTOMRIGHT", 0, -6)
    function e:set(t, hint)
        if not t then
            self:Hide()
            return
        end
        self.text:SetText(t)
        self.hint:SetText(hint or "")
        -- With a hint the two lines sit round the middle, without one the
        -- sentence is in it.
        self.text:ClearAllPoints()
        local y = (hint and hint ~= "") and 14 or 0
        local point = y > 0 and "BOTTOM" or ""
        self.text:SetPoint(point .. "LEFT", self, "LEFT", pad, y)
        self.text:SetPoint(point .. "RIGHT", self, "RIGHT", -pad, y)
        self:Show()
    end
    if text then e:set(text, opts.hint) else e:Hide() end
    return e
end

-- Gives a text a black outline, like the HUD's cooldown numbers.
--
-- A count on an item icon needs it, because a soft shadow vanishes on a
-- bright or busy icon. The outline stays when the window font changes, since
-- T.restyle keeps a text's flags.
function T.outline(fs)
    local path, size = fs:GetFont()
    fs:SetFont(path or T.BOLD, size or 11, "OUTLINE")
    fs:SetShadowOffset(0, 0)
    return fs
end

-- The font size of a count on an icon `icon` pixels high, when nothing else
-- sits on that icon.
--
-- A big icon has room for a bigger number, so a 34 px mail attachment gets a
-- 14 px count. An icon under 30 px keeps the usual 11. An icon that also shows
-- a cooldown or other text in its middle, like the HUD's, keeps a small count
-- whatever its size, so the two don't crowd each other.
function T.countSize(icon)
    if (icon or 0) < 30 then return 11 end
    return math.floor(icon * 0.4 + 0.5)
end

-- Puts a one-line text at `size`, or one step smaller (`small`) when its
-- words don't fit `room` at `size`, so a long name loses a point before it
-- loses its end. Answers whether the words fit now. A text made by T.text
-- keeps the size through T.restyle.
function T.fitSize(fs, room, size, small)
    local path, _, flags = fs:GetFont()
    if not path then return true end
    local function set(s)
        fs:SetFont(path, s, flags or "")
        if texts[fs] then texts[fs].size = s end
    end
    set(size)
    local function width()
        return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth() or 0
    end
    if width() <= room or not small or small >= size then return width() <= room end
    set(small)
    return width() <= room
end

-- Gives a tooltip's lines the font of its own body lines. We call it after
-- adding lines to a tooltip, with `from` the first line we added.
--
-- We go over every line under line 2, not only ours from `from`. Tooltip.lua
-- puts its price and ledger lines above the key hints by writing them into
-- lines the tooltip already had, and those keep that line's font: the game's,
-- or a hint's that was put back from small. So the moved lines came out in
-- another size than the rest. The tooltip's own lines already have the body
-- font, so going over them too changes nothing there.
--
-- EUI's tooltip skin sets its font on every line when the tooltip shows.
-- But a tooltip that's filled again while it's up doesn't show again: holding
-- Shift, or moving from one bag slot to the next. Then a line we add past the
-- ones it had before keeps the game's own font, at another size. Line 2 is
-- always a body line, so we copy its font. With one line or none before ours,
-- there's no body line of the tooltip's own to copy. A line T.tipSmall made
-- small stays small.
-- The global names of line `i`'s font strings on the tooltip called `name`,
-- like GameTooltipTextLeft3 and GameTooltipTextRight3.
--
-- We make each name once and keep it. Building it again on every pass made a
-- new string for the line's number, and we go over every line of an item
-- tooltip each time the game fills it, about three times a second.
local lineNames = {}

local function tipLineNames(name, i)
    local t = lineNames[name]
    if not t then
        t = { left = {}, right = {} }
        lineNames[name] = t
    end
    local left = t.left[i]
    if not left then
        left = name .. "TextLeft" .. i
        t.left[i], t.right[i] = left, name .. "TextRight" .. i
    end
    return left, t.right[i]
end

-- Sets one tooltip line's font when it differs.
--
-- It's a plain function, not a loop over a { left, right } list, because the
-- game refreshes a shown item tooltip about three times a second. A new list
-- for each of its lines was most of the garbage our tooltip hooks made.
local function matchFont(fs, path, size, flags)
    if not fs then return end
    local p, s, f = fs:GetFont()
    if p ~= path or s ~= size or f ~= flags then fs:SetFont(path, size, flags) end
end

function T.tipFont(tip, from)
    if not (tip and tip.NumLines and tip.GetName) or (from or 0) <= 2 then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    local name = tip:GetName()
    local ref = name and _G[name .. "TextLeft2"]
    if not (ref and ref.GetFont) or T.tipLineIsSmall(tip, 2) then return end
    local path, size, flags = ref:GetFont()
    if not path then return end
    for i = 3, tip:NumLines() do
        if not T.tipLineIsSmall(tip, i) then
            -- The right side only counts when the left one is there, like the
            -- game's own lines, where both always exist together.
            local l, r = tipLineNames(name, i)
            local left = _G[l]
            if left then
                matchFont(left, path, size, flags)
                matchFont(_G[r], path, size, flags)
            end
        end
    end
end

function T.fill(parent, color, alpha, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    if color == T.ACCENT then accentFills[t] = alpha or 1 end
    return t
end

-- The textured background of our windows: the config window, and the floating
-- ones like Supplies, Macros and the Profiler graph.
--
-- It starts from EllesmereUI's bag window: its textured panel under a quarter
-- of black. BayovCore keeps a copy of the texture in its Media, so it doesn't
-- need EUI for it. So that it doesn't pass for the bags, we make it slate
-- rather than brown by default: the texture desaturated and tinted towards our
-- blue accent, and turned upside down so its light falls elsewhere. A faint
-- brushed grain (EllesmereUI's matte bar texture, also copied) goes over it.
--
-- Buff Coordinator can't ship EUI's files, so its Theme.lua points
-- T.PANEL_TEX and T.GRAIN_TEX at art of its own (bayovui/build/panel_texture.py)
-- that's drawn the way it shows, with T.PANEL_FLIP off.
--
-- BayovCore's Look tab sets the texture, tint, darkness, grain and opacity
-- (its Config.lua hands them to us through NS.PanelLook). A change there
-- restyles every window drawn with T.panel at once, open or not. Without
-- NS.PanelLook a panel has PANEL_LOOK, the Look tab's defaults.
--
-- NS.PanelLook gets the panel's frame, so an addon can give some windows a
-- look of their own. BayovCore tints its windows by category that way
-- (T.windowLook in its Theme.lua). A look's `tint` is the name of one of
-- T.PANEL_TINTS or a colour of its own, and `flip` (when set) overrides
-- T.PANEL_FLIP.
--
-- It takes two sublevels of BACKGROUND, from `sub` (0 when not given). The
-- caller draws its own border, like T.windowEdge.
T.PANEL_TEX = MEDIA .. "Panel.png"
T.GRAIN_TEX = MEDIA .. "Grain.tga"
T.PANEL_FLIP = true

-- The tints the Look tab offers. "Original" is the texture's own brown.
T.PANEL_TINTS = {
    Blue     = { 0.80, 0.92, 1.00 },
    Grey     = { 0.85, 0.85, 0.85 },
    Original = false,
}

local PANEL_LOOK = { texture = "Panel", tint = "Blue", dark = 0.25, grain = 0.06, opacity = 1 }
local panels = setmetatable({}, { __mode = "k" })

local function restyle(f)
    local look = (NS.PanelLook and NS.PanelLook(f)) or PANEL_LOOK
    local o = look.opacity
    if look.texture == "Plain" then
        f.bg:SetDesaturated(false)
        f.bg:SetVertexColor(1, 1, 1, 1)
        f.bg:SetColorTexture(T.BG[1], T.BG[2], T.BG[3], o)
    else
        local tint = look.tint
        if type(tint) ~= "table" then tint = T.PANEL_TINTS[tint] end
        local flip = look.flip
        if flip == nil then flip = T.PANEL_FLIP end
        f.bg:SetTexture(T.PANEL_TEX)
        if flip then f.bg:SetTexCoord(1, 0, 1, 0) else f.bg:SetTexCoord(0, 1, 0, 1) end
        f.bg:SetDesaturated(tint and true or false)
        if tint then
            f.bg:SetVertexColor(tint[1], tint[2], tint[3], o)
        else
            f.bg:SetVertexColor(1, 1, 1, o)
        end
    end
    f.shade:SetColorTexture(0, 0, 0, look.dark * o)
    f.grain:SetTexture(T.GRAIN_TEX)
    f.grain:SetAlpha(look.grain * o)
end

function T.panel(f, sub)
    sub = sub or 0
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, sub)
    f.bg:SetAllPoints(f)
    f.shade = f:CreateTexture(nil, "BACKGROUND", nil, sub + 1)
    f.shade:SetAllPoints(f)
    f.grain = f:CreateTexture(nil, "BACKGROUND", nil, sub + 1)
    f.grain:SetAllPoints(f)
    panels[f] = true
    restyle(f)
end

-- After a Look setting changed, or the panel art did.
function T.restylePanels()
    for f in pairs(panels) do restyle(f) end
end

-- A horizontal fade, from `a1` at the left to `a2` at the right. The gradient
-- call changed shape between clients (colour objects on newer ones, alphas on
-- older ones), so we try both and fall back to an even tint.
--
-- `orientation` "VERTICAL" fades from `a1` at the bottom to `a2` at the top
-- instead.
local function gradient(tex, color, a1, a2, orientation)
    local r, g, b = color[1], color[2], color[3]
    local o = orientation or "HORIZONTAL"
    if tex.SetGradient and _G.CreateColor then
        local ok = pcall(tex.SetGradient, tex, o,
                         _G.CreateColor(r, g, b, a1), _G.CreateColor(r, g, b, a2))
        if ok then return end
    end
    if tex.SetGradientAlpha then
        local ok = pcall(tex.SetGradientAlpha, tex, o,
                         r, g, b, a1, r, g, b, a2)
        if ok then return end
    end
    return false
end

function T.fade(tex, color, a1, a2, orientation)
    tex:SetColorTexture(1, 1, 1, 1)
    if gradient(tex, color, a1, a2, orientation) == false then
        tex:SetColorTexture(color[1], color[2], color[3], (a1 + a2) / 2)
    end
end

-- One screen pixel in this frame's units. At 1440p one UI unit is nearly two
-- pixels, so a border of one unit would look twice as thick as EUI's.
function T.pixel(frame)
    if not _G.GetPhysicalScreenSize then return 1 end
    local _, h = _G.GetPhysicalScreenSize()
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if not h or h <= 0 or not scale or scale <= 0 then return 1 end
    return 768 / h / scale
end

-- Four 1 pixel edges just inside a frame. T.paint recolours them, and
-- T.edgeWidth makes them wider.
--
-- How many UI units make a pixel depends on the UI scale, and most of our
-- frames are made at load, before the game has applied it. Edges sized then
-- came out thinner than a pixel, and on Reset all the left and bottom ones
-- vanished. So we size them again each time the frame is shown.
local function fitEdges(frame)
    local e = frame.edges
    if not e then return end
    local px = (frame.edgeWidth or 1) * T.pixel(frame)
    e[1]:SetHeight(px)
    e[2]:SetHeight(px)
    e[3]:SetWidth(px)
    e[4]:SetWidth(px)
end

-- The edges don't snap to the pixel grid. A button placed at a fractional
-- position, like one centered or right-aligned on a page, has edges that start
-- partway into a pixel. With snapping on, the game rounds both sides of such a
-- 1 pixel edge to the same pixel line, and that edge vanishes. EUI turns
-- snapping off on its borders for the same reason.
function T.border(frame, color, alpha, layer)
    local e = {}
    for i = 1, 4 do
        e[i] = frame:CreateTexture(nil, layer or "BORDER")
        if e[i].SetSnapToPixelGrid then
            e[i]:SetSnapToPixelGrid(false)
            e[i]:SetTexelSnappingBias(0)
        end
    end
    e[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    e[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    e[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    e[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    e[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    e[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    e[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    e[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.edges = e
    -- The frame's fill doesn't snap either. A box at a fractional spot
    -- otherwise has its fill rounded to a pixel and its edges drawn where
    -- they are, with a strip of page between them on one side.
    if frame.bg and frame.bg.SetSnapToPixelGrid then
        frame.bg:SetSnapToPixelGrid(false)
        frame.bg:SetTexelSnappingBias(0)
    end
    fitEdges(frame)
    if frame.HookScript then frame:HookScript("OnShow", fitEdges) end
    T.paint(frame, color or { 1, 1, 1 }, alpha or 0.08)
    return e
end

-- Fits the edges of `frame` and of every frame inside it again, after its
-- scale changed.
--
-- The edges are fitted when they're made and on each show. A frame whose
-- scale changes while it's on show keeps edges fitted to the old scale. When
-- the auction window shrinks Blizzard's to a scale of 0.001 to hide it, our
-- buttons on it got edges 1000 times too thick, which showed as wide bands
-- once Blizzard's window was back at its own scale.
function T.refit(frame)
    if not frame then return end
    if frame.edges then fitEdges(frame) end
    if not frame.GetChildren then return end
    local n = frame.GetNumChildren and frame:GetNumChildren() or 0
    if n == 0 then return end
    local kids = { frame:GetChildren() }
    for i = 1, #kids do T.refit(kids[i]) end
end

-- Makes the edges of T.border's `frame` `n` screen pixels wide. The width
-- stays when the frame shows again, which fits the edges anew.
function T.edgeWidth(frame, n)
    frame.edgeWidth = n
    fitEdges(frame)
end

function T.paint(frame, color, alpha)
    accentEdges[frame] = color == T.ACCENT and (alpha or 1) or nil
    for _, t in ipairs(frame.edges or {}) do
        t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    end
end

-- The soft shadow round a window and its faint edge. The shadow is three
-- dark rings outside the window, each fainter, under everything the window
-- draws.
function T.windowEdge(f)
    for i, a in ipairs({ 0.45, 0.22, 0.10 }) do
        local s = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        s:SetColorTexture(0, 0, 0, a)
        s:SetPoint("TOPLEFT", f, "TOPLEFT", -i * 2, i * 2)
        s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", i * 2, -i * 2)
    end
    T.border(f, { 1, 1, 1 }, 0.08)
end

-- The small shadow under a popup, menu or dropdown list (T.popupShadow).
-- It's BayovCore's, drawn from its media, so a popup in Buff Coordinator
-- alone has none.
local function popupShadow(f)
    if T.popupShadow then T.popupShadow(f) end
end

-- A small panel that opens from a button, like a legend, in the look of our
-- menus: a flat dark fill and a faint border. The textured panel is for
-- windows only.
function T.popup(f)
    f.bg = T.fill(f, { 0.07, 0.08, 0.10 }, 0.98, "BACKGROUND")
    f.bg:SetAllPoints(f)
    T.border(f, { 1, 1, 1 }, 0.18)
    popupShadow(f)
end

-- How much of each side of an icon we crop. The game's icons have a bevelled
-- bezel round the edge, and this is enough to lose all of it.
T.ICON_ZOOM = 0.1

-- Puts `art` on a plain texture `tex`. `art` is a path or a file ID, drawn
-- whole, or a piece of a bigger file: { file = <path or file ID>, coords =
-- { left, right, top, bottom }, grey = <true to desaturate> }, like the game's
-- quest marks in BayovCore's T.QUEST.
--
-- We draw a piece from its file and corners, never with SetAtlas. On Forever a
-- SetTexCoord after SetAtlas counts inside the atlas, so a pooled texture
-- that took an atlas once would crop the next icon it shows.
--
-- `setTexture` is the texture's own SetTexture, for T.icon, which wraps it.
function T.setArt(tex, art, setTexture)
    setTexture = setTexture or tex.SetTexture
    if type(art) == "table" then
        setTexture(tex, art.file)
        local c = art.coords
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
        if tex.SetDesaturated and (art.grey or tex.artGrey) then
            tex:SetDesaturated(art.grey and true or false)
            tex.artGrey = art.grey and true or nil
        end
        return
    end
    setTexture(tex, art)
    tex:SetTexCoord(0, 1, 0, 1)
    -- A grey piece left its texture grey. Anything else keeps the grey its
    -- owner gave it.
    if tex.artGrey then
        tex:SetDesaturated(false)
        tex.artGrey = nil
    end
end

-- A spell or item icon, zoomed in past the game's bezel, with a 1 pixel black
-- edge round it. `plain` leaves the edge off, for an icon that sits in a frame
-- with an edge of its own.
--
-- Our logo is a cube on a clear background, so it shows whole and without the
-- edge. That holds when the logo is set later too, like a row that shows the
-- logo for the window's own settings, so SetTexture decides it each time.
--
-- The edge is four of the parent's textures anchored to the icon. They are
-- not the icon's own, so we make the icon's Show, Hide, SetShown and SetAlpha
-- move them along. An icon with no texture has no edge either, so an empty
-- slot doesn't show a black square.
function T.icon(parent, path, size, plain)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    local e = {}
    -- `edged` says the icon has a texture that gets an edge, and `off` that
    -- SetEdge took the edge away (0 px).
    local edged, off = false, false
    local function showEdges(on)
        for _, x in ipairs(e) do x:SetShown(on) end
    end
    if not plain then
        -- The edges can't snap to the pixel grid (T.border says why), so the
        -- icon doesn't either. Otherwise an icon at a fractional position, like
        -- one in the sidebar, rounds to a pixel its edges don't, and shows a
        -- sliver of itself outside them.
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        for i = 1, 4 do
            e[i] = parent:CreateTexture(nil, "OVERLAY", nil, 7)
            if e[i].SetSnapToPixelGrid then
                e[i]:SetSnapToPixelGrid(false)
                e[i]:SetTexelSnappingBias(0)
            end
            e[i]:SetColorTexture(0, 0, 0, 1)
        end
        e[1]:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
        e[1]:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
        e[2]:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
        e[2]:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
        e[3]:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
        e[3]:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
        e[4]:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
        e[4]:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
        local width = 1
        local function fit()
            local px = T.pixel(parent) * width
            e[1]:SetHeight(px)
            e[2]:SetHeight(px)
            e[3]:SetWidth(px)
            e[4]:SetWidth(px)
        end
        fit()
        if parent.HookScript then parent:HookScript("OnShow", fit) end
        -- t:SetEdge(color, px) colours the edge and makes it `px` pixels
        -- wide, to mark an icon that matters (the Bestiary's stuns in red).
        -- t:SetEdge() puts back the black 1 pixel edge, and t:SetEdge(nil, 0)
        -- hides it. The game draws a texture 0 pixels high at its full
        -- size, so 0 hides the edges rather than sizing them.
        function t:SetEdge(color, px)
            local r, g, b = 0, 0, 0
            if color then r, g, b = color[1], color[2], color[3] end
            for _, x in ipairs(e) do x:SetColorTexture(r, g, b, 1) end
            off = px ~= nil and px <= 0
            width = off and 1 or (px or 1)
            fit()
            showEdges(edged and not off and (not t.IsShown or t:IsShown()) and true or false)
        end
    end
    local function wrap(name, after)
        local orig = t[name]
        if not orig then return end
        t[name] = function(self, ...)
            orig(self, ...)
            after(...)
        end
    end
    wrap("Show", function() showEdges(edged and not off) end)
    wrap("Hide", function() showEdges(false) end)
    wrap("SetShown", function(on) showEdges(edged and not off and on and true or false) end)
    wrap("SetAlpha", function(a) for _, x in ipairs(e) do x:SetAlpha(a) end end)
    -- It also takes a piece of a bigger file (T.setArt), like the game's
    -- quest marks. Those have their own outline, so they show whole, with no
    -- crop and no edge.
    local setTexture = t.SetTexture
    if setTexture then
        function t.SetTexture(self, p, ...)
            local piece = type(p) == "table"
            if piece then T.setArt(self, p, setTexture) else setTexture(self, p, ...) end
            if not piece then
                local z = T.ICON_ZOOM
                -- t.whole is set on a glyph of our own that has no bezel to crop.
                if p == T.LOGO or t.whole then t:SetTexCoord(0, 1, 0, 1)
                else t:SetTexCoord(z, 1 - z, z, 1 - z) end
                if self.artGrey then
                    self:SetDesaturated(false)
                    self.artGrey = nil
                end
            end
            -- A glyph of our own (t.whole) has no edge either.
            edged = p ~= nil and p ~= T.LOGO and not t.whole and not piece
            showEdges(edged and not off and (not t.IsShown or t:IsShown()) and true or false)
        end
    end

    t:SetTexture(path or [[Interface\Icons\INV_Misc_QuestionMark]])
    return t
end

-- The game's icon of `class` ("WARRIOR"), for T.icon.
function T.classIcon(class)
    return [[Interface\Icons\ClassIcon_]] .. class:sub(1, 1) .. class:sub(2):lower()
end

-- A round icon: the icon cut to a circle with the game's portrait mask, on a
-- dark disc a little wider, so it stands out on a map as well as on a panel.
--
-- The disc is the parent's texture, so like T.icon's edges, the icon's Show,
-- Hide, SetShown and SetAlpha move it along. t:SetEdge(px) sets how far the
-- disc shows past the icon, 1 by default. The world map's canvas zooms, and
-- there a pin sets it again at each zoom so it stays one pixel on the screen.
--
-- t:SetIcon(icon, round) takes a spell or item icon by its file ID, which we
-- cut round on its disc as above. It also takes the name of one of the game's
-- atlas icons, like "innkeeper", or the path of art of our own, like the
-- route's footprints. Those already have their own shape and outline, so we
-- draw them as they are, with no cut and no disc, unless round is true.
--
-- An atlas icon that isn't square, like the map's graveyard (12 by 16), keeps
-- its shape: we fit it in the icon's square instead of stretching it. So
-- anchor the icon by its CENTER, not by two corners. t:SetBox(size) sets
-- that square, like the world map pins do at each zoom.
--
-- We size it in whole screen pixels, so the game's pixel snapping doesn't
-- shave a pixel off its sides. And when a whole multiple of the atlas's own
-- size (the graveyard's 18 pixels, twice over at 1440p) is near the square,
-- we take that, so a 1 pixel outline stays a sharp line instead of a blur.
--
-- It also takes a piece of a texture, as a table: { file = <path or file
-- ID>, coords = { left, right, top, bottom }, w = <pixels>, h = <pixels> }.
-- That's for small art in a bigger file, like the route's graveyard. It's
-- drawn as it is too.
T.CIRCLE = [[Interface\CHARACTERFRAME\TempPortraitAlphaMask]]
T.DOT = MEDIA .. "Dot"

-- The changed mark (T.MARK's gold dot) as a texture of its own, for a tab.
-- T.MARK inside a font string sat above the words' middle, so a tab anchors
-- this one to its words' middle instead. Hidden on arrival.
T.MARK_DOT = 7
function T.markDot(parent)
    local m = parent:CreateTexture(nil, "OVERLAY")
    m:SetTexture(T.DOT)
    m:SetSize(T.MARK_DOT, T.MARK_DOT)
    m:SetVertexColor(1, 209 / 255, 0)
    m:Hide()
    return m
end

-- The changed mark on a tab whose words sit in its middle (T.tab, a settings
-- page's strip). `pad` is how much wider than its words the tab is.
--
-- With the mark the tab grows by 12, and the words move 6 left, so the words
-- and the mark sit in the middle together and the line under the tab reaches
-- past both.
local TAB_MARK_GAP, TAB_MARK_W = 4, 12
function T.tabMark(b, pad)
    b.mark = T.markDot(b)
    b.mark:SetPoint("LEFT", b.label, "RIGHT", TAB_MARK_GAP, 0)
    function b:setChanged(on)
        on = on and true or false
        self.mark:SetShown(on)
        self.label:ClearAllPoints()
        self.label:SetPoint("CENTER", self, "CENTER", on and -TAB_MARK_W / 2 or 0, 1)
        self:SetWidth(floor((self.label:GetStringWidth() or 40) + pad + (on and TAB_MARK_W or 0)))
    end
end

function T.roundIcon(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    t:SetSize(size, size)
    local z = T.ICON_ZOOM
    t:SetTexCoord(z, 1 - z, z, 1 - z)
    local m = parent.CreateMaskTexture and t.AddMaskTexture and parent:CreateMaskTexture()
    if m then
        m:SetTexture(T.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
    end
    local disc = parent:CreateTexture(nil, "ARTWORK", nil, 0)
    disc:SetTexture(T.DOT)
    disc:SetVertexColor(0, 0, 0, 0.85)
    function t.SetEdge(_, px)
        disc:ClearAllPoints()
        disc:SetPoint("TOPLEFT", t, "TOPLEFT", -px, px)
        disc:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", px, -px)
    end
    t:SetEdge(1)
    -- An atlas icon has no disc, so the disc shows only with a texture.
    local bare = false
    -- The square we draw in, the width over the height of what's in it, and
    -- an atlas icon's own height in its texture's pixels.
    local box, shape, own = size, 1, nil
    local function fit(self)
        local w, h = box, box
        if shape > 1 then h = box / shape elseif shape < 1 then w = box * shape end
        local px = T.pixel(parent)
        if own then
            local whole = max(1, floor(h / px / own + 0.5)) * own * px
            if whole >= h * 0.8 and whole <= h * 1.25 then w, h = whole * shape, whole end
        end
        self:SetSize(max(1, floor(w / px + 0.5)) * px, max(1, floor(h / px + 0.5)) * px)
    end
    function t.SetBox(self, s)
        box = s
        fit(self)
    end
    local function wrap(name, after)
        local orig = t[name]
        if not orig then return end
        t[name] = function(self, ...)
            orig(self, ...)
            after(...)
        end
    end
    wrap("Show", function() disc:SetShown(not bare) end)
    wrap("Hide", function() disc:Hide() end)
    wrap("SetShown", function(on) disc:SetShown(on and not bare or false) end)
    wrap("SetAlpha", function(a) disc:SetAlpha(a) end)
    function t.SetIcon(self, icon, round)
        local atlas = type(icon) == "string" and not icon:find("\\", 1, true)
        local piece = type(icon) == "table"
        local plain = not (round or type(icon) == "number")
        if m and plain ~= bare then
            if not plain then self:AddMaskTexture(m)
            elseif self.RemoveMaskTexture then self:RemoveMaskTexture(m) end
        end
        bare = plain
        shape, own = 1, nil
        if atlas then
            self:SetAtlas(icon)
            local CT = _G.C_Texture
            local info = CT and CT.GetAtlasInfo and CT.GetAtlasInfo(icon)
            if info and (info.width or 0) > 0 and (info.height or 0) > 0 then
                shape, own = info.width / info.height, info.height
            end
        elseif piece then
            self:SetTexture(icon.file)
            self:SetTexCoord(icon.coords[1], icon.coords[2], icon.coords[3], icon.coords[4])
            shape, own = icon.w / icon.h, icon.h
        else
            self:SetTexture(icon)
            if plain then self:SetTexCoord(0, 1, 0, 1) else self:SetTexCoord(z, 1 - z, z, 1 - z) end
        end
        fit(self)
        disc:SetShown(not bare and (not self.IsShown or self:IsShown()) and true or false)
    end
    return t
end

-- A circle icon: a spell or item icon cut round, with a 1 pixel black edge
-- and, when given a colour, a ring of that colour just inside the edge.
--
-- It's the one round look for what stands for a loadout or a gear set: the
-- gear set HUD by the player frame, the loadouts' badges, the side lists of
-- the Loadouts and Gear Sets windows, the loadout picker and the menus. A
-- loadout shows its colour as the ring. A set has the plain black edge.
--
-- It answers the outer disc, a texture like T.icon's: anchor it, size it and
-- show or hide it as one. t:SetTexture(path) sets the picture,
-- t:SetDesaturated(on) and t:SetDim(on) grey it out, t:SetLit(on) lightens
-- it under the mouse, and t:SetEdge(color, px)
-- sets the ring (nil for none). t:SetEdge(color, px, true) colours the outer
-- edge itself instead, `px` wide, like a queued swap's amber.
--
-- The discs and the picture each have their own round mask (the game's
-- portrait mask), inset by whole screen pixels, so the rings stay sharp.
function T.circleIcon(parent, path, size)
    local function disc(sub)
        local d = parent:CreateTexture(nil, "ARTWORK", nil, sub)
        if d.SetSnapToPixelGrid then
            d:SetSnapToPixelGrid(false)
            d:SetTexelSnappingBias(0)
        end
        local m = parent.CreateMaskTexture and d.AddMaskTexture and parent:CreateMaskTexture()
        if m then
            m:SetTexture(T.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(d)
            d:AddMaskTexture(m)
        end
        return d
    end
    local t = disc(-3)
    t:SetColorTexture(0, 0, 0, 1)
    t:SetSize(size or 16, size or 16)
    local ring = disc(-2)
    local back = disc(-1)
    back:SetColorTexture(0.06, 0.07, 0.08, 1)
    local img = disc(0)
    local lit = disc(1)
    lit:SetColorTexture(1, 1, 1, 0.12)
    lit:Hide()
    local z = T.ICON_ZOOM
    t.ring, t.back, t.img = ring, back, img

    local edgePx, ringPx, ringOn = 1, 0, false
    local function fit()
        local px = T.pixel(parent)
        local e, r = edgePx * px, (ringOn and ringPx or 0) * px
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", t, "TOPLEFT", e, -e)
        ring:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -e, e)
        for _, x in ipairs({ back, img, lit }) do
            x:ClearAllPoints()
            x:SetPoint("TOPLEFT", t, "TOPLEFT", e + r, -(e + r))
            x:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -(e + r), e + r)
        end
    end
    fit()
    if parent.HookScript then parent:HookScript("OnShow", fit) end
    t.Refit = fit

    local colorTex = t.SetColorTexture
    function t.SetEdge(self, color, px, outer)
        if outer then
            colorTex(self, color and color[1] or 0, color and color[2] or 0, color and color[3] or 0, 1)
            edgePx, ringOn = px or 1, false
        else
            colorTex(self, 0, 0, 0, 1)
            edgePx, ringOn, ringPx = 1, color ~= nil, px or 1
            if color then ring:SetColorTexture(color[1], color[2], color[3], 1) end
        end
        ring:SetShown(ringOn and (not self.IsShown or self:IsShown()) and true or false)
        fit()
    end
    function t.SetTexture(_, p)
        img:SetTexture(p or [[Interface\Icons\INV_Misc_QuestionMark]])
        img:SetTexCoord(z, 1 - z, z, 1 - z)
    end
    function t.SetDesaturated(_, on) img:SetDesaturated(on and true or false) end
    -- A soft white over the picture, for a button under the mouse.
    function t.SetLit(_, on) lit:SetShown(on and true or false) end
    -- The empty look: grey and darker, for a slot of the HUD with no set worn.
    function t.SetDim(_, on)
        img:SetDesaturated(on and true or false)
        local v = on and 0.55 or 1
        img:SetVertexColor(v, v, v, 1)
    end
    local function wrap(name, after)
        local orig = t[name]
        if not orig then return end
        t[name] = function(self, ...)
            orig(self, ...)
            after(...)
        end
    end
    wrap("Show", function() img:Show() back:Show() ring:SetShown(ringOn) end)
    wrap("Hide", function() img:Hide() back:Hide() ring:Hide() lit:Hide() end)
    wrap("SetShown", function(on)
        img:SetShown(on and true or false)
        back:SetShown(on and true or false)
        ring:SetShown(on and ringOn or false)
    end)
    wrap("SetAlpha", function(a) img:SetAlpha(a) back:SetAlpha(a) ring:SetAlpha(a) end)
    ring:Hide()
    t:SetTexture(path)
    return t
end

-- =============================================================
-- Sounds
-- =============================================================
-- The sounds the game's own windows make. A window like the character window
-- plays one when it opens and one when it closes, and a popup like the game
-- menu has its own pair. The numbers are the same sounds, for a client
-- without SOUNDKIT.
T.SOUNDS = {
    open = { "IG_CHARACTER_INFO_OPEN", 839 },
    close = { "IG_CHARACTER_INFO_CLOSE", 840 },
    popup = { "IG_MAINMENU_OPEN", 850 },
    popupClose = { "IG_MAINMENU_CLOSE", 851 },
    -- A button of the game's templates. Ours are plain frames and make no
    -- sound of their own.
    click = { "IG_MAINMENU_OPTION", 852 },
    -- A talent point put in or taken out, as the game's talent window plays
    -- them. A client without them clicks instead.
    talentAdd = { "UI_CLASS_TALENT_NODE_SPEND", 852 },
    talentRemove = { "UI_CLASS_TALENT_NODE_REFUND", 852 },
}

local hushed = false

function T.sound(what)
    local s = T.SOUNDS[what]
    if hushed or not (s and _G.PlaySound) then return end
    local kit = _G.SOUNDKIT
    pcall(_G.PlaySound, kit and kit[s[1]] or s[2])
end

-- Runs `fn` without a sound. A window closing closes the panels beside it,
-- and one close sound is enough.
function T.hush(fn)
    hushed = true
    local ok, err = pcall(fn)
    hushed = false
    if not ok then error(err, 0) end
end

-- Plays a window's open sound when it shows and its close sound when it
-- hides, or a popup's pair when `popup`.
--
-- Hiding the whole interface (Alt+Z) hides every window with it, and showing
-- it again shows them. Neither is the window opening or closing, so they make
-- no sound. A window that's still shown on its own while its parent is
-- hidden is how we tell. Call this after the window's own OnShow and OnHide
-- scripts are set, because setting a script drops the hooks on it.
--
-- A window is shown from the moment it's made, and showing a shown window
-- isn't opening it, so the first open would make no sound. So it starts
-- hidden here, and every window of ours shows itself after it's made.
local opened = setmetatable({}, { __mode = "k" })

function T.windowSounds(f, popup)
    local open, close = popup and "popup" or "open", popup and "popupClose" or "close"
    if f:IsShown() then f:Hide() end
    f:HookScript("OnShow", function(self)
        if opened[self] then return end
        opened[self] = true
        T.sound(open)
    end)
    f:HookScript("OnHide", function(self)
        if not opened[self] or self:IsShown() then return end
        opened[self] = nil
        T.sound(close)
    end)
end

-- Puts one of our windows on the same layer as the game's own windows and
-- EUI's bags, so whichever was clicked or opened last is in front.
--
-- The game only brings a window to the front of the other windows on its own
-- layer (frame strata). Ours used to be on a higher layer than the bags, so
-- Belongings and Supplies took turns in front of each other, but the bags were
-- always under both of them, and the config window was above everything. The
-- game's windows, like the character window, and EUI's bags (unless its Frame
-- Strata setting is changed) are on MEDIUM, so we put ours there too.
--
-- Clicking a window brings it to the front. Opening one doesn't, so each
-- window's open code calls Raise itself (also when it's already open). Popups
-- and menus that open from a window stay on their own higher layers, because
-- they belong in front of everything while they're open.
--
-- T.window(f, scale) also draws the window at scale(), its own Window scale
-- setting (the Ledger's and Belongings'), and T.rescaleWindows() applies it
-- again after the setting changed.
local scaled = setmetatable({}, { __mode = "k" })

local function scaleOf(get)
    local s = get and get()
    return (type(s) == "number" and s > 0) and s or 1
end

function T.window(f, scale)
    f:SetFrameStrata("MEDIUM")
    if f.SetToplevel then f:SetToplevel(true) end
    if scale then
        scaled[f] = scale
        f:SetScale(scaleOf(scale))
    end
end

-- A scale setting changed: each window whose scale is different now keeps
-- its top left corner where it was on screen, and saves where it is through
-- its own drag stop, since that's where every window keeps its place.
function T.rescaleWindows()
    for f, get in pairs(scaled) do
        local old, s = f:GetScale() or 1, scaleOf(get)
        if math.abs(old - s) > 0.001 then
            local l, t = f:GetLeft(), f:GetTop()
            f:SetScale(s)
            if l and t then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * old / s, t * old / s)
                local stop = f:GetScript("OnDragStop")
                if stop then stop(f) end
            end
        end
    end
end

-- Showing and hiding a widget on the game screen, like a card, a row of
-- icons or Buff Coordinator's HUD. It fades in and out over T.FADE_S, the same
-- quarter second the Combat HUD takes. Windows
-- the player opens don't use it.
--
-- T.appear(f) shows `f` and fades it in. It leaves a frame that is already
-- up alone, so a refresh that shows the flight card every 2 seconds doesn't
-- start the fade over. T.vanish(f, done) fades it out, hides it at the end
-- and then calls `done`, if given. While it fades out the frame is still
-- shown, so code that asks f:IsShown() still sees it, and an appear in that
-- time turns the fade around (and `done` never runs).
--
-- T.appear(f, x, y) also slides it in from x and y screen pixels away, and
-- T.vanish(f, done, x, y) slides it out that way. The Upgrades card comes in
-- from the side of the screen it is on, like a toast.
--
-- A widget that sets its own alpha, like one dimmed while nothing needs us,
-- sets it with T.setAlpha. Then the fade goes on top of that alpha rather
-- than overwriting it. T.setAlpha(f, alpha, seconds) glides to the new alpha
-- over that many seconds instead of jumping, like Buff Coordinator's HUD
-- going quiet when the last buff goes up.
--
-- A secure frame is hidden at once. The game doesn't let us hide it in
-- combat, and a fade out that ran into a pull would leave it invisible but
-- still clickable.
T.FADE_S = 0.25

local fading = {}   -- frame -> 1 while it fades in, -1 while it fades out
local after = {}    -- frame -> what to call once it has faded out
local gliding = {}  -- frame -> { from, to, t, seconds } while its own alpha glides
-- How far each frame is through its fade (0 to 1), its own alpha, and the
-- slide it plays. Weak, so a frame we faded once isn't kept.
local fadeK = setmetatable({}, { __mode = "k" })
local ownAlpha = setmetatable({}, { __mode = "k" })
local slides = setmetatable({}, { __mode = "k" })
local fader

local faded = {}  -- frames that finished fading out this step

local function fadeStep(_, elapsed)
    local step = elapsed / T.FADE_S
    for f, dir in pairs(fading) do
        local k = min(1, max(0, (fadeK[f] or 0) + dir * step))
        fadeK[f] = k
        f:SetAlpha((ownAlpha[f] or 1) * k)
        if k == 1 then
            fading[f] = nil
            fadeK[f] = nil
        elseif k == 0 then
            faded[#faded + 1] = f
        end
    end
    -- We hide them only after the loop. Hiding runs the frame's OnHide, and
    -- that or the `done` callback often fades another frame in or out. A new
    -- frame added to `fading` while we walk it breaks the walk ("invalid key
    -- to 'next'"), for example when Raid Buffs swaps one icon for another.
    --
    -- Until then a finished frame stays in `fading` at -1. So when an earlier
    -- frame's callback brings it back with T.appear, it turns around and fades
    -- in again rather than being hidden here.
    for i = 1, #faded do
        local f = faded[i]
        faded[i] = nil
        if fading[f] == -1 and fadeK[f] == 0 then
            fading[f] = nil
            fadeK[f] = nil
            f:Hide()
            -- A plain Show later finds it at its own alpha.
            f:SetAlpha(ownAlpha[f] or 1)
            local done = after[f]
            after[f] = nil
            if done then done() end
        end
    end
    for f, g in pairs(gliding) do
        g.t = g.t + elapsed
        local k = min(1, g.t / g.seconds)
        -- Eases in and out, so it doesn't start or stop with a jerk.
        local e = k * k * (3 - 2 * k)
        ownAlpha[f] = g.from + (g.to - g.from) * e
        f:SetAlpha(ownAlpha[f] * (fadeK[f] or 1))
        if k == 1 then gliding[f] = nil end
    end
    if not next(fading) and not next(gliding) then fader:SetScript("OnUpdate", nil) end
end

local function run()
    fader = fader or CreateFrame("Frame")
    fader:SetScript("OnUpdate", fadeStep)
end

local function fade(f, dir)
    fading[f] = dir
    run()
end

-- The slide is an animation group the client plays, so it costs us nothing
-- per frame. Its first step jumps the frame away at once and its second
-- brings it back, which is the only way a translation can start away from
-- where the frame is. Going out, it moves away and the frame hides as it
-- arrives.
local function slide(f, x, y, coming)
    local g = slides[f]
    if not g then
        g = f.CreateAnimationGroup and f:CreateAnimationGroup()
        if not g then return end
        g.jump = g:CreateAnimation("Translation")
        g.jump:SetOrder(1)
        g.jump:SetDuration(0)
        g.move = g:CreateAnimation("Translation")
        g.move:SetOrder(2)
        g.move:SetDuration(T.FADE_S)
        slides[f] = g
    end
    g:Stop()
    local p = T.pixel(f)
    if coming then
        g.jump:SetOffset(x * p, y * p)
        g.move:SetOffset(-x * p, -y * p)
        g.move:SetSmoothing("OUT")
    else
        g.jump:SetOffset(0, 0)
        g.move:SetOffset(x * p, y * p)
        g.move:SetSmoothing("IN")
    end
    g:Play()
end

function T.setAlpha(f, alpha, seconds)
    local g = gliding[f]
    if g and g.to == alpha then return end
    local now = ownAlpha[f] or 1
    if seconds and seconds > 0 and f:IsShown() and now ~= alpha then
        gliding[f] = { from = now, to = alpha, t = 0, seconds = seconds }
        run()
        return
    end
    gliding[f] = nil
    ownAlpha[f] = alpha
    f:SetAlpha(alpha * (fadeK[f] or 1))
end

function T.appear(f, x, y)
    after[f] = nil
    if f:IsShown() then
        -- Turned around on its way out. It fades back in where it is.
        if fading[f] == -1 then
            if slides[f] then slides[f]:Stop() end
            fade(f, 1)
        end
        return
    end
    fadeK[f] = 0
    f:SetAlpha(0)
    f:Show()
    if x or y then slide(f, x or 0, y or 0, true) end
    fade(f, 1)
end

function T.vanish(f, done, x, y)
    if not f:IsShown() then
        if done then done() end
        return
    end
    after[f] = done
    if fading[f] == -1 then return end
    if f:IsProtected() then
        fading[f], fadeK[f], after[f] = nil, nil, nil
        f:Hide()
        f:SetAlpha(ownAlpha[f] or 1)
        if done then done() end
        return
    end
    fadeK[f] = fadeK[f] or 1
    if x or y then slide(f, x or 0, y or 0, false) end
    fade(f, -1)
end

-- Ends every fade and glide now, as if its time had passed, and any fade that
-- starts once one has ended. For the tests, which have no frames to wait for.
function T.finishFades()
    for _ = 1, 10 do
        if not next(fading) and not next(gliding) then return end
        fadeStep(nil, math.huge)
    end
end

-- =============================================================
-- Controls
-- =============================================================

-- =============================================================
-- Making way
-- =============================================================
-- While we drag something along a list, the others slide aside so a gap
-- opens where it would land. Two layers:
--
--   T.glide moves one frame a part of the way to an offset from where it
--   rests, so it eases in over a few frames. T.unglide puts it back.
--
--   T.makeWay does a whole list: which place the mouse is at, and where
--   each of the others goes to make room there.
--
-- A frame's resting anchors are kept on its first glide. Every anchor moves
-- by the same offset, so a row hung from two corners keeps its width.
local function anchors(f)
    local t = {}
    for i = 1, (f.GetNumPoints and f:GetNumPoints() or 0) or 0 do
        local p = { f:GetPoint(i) }
        if p[1] then t[#t + 1] = p end
    end
    return t
end

-- Moves frame `f` a part `k` (0 to 1) of the way to (dx, dy) from where it
-- rests. Answers whether it's there.
function T.glide(f, dx, dy, k)
    local rest = f.glideRest
    if not rest then
        rest = anchors(f)
        f.glideRest, f.glideX, f.glideY = rest, 0, 0
    end
    if #rest == 0 then return true end
    local x = f.glideX + (dx - f.glideX) * (k or 1)
    local y = f.glideY + (dy - f.glideY) * (k or 1)
    if math.abs(dx - x) < 0.5 then x = dx end
    if math.abs(dy - y) < 0.5 then y = dy end
    f.glideX, f.glideY = x, y
    f:ClearAllPoints()
    for _, p in ipairs(rest) do f:SetPoint(p[1], p[2], p[3], (p[4] or 0) + x, (p[5] or 0) + y) end
    return x == dx and y == dy
end

-- Puts frame `f` back where it rests and forgets it.
function T.unglide(f)
    local rest = f.glideRest
    if not rest then return end
    f.glideRest, f.glideX, f.glideY = nil, nil, nil
    if #rest == 0 then return end
    f:ClearAllPoints()
    for _, p in ipairs(rest) do f:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
end

-- How fast the others slide: the part of the way they go in a second.
local GLIDE_RATE = 30

-- The part of the way a glide goes in a frame `elapsed` seconds long.
function T.glideStep(elapsed)
    return math.min(1, (elapsed or 0) * GLIDE_RATE)
end

local function cursorIn(f)
    local x, y = GetCursorPosition()
    local s = f:GetEffectiveScale()
    return x / s, y / s
end

-- Keeps where the mouse went down on frame `f`, for T.makeWay. The game
-- starts a drag only once the mouse has moved a few pixels, so a dragged
-- frame that went by the mouse at the drag's start would trail behind it
-- by those pixels.
function T.trackPress(f)
    f:HookScript("OnMouseDown", function(self)
        self.pressX, self.pressY = cursorIn(self)
    end)
    f:HookScript("OnMouseUp", function(self) self.pressX, self.pressY = nil, nil end)
end

-- While we drag in scroll frame `sf`, scrolls it slowly when the mouse is
-- near its top or bottom edge, so we can reach the rows out of view. The
-- closer to the edge (or past it), the faster. Call it from the drag's
-- OnUpdate, before way:update.
local EDGE, EDGE_SPEED = 28, 360   -- the edge's depth, and the most pixels a second

function T.edgeScroll(sf, elapsed)
    local range = sf.GetVerticalScrollRange and sf:GetVerticalScrollRange() or 0
    if range <= 0 then return end
    local top, bottom = sf:GetTop(), sf:GetBottom()
    if not (top and bottom) then return end
    local _, y = cursorIn(sf)
    local push = 0
    if y > top - EDGE then
        push = -math.min(1, (y - (top - EDGE)) / EDGE)
    elseif y < bottom + EDGE then
        push = math.min(1, ((bottom + EDGE) - y) / EDGE)
    end
    if push == 0 then return end
    local now = sf:GetVerticalScroll() or 0
    local v = math.min(range, math.max(0, now + push * EDGE_SPEED * (elapsed or 0)))
    if v == now then return end
    if sf.setScroll then sf:setScroll(v) else sf:SetVerticalScroll(v) end
end

-- A list we drag in. `opts`:
--   frames   the list's frames in order
--   from     the place of the one we drag, or nil when it comes from
--            outside the list (it's then put in)
--   axis     "y" for a list down the page (the default), "x" across
--   grid     true for frames that wrap in rows: each takes the spot of
--            the one at its new place, across rows too
--   gap      the room between two frames along the axis
--   extent   the room a frame from outside takes, gap included
--   center   true for a list centred in its parent, which grows from
--            both ends when a frame comes in
--   lift     true when the dragged frame follows the mouse itself. Else
--            the caller shows its own picture of it under the mouse, and
--            the dragged frame's place stays empty. A lifted frame should
--            have T.trackPress, so it stays where the mouse took it. Its
--            middle, not the mouse, says where it lands.
--   inside   a function that says whether the mouse is over the list.
--            When it isn't, nothing makes way and :stop() says nil.
--   scroll   the scroll frame the list is in, for a list down the page.
--            The rows move on screen when it scrolls during the drag (by
--            the wheel, or T.edgeScroll), so we go by where they are in
--            the list, not where they were on screen when the drag began.
--            That keeps the dragged frame under the mouse.
--
-- way:update(elapsed) works out the place and moves the frames a step, from
-- an OnUpdate. way:stop() puts every frame back and says the place, from 1
-- to one past the last, and the frame the dragged one goes before (nil for
-- the end). The place counts the frames as they were, the dragged one too.
function T.makeWay(opts)
    local frames, from = opts.frames, opts.from
    local axis = opts.axis or "y"
    local way = { at = nil }
    -- Where each frame rests, in its own coordinates, read once so the
    -- frames that move don't change the answer.
    -- A frame the game hasn't placed yet has no edges, and doesn't count.
    -- A list down the page needs only the tops and bottoms.
    local rects = {}
    for i, f in ipairs(frames) do
        local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
        if axis == "y" and not opts.grid then l, r = l or 0, r or 0 end
        if axis == "x" and not opts.grid then t, b = t or 0, b or 0 end
        if l and r and t and b then rects[i] = { l = l, r = r, t = t, b = b } end
    end
    local dragged = from and frames[from]
    local level = dragged and dragged:GetFrameLevel()
    if dragged and opts.lift then dragged:SetFrameLevel((level or 1) + 10) end
    local x0, y0
    if dragged then
        x0, y0 = cursorIn(dragged)
        x0, y0 = dragged.pressX or x0, dragged.pressY or y0
    end
    local q = from and rects[from]
    local lifted = dragged and opts.lift and q

    -- How far the list scrolled down since the drag began. The rows went up
    -- on screen by that much, so the mouse is that much lower in the list.
    local sf = opts.scroll
    local s0 = sf and sf:GetVerticalScroll() or 0
    local function mouse(f)
        local cx, cy = cursorIn(f)
        if sf then cy = cy - ((sf:GetVerticalScroll() or 0) - s0) end
        return cx, cy
    end

    -- How far the lifted frame is from where it rests: as far as the mouse
    -- moved, kept within the list unless `free`.
    local function lift(free)
        local cx, cy = mouse(dragged)
        if free then return cx - x0, cy - y0 end
        local lo, hi, bottom, top = q.l, q.l, q.t, q.t
        for _, o in pairs(rects) do
            lo, hi = math.min(lo, o.l), math.max(hi, o.l)
            bottom, top = math.min(bottom, o.t), math.max(top, o.t)
        end
        local dx, dy = 0, 0
        if opts.grid or axis == "x" then dx = math.max(lo - q.l, math.min(hi - q.l, cx - x0)) end
        if opts.grid or axis == "y" then dy = math.max(bottom - q.t, math.min(top - q.t, cy - y0)) end
        return dx, dy
    end

    -- The place the mouse is at, by the rest spots: the first frame past
    -- the mouse, or one past the last. A lifted frame goes by its middle.
    local function place()
        if opts.inside and not opts.inside() then return nil end
        local probe = dragged or frames[1]
        if not probe then return 1 end
        local cx, cy = mouse(probe)
        if lifted then
            local dx, dy = lift(true)
            if not opts.grid and axis == "y" then dx = 0 end
            if not opts.grid and axis == "x" then dy = 0 end
            cx, cy = (q.l + q.r) / 2 + dx, (q.t + q.b) / 2 + dy
        end
        for i = 1, #frames do
            local q = rects[i]
            if i ~= from and q then
                if opts.grid then
                    if cy > q.t or (cy >= q.b and cx < (q.l + q.r) / 2) then return i end
                elseif axis == "x" then
                    if cx < (q.l + q.r) / 2 then return i end
                else
                    if cy > (q.t + q.b) / 2 then return i end
                end
            end
        end
        return #frames + 1
    end

    -- How far frame `i` moves to make way at place `at`.
    local function offset(i, at)
        if not at then return 0, 0 end
        if opts.grid then
            local order = {}
            for j = 1, #frames do
                if j ~= from then order[#order + 1] = j end
            end
            local to = at
            if from and at > from then to = at - 1 end
            table.insert(order, math.min(to, #order + 1), from or 0)
            for j, k in ipairs(order) do
                if k == i then
                    local a, b = rects[i], rects[j]
                    if not (a and b) then return 0, 0 end
                    return b.l - a.l, b.t - a.t
                end
            end
            return 0, 0
        end
        local d
        if from then
            local q = rects[from]
            if not q then return 0, 0 end
            d = (axis == "x" and q.r - q.l or q.t - q.b) + (opts.gap or 0)
        else
            d = opts.extent or 0
        end
        local shift = 0
        if from then
            if at < from and i >= at and i < from then shift = d end
            if at > from + 1 and i > from and i < at then shift = -d end
        elseif opts.center then
            shift = i >= at and d / 2 or -d / 2
        elseif i >= at then
            shift = d
        end
        if axis == "x" then return shift, 0 end
        return 0, -shift
    end

    function way:update(elapsed)
        local at = place()
        self.at = at
        local k = T.glideStep(elapsed)
        for i, f in ipairs(frames) do
            if i ~= from then
                local dx, dy = offset(i, at)
                T.glide(f, dx, dy, k)
            end
        end
        -- The dragged one under the mouse, kept within the list.
        if lifted then
            local dx, dy = lift()
            T.glide(dragged, dx, dy, 1)
        end
        return at
    end

    function way:stop()
        local at = place()
        for _, f in ipairs(frames) do T.unglide(f) end
        if dragged and opts.lift and level then dragged:SetFrameLevel(level) end
        if not at then return nil end
        local before
        if at == from then
            before = frames[from + 1]
        else
            before = frames[at]
        end
        return at, before
    end

    return way
end

-- The four-way move arrow under the mouse over something we can drag, like
-- a row to reorder. It stays while the drag goes on, so the arrow travels
-- with what we carry, and goes back to the pointer when the button is up
-- and the mouse is off it.
--
-- While the mouse is over the frame we ask `ok` again each frame. A Gear
-- Sets row drags only from its icon and name side, so the arrow has to go
-- when the mouse moves on to its Wear button side.
--
-- SetCursor takes the cursor by name. We try it, since a client that
-- doesn't know the name errors.
local MOVE_CURSOR = "UI_MOVE_CURSOR"
local cursorOwner, cursorOk, cursorOn, cursorWatch

local function showArrow(on)
    if on == cursorOn then return end
    if on then
        cursorOn = SetCursor ~= nil and pcall(SetCursor, MOVE_CURSOR) and true or false
    else
        cursorOn = false
        if ResetCursor then ResetCursor() end
    end
end

local function watchCursor()
    if cursorWatch then return cursorWatch end
    cursorWatch = CreateFrame("Frame")
    cursorWatch:Hide()
    cursorWatch:SetScript("OnUpdate", function(self)
        local f = cursorOwner
        local down = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
        -- During a press or a drag the arrow stays as it is.
        if down then return end
        if f and f:IsVisible() and f:IsMouseOver() then
            showArrow(not cursorOk or cursorOk(f) and true or false)
            return
        end
        showArrow(false)
        cursorOwner, cursorOk = nil, nil
        self:Hide()
    end)
    return cursorWatch
end

-- Gives frame `f` the move arrow. `ok`, when given, says whether it can be
-- dragged now, from where the mouse is.
function T.dragCursor(f, ok)
    f:HookScript("OnEnter", function(self)
        if cursorOwner ~= self then
            showArrow(false)
        end
        cursorOwner, cursorOk = self, ok
        showArrow(not ok or ok(self) and true or false)
        watchCursor():Show()
    end)
end

-- The button that puts a changed value back to its default, shown beside the
-- mark. It starts hidden. `enter` and `leave` run after its own hover look,
-- for a tooltip. Without `enter` its tooltip says "Back to the default".
function T.revert(parent, onClick, enter, leave)
    local b = CreateFrame("Button", nil, parent)
    local s = T.CONTROL.revert
    b:SetSize(s, s)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    -- Our own arrow (bayovui/build/glyphs.py), in white so we can tint it.
    b.icon:SetTexture(MEDIA .. "Reset")
    b.icon:SetVertexColor(1, 1, 1, 0.55)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 1)
        if enter then enter(self) else T.tip(self, "Back to the default") end
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(1, 1, 1, 0.55)
        if leave then leave(self) elseif not enter and GameTooltip then GameTooltip:Hide() end
    end)
    b:Hide()
    return b
end

-- A flat button: dark fill, faint border, dim text that brightens on hover.
-- An `accent` one is the view's main action, and there's at most one of those
-- in sight. The text goes through the button's own SetText and GetText, so a
-- caller treats it like any other button. `b:SetText` sizes it to its words
-- unless it was given a width. `b:setAccent(on)` makes it the main action or
-- a plain one, and `b:setTint(color)` paints the main action in another
-- colour than the accent (nil for the accent again).
--
-- `h = "compact"` is the small one for a header or a bar, in place of the
-- local boxed buttons windows drew: 22 high, 12 bold, sized to its words
-- unless given a width. `b.compact` says it is one.
T.CONTROL.buttonCompact = { h = 22, size = 12 }

-- How tall a control is on a window's header row. The header is
-- WindowKit's HEAD_H (28). A 20 high button already looked like it sat on
-- the header's bottom line, so at 18 it keeps 5 px above and below, on the
-- same middle as the title, the cog and the close. The kit marks its header band (and a standard footer) with `rowBand`, and a compact
-- button, a search box, a dropdown or segments made straight on it take this
-- height when the caller gives none.
T.CONTROL.head = 18

-- The height for a control made on `parent`: the header row's when parent is
-- a header band or a standard footer (WindowKit marks both), or `h` anywhere
-- else.
function T.controlH(parent, h)
    if type(parent) == "table" and parent.rowBand then return T.CONTROL.head end
    return h
end

function T.button(parent, label, w, h, accent)
    local size = T.CONTROL.button
    local compact = h == "compact"
    if compact then size, h = T.CONTROL.buttonCompact, T.controlH(parent, T.CONTROL.buttonCompact.h) end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or size.w or 60, h or size.h)
    b.fixed = w ~= nil
    b.compact = compact
    b.bg = T.fill(b, { 1, 1, 1 }, 1)
    b.bg:SetAllPoints(b)
    T.border(b, { 1, 1, 1 }, 0.16)
    b.label = T.text(b, size.size, true, 0.78)
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label:SetJustifyH("CENTER")

    -- The fill is painted from the accent each time, so a button follows a
    -- new accent the next time it's drawn.
    local function look(self, hover)
        local on = self:IsEnabled()
        local accent = self.accent
        local c = self.tint or T.ACCENT
        -- An addon that sets T.PLAIN_WHEN_OFF draws a main action that can't
        -- run as a plain one, so it doesn't look ready to click.
        if accent and not on and T.PLAIN_WHEN_OFF then accent = false end
        if accent then
            self.bg:SetColorTexture(c[1], c[2], c[3], 0.22)
        else
            self.bg:SetColorTexture(0.10, 0.11, 0.13, 0.85)
        end
        T.paint(self, accent and c or { 1, 1, 1 }, not on and 0.06
                                                          or hover and (accent and 0.9 or 0.32)
                                                          or (accent and 0.55 or 0.16))
        self.label:SetTextColor(1, 1, 1, not on and T.A_OFF or hover and 1 or 0.78)
    end
    b.look = look

    function b:SetText(t)
        self.label:SetText(t or "")
        if not self.fixed then self:SetWidth(math.ceil(self.label:GetStringWidth() or 40) + 22) end
    end
    function b:GetText() return self.label:GetText() end
    function b:setAccent(on)
        self.accent = on and true or false
        look(self, false)
    end
    function b:setTint(color)
        if self.tint == color then return end
        self.tint = color
        look(self, false)
    end

    b:SetScript("OnEnter", function(self)
        look(self, true)
        if self.tip then self.tip(self) end
    end)
    b:SetScript("OnLeave", function(self)
        look(self, false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnEnable", function(self) look(self, false) end)
    b:SetScript("OnDisable", function(self) look(self, false) end)
    b.accent = accent and true or false
    b:SetText(label)
    look(b, false)
    return b
end

-- A CSS cubic-bezier(x1, y1, x2, y2) as a function of progress 0 to 1, so
-- motion eases the way the mockups did. T.EASE_SLIDE is the tabs' and sidebars' slide and
-- fade, T.EASE_IN_OUT the loading bar's pass.
function T.cubicBezier(x1, y1, x2, y2)
    local function at(t, a, b)
        local u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    end
    return function(p)
        if p <= 0 then return 0 elseif p >= 1 then return 1 end
        local lo, hi = 0, 1
        for _ = 1, 18 do
            local mid = (lo + hi) / 2
            if at(mid, x1, x2) < p then lo = mid else hi = mid end
        end
        return at((lo + hi) / 2, y1, y2)
    end
end
T.EASE_OUT = T.cubicBezier(0.2, 0.8, 0.2, 1)
T.EASE_IN_OUT = T.cubicBezier(0.45, 0, 0.55, 1)
T.EASE_SLIDE = T.cubicBezier(0.65, 0, 0.35, 1)

-- The motion the header tabs' line and the sidebars' mark share (T.tabLine,
-- T.sideMark): one mark per row of items (tabs, or a list's rows), made on
-- the row's frame (`host`), under the picked item. When the pick changes
-- while the row is on show, it slides from the old item to the new one in
-- `slide` (0.22) s, easing in and out (T.EASE_SLIDE): the leading edge moves
-- at once and the trailing edge `lag` (45%) of that later, so it stretches
-- toward the new item and then shrinks. When the row opens, lays out,
-- scrolls or resizes, the mark just sits on the picked item: it's anchored
-- to that item. Its OnUpdate runs only while it moves.
--
--   L:to(item, key)  the mark goes to that item, sliding when it can. `key`
--                    is what's picked (the item when not given): a list that
--                    reuses its rows as it scrolls passes the record, and the
--                    mark slides only when that changes.
--   L:off(item)      that item is no longer picked
--   L:snap()         puts it on the picked item at once
--   L.cur            the item it's on; L.x, L.w where it's drawn along the
--                    row, from L.cur's start
--
-- A look says how a mark is drawn:
--   look.span(item)        where it sits on `item` at rest: start and length
--   look.offset(from, to)  how far `from` starts past `to` along the row, or
--                          nil while the game can't say
--   look.draw(L, item, x, w), look.show(L, on)
--   look.sameFrame         an item that went off counts as where the mark was
--                          only in the same frame (a pick unlights the old one
--                          and lights the new one together; a list that
--                          scrolled its pick away doesn't slide from there)
T.TAB_LINE = { h = 2, glow = 0.11, glowOut = 7, glowIn = 9, slide = 0.22, lag = 0.45, fade = 0.22,
               settle = 0.1 }
-- A header tab's words and icon: dim, under the mouse, picked, turned off.
local TAB_ALPHA = { off = 0.55, hover = 0.85, on = 1, disabled = 0.30 }
T.TAB_ALPHA = TAB_ALPHA

local slideStep

local function slideRun(L)
    L.drive:SetScript("OnUpdate", slideStep)
end

local function slideMark(host, field, look)
    local S = T.TAB_LINE
    local L = { host = host, fades = {}, look = look }
    host[field] = L
    L.drive = CreateFrame("Frame", nil, host)
    L.drive.line = L

    -- A hidden row stops moving, and a pick in the moment it shows again
    -- (`settle`) doesn't slide: a window that opens on another page has its
    -- mark there.
    if host.HookScript then
        host:HookScript("OnHide", function()
            if L.anim or next(L.fades) then
                L.anim = nil
                for item, f in pairs(L.fades) do item:fadeTo(f.to) end
                L.fades = {}
                L.drive:SetScript("OnUpdate", nil)
                L:snap()
            end
        end)
        host:HookScript("OnShow", function() L.shownAt = GetTime() end)
        host:HookScript("OnSizeChanged", function() L:snap() end)
    end

    -- Whether a pick from `from` to `item` slides, and from how far: both on
    -- show in a row that's been on show a moment, and both where the game
    -- can say.
    local function canSlide(from, item)
        if not from or from == item or not host:IsVisible() or not from:IsShown() then return nil end
        if L.shownAt and GetTime() - L.shownAt < S.settle then return nil end
        return look.offset(from, item)
    end

    function L:to(item, key)
        if key == nil then key = item end
        if self.cur == item and self.key == key and self.anim then return end
        local from = self.cur
        if not from and (not look.sameFrame or self.lastAt == GetTime()) then from = self.last end
        local moved = key ~= self.key
        self.cur, self.last, self.key = item, nil, key
        local d = moved and canSlide(from, item)
        if not d then
            self.anim = nil
            return self:snap()
        end
        -- Where the mark is now, from the new item's start: mid-slide, where
        -- it was drawn.
        local x0, w0
        if self.at == from and self.x then
            x0, w0 = d + self.x, self.w
        else
            local fx, fw = look.span(from)
            x0, w0 = d + (fx or 0), fw or 0
        end
        self.anim = { t = 0, l0 = x0, r0 = x0 + w0 }
        look.draw(self, item, x0, w0)
        -- The old tab, already unlit, dims with the slide rather than at once.
        if not from.on and from.fadeTo and from.alpha == from:alphaNow() then
            from:fadeTo(TAB_ALPHA.on)
            self:fade(from, TAB_ALPHA.on, from:alphaNow())
        end
        slideRun(self)
        return true
    end

    function L:off(item)
        if self.cur ~= item then return end
        self.cur, self.last, self.lastAt = nil, item, GetTime()
        if self.anim then return end
        -- A list unlights the old row and lights the new one in either
        -- order, so its mark goes on the next frame, when nothing took it:
        -- never hidden and shown again in one click.
        if look.sameFrame then return slideRun(self) end
        look.show(self, false)
    end

    function L:snap()
        self.anim = nil
        local item = self.cur
        if not item then return look.show(self, false) end
        local x, w = look.span(item)
        if not x then return look.show(self, false) end
        look.draw(self, item, x, w)
    end

    -- A tab's words and icon fading to `to`.
    function L:fade(item, from, to)
        self.fades[item] = { t = 0, from = from, to = to }
        slideRun(self)
    end
    return L
end

-- One frame of a mark's slide and the tabs' fades. It stops itself once
-- nothing moves.
slideStep = function(drive, elapsed)
    local L, S = drive.line, T.TAB_LINE
    local look = L.look
    local moving = false
    local a = L.anim
    if a and L.cur then
        a.t = a.t + (elapsed or 0)
        local item = L.cur
        local x1, w1 = look.span(item)
        local l1, r1 = x1 or 0, (x1 or 0) + (w1 or 0)
        local lag = S.slide * S.lag
        -- Going right (or down), the far edge leads and the near one follows.
        local right = l1 > a.l0
        local function edge(from, to, late)
            local p = (a.t - (late and lag or 0)) / S.slide
            return from + (to - from) * T.EASE_SLIDE(min(1, max(0, p)))
        end
        if a.t >= S.slide + lag then
            L:snap()
        else
            local l = edge(a.l0, l1, right)
            local r = edge(a.r0, r1, not right)
            look.draw(L, item, l, r - l)
            moving = true
        end
    elseif a then
        L.anim = nil
        look.show(L, false)
    elseif not L.cur then
        look.show(L, false)
    end
    for item, f in pairs(L.fades) do
        f.t = f.t + (elapsed or 0)
        local p = min(1, f.t / S.fade)
        item:fadeTo(f.from + (f.to - f.from) * T.EASE_SLIDE(p))
        if p >= 1 then L.fades[item] = nil else moving = true end
    end
    if not moving then drive:SetScript("OnUpdate", nil) end
end

-- The accent line under the picked tab of a row of header tabs (T.tab's
-- header look, T.tabStrip, the config window's strip). One line per row,
-- made on the row's frame (`host`) the first time a tab there lights, so the
-- header tabs and every strip share this one piece.
--
-- It's 2 high on the row's bottom edge, the accent, as wide as the picked
-- tab's words (or icon) plus `lineOut` each side, with a soft accent glow
-- round it (Media/LineGlow.tga, three slices). It slides as above, and the
-- two tabs' words fade between dim and bright over `fade` s. A tab's words
-- that change put it under them at once.
--
--   L = T.tabLine(host)  the row's line (made once, host.tabLine)
local function tabLineDraw(L, tab, x, w)
    local line = L.line
    line:ClearAllPoints()
    line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", x, 0)
    line:SetWidth(max(1, w))
    L.x, L.w, L.at = x, w, tab
    local c = T.ACCENT
    line:SetColorTexture(c[1], c[2], c[3], 1)
    for i, g in ipairs(L.glows) do
        g:SetVertexColor(c[1], c[2], c[3], T.TAB_LINE.glow)
        g:SetShown(i ~= 2 or w > 2 * T.TAB_LINE.glowIn)
    end
    line:Show()
end

local function tabLineShow(L, on)
    L.line:SetShown(on)
    for _, g in ipairs(L.glows) do g:SetShown(on) end
end

local TAB_LOOK = {
    span = function(tab) return tab.barX, tab.barW end,
    offset = function(from, tab)
        local fl, tl = from:GetLeft(), tab:GetLeft()
        if fl and tl then return fl - tl end
    end,
    draw = tabLineDraw,
    show = tabLineShow,
}

function T.tabLine(host)
    if host.tabLine then return host.tabLine end
    local S = T.TAB_LINE
    local L = slideMark(host, "tabLine", TAB_LOOK)
    L.line = host:CreateTexture(nil, "OVERLAY")
    L.line:SetHeight(S.h)
    L.line:Hide()
    -- The glow: the left end, the middle stretched along the line, the right end.
    local tall, cap = S.h + 2 * S.glowOut, S.glowOut + S.glowIn
    L.glows = {}
    for i, coords in ipairs({ { 0, 0.5 }, { 0.49, 0.51 }, { 0.5, 1 } }) do
        local g = host:CreateTexture(nil, "ARTWORK")
        g:SetTexture(T.media("LineGlow"))
        g:SetTexCoord(coords[1], coords[2], 0, 1)
        if g.SetBlendMode then g:SetBlendMode("ADD") end
        g:SetHeight(tall)
        g:Hide()
        L.glows[i] = g
    end
    local gl, gm, gr = L.glows[1], L.glows[2], L.glows[3]
    gl:SetWidth(cap)
    gr:SetWidth(cap)
    gl:SetPoint("LEFT", L.line, "LEFT", -S.glowOut, 0)
    gr:SetPoint("RIGHT", L.line, "RIGHT", S.glowOut, 0)
    gm:SetPoint("TOPLEFT", gl, "TOPRIGHT", 0, 0)
    gm:SetPoint("BOTTOMRIGHT", gr, "BOTTOMLEFT", 0, 0)
    return L
end

-- The picked row of a sidebar, or of any list down a window's left: the
-- tabs' line turned on its side. An accent wash over the whole row, fading
-- from `wash` (.24) at its left to nothing at its right, and a `bar` (3) px
-- accent bar down its left edge. One mark per list, made on the frame its
-- rows sit in (`host`, the scroll child in a scrolling list, so the mark
-- scrolls with its row and is cut off where the rows are), and it slides
-- from row to row the way the tabs' line does: the edge in the way it goes
-- first, the other 45% later. It sits on the row it's on through a scroll,
-- a layout or a resize, and it hides while that row does.
--
--   M = T.sideMark(host)              the list's mark (made once, host.sideMark).
--                                     An unpicked row's mark goes on the next
--                                     frame, unless another row took it.
--   T.sidePick(row, on, key, host)    lights or unlights `row` (on its
--                                     parent's mark when `host` isn't given).
--                                     `key` is the record a reused row shows.
--
-- A card list keeps its own look: this is for rows.
T.SIDE_MARK = { wash = 0.24, bar = 3 }

local function sideShow(M, on)
    M.wash:SetShown(on)
    M.bar:SetShown(on)
end

local function sideDraw(M, row, y, h)
    local wash = M.wash
    wash:ClearAllPoints()
    wash:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -y)
    wash:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -y)
    wash:SetHeight(max(1, h))
    M.x, M.w, M.at = y, h, row
    local c = T.ACCENT
    T.fade(wash, c, T.SIDE_MARK.wash, 0)
    M.bar:SetColorTexture(c[1], c[2], c[3], 1)
    -- The mark hides with its row (a folded heading, a search, a row the
    -- list isn't using), and comes back with it.
    if not row.sideMarkHooked and row.HookScript then
        row.sideMarkHooked = true
        row:HookScript("OnHide", function(self)
            if M.at == self then sideShow(M, false) end
        end)
        row:HookScript("OnShow", function(self)
            if M.cur == self then M:snap() end
        end)
    end
    sideShow(M, row:IsShown() and true or false)
end

local SIDE_LOOK = {
    span = function(row) return 0, row:GetHeight() or 0 end,
    offset = function(from, row)
        local ft, rt = from:GetTop(), row:GetTop()
        if ft and rt then return rt - ft end
    end,
    draw = sideDraw,
    show = sideShow,
    sameFrame = true,
}

function T.sideMark(host)
    if host.sideMark then return host.sideMark end
    local M = slideMark(host, "sideMark", SIDE_LOOK)
    M.wash = host:CreateTexture(nil, "BACKGROUND")
    M.bar = host:CreateTexture(nil, "ARTWORK")
    M.bar:SetWidth(T.SIDE_MARK.bar)
    M.bar:SetPoint("TOPLEFT", M.wash, "TOPLEFT", 0, 0)
    M.bar:SetPoint("BOTTOMLEFT", M.wash, "BOTTOMLEFT", 0, 0)
    sideShow(M, false)
    return M
end

function T.sidePick(row, on, key, host)
    host = host or row:GetParent()
    if not host then return nil end
    local M = T.sideMark(host)
    if on then M:to(row, key) else M:off(row) end
    return M
end

-- Puts a row's line under its picked tab again, after the row laid its tabs
-- out. Nothing when no tab there has lit yet.
function T.snapTabLine(host)
    local L = host and host.tabLine
    if L and not L.anim then L:snap() end
end

-- A tab in a window's header. Regular text at .55, .85 under the mouse and 1
-- when chosen, at the window title's size and on its middle. A tab has no
-- fill of its own, chosen or not, and no gradient. The chosen one shows by
-- the row's one accent line (T.tabLine): 2 high on the row's bottom edge,
-- with a soft glow, as wide as its words (or its icon, and the icon and words
-- together) plus `lineOut` (4) on each side, and it slides when the pick
-- changes. It is the header's full height and tabs sit flush, `pad` (8) each
-- side, so the words of two tabs are 16 apart.
--
-- `opts.icon` puts a 14 px icon before the words (`opts.plain` leaves the
-- icon's black edge off, for a white glyph, which shows whole at 16), about
-- the title icon's size.
-- With no words it's an icon-only tab, 30 wide (16 between two icons). Badges: `tab:setBadge(true)` is an orange dot for something
-- to do, `tab:setBadge(n)` a small dim count after the words (a string,
-- like "3/18", shows as it is), and
-- `tab:setChanged(on)` the changed mark.
local HEAD_TAB = { pad = 8, iconGap = 6, icon = 14, iconOnly = 30, lineOut = 4,
                   count = 11, countGap = 5, markGap = 4 }
-- A plain icon is a white glyph of our own, like Social's tabs. It has no
-- bezel, and its round strokes reach close to its edges, so we show it whole
-- instead of cropped like a game icon (the crop cut the sides off the Chats
-- bubble and the Recent allies clock). Whole, the art is smaller in its box,
-- so its box is the title icon's 16 and it looks the same size as that icon.
HEAD_TAB.glyph = 16
T.HEAD_TAB = HEAD_TAB
local function headTab(parent, label, h, opts)
    local S = HEAD_TAB
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(h or 35)
    b.head = true
    if opts.icon then
        b.icon = T.icon(b, opts.icon, opts.plain and S.glyph or S.icon, opts.plain)
        if opts.plain then
            b.icon.whole = true
            b.icon:SetTexCoord(0, 1, 0, 1)
        end
    end
    b.label = T.text(b, T.SIZE.body, false, TAB_ALPHA.off)
    b.label:SetWordWrap(false)
    b.count = T.text(b, S.count, true, T.A_DIM)
    b.count:Hide()
    b.mark = T.markDot(b)
    b.dot = T.fill(b, T.ORANGE, 1, "OVERLAY")
    b.dot:SetSize(6, 6)
    b.dot:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -10)
    b.dot:Hide()

    -- Where the row's accent line goes under this tab: under the icon and the
    -- words, which are `w` wide from `x`, reaching lineOut past them on each
    -- side. A picked tab whose words changed puts the line there at once.
    local function underline(self, x, w)
        x, w = x - S.lineOut, w + 2 * S.lineOut
        self.barX, self.barW = x, w
        local L = self.on and parent.tabLine
        if L and L.cur == self and not L.anim then L:snap() end
    end

    -- Lays out the icon, the words and the badges from the left, and sizes
    -- the tab to them.
    function b:layout()
        local text = self.label:GetText() or ""
        local words = text ~= ""
        self.label:SetShown(words)
        if self.icon and not words then
            self.icon:ClearAllPoints()
            self.icon:SetPoint("CENTER", self, "CENTER", 0, 0)
            self:SetWidth(S.iconOnly)
            underline(self, (S.iconOnly - S.icon) / 2, S.icon)
            return
        end
        local x = S.pad
        if self.icon then
            self.icon:ClearAllPoints()
            self.icon:SetPoint("CENTER", self, "LEFT", x + S.icon / 2, 0)
            x = x + S.icon + S.iconGap
        end
        -- On the title's middle: the kit's title sits at the header's
        -- middle with no lift.
        self.label:ClearAllPoints()
        self.label:SetPoint("LEFT", self, "LEFT", x, 0)
        x = x + floor((self.label:GetStringWidth() or 0) + 0.5)
        local lineEnd = x
        if self.count:IsShown() then
            self.count:ClearAllPoints()
            self.count:SetPoint("LEFT", self.label, "RIGHT", S.countGap, 0)
            x = x + S.countGap + floor((self.count:GetStringWidth() or 0) + 0.5)
        end
        -- The mark sits on the words' middle, and the line under a picked
        -- tab reaches past it too.
        if self.mark:IsShown() then
            self.mark:ClearAllPoints()
            self.mark:SetPoint("LEFT", self, "LEFT", x + S.markGap, 0)
            x = x + S.markGap + T.MARK_DOT
            lineEnd = x
        end
        underline(self, S.pad, lineEnd - S.pad)
        self:SetWidth(x + S.pad)
    end

    function b:alphaNow()
        local enabled = not self.IsEnabled or self:IsEnabled()
        return not enabled and TAB_ALPHA.disabled or self.on and TAB_ALPHA.on
               or self.over and TAB_ALPHA.hover or TAB_ALPHA.off
    end
    function b:fadeTo(a)
        self.alpha = a
        self.label:SetTextColor(1, 1, 1, a)
        if self.icon then self.icon:SetAlpha(a) end
    end
    -- `slow` fades the words to their alpha (a pick that slides), rather
    -- than setting it at once (the mouse, a pick that doesn't).
    function b:paint(slow)
        local a = self:alphaNow()
        local L = parent.tabLine
        if slow and L and self.alpha and self.alpha ~= a then return L:fade(self, self.alpha, a) end
        if L then L.fades[self] = nil end
        self:fadeTo(a)
    end
    function b:light(on)
        on = on and true or false
        local was = self.on
        self.on = on
        local L = T.tabLine(parent)
        if on then L:to(self) else L:off(self) end
        self:paint(was ~= on and L.anim ~= nil)
    end
    -- true: the orange dot. A number: the count after the words (none at 0).
    -- A string: that, in the count's place. false or nil: neither.
    function b:setBadge(v)
        self.dot:SetShown(v == true)
        local n = type(v) == "number" and v > 0 and tostring(v)
                  or type(v) == "string" and v ~= "" and v or nil
        self.count:SetText(n or "")
        self.count:SetShown(n ~= nil)
        self.badge = v
        self:layout()
    end
    function b:setChanged(on)
        self.mark:SetShown(on and true or false)
        self:layout()
    end
    function b:SetText(t)
        self.label:SetText(t or "")
        self:layout()
    end
    function b:GetText() return self.label:GetText() end

    b:SetScript("OnEnter", function(self)
        self.over = true
        self:paint()
    end)
    b:SetScript("OnLeave", function(self)
        self.over = false
        self:paint()
    end)
    b:SetScript("OnEnable", function(self) self:paint() end)
    b:SetScript("OnDisable", function(self) self:paint() end)
    b.label:SetText(label or "")
    b:layout()
    b:paint()
    return b
end

-- A page's tab: its name, dim until it's the one on show, which is white with
-- an accent line under it. `opts.head` makes the header's tab instead (above).
function T.tab(parent, label, h, opts)
    if opts and opts.head then return headTab(parent, label, h, opts) end
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(h or 24)
    b.label = T.text(b, T.SIZE.tab, true, T.A_DIM)
    b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
    b.label:SetText(label)
    b.line = T.fill(b, T.ACCENT, 1, "ARTWORK")
    b.line:SetHeight(2)
    b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 6, 0)
    b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 0)
    b.line:Hide()
    b:SetWidth(floor((b.label:GetStringWidth() or 40) + 24))
    T.tabMark(b, 24)
    function b:light(on)
        self.on = on
        self.line:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 1)
        self.line:SetShown(on and true or false)
        self.label:SetTextColor(1, 1, 1, on and 1 or T.A_DIM)
    end
    b:SetScript("OnEnter", function(self)
        if not self.on then self.label:SetTextColor(1, 1, 1, 0.85) end
    end)
    b:SetScript("OnLeave", function(self)
        self.label:SetTextColor(1, 1, 1, self.on and 1 or T.A_DIM)
    end)
    return b
end

-- A strip of tabs in a window's body, for pages under the header, like the
-- Training window's Overview and Talent Plan. The tabs are T.tab's header
-- tabs, flush from the left on a faint line, the look of the config window's
-- strip.
--
--   s = T.tabStrip(parent, { { key = "sets", label = "Sets", icon, plain, tip }, ... },
--                  { pick = function(key) end, h = 30, key = "sets" })
--   s:select(key, quiet)   lights that tab and calls pick, or only lights it
--                          when quiet; false for a key it has no tab for
--   s.key                  the tab lit; s.tabs in order, s.byKey by key
--   s:setTabs(list)        the tabs it has now, in the same format: a key it
--                          had keeps its tab, a key that's gone hides
--   s:setBadge(key, v), s:setChanged(key, on)   a tab's badges (T.tab)
--
-- An item's `tip` is a string, or a function(tab) that shows the tooltip.
-- The strip is as wide as its tabs. With `opts.wide` the caller sets its
-- width, so its line runs the whole width, and `opts.inset` starts the tabs
-- that far in from its left edge.
T.TAB_STRIP = { h = 30, rule = 0.07 }
function T.tabStrip(parent, items, opts)
    opts = opts or {}
    local S = T.TAB_STRIP
    local h = opts.h or S.h
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(h)
    s.rule = T.fill(s, { 1, 1, 1 }, S.rule, "BACKGROUND")
    s.rule:SetHeight(1)
    s.rule:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0)
    s.rule:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
    s.tabs, s.byKey = {}, {}
    local made = {}

    local function make(it, key)
        local b = T.tab(s, it.label, h, { head = true, icon = it.icon, plain = it.plain })
        b.key = key
        b:SetScript("OnClick", function(self) s:select(self.key) end)
        b:HookScript("OnEnter", function(self)
            local tip = self.item and self.item.tip
            if type(tip) == "function" then
                tip(self)
            elseif tip then
                local label = self.item.label
                T.tip(self, label or tip, label and { tip } or nil)
            end
        end)
        b:HookScript("OnLeave", function(self)
            if self.item and self.item.tip and _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        made[key] = b
        return b
    end

    function s:layout()
        local x = opts.inset or 0
        for _, b in ipairs(self.tabs) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
            x = x + (b:GetWidth() or 0)
        end
        if not opts.wide then self:SetWidth(x) end
        T.snapTabLine(self)
        return x
    end

    function s:setTabs(list)
        for _, b in ipairs(self.tabs) do b:Hide() end
        self.tabs, self.byKey = {}, {}
        for i, it in ipairs(list or {}) do
            local key = it.key == nil and i or it.key
            local b = made[key]
            if b then
                if it.icon and b.icon and b.icon.SetTexture then b.icon:SetTexture(it.icon) end
                if (it.label or "") ~= (b:GetText() or "") then b:SetText(it.label) end
            else
                b = make(it, key)
            end
            b.item = it
            b:Show()
            self.tabs[i], self.byKey[key] = b, b
        end
        if self.key ~= nil and not self.byKey[self.key] then self.key = nil end
        for _, b in ipairs(self.tabs) do b:light(b.key == self.key) end
        self:layout()
    end

    function s:select(key, quiet)
        if not self.byKey[key] then return false end
        self.key = key
        for _, b in ipairs(self.tabs) do b:light(b.key == key) end
        local pick = self.pick or opts.pick
        if not quiet and pick then pick(key) end
        return true
    end

    function s:setBadge(key, v)
        local b = self.byKey[key]
        if not b then return end
        b:setBadge(v)
        self:layout()
    end

    function s:setChanged(key, on)
        local b = self.byKey[key]
        if not b then return end
        b:setChanged(on)
        self:layout()
    end

    s:setTabs(items)
    if opts.key ~= nil then s:select(opts.key, true) end
    return s
end

-- A switch, EUI's toggle: a track that fills with the accent when on, and a
-- square knob that slides to the side it is on. `toggle:show(on, enabled)`
-- paints it. The slide is a short ease rather than a jump.
function T.toggle(parent)
    local size = T.CONTROL.toggle
    local W, KNOB = size.w, size.knob
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(W, size.h)
    c.track = T.fill(c, { 1, 1, 1 }, 1, "BACKGROUND")
    c.track:SetAllPoints(c)
    T.border(c, { 1, 1, 1 }, 0.10)
    c.knob = c:CreateTexture(nil, "ARTWORK")
    c.knob:SetSize(KNOB, KNOB)
    c.knob:SetColorTexture(1, 1, 1, 1)
    c.x = 3

    local travel = W - KNOB - 6
    local function place(self, x)
        self.x = x
        self.knob:ClearAllPoints()
        self.knob:SetPoint("LEFT", self, "LEFT", x, 0)
    end
    place(c, 3)

    local function onUpdate(self, elapsed)
        local goal = self.goal or 3
        local step = (elapsed or 0.016) * 220
        if math.abs(goal - self.x) <= step then
            place(self, goal)
            self:SetScript("OnUpdate", nil)
        else
            place(self, self.x + (goal > self.x and step or -step))
        end
    end

    function c:show(on, enabled)
        self:SetChecked(on and true or false)
        if enabled then self:Enable() else self:Disable() end
        local a = enabled and 1 or 0.35
        if on then
            self.track:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3],
                                       0.80 * a)
            self.knob:SetColorTexture(1, 1, 1, a)
        else
            self.track:SetColorTexture(0.27, 0.28, 0.31, 0.65 * a)
            self.knob:SetColorTexture(1, 1, 1, 0.5 * a)
        end
        local goal = on and (3 + travel) or 3
        self.goal = goal
        if self.x ~= goal then
            if self.IsVisible and self:IsVisible() then
                self:SetScript("OnUpdate", onUpdate)
            else
                place(self, goal)
            end
        end
    end
    return c
end

-- A flat edit box: a dark well with a faint border that lights up in the
-- accent while you type in it. `onFocusLost` is called after we repaint, so
-- the caller can still decide what losing focus means.
function T.edit(parent, w, h)
    local size = T.CONTROL.edit
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w or size.w, h or size.h)
    e:SetAutoFocus(false)
    e:SetFont(T.FONT, size.size, "")
    e:SetTextColor(1, 1, 1, T.A_TEXT)
    e:SetJustifyH("CENTER")
    if e.SetTextInsets then e:SetTextInsets(6, 6, 0, 0) end
    e.bg = T.fill(e, T.INPUT, 0.9)
    e.bg:SetAllPoints(e)
    T.border(e, { 1, 1, 1 }, 0.12)
    e:SetScript("OnEditFocusGained", function(self)
        T.paint(self, T.ACCENT, 0.9)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        T.paint(self, self.restEdge or { 1, 1, 1 }, self.restAlpha or 0.12)
        if self.onFocusLost then self.onFocusLost(self) end
    end)
    return e
end

-- Gives edit box `e` (from T.edit) a solid fill and a solid `edge`.
--
-- The faint white edge of T.edit mixes with what's behind it. On a tinted
-- window, like the Mailbox's market tint, that turns it a muddy olive. A
-- solid grey edge and fill look the same on every tint.
T.SOLID_EDGE = { 0.2, 0.2, 0.2 }
function T.solidEdit(e, edge)
    e.restEdge, e.restAlpha = edge or T.SOLID_EDGE, 1
    if e.bg then e.bg:SetColorTexture(T.INPUT[1], T.INPUT[2], T.INPUT[3], 1) end
    if not (e.HasFocus and e:HasFocus()) then T.paint(e, e.restEdge, 1) end
    return e
end

-- Sets an edit box's text unless we're typing in it or it already says that.
--
-- Pages redraw behind your back, like Supplies whenever the game sends item
-- info, which can be every 0.2 seconds while bags load. Setting the text
-- while you type wipes what you typed. Setting the same text again makes a
-- centered box jump, so a row's Keep box flickered while you typed in Warn at.
function T.setText(edit, text)
    if edit:HasFocus() then return false end
    text = text or ""
    if edit:GetText() == text then return false end
    edit:SetText(text)
    edit:SetCursorPosition(0)
    return true
end

-- One segment of a choice: the chosen one is filled with the accent, the
-- rest are dark. `seg:show(selected, enabled)` paints it.
function T.segment(parent, label, w, h)
    local size = T.CONTROL.segment
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or size.h)
    b.bg = T.fill(b, { 1, 1, 1 }, 0.05)
    b.bg:SetAllPoints(b)
    T.border(b, { 1, 1, 1 }, 0.10)
    b.label = T.text(b, size.size, true, T.A_DIM)
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetText(label)
    function b:show(selected, enabled)
        local a = enabled and 1 or 0.4
        if selected then
            self.bg:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3],
                                    0.55 * a)
            T.paint(self, T.ACCENT, 0.9 * a)
            self.label:SetTextColor(1, 1, 1, a)
        else
            self.bg:SetColorTexture(1, 1, 1, 0.05)
            T.paint(self, { 1, 1, 1 }, 0.10)
            self.label:SetTextColor(1, 1, 1, enabled and T.A_DIM or T.A_OFF)
        end
    end
    return b
end

-- A compact switch for a mode or a filter (Short/All, a view, a range): boxed
-- segments side by side that share their borders, 11 bold at 22 high, each
-- as wide as its words. A near-black fill and a grey edge that brightens
-- under the mouse; the chosen one is washed with the accent and its words
-- go white. Page switches are tabs (T.tab), not this.
--
--   s = T.segments(parent, { { key = "short", label = "Short", tip = fn }, ... },
--                  { pick = function(key) end, h = 22 })
--   s:show(key, enabled)   paints the chosen one, and answers the whole width
--   s.segs                 the segments, each with .key; s.key the chosen one
--
-- An item's `w` fixes its width; `tip(seg)` shows its tooltip.
T.CONTROL.segments = { h = 22, size = 11, pad = 18, fill = { 0.02, 0.02, 0.02 },
                       edge = { 0.25, 0.25, 0.25 }, hover = { 0.45, 0.45, 0.45 },
                       glow = 0.22, off = 0.6 }
function T.segments(parent, items, opts)
    opts = opts or {}
    local S = T.CONTROL.segments
    local h = opts.h or T.controlH(parent, S.h)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(h)
    row.segs = {}
    row.enabled = true
    local x = 0
    for i, it in ipairs(items) do
        local s = CreateFrame("Button", nil, row)
        s:SetHeight(h)
        s.fill = T.fill(s, S.fill, 1, "BACKGROUND")
        s.fill:SetAllPoints(s)
        s.glow = T.fill(s, T.ACCENT, S.glow, "BORDER")
        s.glow:SetAllPoints(s)
        s.glow:Hide()
        T.border(s, S.edge, 1, "OVERLAY")
        s.label = T.text(s, S.size, true, S.off)
        s.label:SetPoint("CENTER", s, "CENTER", 0, 0)
        s.label:SetJustifyH("CENTER")
        s.label:SetText(it.label or "")
        s.key = it.key == nil and i or it.key
        local w = it.w or floor((s.label:GetStringWidth() or 0) + 0.5) + S.pad
        s:SetWidth(w)
        s:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        s:SetScript("OnEnter", function(self)
            if row.enabled then T.paint(self, S.hover, 1) end
            if it.tip then it.tip(self) end
        end)
        s:SetScript("OnLeave", function(self)
            T.paint(self, S.edge, 1)
            if it.tip and _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        s:SetScript("OnClick", function(self)
            if not row.enabled then return end
            local pick = row.pick or opts.pick
            if pick then pick(self.key) end
        end)
        row.segs[i] = s
        x = x + w - 1
    end
    row:SetWidth(#row.segs > 0 and x + 1 or 0)

    function row:show(key, enabled)
        self.key = key
        self.enabled = enabled ~= false
        local a = self.enabled and 1 or 0.4
        for _, s in ipairs(self.segs) do
            local on = s.key == key
            s.glow:SetShown(on)
            s.label:SetTextColor(1, 1, 1, (on and 1 or S.off) * a)
        end
        return self:GetWidth()
    end
    row:show(opts.key)
    return row
end

-- A slider: a thin track that fills with the accent up to a white knob. It is
-- the client's own Slider, so the caller sets its range and step and listens
-- to OnValueChanged. The mouse wheel moves it one step.
function T.slider(parent, w)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(w or 120, 14)
    s:SetHitRectInsets(0, 0, -4, -4)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = T.fill(s, { 1, 1, 1 }, 0.12, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(4)
    local knob = s:CreateTexture(nil, "OVERLAY")
    knob:SetColorTexture(1, 1, 1, 0.95)
    knob:SetSize(6, 14)
    s:SetThumbTexture(knob)
    local done = T.fill(s, T.ACCENT, 0.8, "ARTWORK")
    done:SetPoint("LEFT", track, "LEFT", 0, 0)
    done:SetPoint("RIGHT", knob, "CENTER", 0, 0)
    done:SetHeight(4)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * self:GetValueStep())
    end)
    return s
end

-- A slider we drag ourselves, for a value that's costly to apply, like
-- Upgrades' survival slider, which scores every item again.
--
-- The game's Slider tells us of every step, and applying each one redrew
-- the page under the drag, which made the drag stutter or drop. This one
-- follows the cursor on every frame and tells `onChange(v)` of each step,
-- for something cheap like the number beside it. `onCommit(v)` comes once,
-- when we let go, and that's where the value is applied. A click anywhere on
-- it jumps there and starts the drag, and the wheel steps it.
--
--   r = T.range(parent, w, lo, hi, step)
--   r:SetValue(v), r:GetValue(), r.onChange, r.onCommit
function T.range(parent, w, lo, hi, step)
    local size = T.CONTROL.range
    local KNOB_W = size.knobW
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(w or 120, size.h)
    r:EnableMouse(true)
    r:EnableMouseWheel(true)
    r.lo, r.hi, r.step = lo or 0, hi or 1, step or 0.05
    r.value = r.lo

    local track = T.fill(r, { 1, 1, 1 }, 0.12, "BACKGROUND")
    track:SetPoint("LEFT", r, "LEFT", 0, 0)
    track:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    track:SetHeight(4)
    local done = T.fill(r, T.ACCENT, 0.8, "ARTWORK")
    done:SetPoint("LEFT", r, "LEFT", 0, 0)
    done:SetHeight(4)
    local knob = r:CreateTexture(nil, "OVERLAY")
    knob:SetSize(KNOB_W, size.knobH)
    knob:SetColorTexture(1, 1, 1, 0.85)
    r.knob = knob

    local function snap(v)
        v = math.min(math.max(v, r.lo), r.hi)
        return r.lo + floor((v - r.lo) / r.step + 0.5) * r.step
    end

    local function paint(self)
        local span = max(1, (self:GetWidth() or 0) - KNOB_W)
        local x = KNOB_W / 2 + (self.value - self.lo) / (self.hi - self.lo) * span
        knob:ClearAllPoints()
        knob:SetPoint("CENTER", self, "LEFT", x, 0)
        done:SetWidth(max(1, x))
        done:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.8)
        local lit = self.dragging or self.over
        knob:SetColorTexture(1, 1, 1, lit and 1 or 0.85)
    end

    function r:SetValue(v)
        self.value = snap(v)
        paint(self)
    end

    function r:GetValue() return self.value end

    local function step(self, v)
        v = snap(v)
        if v == self.value then return end
        self.value = v
        paint(self)
        if self.onChange then self.onChange(v) end
    end

    local function cursorValue(self)
        local x = GetCursorPosition() / self:GetEffectiveScale()
        local span = max(1, self:GetWidth() - KNOB_W)
        return self.lo + (x - self:GetLeft() - KNOB_W / 2) / span * (self.hi - self.lo)
    end

    local function stop(self)
        if not self.dragging then return end
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        paint(self)
        if self.onCommit then self.onCommit(self.value) end
    end

    local function follow(self)
        -- The button may come up outside the game window, where we never
        -- hear of it, so we look for ourselves.
        if not IsMouseButtonDown("LeftButton") then return stop(self) end
        step(self, cursorValue(self))
    end

    r:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        self.dragging = true
        step(self, cursorValue(self))
        paint(self)
        self:SetScript("OnUpdate", follow)
    end)
    r:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then stop(self) end
    end)
    r:SetScript("OnHide", stop)
    r:SetScript("OnEnter", function(self) self.over = true paint(self) end)
    r:SetScript("OnLeave", function(self) self.over = false paint(self) end)
    r:SetScript("OnSizeChanged", paint)
    r:SetScript("OnMouseWheel", function(self, delta)
        local before = self.value
        step(self, self.value + delta * self.step)
        if self.value ~= before and self.onCommit then self.onCommit(self.value) end
    end)
    paint(r)
    return r
end

-- A section heading: small dim capitals and a hairline under it, as in EUI.
-- It isn't in the accent, because the accent means "selected or on" and a
-- heading is neither.
function T.heading(parent, label)
    local size = T.CONTROL.heading
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(size.h)
    h.label = T.text(h, size.size, true, T.A_DIM)
    h.label:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, size.y)
    h.label:SetText((label or ""):upper())
    h.line = T.fill(h, { 1, 1, 1 }, 0.07, "ARTWORK")
    h.line:SetHeight(1)
    h.line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    h.line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    return h
end

-- A small chip: a few words in a tinted box, for a status like "Not in a
-- group" or "View only". The one chip of the window, so a state, a tag and a
-- count all look the same. `chip:show(text, color, caps)` paints it, in the
-- text's own case unless `caps`. With no `color` it's the plain grey chip.
-- The words are cut at `chip.maxW` when it's set. A status, not a control:
-- a chip that's clicked is T.chipButton.
function T.chip(parent)
    local size = T.CONTROL.chip
    local pad = size.pad
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(size.h)
    c.bg = T.fill(c, { 1, 1, 1 }, 0.08)
    c.bg:SetAllPoints(c)
    T.border(c, { 1, 1, 1 }, 0.15)
    c.label = T.text(c, size.size, true, 1)
    c.label:SetPoint("CENTER", c, "CENTER", 0, 0)
    if c.label.SetWordWrap then c.label:SetWordWrap(false) end
    function c:show(text, color, caps)
        self.color = color
        self.label:SetWidth(0)
        self.label:SetText(caps and text:upper() or text)
        if color then
            self.label:SetTextColor(color[1], color[2], color[3], 1)
            self.bg:SetColorTexture(color[1], color[2], color[3], 0.12)
            T.paint(self, color, 0.45)
        else
            self.label:SetTextColor(1, 1, 1, 0.8)
            self.bg:SetColorTexture(1, 1, 1, 0.08)
            T.paint(self, { 1, 1, 1 }, 0.15)
        end
        local w = floor((self.label:GetStringWidth() or 40) + pad)
        if self.maxW and w > self.maxW then
            w = self.maxW
            self.label:SetWidth(w - pad)
        end
        self:SetWidth(w)
        self:Show()
    end
    return c
end

-- A filter chip: a few words in a box that's clicked to turn the filter on
-- or off. Off it's a faint box with words at .70; under the mouse its edge
-- and words brighten; on, it's washed with the accent. `opts.color` tints
-- the words (T.ORANGE for a filter that wants attention). `opts.remove`
-- adds a cross after the words that reddens under the mouse, for a chip that
-- takes its filter off when clicked.
--
--   c = T.chipButton(parent, "Soulbound", { pick = function(c) end })
--   c:setOn(on)      c:setText(text)      c.on
T.CONTROL.chipButton = { h = 20, size = 11, pad = 7, fill = 0.05, edge = 0.15, hover = 0.32,
                         off = 0.7, glow = 0.22, glowEdge = 0.7 }
local CROSS = "\195\151"
function T.chipButton(parent, label, opts)
    opts = opts or {}
    local S = T.CONTROL.chipButton
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(opts.h or S.h)
    c.bg = T.fill(c, { 1, 1, 1 }, S.fill)
    c.bg:SetAllPoints(c)
    T.border(c, { 1, 1, 1 }, S.edge)
    c.label = T.text(c, S.size, true, S.off)
    c.label:SetPoint("LEFT", c, "LEFT", S.pad, 0)
    c.label:SetWordWrap(false)
    c.on, c.over = false, false
    local function words(self)
        local t = self.text or ""
        if opts.remove then
            t = t .. "  " .. (self.over and "|cffff4d4d" .. CROSS .. "|r" or "|cff8c919a" .. CROSS .. "|r")
        end
        return t
    end
    function c:paint()
        local col = opts.color
        local a = (self.on or self.over) and 1 or S.off
        if self.on then
            self.bg:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], S.glow)
            T.paint(self, T.ACCENT, S.glowEdge)
        else
            self.bg:SetColorTexture(1, 1, 1, S.fill)
            T.paint(self, { 1, 1, 1 }, self.over and S.hover or S.edge)
        end
        self.label:SetText(words(self))
        if col and not self.on then
            self.label:SetTextColor(col[1], col[2], col[3], 1)
        else
            self.label:SetTextColor(1, 1, 1, a)
        end
    end
    function c:setText(text)
        self.text = text or ""
        self.label:SetText(words(self))
        self:SetWidth(floor((self.label:GetStringWidth() or 0) + 0.5) + 2 * S.pad)
        self:paint()
    end
    function c:setOn(on)
        self.on = on and true or false
        self:paint()
    end
    c:SetScript("OnEnter", function(self)
        self.over = true
        self:paint()
        if self.tip then self.tip(self) end
    end)
    c:SetScript("OnLeave", function(self)
        self.over = false
        self:paint()
        if self.tip and _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    c:SetScript("OnClick", function(self)
        local pick = self.pick or opts.pick
        if pick then pick(self) end
    end)
    c:setText(label)
    if opts.on then c:setOn(true) end
    return c
end

-- =============================================================
-- Pop-ups: dropdowns and menus
-- =============================================================
-- One pop-up is open at a time, a dropdown's list or a menu. Opening one
-- closes the other, and a click anywhere but on it closes it.
--
-- A click on the button that opened it closes it too. That click's mouse
-- down closes the pop-up before the button's own click runs, so we note the
-- button, and its click then leaves the pop-up closed instead of opening it
-- again (T.closedBy).
local menus = {}
local closeMenus
local openDrop            -- the dropdown list on show, or nil
local closed = {}         -- the button whose mouse down just closed a pop-up

-- Whether the mouse is over `f`, false when the game won't say.
--
-- The game refuses to measure a frame anchored to a nameplate ("Can't measure
-- restricted regions") and IsMouseOver() then throws. That happened with a
-- menu opened from an Object Highlight icon, which sits on a nameplate.
local function mouseOver(f)
    if not (f and f.IsMouseOver) then return false end
    if f.IsAnchoringRestricted and f:IsAnchoringRestricted() then return false end
    local ok, over = pcall(f.IsMouseOver, f)
    return ok and over and true or false
end

local catcher = CreateFrame("Frame")
catcher:SetScript("OnEvent", function()
    for _, x in pairs(menus) do
        if x:IsShown() and x:IsMouseOver() then return end
    end
    if openDrop and openDrop:IsShown() and openDrop:IsMouseOver() then return end
    local owner = (menus[1] and menus[1]:IsShown() and menus[1].owner) or (openDrop and openDrop.owner)
    if mouseOver(owner) then
        closed.owner, closed.t = owner, GetTime and GetTime() or 0
    end
    closeMenus()
end)

-- We listen only while a pop-up is open, since every click in the game
-- fires this.
local function listen()
    local open = (menus[1] and menus[1]:IsShown()) or (openDrop and openDrop:IsShown())
    if open then catcher:RegisterEvent("GLOBAL_MOUSE_DOWN") else catcher:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
end

-- Whether the mouse down of this click on `owner` closed its pop-up, so the
-- click shouldn't open it again.
function T.closedBy(owner)
    local was = owner ~= nil and closed.owner == owner and ((GetTime and GetTime() or 0) - (closed.t or 0)) < 1
    closed.owner = nil
    return was
end

-- A choice from a list too long for segments: a button that shows the chosen
-- one, and a menu of every choice under it on a click.
--
--   dd = T.dropdown(parent, w, h)
--   dd:setItems({ { value = v, label = "Text", swatch = {r,g,b}, icon = path } })
--                              `indent` moves an item right in the menu, in px.
--                              An `icon` shows in the swatch's place, cropped
--                              like T.icon, with the swatch's color as its edge.
--                              With `round`, it's a T.circleIcon instead, with
--                              `ring` as its ring (a loadout's color).
--   dd:show(value, enabled)    paints the chosen one
--   dd.onPick(value)           called when one is picked
--
-- The menu sits on the dialog strata, above the window, and closes when a
-- choice is picked, on a second click, on a click anywhere else, when another
-- pop-up opens, or when the dropdown hides.
--
-- T.dropButton(parent, w, h) is the button alone, in the look every
-- dropdown of ours has, for a button that opens a menu of its own (the
-- Ledger's Group by and Count pickers, K.picker).
function T.dropButton(parent, w, h)
    local size = T.CONTROL.dropdown
    local d = CreateFrame("Button", nil, parent)
    d:SetSize(w or size.w, h or T.controlH(parent, size.h))
    d.bg = T.fill(d, T.INPUT, 0.9)
    d.bg:SetAllPoints(d)
    T.border(d, { 1, 1, 1 }, 0.14)
    d.swatch = T.fill(d, { 1, 1, 1 }, 1, "ARTWORK")
    d.swatch:SetSize(10, 10)
    d.swatch:SetPoint("LEFT", d, "LEFT", 8, 0)
    d.swatch:Hide()
    d.itemIcon = T.icon(d, nil, 14)
    d.itemIcon:SetPoint("LEFT", d, "LEFT", 7, 0)
    d.itemIcon:Hide()
    d.label = T.text(d, size.size, true, T.A_TEXT)
    d.label:SetPoint("LEFT", d, "LEFT", 8, 0)
    d.label:SetPoint("RIGHT", d, "RIGHT", -20, 0)
    if d.label.SetWordWrap then d.label:SetWordWrap(false) end
    d.arrow = T.chevron(d, 10)
    d.arrow:SetPoint("RIGHT", d, "RIGHT", -7, 0)
    return d
end

local menuCount = 0
function T.dropdown(parent, w, h)
    local d = T.dropButton(parent, w, h)
    local ROW, SIZE = T.CONTROL.dropdown.row, T.CONTROL.dropdown.size
    d.items = {}

    -- The menu isn't the dropdown's child. A settings page scrolls, and its
    -- scroll frame cuts off whatever reaches past its edge, so a menu inside
    -- it would be cut off at the bottom of the page. It takes the
    -- dropdown's scale when it opens instead.
    menuCount = menuCount + 1
    local menu = CreateFrame("Frame", ADDON .. "DropdownMenu" .. menuCount, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
    -- A dropdown low in a window (a footer's) keeps its menu on screen.
    if menu.SetClampedToScreen then menu:SetClampedToScreen(true) end
    menu.bg = T.fill(menu, { 0.07, 0.08, 0.10 }, 0.98)
    menu.bg:SetAllPoints(menu)
    T.border(menu, { 1, 1, 1 }, 0.18)
    popupShadow(menu)
    menu:Hide()
    menu.rows = {}
    menu.owner = d
    menu:SetScript("OnHide", function(self)
        if openDrop == self then openDrop = nil end
        listen()
    end)
    d.menu = menu

    local function paintRow(r, over)
        r.hl:SetShown(over or r.value == d.value)
        r.hl:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], over and 0.35 or 0.18)
    end

    -- An item may carry `closed`, shorter words for the dropdown itself
    -- when it's picked ("PvP" for the menu's "PvP · 4 · In use"). The menu
    -- grows wider than the dropdown to fit its longest row.
    function d:setItems(items)
        self.items = items
        local wide = 0
        for i, it in ipairs(items) do
            local r = menu.rows[i]
            if not r then
                r = CreateFrame("Button", nil, menu)
                r:SetHeight(ROW)
                r.hl = T.fill(r, T.ACCENT, 0.2)
                r.hl:SetAllPoints(r)
                r.swatch = T.fill(r, { 1, 1, 1 }, 1, "ARTWORK")
                r.swatch:SetSize(10, 10)
                r.swatch:SetPoint("LEFT", r, "LEFT", 8, 0)
                r.itemIcon = T.icon(r, nil, 14)
                r.itemIcon:Hide()
                r.label = T.text(r, SIZE, false, T.A_TEXT)
                r:SetScript("OnEnter", function(self) paintRow(self, true) end)
                r:SetScript("OnLeave", function(self) paintRow(self, false) end)
                r:SetScript("OnClick", function(self)
                    menu:Hide()
                    if d.onPick then d.onPick(self.value) end
                end)
                menu.rows[i] = r
            end
            r.value = it.value
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -1 - (i - 1) * ROW)
            r:SetPoint("RIGHT", menu, "RIGHT", -1, 0)
            r.label:ClearAllPoints()
            local x = it.indent or 0
            r.swatch:ClearAllPoints()
            r.swatch:SetPoint("LEFT", r, "LEFT", 8 + x, 0)
            r.itemIcon:ClearAllPoints()
            r.itemIcon:SetPoint("LEFT", r, "LEFT", 7 + x, 0)
            local lx = 8
            if r.circle then r.circle:Hide() end
            if it.icon and it.round then
                r.swatch:Hide()
                r.itemIcon:Hide()
                if not r.circle then r.circle = T.circleIcon(r, nil, 14) end
                r.circle:ClearAllPoints()
                r.circle:SetPoint("LEFT", r, "LEFT", 7 + x, 0)
                r.circle:SetTexture(it.icon)
                r.circle:SetEdge(it.ring)
                r.circle:Show()
                lx = 27
            elseif it.icon then
                r.swatch:Hide()
                r.itemIcon:SetTexture(it.icon)
                r.itemIcon:SetEdge(it.swatch)
                r.itemIcon:Show()
                lx = 27
            elseif it.swatch then
                r.itemIcon:Hide()
                r.swatch:SetColorTexture(it.swatch[1], it.swatch[2], it.swatch[3], 1)
                r.swatch:Show()
                lx = 24
            else
                r.itemIcon:Hide()
                r.swatch:Hide()
            end
            r.label:SetPoint("LEFT", r, "LEFT", lx + x, 0)
            r.label:SetText(it.label or tostring(it.value))
            local tw = r.label.GetStringWidth and r.label:GetStringWidth()
            if type(tw) == "number" then wide = max(wide, tw + lx + x + 8 + 2) end
            r:Show()
        end
        for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
        menu:SetSize(max(self:GetWidth() or 160, 120, math.ceil(wide)), #items * ROW + 2)
    end

    function d:show(value, enabled)
        self.value = value
        local it
        for _, x in ipairs(self.items) do if x.value == value then it = x end end
        self.label:ClearAllPoints()
        if self.circle then self.circle:Hide() end
        if it and it.icon and it.round then
            self.swatch:Hide()
            self.itemIcon:Hide()
            if not self.circle then
                self.circle = T.circleIcon(self, nil, 14)
                self.circle:SetPoint("LEFT", self, "LEFT", 7, 0)
            end
            self.circle:SetTexture(it.icon)
            self.circle:SetEdge(it.ring)
            self.circle:Show()
            self.circle:SetAlpha(enabled and 1 or 0.4)
            self.label:SetPoint("LEFT", self, "LEFT", 27, 0)
        elseif it and it.icon then
            self.swatch:Hide()
            self.itemIcon:SetTexture(it.icon)
            self.itemIcon:SetEdge(it.swatch)
            self.itemIcon:Show()
            self.itemIcon:SetAlpha(enabled and 1 or 0.4)
            self.label:SetPoint("LEFT", self, "LEFT", 27, 0)
        elseif it and it.swatch then
            self.itemIcon:Hide()
            self.swatch:SetColorTexture(it.swatch[1], it.swatch[2], it.swatch[3], enabled and 1 or 0.4)
            self.swatch:Show()
            self.label:SetPoint("LEFT", self, "LEFT", 24, 0)
        else
            self.itemIcon:Hide()
            self.swatch:Hide()
            self.label:SetPoint("LEFT", self, "LEFT", 8, 0)
        end
        self.label:SetPoint("RIGHT", self, "RIGHT", -20, 0)
        self.label:SetText(it and (it.closed or it.label or tostring(it.value)) or tostring(value or ""))
        self.label:SetTextColor(1, 1, 1, enabled and T.A_TEXT or T.A_OFF)
        if enabled then self:Enable() else self:Disable() menu:Hide() end
        for _, r in ipairs(menu.rows) do paintRow(r, false) end
    end

    d:SetScript("OnClick", function(self)
        if T.closedBy(self) then return end
        if menu:IsShown() then menu:Hide() return end
        closeMenus()
        local s, u = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if s and u and u > 0 then menu:SetScale(s / u) end
        -- A dropdown on the full screen map is on the menu's strata too, so
        -- the menu goes above it there.
        if menu.SetFrameLevel then
            menu:SetFrameLevel(max(menu:GetFrameLevel() or 1, (self:GetFrameLevel() or 1) + 10))
        end
        openDrop = menu
        menu:Show()
        listen()
    end)
    d:SetScript("OnHide", function() menu:Hide() end)
    return d
end

-- =============================================================
-- Menus
-- =============================================================
-- A right-click menu in our look, in place of the game's (MenuUtil), whose
-- gold ticks and boxes match nothing else of ours. It takes the same calls as
-- MenuUtil, so a menu written for it moves over by changing one line:
--
--   T.menu(owner, function(owner, root)
--       root:CreateTitle("Blessings")
--       root:CreateRadio("Auto", isAuto, setAuto)
--       root:CreateDivider()
--       root:CreateCheckbox("Track this duty", isTracked, toggleTracked)
--       local more = root:CreateButton("Not here")   -- with items, a submenu
--       more:CreateCheckbox(name, isPicked, togglePicked)
--       root:CreateNote("Dim words that do nothing on a click")
--       root:CreateButton("Settings", openSettings)
--   end)
--
-- A tick or a radio keeps the menu open and paints it again, so several can be
-- picked in one go. A button closes it, and so does a click anywhere else or
-- Escape.
--
-- Any item can carry a few dim words at its right, like what Auto would pick:
--
--   root:CreateRadio("Auto", isAuto, setAuto).right = "Raid"
--
-- An item with `disabled` set shows faint and does nothing on a click.
-- Submenus can go as deep as the items do.
--
-- An item can have an icon before its words, and then the words of every
-- button in that menu line up after the icons. One that undoes something,
-- like Remove friend, can be in red:
--
--   local it = root:CreateButton("Remove friend", remove)
--   it.icon, it.danger = T.media("UserMinus"), true
--
-- An item that stands for a loadout or a gear set shows its icon round, as
-- everywhere else (T.circleIcon): `circle` is the icon, `ring` the loadout's
-- colour, and `indent` moves the icon and words right, for a tree.
--
-- A title can be in a colour, like a player's name in their class colour.
-- Then it keeps its case and shows bold and full size:
--
--   root:CreateTitle(name).color = { 0.96, 0.55, 0.73 }
local MENU_ROW, MENU_GAP, MENU_BOX, MENU_ICON = 22, 9, 12, 14
local MENU_DANGER = { 1.00, 0.45, 0.30 }

local Items = {}
Items.__index = Items
local function newItems() return setmetatable({ items = {} }, Items) end
local function addItem(self, it)
    self.items[#self.items + 1] = it
    return it
end
function Items:CreateTitle(text) return addItem(self, { kind = "title", text = text }) end
-- A line of dim words that does nothing on a click, like what the picks of
-- an assignment mean.
function Items:CreateNote(text) return addItem(self, { kind = "note", text = text }) end
function Items:CreateDivider() return addItem(self, { kind = "divider" }) end
function Items:CreateRadio(text, isOn, pick)
    return addItem(self, { kind = "radio", text = text, isOn = isOn, click = pick })
end
function Items:CreateCheckbox(text, isOn, toggle)
    return addItem(self, { kind = "check", text = text, isOn = isOn, click = toggle })
end
-- A button that gets items of its own becomes a submenu.
function Items:CreateButton(text, click)
    local it = newItems()
    it.kind, it.text, it.click = "button", text, click
    return addItem(self, it)
end

-- Text in capitals, for a menu's title, with its escapes left as they are.
--
-- A title like a player's name has their spec's icon in it (|T...|t) and
-- their class colour (|cff...|r). Those only work in lower case where they
-- are, so a plain upper() showed the icon's path as text instead of the icon.
function T.upper(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local p = s:find("|", i, true)
        if not p then
            out[#out + 1] = s:sub(i):upper()
            break
        end
        out[#out + 1] = s:sub(i, p - 1):upper()
        local c, e = s:sub(p + 1, p + 1), p + 1
        if c == "T" or c == "A" then
            local _, q = s:find("|" .. c:lower(), p + 2, true)
            e = q or n
        elseif c == "c" then
            e = math.min(n, p + 9)
        end
        out[#out + 1] = s:sub(p, e)
        i = e + 1
    end
    return table.concat(out)
end

-- A row is lit while the mouse is on it. A picked radio stays lit, fainter,
-- the way our dropdowns show the chosen row, so a radio has no dot of its own.
--
-- With T.GREY_HOVER (Buff Coordinator's menus) the row under the mouse, or
-- whose submenu is open, is a soft grey instead, and only the picked radio is
-- in the accent, the way the plan picker shows the plan in use. A row whose
-- submenu has a pick in it is half as much in the accent, with its arrow in
-- the accent too, so the pick can be found from the top.
local function paintRow(r)
    local a = T.ACCENT
    if T.GREY_HOVER then
        r.sel:SetColorTexture(a[1], a[2], a[3], r.on and 0.16 or 0.08)
        r.sel:SetShown(r.on or r.inner or false)
        r.hl:SetColorTexture(1, 1, 1, 0.06)
        r.hl:SetShown(r.over or r.open or false)
        if r.inner then
            r.arrow:SetTextColor(a[1], a[2], a[3], 1)
        else
            r.arrow:SetTextColor(1, 1, 1, T.A_DIM)
        end
        return
    end
    r.sel:Hide()
    r.hl:SetColorTexture(a[1], a[2], a[3], r.over and 0.35 or 0.18)
    r.hl:SetShown(r.over or r.on)
end

-- Whether a radio or a tick among `it`'s items is on, in its submenus too.
local function hasPick(it)
    for _, x in ipairs(it.items or {}) do
        if (x.kind == "radio" or x.kind == "check") and x.isOn and x.isOn() then return true end
        if x.kind == "button" and hasPick(x) then return true end
    end
    return false
end

local function menuRow(menu)
    local size = T.CONTROL.menu
    local r = CreateFrame("Button", nil, menu)
    r:SetHeight(MENU_ROW)
    r.sel = T.fill(r, T.ACCENT, 0.16, "BORDER")
    r.sel:SetAllPoints(r)
    r.sel:Hide()
    r.hl = T.fill(r, { 1, 1, 1 }, 0.06)
    r.hl:SetAllPoints(r)
    r.hl:Hide()
    r.line = T.fill(r, { 1, 1, 1 }, 0.08, "ARTWORK")
    r.line:SetHeight(1)
    r.line:SetPoint("LEFT", r, "LEFT", 8, 0)
    r.line:SetPoint("RIGHT", r, "RIGHT", -8, 0)

    -- The tick box: a square with a 1 pixel edge, filled in the accent
    -- colour when it's on.
    r.box = CreateFrame("Frame", nil, r)
    r.box:SetSize(MENU_BOX, MENU_BOX)
    r.box:SetPoint("LEFT", r, "LEFT", 8, 0)
    r.box.bg = T.fill(r.box, { 0, 0, 0 }, 0.45)
    r.box.bg:SetAllPoints(r.box)
    T.border(r.box, { 1, 1, 1 }, 0.35)
    r.box.on = T.fill(r.box, T.ACCENT, 1, "ARTWORK")
    r.box.on:SetPoint("TOPLEFT", r.box, "TOPLEFT", 3, -3)
    r.box.on:SetPoint("BOTTOMRIGHT", r.box, "BOTTOMRIGHT", -3, 3)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(MENU_ICON, MENU_ICON)
    r.icon:SetPoint("LEFT", r, "LEFT", 9, 0)
    r.icon:Hide()
    r.label = T.text(r, size.size, false, T.A_TEXT)
    if r.label.SetWordWrap then r.label:SetWordWrap(false) end
    r.arrow = T.text(r, size.size, false, T.A_DIM)
    r.arrow:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.arrow:SetText("\226\128\186")
    r.right = T.text(r, size.right, false, T.A_DIM)
    if r.right.SetWordWrap then r.right:SetWordWrap(false) end

    r:SetScript("OnEnter", function(self)
        local it = self.item
        if not it or it.kind == "title" or it.kind == "divider" or it.kind == "note" or it.disabled then return end
        self.over = true
        paintRow(self)
        -- A row closes the submenus open past its own menu, and a row with
        -- items opens its submenu, at any depth.
        local lv = self.level + 1
        while menus[lv] do
            menus[lv]:Hide()
            lv = lv + 1
        end
        for _, o in ipairs(menu.rows) do
            if o.open then
                o.open = false
                paintRow(o)
            end
        end
        if it.kind == "button" and #it.items > 0 then
            self.open = true
            paintRow(self)
            T.openMenu(it, self.level + 1, self)
        end
    end)
    r:SetScript("OnLeave", function(self)
        self.over = false
        paintRow(self)
    end)
    r:SetScript("OnClick", function(self)
        local it = self.item
        if not it or it.disabled then return end
        if it.kind == "check" or it.kind == "radio" then
            if it.click then it.click() end
            for _, m in pairs(menus) do if m:IsShown() then m.paint() end end
        elseif it.kind == "button" and #it.items == 0 then
            closeMenus()
            if it.click then it.click() end
        end
    end)
    return r
end

local function menuFrame(level)
    local m = menus[level]
    if m then return m end
    local name = level == 1 and T.MENU_NAME or nil
    m = CreateFrame("Frame", name, UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(level * 20)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m.bg = T.fill(m, { 0.07, 0.08, 0.10 }, 0.98)
    m.bg:SetAllPoints(m)
    T.border(m, { 1, 1, 1 }, 0.18)
    m.rows = {}
    m:Hide()
    if level == 1 then
        if name and type(_G.UISpecialFrames) == "table" then
            table.insert(_G.UISpecialFrames, name)
        end
        -- A click anywhere but on a menu closes them (the catcher above).
        m:SetScript("OnShow", function() listen() end)
    end
    -- A menu that closes takes its open submenus with it.
    m:SetScript("OnHide", function(self)
        if level == 1 then listen() end
        local deeper = menus[level + 1]
        if deeper then deeper:Hide() end
    end)
    -- After the scripts above, since the shadow hooks OnShow to fit itself.
    popupShadow(m)

    -- Whether each tick and radio is on, and each submenu has one on, asked
    -- again after every click.
    function m.paint()
        for _, r in ipairs(m.rows) do
            local it = r.item
            if it and r:IsShown() and (it.kind == "check" or it.kind == "radio") then
                local on = it.isOn and it.isOn() and true or false
                r.box.on:SetShown(on)
                r.on = it.kind == "radio" and on
                paintRow(r)
            elseif it and r:IsShown() and it.kind == "button" and #it.items > 0 then
                r.inner = hasPick(it)
                paintRow(r)
            end
        end
    end
    menus[level] = m
    return m
end

closeMenus = function()
    for _, m in pairs(menus) do m:Hide() end
    if openDrop then openDrop:Hide() end
end
T.closeMenus = function() closeMenus() end

-- Whether the mouse is over a menu that's open, for a panel of our own that
-- closes on a click elsewhere but opened a menu itself.
function T.menuHasMouse()
    for _, m in pairs(menus) do
        if m:IsShown() and m:IsMouseOver() then return true end
    end
    return openDrop ~= nil and openDrop:IsShown() and openDrop:IsMouseOver() and true or false
end

-- Lays out one level of the menu and shows it, beside `row` for a submenu,
-- under `under` for a menu of a button, and at the cursor otherwise.
function T.openMenu(desc, level, row, under)
    local size = T.CONTROL.menu
    local m = menuFrame(level)
    local a = T.ACCENT
    local y, w = 1, 140
    local icons = false
    for _, it in ipairs(desc.items) do
        if it.icon or it.circle then icons = true end
    end
    for i, it in ipairs(desc.items) do
        local r = m.rows[i] or menuRow(m)
        m.rows[i] = r
        r.item, r.level = it, level
        local h = it.kind == "divider" and MENU_GAP or MENU_ROW
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -y)
        r:SetPoint("RIGHT", m, "RIGHT", -1, 0)
        -- The accent can change, so a row made before it did takes the new
        -- one here.
        r.box.on:SetColorTexture(a[1], a[2], a[3], 1)
        r.over, r.on, r.open, r.inner = false, false, false, false
        r.hl:Hide()
        r.sel:Hide()
        r.line:SetShown(it.kind == "divider")
        r.box:SetShown(it.kind == "check")
        r.arrow:SetShown(it.kind == "button" and #it.items > 0)
        r.arrow:SetTextColor(1, 1, 1, T.A_DIM)
        r.label:ClearAllPoints()
        r.icon:SetShown(it.icon ~= nil)
        if it.icon then
            r.icon:SetTexture(it.icon)
            local c = it.danger and MENU_DANGER or { 1, 1, 1 }
            r.icon:SetVertexColor(c[1], c[2], c[3], it.disabled and T.A_FAINT or 0.8)
        end
        local indent = it.indent or 0
        if it.circle then
            if not r.circle then r.circle = T.circleIcon(r, nil, MENU_ICON) end
            r.circle:ClearAllPoints()
            r.circle:SetPoint("LEFT", r, "LEFT", 9 + indent, 0)
            r.circle:SetTexture(it.circle)
            r.circle:SetEdge(it.ring)
            r.circle:Show()
            r.circle:SetAlpha(it.disabled and T.A_FAINT or 1)
        elseif r.circle then
            r.circle:Hide()
        end
        local x = 10
        if it.kind == "check" then
            x = 8 + MENU_BOX + 8
        elseif icons and (it.kind == "button" or it.kind == "radio") then
            x = 9 + MENU_ICON + 8 + indent
        end
        r.label:SetPoint("LEFT", r, "LEFT", x, 0)
        if it.kind == "title" and it.color then
            r.label:SetFont(T.BOLD, T.SIZE.body, "")
            r.label:SetText(it.text or "")
            r.label:SetTextColor(it.color[1], it.color[2], it.color[3], 1)
        elseif it.kind == "title" then
            r.label:SetFont(T.BOLD, T.SIZE.caption, "")
            r.label:SetText(T.upper(it.text or ""))
            r.label:SetTextColor(1, 1, 1, T.A_DIM)
        elseif it.kind == "note" then
            r.label:SetFont(T.FONT, T.SIZE.body, "")
            r.label:SetText(it.text or "")
            r.label:SetTextColor(1, 1, 1, T.A_DIM)
        else
            r.label:SetFont(T.FONT, size.size, "")
            r.label:SetText(it.text or "")
            local c = it.danger and MENU_DANGER or { 1, 1, 1 }
            r.label:SetTextColor(c[1], c[2], c[3], it.disabled and T.A_FAINT or T.A_TEXT)
        end
        r.right:ClearAllPoints()
        r.right:SetPoint("RIGHT", r, "RIGHT", r.arrow:IsShown() and -24 or -10, 0)
        r.right:SetText(it.right or "")
        if it.kind ~= "divider" then
            local extra = it.right and ((r.right:GetStringWidth() or 0) + 18) or 0
            w = max(w, x + (r.label:GetStringWidth() or 0) + extra
                         + (r.arrow:IsShown() and 30 or 16))
        else
            r.label:SetText("")
        end
        r:Show()
        y = y + h
    end
    for i = #desc.items + 1, #m.rows do
        m.rows[i]:Hide()
        m.rows[i].item = nil
    end
    m:SetSize(floor(w + 2), y + 1)
    m:ClearAllPoints()
    if row then
        -- A submenu goes to the right of its row, or to the left when it
        -- wouldn't fit on screen there. Clamped to the screen instead, it
        -- would cover the menu it came from.
        local s = row:GetEffectiveScale() / m:GetEffectiveScale()
        if (row:GetRight() or 0) * s + m:GetWidth() + 2 > UIParent:GetWidth() then
            m:SetPoint("TOPRIGHT", row, "TOPLEFT", -2, 1)
        else
            m:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 1)
        end
    elseif under then
        m:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 0, -2)
    else
        local x, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 2, cy / s - 2)
    end
    m.paint()
    m:Show()
    return m
end

-- The window `f` is in: its last parent below UIParent, or `f` itself.
local function windowOf(f)
    local p = f.GetParent and f:GetParent()
    while p and p ~= UIParent do
        f, p = p, p.GetParent and p:GetParent()
    end
    return f
end

-- `under` opens it under the owner, for a button that drops a menu down, in
-- place of at the cursor. A second click on the owner closes it. A menu with
-- no button of its own (UIParent owns it) opens afresh each time.
function T.menu(owner, build, under)
    if T.closedBy(owner) then return end
    local open = menus[1]
    if owner and owner ~= UIParent and open and open:IsShown() and open.owner == owner then
        closeMenus()
        return
    end
    closeMenus()
    local root = newItems()
    build(owner, root)
    local m = T.openMenu(root, 1, nil, under and owner or nil)
    if not m then return m end
    m.owner = owner
    -- The menu goes with its owner's window, as when the window closes by a
    -- slash command. A menu left open would still edit what that window showed.
    --
    -- We watch the window and not the owner, because owners hide on purpose
    -- while their menu should stay open. Buff Coordinator's raid pane hides
    -- every player row before it draws again, so a Spec pick in a player's
    -- menu (or any roster change) would close that menu.
    m.window = owner and owner ~= UIParent and windowOf(owner) or nil
    local win = m.window
    if win and win.HookScript and not win.menuGoesWith then
        win.menuGoesWith = true
        win:HookScript("OnHide", function(self)
            local open1 = menus[1]
            if open1 and open1:IsShown() and open1.window == self then closeMenus() end
        end)
    end
    return m
end

-- =============================================================
-- Close, help and the hover edge
-- =============================================================
-- The close button in a window's corner: a faint cross that lights up red.
local CLOSE_A, CLOSE_HOT = 0.45, { 1.00, 0.45, 0.30 }

-- The cross is two lines crossed in the middle of the button, not the "×"
-- glyph. A glyph sits where its font puts it in the line, which was a few
-- pixels above the middle of a card, and the lines are in the middle of
-- whatever the button is centred on.
local CLOSE_LEN, CLOSE_W = 10, 1.5

function T.close(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b.lines = {}
    for i, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local t = T.fill(b, { 1, 1, 1 }, CLOSE_A, "ARTWORK")
        t:SetSize(CLOSE_LEN, CLOSE_W)
        t:SetPoint("CENTER", b, "CENTER", 0, 0)
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        t:SetRotation(angle)
        b.lines[i] = t
    end
    local function paint(c, a)
        for _, t in ipairs(b.lines) do t:SetColorTexture(c[1], c[2], c[3], a) end
    end
    b:SetScript("OnEnter", function() paint(CLOSE_HOT, 1) end)
    b:SetScript("OnLeave", function() paint({ 1, 1, 1 }, CLOSE_A) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A white edge around button `b` while the mouse is over it, which says it
-- can be clicked. `ok`, when given, says whether it can be clicked now (a
-- player who can't edit gets no edge).
function T.hoverEdge(b, ok)
    local hl = CreateFrame("Frame", nil, b)
    hl:SetAllPoints(b)
    hl:SetFrameLevel(b:GetFrameLevel() + 3)
    T.border(hl, { 1, 1, 1 }, 0.9, "OVERLAY")
    hl:Hide()
    b:HookScript("OnEnter", function(self) hl:SetShown(not ok or ok(self)) end)
    b:HookScript("OnLeave", function() hl:Hide() end)
    b.hoverEdge = hl
    return hl
end

-- A "?" beside the close cross, as quiet as it is. It lights in the accent
-- under the mouse, and the caller shows what it explains on hover.
--
-- We centre the glyph in the button with no offset. We tried a pixel up and a
-- pixel down before, and in game it lines up best with the cross centred.
function T.help(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b.label = T.text(b, 13, true, CLOSE_A)
    b.label:SetPoint("CENTER", b, "CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetText("?")
    b:HookScript("OnEnter", function(self)
        self.label:SetTextColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 1)
    end)
    b:HookScript("OnLeave", function(self) self.label:SetTextColor(1, 1, 1, CLOSE_A) end)
    return b
end

-- =============================================================
-- Scrolling
-- =============================================================
-- A scroll frame with EUI's thin bar: a 4 pixel track on the right and a
-- thumb you can drag, which hides when everything fits. The wheel scrolls by
-- a fixed step. `sf.child` is what the caller fills, and the caller sets its
-- height; `sf:update()` re-reads it.
local STEP = 48
local GLIDE_S = 0.3

-- The resize grip, a triangle of dots in the bottom right corner of `f`,
-- lit in the accent under the mouse. `done(f)` runs when a drag ends, to keep
-- the new size, and `reset(f)` on a right-click, to put the size back to the
-- one it opens at. Its tooltip says so.
--
-- We pin the top left corner before sizing. A window anchored by its middle
-- grows on both sides, so the corner under the mouse would only move half as
-- far as the mouse.
--
-- We size it ourselves rather than with StartSizing. The game's sizing moves
-- the window by how far the mouse moved each frame, so once the window stops
-- at its smallest size and the mouse keeps going, the corner and the mouse
-- part ways. Dragging back then grows the window straight away, and it ends
-- up wider than where the mouse is. We take the size from where the mouse is
-- now against where the drag began, so the corner stays under the mouse.
function T.grip(f, done, reset)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip.dots = {}
    for _, d in ipairs({ { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 },
                         { 0, 2 } }) do
        local dot = T.fill(grip, { 1, 1, 1 }, 0.28, "OVERLAY")
        dot:SetSize(2, 2)
        dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3 - d[1] * 4,
                     3 + d[2] * 4)
        grip.dots[#grip.dots + 1] = dot
    end
    local function light(on)
        for _, dot in ipairs(grip.dots) do
            if on then
                dot:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 1)
            else
                dot:SetColorTexture(1, 1, 1, 0.28)
            end
        end
    end
    local function tip(self)
        local gt = GameTooltip
        if not gt then return end
        gt:SetOwner(self, "ANCHOR_RIGHT")
        gt:AddLine("Size", 1, 1, 1)
        local hints = { { "Drag", "resize" } }
        if reset then hints[2] = { "Right-click", "reset the size" } end
        T.tipHints(gt, hints)
        gt:Show()
    end
    grip:SetScript("OnEnter", function(self)
        light(true)
        tip(self)
    end)
    grip:SetScript("OnLeave", function()
        light(false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    local function bounds()
        if f.GetResizeBounds then return f:GetResizeBounds() end
        local minW, minH = 1, 1
        if f.GetMinResize then minW, minH = f:GetMinResize() end
        local maxW, maxH
        if f.GetMaxResize then maxW, maxH = f:GetMaxResize() end
        return minW, minH, maxW, maxH
    end
    local function cursor()
        local x, y = GetCursorPosition()
        local s = f:GetEffectiveScale()
        return x / s, y / s
    end
    local function stop(self)
        if not self.drag then return end
        self.drag = nil
        self:SetScript("OnUpdate", nil)
        if done then done(f) end
    end
    local function follow(self)
        -- The button may come up outside the game window, where we never
        -- hear of it, so we look for ourselves.
        if not IsMouseButtonDown("LeftButton") then return stop(self) end
        local d = self.drag
        local x, y = cursor()
        local minW, minH, maxW, maxH = bounds()
        local w = max(minW or 1, d.w + x - d.x)
        local h = max(minH or 1, d.h + d.y - y)
        if maxW and maxW > 0 then w = min(w, maxW) end
        if maxH and maxH > 0 then h = min(h, maxH) end
        -- A window that keeps its shape (WindowKit's `aspect`) follows the
        -- mouse with one side, and the other side comes from it.
        -- Of the size that follows the mouse across and the one that follows
        -- it down, the larger wins. Picking by which way the mouse moved more
        -- made the window jump when that changed mid-drag.
        if f.keepAspect then
            local w1, h1 = f.keepAspect(d.w + x - d.x, h, "w", minW, minH, maxW, maxH)
            local w2, h2 = f.keepAspect(w, d.h + d.y - y, "h", minW, minH, maxW, maxH)
            if w1 >= w2 then w, h = w1, h1 else w, h = w2, h2 end
        end
        f:SetSize(w, h)
    end
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local l, t = f:GetLeft(), f:GetTop()
        if l and t then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
        end
        local x, y = cursor()
        self.drag = { x = x, y = y, w = f:GetWidth(), h = f:GetHeight() }
        self:SetScript("OnUpdate", follow)
    end)
    grip:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            if reset then reset(f) end
            return
        end
        stop(self)
    end)
    if grip.SetFrameLevel and f.GetFrameLevel then
        grip:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    end
    return grip
end

-- How far a scrollbar's bottom has to come up to clear the resize grip of
-- the window it's in (`f.grip`), in the scroll frame's units: 0 when the bar
-- doesn't run down beside the grip. A window with no footer puts its lists
-- right down to its bottom edge, where the grip sits.
local function gripRoom(sf, barW)
    local p = sf.GetParent and sf:GetParent()
    local grip
    while p do
        if type(p.grip) == "table" and p.grip.IsShown and p.grip:IsShown() then
            grip = p.grip
            break
        end
        p = p.GetParent and p:GetParent()
    end
    if not (grip and sf.GetEffectiveScale and grip.GetEffectiveScale) then return 0 end
    local s, gs = sf:GetEffectiveScale() or 1, grip:GetEffectiveScale() or 1
    local r, b, t = sf:GetRight(), sf:GetBottom(), sf:GetTop()
    local gl, gr, gt, gb = grip:GetLeft(), grip:GetRight(), grip:GetTop(), grip:GetBottom()
    if not (r and b and t and gl and gr and gt and gb) or s <= 0 then return 0 end
    r, b, t = r * s, b * s, t * s
    gl, gr, gt, gb = gl * gs, gr * gs, gt * gs, gb * gs
    if r <= gl or r - barW * s >= gr or b >= gt or t <= gb then return 0 end
    return (gt - b) / s + 2
end

-- A scrolling list. opts.shadow puts T.scrollShadow on it: true or "TOP"
-- for a list under a fixed bar, "BOTTOM" over one, "BOTH" between two. Its
-- bar stops short of the window's resize grip when it would run into it.
function T.scroll(parent, opts)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
    sf.child = child

    local track = CreateFrame("Frame", nil, sf)
    track:SetWidth(4)
    track:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
    track.bg = T.fill(track, { 1, 1, 1 }, 0.04)
    track.bg:SetAllPoints(track)
    sf.track = track

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(4)
    thumb.tex = T.fill(thumb, { 1, 1, 1 }, 0.27, "ARTWORK")
    thumb.tex:SetAllPoints(thumb)
    if thumb.SetHitRectInsets then thumb:SetHitRectInsets(-6, -6, 0, 0) end
    sf.thumb = thumb

    local function range()
        return sf.GetVerticalScrollRange and sf:GetVerticalScrollRange() or 0
    end

    function sf:setScroll(v, gliding)
        if not gliding and self.GetScript and self:GetScript("OnUpdate") then
            self:SetScript("OnUpdate", nil)
        end
        local r = range()
        v = math.min(max(v or 0, 0), r)
        if self.SetVerticalScroll then self:SetVerticalScroll(v) end
        self:update()
    end

    -- Scrolls to `v` over a moment, slowing as it arrives, rather than
    -- jumping there. The wheel or another setScroll stops it.
    --
    -- We don't hold `v` to the scroll range here. When the content just grew
    -- (a search was cleared and the whole list came back), the game updates
    -- the range only at the end of the frame, so the old short range would
    -- stop us at the top. Each step's setScroll holds it to the range then.
    function sf:glide(v)
        local from = self.GetVerticalScroll and self:GetVerticalScroll() or 0
        local to = max(v or 0, 0)
        if math.abs(to - from) < 1 or not self.GetVerticalScroll then return self:setScroll(to) end
        local t = 0
        self:SetScript("OnUpdate", function(me, dt)
            t = t + (dt or GLIDE_S)
            local k = math.min(1, t / GLIDE_S)
            k = 1 - (1 - k) ^ 3
            me:setScroll(from + (to - from) * k, true)
            if k >= 1 then me:SetScript("OnUpdate", nil) end
        end)
    end

    -- Keeps the list where it's scrolled through a collapse.
    --
    -- Folding a group or shutting a row's details near the bottom makes the
    -- list shorter than the spot we were scrolled to. The game then pulls the
    -- whole list down, and the header we just clicked jumps away from the
    -- mouse. So a list calls sf:hold() right before it collapses something,
    -- and the list then stays at least as tall as its bottom edge was, with
    -- blank space under the last row. A collapse that slides shut calls it as
    -- the slide starts (or on each step), so the blank space grows under the
    -- rows while they slide up, and nothing in view moves but the rows under
    -- what shut.
    --
    -- The blank space goes away as we scroll back up, when the rows grow to
    -- fill the list again, when no row is left in view at all (a search left
    -- a few rows far above us), and when the list hides.
    --
    -- It only works for a list that sets its rows' height with
    -- sf:setContentHeight(h) rather than on sf.child, since it has to know
    -- how tall the rows are without the blank space. WorldMapQuests' drawer
    -- was the first to do it, and AuctionWindow's lists (AW.list) do too.
    sf.held = 0
    function sf:hold()
        if not self.rowsH then return end
        local cur = self.GetVerticalScroll and self:GetVerticalScroll() or 0
        if cur <= 0.5 then return end
        self.held = max(self.held, cur + (self:GetHeight() or 0))
    end

    -- Sets how tall the rows are, `h`. While we hold room under them (see
    -- sf:hold), the scroll child stays taller than that. Rows that grow back
    -- to where we held give it up.
    function sf:setContentHeight(h)
        h = max(h or 0, 0)
        local was = self.rowsH or 0
        self.rowsH = h
        if self.held > 0 and h > was and h >= self.held then self.held = 0 end
        child:SetHeight(max(1, h, self.held))
    end

    -- How tall the rows are, without the blank space we hold under them.
    function sf:contentHeight()
        return self.rowsH or child:GetHeight() or 0
    end

    -- Gives back the blank space we no longer need. Scrolling up shrinks it to
    -- the new bottom edge, so scrolling down never reaches past it again.
    local function letGo(self)
        local held = self.held
        if held <= 0 then return end
        local rows = self.rowsH or 0
        local cur = self.GetVerticalScroll and self:GetVerticalScroll() or 0
        local bottom = cur + (self:GetHeight() or 0)
        if cur <= 0.5 or rows <= cur then held = 0
        elseif bottom < held then held = bottom > rows and bottom or 0 end
        if held ~= self.held then
            self.held = held
            child:SetHeight(max(1, rows, held))
        end
    end

    -- Drops the blank space at once, for a list that hides or gets new rows.
    function sf:letGo()
        if self.held <= 0 then return end
        self.held = 0
        child:SetHeight(max(1, self.rowsH or 0))
    end
    sf:SetScript("OnHide", function(self) self:letGo() end)

    function sf:update()
        letGo(self)
        -- A list that paints only its rows in view (AuctionWindow's) hears
        -- each scroll here.
        if self.onScroll then self:onScroll() end
        local r = range()
        local h = self:GetHeight() or 0
        if r <= 0.5 or h <= 0 then
            track:Hide()
            return
        end
        track:Show()
        local room = gripRoom(self, 4)
        if room ~= (track.gripRoom or 0) then
            track.gripRoom = room
            track:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, room)
        end
        local len = max(1, h - room)
        local th = max(30, len * h / (h + r))
        local cur = self.GetVerticalScroll and self:GetVerticalScroll() or 0
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(len - th) * (cur / r))
    end

    if sf.EnableMouseWheel then sf:EnableMouseWheel(true) end
    -- A scroll inside another (a table on a scrolling page) passes the wheel
    -- on when it has nowhere to go that way, so the page still scrolls under
    -- the mouse.
    --
    -- It passes it on too while the page cuts it off on the side the wheel
    -- goes to. A table whose bottom is below the page's edge first comes up
    -- into view on a scroll down, and only then scrolls its own rows. That
    -- shows more of its rows either way, and the player sees the whole table
    -- before it moves on its own.
    local function outer(self)
        local p = self.GetParent and self:GetParent()
        while p do
            if p.setScroll and p.GetScript and p:GetScript("OnMouseWheel") then return p end
            p = p.GetParent and p:GetParent()
        end
    end
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self.GetVerticalScroll and self:GetVerticalScroll() or 0
        local r = range()
        local o = outer(self)
        local pass = r <= 0.5 or (delta > 0 and cur <= 0.5) or (delta < 0 and cur >= r - 0.5)
        if o and not pass and self.GetTop and o.GetTop then
            local t, b, ot, ob = self:GetTop(), self:GetBottom(), o:GetTop(), o:GetBottom()
            if t and b and ot and ob then
                pass = (delta < 0 and b < ob - 0.5) or (delta > 0 and t > ot + 0.5)
            end
        end
        if pass then
            if o then return o:GetScript("OnMouseWheel")(o, delta) end
            if r <= 0.5 then return end
        end
        self:setScroll(cur - delta * STEP)
    end)
    -- Only keeps the scroll inside the new range, so a glide carries on.
    sf:SetScript("OnScrollRangeChanged", function(self) self:setScroll(
        self.GetVerticalScroll and self:GetVerticalScroll() or 0, true) end)
    sf:SetScript("OnSizeChanged", function(self) self:update() end)

    -- Dragging the thumb. The cursor moves in screen pixels, so we divide by
    -- the effective scale to get back to the frame's units. The drag ends
    -- when the button comes up, when the window hides, or when the button
    -- came up outside the game window, where we never hear of it.
    local function stopDrag(self)
        self:SetScript("OnUpdate", nil)
        self.tex:SetColorTexture(1, 1, 1, self.IsMouseOver and self:IsMouseOver() and 0.45 or 0.27)
    end
    thumb:SetScript("OnMouseDown", function(self)
        local _, y = GetCursorPosition()
        self.from = y / self:GetEffectiveScale()
        self.start = sf.GetVerticalScroll and sf:GetVerticalScroll() or 0
        self:SetScript("OnUpdate", function(me)
            if not IsMouseButtonDown("LeftButton") then return stopDrag(me) end
            local _, cy = GetCursorPosition()
            local h = (sf:GetHeight() or 1) - (track.gripRoom or 0)
            local th = me:GetHeight() or 30
            local r = range()
            local moved = me.from - cy / me:GetEffectiveScale()
            if h - th > 0 then
                sf:setScroll(me.start + moved * r / (h - th))
            end
        end)
        self.tex:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.8)
    end)
    thumb:SetScript("OnMouseUp", stopDrag)
    thumb:SetScript("OnHide", stopDrag)
    thumb:SetScript("OnEnter", function(self)
        if not self:GetScript("OnUpdate") then
            self.tex:SetColorTexture(1, 1, 1, 0.45)
        end
    end)
    thumb:SetScript("OnLeave", function(self)
        if not self:GetScript("OnUpdate") then
            self.tex:SetColorTexture(1, 1, 1, 0.27)
        end
    end)
    local shadow = opts and opts.shadow
    if shadow then
        if shadow ~= "BOTTOM" then T.scrollShadow(sf) end
        if shadow == "BOTTOM" or shadow == "BOTH" then T.scrollShadow(sf, "BOTTOM") end
    end
    return sf
end

-- Holds the scroll of the list `f` sits in (T.scroll's sf:hold), for a part
-- deep inside a page that folds itself, like a "Show less" under a ranking.
-- A list that doesn't set its height with setContentHeight is left alone.
function T.holdScroll(f)
    local p = f
    while p do
        if p.hold and p.setContentHeight then return p:hold() end
        p = p.GetParent and p:GetParent()
    end
end

-- Flashes `f` in the accent, fading out over a moment, to point at it: a
-- settings row we jumped to, or a supply we just added. `T.flash(f, false)`
-- stops it, for a pooled row that's showing something else now.
local FLASH_S = 1.2

function T.flash(f, on)
    if on == false then
        if f.flashTimer then f.flashTimer:SetScript("OnUpdate", nil) end
        if f.flash then f.flash:SetAlpha(0) end
        return
    end
    if not f.flash then
        f.flash = T.fill(f, T.ACCENT, 0, "OVERLAY")
        f.flash:SetAllPoints(f)
    end
    local start = GetTime()
    f.flash:SetAlpha(1)
    f.flash:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.35)
    local timer = f.flashTimer or CreateFrame("Frame", nil, f)
    f.flashTimer = timer
    timer:SetScript("OnUpdate", function(self)
        local t = (GetTime() - start) / FLASH_S
        if t >= 1 then
            f.flash:SetAlpha(0)
            self:SetScript("OnUpdate", nil)
        else
            f.flash:SetAlpha(1 - t)
        end
    end)
end

-- The shadow a fixed bar casts down onto what's under it, filling `host`.
-- Media/Shadow.tga fades it from top to bottom, and its two ends fade in
-- from the sides, so it doesn't stop with a hard edge at either side.
local SHADOW_A = 0.55
local SHADOW_END = 16
local SHADOW_TEX = MEDIA .. "Shadow"
local BLACK = { 0, 0, 0 }
-- `up` turns it over, dark at the bottom, for a shadow cast up from a bar
-- under a list.
function T.shadow(host, up)
    local function piece()
        local t = host:CreateTexture(nil, "OVERLAY")
        t:SetTexture(SHADOW_TEX)
        if up then t:SetTexCoord(0, 1, 1, 0) end
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        return t
    end
    local l, m, r = piece(), piece(), piece()
    l:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    l:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
    l:SetWidth(SHADOW_END)
    r:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    r:SetWidth(SHADOW_END)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0)
    m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT", 0, 0)
    m:SetVertexColor(0, 0, 0, SHADOW_A)
    if gradient(l, BLACK, 0, SHADOW_A) == false then l:SetVertexColor(0, 0, 0, SHADOW_A / 2) end
    if gradient(r, BLACK, SHADOW_A, 0) == false then r:SetVertexColor(0, 0, 0, SHADOW_A / 2) end
    return host
end

-- A shadow along the top of a list that scrolls under a fixed bar, like a
-- table's column headers or a filter row. It shows while the list is scrolled
-- down, so the bar reads as a layer above the rows, and goes at the top.
--
-- It follows the scroll frame's own OnVerticalScroll, which every way of
-- scrolling sets off, the wheel, the thumb and a list scrolled back by code.
-- Half a pixel of slack, because a scroll back to the top can stop a hair
-- short of 0.
--
-- It fades in over SHADOW_FADE_S as the list leaves the top, and out the
-- same way when it gets back.
--
-- T.scrollShadow(sf, "BOTTOM") is the same along the bottom, for a list with
-- a fixed bar under it. It shows while there's more of the list below.
local SHADOW_H = 12
local SHADOW_FADE_S = 0.2
function T.scrollShadow(sf, edge)
    local bottom = edge == "BOTTOM"
    -- It starts a pixel past the list. The game rounds where a texture
    -- lands to the screen's pixels but not where the list cuts off its rows,
    -- so starting level with the list could leave a pixel of a row past it.
    local host = CreateFrame("Frame", nil, sf)
    local up = T.pixel(sf)
    if bottom then
        host:SetPoint("BOTTOMLEFT", sf, "BOTTOMLEFT", 0, -up)
        host:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, -up)
    else
        host:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, up)
        host:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, up)
    end
    host:SetHeight(SHADOW_H + up)
    host:SetFrameLevel((sf:GetFrameLevel() or 0) + 20)
    T.shadow(host, bottom)
    -- We lift it over the rows again each time it shows. Raising the window
    -- re-levels everything in it, which can leave the rows above the shadow.
    local want, alpha = 0, 0
    local function step(_, dt)
        local d = (dt or 0) / SHADOW_FADE_S
        alpha = want > alpha and math.min(want, alpha + d) or math.max(want, alpha - d)
        host:SetAlpha(alpha)
        if alpha == want then
            host:SetScript("OnUpdate", nil)
            if alpha == 0 then host:Hide() end
        end
    end
    local function refresh(_, _, first)
        local s = sf.GetVerticalScroll and sf:GetVerticalScroll() or 0
        local on = s > 0.5
        if bottom then
            local range = sf.GetVerticalScrollRange and sf:GetVerticalScrollRange() or 0
            -- Blank space a collapse holds under the rows (sf:hold) isn't
            -- more of the list.
            if (sf.held or 0) > 0 and sf.rowsH then
                range = min(range, max(0, sf.rowsH - (sf:GetHeight() or 0)))
            end
            on = range - s > 0.5
        end
        if on and not host:IsShown() then
            host:SetFrameLevel((sf:GetFrameLevel() or 0) + 20)
            host:Show()
        end
        want = on and 1 or 0
        if first then
            alpha = want
            host:SetAlpha(alpha)
            host:SetShown(on)
        elseif alpha ~= want then
            host:SetScript("OnUpdate", step)
        end
    end
    sf:HookScript("OnVerticalScroll", refresh)
    -- The rows below come and go as the list grows, shrinks or is sized.
    if bottom then
        sf:HookScript("OnScrollRangeChanged", function() refresh() end)
        sf:HookScript("OnSizeChanged", function() refresh() end)
    end
    refresh(nil, nil, true)
    if bottom then sf.shadowBottom = host else sf.shadow = host end
    return host
end

-- The same sideways: a 4 pixel track under the frame, which hides when
-- everything fits, and the wheel scrolls sideways while there is somewhere to
-- go. The track goes on `holder`, outside the scroll frame, which would clip it.
function T.hscroll(parent, holder)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
    sf.child = child

    local track = CreateFrame("Frame", nil, holder or parent)
    track:SetHeight(4)
    track:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", 0, -5)
    track:SetPoint("TOPRIGHT", sf, "BOTTOMRIGHT", 0, -5)
    track.bg = T.fill(track, { 1, 1, 1 }, 0.08)
    track.bg:SetAllPoints(track)
    sf.track = track

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetHeight(4)
    thumb.tex = T.fill(thumb, { 1, 1, 1 }, 0.35, "ARTWORK")
    thumb.tex:SetAllPoints(thumb)
    if thumb.SetHitRectInsets then thumb:SetHitRectInsets(0, 0, -6, -6) end
    sf.thumb = thumb

    local function range()
        return sf.GetHorizontalScrollRange and sf:GetHorizontalScrollRange() or 0
    end
    local function cur()
        return sf.GetHorizontalScroll and sf:GetHorizontalScroll() or 0
    end

    function sf:setScroll(v)
        v = math.min(max(v or 0, 0), range())
        if self.SetHorizontalScroll then self:SetHorizontalScroll(v) end
        self:update()
    end

    function sf:update()
        local r = range()
        local w = self:GetWidth() or 0
        local on = r > 0.5 and w > 0
        if self.EnableMouseWheel then self:EnableMouseWheel(on) end
        if not on then
            track:Hide()
            return
        end
        track:Show()
        local tw = max(30, w * w / (w + r))
        thumb:SetWidth(tw)
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", track, "LEFT", (w - tw) * (cur() / r), 0)
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        self:setScroll(cur() - delta * STEP)
    end)
    sf:SetScript("OnScrollRangeChanged", function(self) self:setScroll(cur()) end)
    sf:SetScript("OnSizeChanged", function(self) self:update() end)

    thumb:SetScript("OnMouseDown", function(self)
        local x = GetCursorPosition()
        self.from = x / self:GetEffectiveScale()
        self.start = cur()
        self:SetScript("OnUpdate", function(me)
            local cx = GetCursorPosition()
            local w = sf:GetWidth() or 1
            local tw = me:GetWidth() or 30
            local moved = cx / me:GetEffectiveScale() - me.from
            if w - tw > 0 then sf:setScroll(me.start + moved * range() / (w - tw)) end
        end)
        self.tex:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.8)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        self.tex:SetColorTexture(1, 1, 1, 0.35)
    end)
    return sf
end

-- =============================================================
-- Tooltips
-- =============================================================
-- The lines we add to a tooltip that say how to use something ("Click",
-- "Drag", "Alt+click") or give an ID are smaller than the rest of its text,
-- so they don't compete with what the tooltip is about. BayovCore's Tooltips
-- page sets the size (Modules/Tooltip.lua). Where that module isn't loaded,
-- like in Buff Coordinator, the size is TIP_SMALL.
--
-- A tooltip reuses its lines' font strings for whatever it shows next, and a
-- font set on one stays. So we remember each line's font before we shrink it,
-- and put it back when the tooltip is cleared.
--
-- EUI's tooltip skin sets the font of every line when a tooltip shows
-- (_ttFonts in EllesmereUIBlizzardSkin), which made our lines big again. It
-- happened on the first fill of a hover only, since a refill of a tooltip
-- that's already showing doesn't show it again. So the Alt+click hint in the
-- bags went big, then small at the bag button's next refill. We hook OnShow
-- too, after EUI, and make our lines small again. We change only the size,
-- so EUI's face and outline stay.
T.TIP_SMALL = 10

local shrunk = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })

local function unshrink(fs)
    local o = shrunk[fs]
    if not o then return end
    shrunk[fs] = nil
    -- Back on its font object when that still gives the font it had, so it
    -- follows a later change of the object (EUI's font setting). Otherwise
    -- the exact font it had.
    local obj = o.obj
    if obj and obj.GetFont and select(1, obj:GetFont()) == o.path
       and select(2, obj:GetFont()) == o.size then
        fs:SetFontObject(obj)
    else
        fs:SetFont(o.path, o.size, o.flags)
    end
end

-- The left texts of each tooltip's key hints (T.tipHints), so code that
-- moves lines can tell a hint by its text wherever it went.
local hintTexts = setmetatable({}, { __mode = "k" })

local function onCleared(tip)
    hintTexts[tip] = nil
    for fs, o in pairs(shrunk) do
        if o.tip == tip then unshrink(fs) end
    end
end

local function smallSize()
    return NS.Tooltip and NS.Tooltip.smallSize and NS.Tooltip.smallSize() or T.TIP_SMALL
end

-- The font the line has now, in the small size, or the font it was matched
-- to (T.tipDone).
local function small(fs)
    local o = shrunk[fs]
    if o and o.want then
        fs:SetFont(o.want[1], o.want[2], o.want[3])
        return
    end
    local path, _, flags = fs:GetFont()
    if path then fs:SetFont(path, smallSize(), flags) end
end

-- Remembers line `fs`'s font, to put it back when the tooltip clears.
--
-- We keep the line's text with it too. The tooltip's lines are reused by the
-- next fill, and a fill that doesn't clear the tooltip first would otherwise
-- leave a line small that now holds something else. Moving from one item to
-- the next made "Click" small on one and big on the other, by whichever line
-- the hints landed on.
local function remember(tip, fs)
    local o = shrunk[fs]
    if not o then
        local path, size, flags = fs:GetFont()
        if not path then return false end
        o = { obj = fs.GetFontObject and fs:GetFontObject(), path = path, size = size,
              flags = flags }
        shrunk[fs] = o
    end
    o.tip, o.text = tip, fs:GetText()
    return true
end

local function shrink(tip, fs)
    if not fs or not remember(tip, fs) then return end
    shrunk[fs].want = nil
    small(fs)
end

-- After EUI set every line's font on show. Showing the tooltip again makes
-- it fit the smaller lines. It's already shown, so OnShow doesn't run again.
-- A line that holds other text now is from an earlier fill, so it goes back.
local function onShow(tip)
    local any = false
    for fs, o in pairs(shrunk) do
        if o.tip == tip then
            -- Another addon's fill can leave a secret text on a line we
            -- shrank, and comparing a secret is an error. Such a line isn't
            -- ours any more, so it goes back.
            local text = fs:GetText()
            local secret = _G.issecretvalue
                and (_G.issecretvalue(text) or _G.issecretvalue(o.text))
            if not secret and text == o.text then
                small(fs)
                any = true
            else
                unshrink(fs)
            end
        end
    end
    if any then pcall(tip.Show, tip) end
end

local function hook(tip)
    if hooked[tip] or not tip.HookScript then return end
    hooked[tip] = true
    tip:HookScript("OnTooltipCleared", onCleared)
    tip:HookScript("OnHide", onCleared)
    tip:HookScript("OnShow", onShow)
end

local function lineStrings(tip, i)
    local name = tip.GetName and tip:GetName()
    if not name then return nil end
    local l, r = tipLineNames(name, i)
    return _G[l], _G[r]
end

-- Line `i` of the tooltip small, or back to its own size when `small` is false.
function T.tipLineSmall(tip, i, small)
    if not (tip and i and i >= 1) then return end
    hook(tip)
    local l, r = lineStrings(tip, i)
    if small == false then
        if l then unshrink(l) end
        if r then unshrink(r) end
    else
        shrink(tip, l)
        shrink(tip, r)
    end
end

function T.tipLineIsSmall(tip, i)
    local l = lineStrings(tip, i)
    local o = l and shrunk[l]
    return o ~= nil and not o.want
end

-- The last `n` lines of the tooltip small (1 when left out), right after we
-- added them.
function T.tipSmall(tip, n)
    if not (tip and tip.NumLines) then return end
    local last = tip:NumLines()
    if type(last) ~= "number" then return end
    for i = last - (n or 1) + 1, last do T.tipLineSmall(tip, i) end
end

-- Key hints at the bottom of a tooltip, under a blank line. Every BayovCore
-- tooltip says its clicks and drags this one way: small and dim, the key on
-- the left a little brighter than what it does on the right. `hints` is
-- { { "Click", "change who's on it" }, { "Shift-click", "..." } }.
--
-- Keys are "Click", "Right-click", "Shift-click", "Alt-click", "Ctrl-click",
-- "Shift-right-click", "Double-click", "Drag" and "Scroll". What it does is
-- a short phrase in lower case with no full stop.
T.TIP_HINT_KEY, T.TIP_HINT_TEXT = T.A_SUB, T.A_DIM
function T.tipHints(tip, hints)
    if not hints or #hints == 0 then return end
    -- One blank line above the hints. None when the tooltip already ends in
    -- a blank line ("" or " "), or in hints from an earlier call, so a
    -- helper's hints and a caller's extra one stay together.
    local n = tip.NumLines and tip:NumLines()
    if type(n) == "number" and n >= 1 then
        local last = lineStrings(tip, n)
        local text = last and last:GetText()
        -- A spell's own lines can be secret in combat, and a secret line
        -- isn't blank as far as we can tell.
        local hidden = _G.issecretvalue and _G.issecretvalue(text)
        local blank = last and not hidden and (text == nil or (type(text) == "string" and not text:find("%S")))
        if not (blank or T.tipLineIsHint(tip, n)) then tip:AddLine(" ") end
    end
    local k, v = T.TIP_HINT_KEY, T.TIP_HINT_TEXT
    local texts = hintTexts[tip] or {}
    hintTexts[tip] = texts
    for _, h in ipairs(hints) do
        tip:AddDoubleLine(h[1], h[2], k, k, k, v, v, v)
        texts[h[1]] = true
    end
    T.tipSmall(tip, #hints)
end

-- Whether line `i` is one of the key hints, or the blank line above them.
function T.tipLineIsHint(tip, i)
    local texts = hintTexts[tip]
    local l = texts and lineStrings(tip, i)
    if not l then return false end
    local text = l:GetText()
    if _G.issecretvalue and _G.issecretvalue(text) then return false end
    return text ~= nil and texts[text] == true
end

-- Shows tooltip `tip` with every line under the title in one size.
--
-- A tooltip skin (EUI's) sets the font of every line when the tooltip shows.
-- Lines added after that keep the game's own font, and so does a line the
-- tooltip never had before. A spell's tooltip shows as soon as the spell is
-- set, so the lines we add under it came out a different size from the
-- spell's. We give every line the font of the first one under the title,
-- and put each back when the tooltip clears. The small hint lines stay
-- small.
function T.tipDone(tip)
    tip:Show()
    local n = tip.NumLines and tip:NumLines()
    if type(n) ~= "number" then return end
    local path, size, flags
    for i = 2, n do
        local l = lineStrings(tip, i)
        if l and not shrunk[l] then
            path, size, flags = l:GetFont()
            break
        end
    end
    if not path then return end
    hook(tip)
    local changed = false
    for i = 2, n do
        local l, r = lineStrings(tip, i)
        for _, fs in ipairs({ l, r }) do
            if fs and not shrunk[fs] then
                local p, s = fs:GetFont()
                if (p ~= path or s ~= size) and remember(tip, fs) then
                    shrunk[fs].want = { path, size, flags }
                    small(fs)
                    changed = true
                end
            end
        end
    end
    if changed then tip:Show() end
end

-- A tooltip's lines. Each is one of:
--   "text"                 grey (.8), wrapped
--   { text }               white, wrapped
--   { text, r, g, b }      in that colour (wrap = false keeps it one line)
--   { left, right }        a double line: left grey, right white
-- `color` ({ r, g, b }) is the colour of a line that doesn't give its own:
-- a string, a { text } and a double line's left side.
local TIP_GREY, TIP_WHITE = { 0.8, 0.8, 0.8 }, { 1, 1, 1 }
local function tipLine(tip, l, color)
    if type(l) ~= "table" then
        local c = color or TIP_GREY
        return tip:AddLine(l, c[1], c[2], c[3], true)
    end
    if l[2] ~= nil and l[3] == nil then
        local c = color or TIP_GREY
        return tip:AddDoubleLine(l[1], l[2], c[1], c[2], c[3], 1, 1, 1)
    end
    if l[2] == nil then
        local c = color or TIP_WHITE
        return tip:AddLine(l[1], c[1], c[2], c[3], l.wrap ~= false)
    end
    tip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1, l.wrap ~= false)
end

-- Adds a white title, `lines` and the key `hints` to a tooltip that already
-- has its owner, like the one a tile or a game hook hands us. `color` is
-- the colour of lines that don't give their own (tipLine above).
function T.tipAdd(tip, title, lines, hints, color)
    if title then tip:AddLine(title, 1, 1, 1) end
    for _, l in ipairs(lines or {}) do tipLine(tip, l, color) end
    T.tipHints(tip, hints)
end

-- Where a tooltip goes: "ANCHOR_TOP", or "TOP" for short.
local function tipAnchor(a)
    if not a then return "ANCHOR_RIGHT" end
    if a:find("^ANCHOR_") then return a end
    return "ANCHOR_" .. a
end

-- A tooltip with a white title, then `lines` (T.tipAdd), then the key
-- `hints` under a blank line. `opts` is where it goes ("RIGHT", the default,
-- "TOP", "BOTTOM", "LEFT", "CURSOR", "NONE"), or a table
-- { anchor, x, y, color }: the place, an offset from it, and the colour of
-- lines that don't give their own.
function T.tip(owner, title, lines, hints, opts)
    local tip = _G.GameTooltip
    if not tip then return end
    local anchor, x, y, color = opts, nil, nil, nil
    if type(opts) == "table" then
        anchor, x, y, color = opts.anchor, opts.x, opts.y, opts.color
    end
    anchor = tipAnchor(anchor)
    if x or y then
        tip:SetOwner(owner, anchor, x or 0, y or 0)
    else
        tip:SetOwner(owner, anchor)
    end
    tip:SetText(title, 1, 1, 1)
    T.tipAdd(tip, nil, lines, hints, color)
    T.tipDone(tip)
end

-- =============================================================
-- Popups
-- =============================================================
-- A question in the game's own popup: yes or no (T.confirm), or a line to
-- type (T.ask). Each kind is one dialog, made the first time it's needed,
-- and named after the addon, so BayovCore's and Buff Coordinator's don't
-- share one.
--
-- Each dialog keeps its own question. A name box may still be open when a
-- yes or no comes up, like Save as asking to replace a plan, and its Accept
-- must answer the name, never the other question. Without the game's
-- popups (the tests) a question answers itself: yes, or the line it starts
-- with.
local asking = {}
-- The longest line a player may type.
local ASK_LETTERS = 120

local function dialog(key, withBox)
    local dialogs = _G.StaticPopupDialogs
    local which = ADDON:upper() .. "_" .. key
    if dialogs[which] then return which end
    local d = {
        text = "%s",
        button1 = withBox and (_G.ACCEPT or "Accept") or (_G.YES or "Yes"),
        button2 = withBox and (_G.CANCEL or "Cancel") or (_G.NO or "No"),
        hasEditBox = withBox,
        maxLetters = withBox and ASK_LETTERS or nil,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(self)
            local box = self and (self.editBox or self.EditBox)
            local a = asking[key]
            if box and a then
                box:SetText(a.default or "")
                box:HighlightText()
            end
        end,
        OnAccept = function(self)
            local a = asking[key]
            asking[key] = nil
            if not a then return end
            if not withBox then return a.fn() end
            local box = self and (self.editBox or self.EditBox)
            local text = box and box:GetText()
            text = text and text:match("^%s*(.-)%s*$")
            if text and (text ~= "" or a.empty) then a.fn(text) end
        end,
        OnCancel = function() asking[key] = nil end,
    }
    if withBox then
        d.EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            d.OnAccept(parent)
            parent:Hide()
        end
        d.EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end
    end
    dialogs[which] = d
    return which
end

local function popups()
    return _G.StaticPopup_Show ~= nil and _G.StaticPopupDialogs ~= nil
end

-- Runs `fn` once the player says yes to `text`.
function T.confirm(text, fn)
    if not popups() then return fn() end
    local which = dialog("CONFIRM", false)
    asking.CONFIRM = { fn = fn }
    _G.StaticPopup_Show(which, text)
end

-- Asks for a line with `text`, starting from `default`, and runs `fn(line)`
-- with what the player typed, trimmed. An empty line is no answer, unless
-- `opts.empty` (a note that may stay empty). `opts.accept` names the yes
-- button when it isn't Accept, like Send.
function T.ask(text, default, fn, opts)
    opts = opts or {}
    if not popups() then
        if (default and default ~= "") or opts.empty then return fn(default or "") end
        return
    end
    local which = dialog("ASK", true)
    _G.StaticPopupDialogs[which].button1 = opts.accept or _G.ACCEPT or "Accept"
    asking.ASK = { default = default, fn = fn, empty = opts.empty }
    _G.StaticPopup_Show(which, text)
end

return T
