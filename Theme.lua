-- Theme -- Buff Coordinator's own part of the look, on top of
-- Shared/Theme.lua.
--
-- The controls, menus, tooltips and fades are in the shared file, which
-- BayovCore loads too, so our window looks like BayovCore's. Here is what's
-- only ours: our sizes, a little smaller than BayovCore's because our window
-- is small and holds a long list, the accent and font from our settings,
-- what each colour means (T.COLOR) and the tooltips of a buff's spell.
--
-- The accent and the font come from our settings, so T.ACCENT is one table
-- we change in place, and T.restyle puts a new one on everything already
-- made.

local _, NS = ...
local O = NS.Options

local floor = math.floor

local T = NS.Theme

-- The type scale. Every text in the window is one of these sizes.
--
-- `title` is the window's name, `tab` a page's tab, `label` a row's name,
-- `body` a description, a status or a row's detail, and `caption` the small
-- print, like a section heading or the blessing table's counts.
T.SIZE = { title = 18, tab = 13, label = 12, body = 11, caption = 10 }
T.CONTROL = {
    button   = { w = 60, h = 20, size = T.SIZE.body },
    toggle   = { w = 32, h = 16, knob = 10 },
    range    = { h = 14, knobW = 8, knobH = 12 },
    heading  = { h = 24, size = T.SIZE.caption + 1, y = 5 },
    chip     = { h = 16, size = T.SIZE.caption, pad = 12 },
    segment  = { h = 22, size = T.SIZE.body },
    dropdown = { w = 150, h = 20, row = 20, size = T.SIZE.body },
    edit     = { w = 76, h = 22, size = T.SIZE.label },
    revert   = 16,
    menu     = { size = T.SIZE.tab, right = T.SIZE.body },
}

-- Our menus light a row grey under the mouse, and only the pick in the
-- accent, the way the plan picker shows the plan in use.
T.GREY_HOVER = true

-- What a colour means, the same everywhere: on the cards, in the constraints
-- panel, in the legend, on the HUD, the coverage strip and the raid pane.
-- One colour, one meaning:
--   hand     gold    set by hand
--   bad      red     missing, or set by hand but it can't be done
--   low      orange  running out
--   up       green   up, or auto went by what was set by hand
--   idle     grey    not here, or not needed
--   changed  blue    changed in your draft. It's the accent itself, so it
--                    follows the accent setting.
--
-- The HUD's missing and running out are the player's own glow colours
-- (O.COLORS), which start out as this red and orange.
T.COLOR = {
    hand = { 1.00, 0.82, 0.00 },
    bad = { 1.00, 0.25, 0.22 },
    low = { 1.00, 0.58, 0.15 },
    up = { 0.36, 0.86, 0.56 },
    idle = { 0.55, 0.55, 0.55 },
    changed = T.ACCENT,
}
-- An assignment nobody here can give, in the orange of running out.
T.COLOR.gap = T.COLOR.low

-- A chip that only tells, like View only, and means none of the above.
T.NEUTRAL = { 0.75, 0.75, 0.75 }
-- Dim words in a line of text, for what's said in passing: "(busy: Kings)".
T.DIM = "|cff8c8c8c"

-- The colours as the legend explains them, in the words of what's drawn.
T.LEGEND = {
    { color = "hand", word = "Gold", text = "An override. A gold dot after a name, or a gold line under an icon." },
    { color = "bad", word = "Red",
      text = "Missing, an override that can't be done, or one that leaves someone without a buff." },
    { color = "low", word = "Orange",
      text = "Running out soon, nobody here can give it, or an override gives someone a buff they rank lower." },
    { color = "up", word = "Green", text = "Up, or blessings a player set for themselves." },
    { color = "idle", word = "Grey", text = "Not here, not needed, or an override that does nothing." },
    { color = "changed", word = "Blue", text = "Changed in your draft." },
}

-- A colour of T.COLOR (or any { r, g, b }) as the start of a coloured run of
-- text, "|cffff4038".
function T.hex(key)
    local c = type(key) == "table" and key or T.COLOR[key]
    return string.format("|cff%02x%02x%02x", floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255))
end

-- A tooltip line for T.tip in a colour of T.COLOR.
function T.line(text, key)
    local c = T.COLOR[key]
    return { text, c[1], c[2], c[3] }
end

-- The largest size of the DOWNRANK word that fits an icon, and the smallest
-- we'd still read. An icon narrower than that gets the smallest, a little
-- wider than itself.
--
-- We step by half a size so the word gets as big as the icon allows. Whole
-- steps left it a full size smaller than it had to be on a 38 wide raid buff
-- icon (ticket #50).
local DOWNRANK_SIZES = { 12, 11.5, 11, 10.5, 10, 9.5, 9, 8.5, 8, 7.5, 7, 6.5, 6 }

-- Shows or hides the DOWNRANK word along the top of icon `f`, in `color`
-- (orange by default), fitting `room` wide (the icon's width by default).
-- `drop` moves it further down, to clear other text on that edge. `scale`
-- makes the word that much bigger than what fits, like 1.2 on the widgets'
-- icons, where the user wanted it larger even if it pokes past the edges
-- (ticket #50).
function T.downrank(f, on, color, room, drop, scale)
    local tag = f.downrankTag
    if not on then
        if tag then tag:Hide() end
        return
    end
    if not tag then
        tag = (f.over or f):CreateFontString(nil, "OVERLAY")
        tag:SetJustifyH("CENTER")
        tag:SetWordWrap(false)
        f.downrankTag = tag
    end
    room = room or f:GetWidth()
    local y = -(drop or 0) - 2 * T.pixel(f)
    local fits = T.BOLD .. room .. "/" .. (scale or 1) .. "/" .. y .. "/" .. f:GetWidth()
    if f.downrankFits ~= fits then
        f.downrankFits = fits
        -- The string's width leaves out its outline, so we keep a margin on
        -- each side. Without it the word on a 38 wide raid buff icon came
        -- out a pixel or two past the icon's edges (ticket #30).
        local fit, size = room - 4, nil
        for _, s in ipairs(DOWNRANK_SIZES) do
            size = s
            tag:SetFont(T.BOLD, size, "OUTLINE")
            tag:SetText(NS.Tracking.DOWNRANK)
            if tag:GetStringWidth() <= fit then break end
        end
        if scale and scale ~= 1 then tag:SetFont(T.BOLD, size * scale, "OUTLINE") end
        -- We anchor the word to both edges of the icon, the same distance out
        -- on each side, and center it in there. Anchored by its top middle
        -- alone, the game rounded its left edge to a pixel and the word sat
        -- off center.
        local pad = math.max(0, (tag:GetStringWidth() - f:GetWidth()) / 2) + 4
        tag:ClearAllPoints()
        tag:SetPoint("TOPLEFT", f, "TOPLEFT", -pad, y)
        tag:SetPoint("TOPRIGHT", f, "TOPRIGHT", pad, y)
    end
    color = color or T.COLOR.low
    tag:SetTextColor(color[1], color[2], color[3], 1)
    tag:Show()
end

-- =============================================================
-- The panel art
-- =============================================================
-- BayovCore's panel and grain are copies of EllesmereUI's files, which we
-- can't ship. So when BayovCore is loaded we draw its own files from its
-- folder, the same way it does: turned upside down, desaturated and tinted.
-- Then our window and BayovCore's look the same.
--
-- Without BayovCore we draw Media/Panel.tga and Media/Grain.tga, our own,
-- drawn by bayovui/build/panel_texture.py to look like BayovCore's at the
-- same size. Ours is drawn the way it shows, so it isn't turned upside down.
local OWN_PANEL, OWN_GRAIN = T.media("Panel"), T.media("Grain")
local BAYOV_PANEL = [[Interface\AddOns\BayovCore\Media\Panel.png]]
local BAYOV_GRAIN = [[Interface\AddOns\BayovCore\Media\Grain.tga]]

local function bayovCore()
    local api = _G.C_AddOns
    if api and api.IsAddOnLoaded then return api.IsAddOnLoaded("BayovCore") and true or false end
    return _G.IsAddOnLoaded and _G.IsAddOnLoaded("BayovCore") and true or false
end

local function panelArt()
    local theirs = bayovCore()
    T.PANEL_TEX = theirs and BAYOV_PANEL or OWN_PANEL
    T.GRAIN_TEX = theirs and BAYOV_GRAIN or OWN_GRAIN
    T.PANEL_FLIP = theirs
end
panelArt()

-- =============================================================
-- The accent and the font
-- =============================================================
-- Reads the accent and the font from our settings, and which panel art we
-- draw. By the time our settings load, every addon has.
function T.load()
    local c = O.color("accent")
    T.ACCENT[1], T.ACCENT[2], T.ACCENT[3] = c[1], c[2], c[3]
    T.FONT = O.fontPath(O.get("windowFont"))
    T.BOLD = T.FONT:find("PTSansNarrow%-Regular") and T.PT_BOLD or T.FONT
    panelArt()
    T.restylePanels()
end

NS.listen("loaded", T.load)
NS.listen("option", function(key)
    if key == nil or key == "accent" or key == "windowFont" then
        local font, bold = T.FONT, T.BOLD
        T.load()
        T.restyle(font, bold)
    end
end)

-- =============================================================
-- Spell tooltips
-- =============================================================
-- An icon of a buff or debuff shows the game's own tooltip of its spell,
-- then ours under it. The spell is the one that puts it up, so a totem
-- shows the totem and Moonkin Aura shows Moonkin Form. Of a buff with
-- ranks, it's the best rank the highest level in the group has, so the
-- numbers are the ones the raid gets, not rank 1's. A judgement shows the
-- judgement, not the seal it's learned with. A buff's `tip` (Data.lua) wins
-- over all of it.
function T.tipSpell(b)
    if b.tip then return b.tip end
    local own = type(b.cast) == "number" and b.cast or b.spells[1]
    if b.learn or not b.ranks then return own end
    local top
    for _, m in ipairs(NS.Roster.list()) do
        if m.level and m.level > (top or 0) then top = m.level end
    end
    local _, spell = NS.Duties.rankFor(b, top)
    return spell or own
end

-- Starts tooltip `tip`, owned already, with the game's tooltip of `spell`,
-- else of buff `b`'s (T.tipSpell), else with `title`. Returns whether it
-- shows the spell.
function T.spellHead(tip, b, title, spell)
    local id = spell or (b and T.tipSpell(b))
    if id and pcall(tip.SetSpellByID, tip, id) and (tip:NumLines() or 0) > 0 then return true end
    tip:SetText(title or (b and NS.Tracking.title(b)) or "", 1, 1, 1)
    return false
end

-- The spell's tooltip (T.spellHead), then our `lines` and `hints` under it,
-- each after a blank line.
function T.spellTip(owner, b, title, lines, hints, spell)
    local tip = _G.GameTooltip
    if not tip then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    T.spellHead(tip, b, title, spell)
    if lines and #lines > 0 then
        tip:AddLine(" ")
        for _, l in ipairs(lines) do
            if type(l) == "table" then
                tip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1, true)
            else
                tip:AddLine(l, 0.8, 0.8, 0.8, true)
            end
        end
    end
    if hints and #hints > 0 then
        tip:AddLine(" ")
        T.tipHints(tip, hints)
    end
    T.tipDone(tip)
end

return T
