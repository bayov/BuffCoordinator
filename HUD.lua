-- The HUD: one icon for each of our assignments, and the Next buff button.
--
-- Each icon shows how many of its players have the buff ("14/15"), the time
-- left on the one that runs out first, and glows when someone is missing
-- it. A click buffs the next one (Buffer.lua). All our blessings share one
-- icon, because we put one blessing on each person, whichever it is.
--
-- An assignment we're a backup for has an icon too, tagged "backup". It
-- only glows once someone has been missing the buff for a while.
--
-- The Next buff button first in the row (the auto-buff button in the code)
-- walks through every assignment of ours in turn. It wears the icon of the
-- spell its next press casts, or our logo when there's nothing to cast. So
-- it often shows the same spell as an icon beside it, and it looks unlike
-- the icons to tell the two apart. It has a size of its own (square and
-- taller than the icons by default), a border instead of the glow (black,
-- blue under the mouse), and a larger count of who's still to buff, red
-- when someone is missing a buff and yellow when only some run out soon.
-- The icon of that assignment glows, and one glow is enough. All of that is
-- on its own part of the HUD tab ("Next buff button"). It's
-- also how we move the HUD (Shift-drag it, or Shift-click it for move mode
-- and the arrow keys) and open the assignments window (Right-click it). A
-- key can press it too ("Next buff" in the game's key bindings), and a line
-- under it says what the next press does, like "Fortitude > Grom (group 3)".
-- In combat it says "mouseover: Fortitude" when the key is bound, since
-- that's what the key does there. Without a key it's a click, which casts on
-- our friendly target, so it says "Fortitude on your friendly target"
-- (Buffer.lua).
--
-- The drag and the click that start a move need Shift because the button
-- casts on the mouse press itself when the game's "cast on key down" setting
-- is on. A plain drag would put a buff on someone first.
--
-- An icon's colour says what a click can do:
--   red        someone is missing the buff and a click reaches them (the
--              "Missing colour" setting)
--   orange     a buff runs out soon (the "Running out colour" setting)
--   mouseover  in combat, someone is missing it and a click casts it on our
--              friendly target (the key on our mouseover). In colour, with
--              a thin ring instead of the moving glow.
--   dim        someone is missing it but a click can't help now: they're
--              out of reach (far, out of sight, offline), we can't cast it
--              (no reagent, no mana), or in combat it can't pick a blessing
-- The tooltip names who is missing it and why. Anything missing keeps the
-- HUD from fading, even when the icon is dim.
--
-- Shouts and totems last a couple of minutes, so between pulls they're
-- down more often than not. Out of combat a missing one keeps the idle look,
-- with its count but no glow and no sound, and doesn't keep the HUD from
-- fading. It lights up in combat.
--
-- The pull check: on a ready check the HUD flashes once and says which of
-- our buffs run out within the fight, like "Refresh 3 Fortitude: Grom,
-- Jaina, Uther" (Tracking.lua). When our assignments change we say so in
-- one line and flash the new icon. While nothing is due the HUD can fade
-- almost away (the "Fade when all is up" setting).
--
-- Preview on the HUD tab of the window previews the HUD with made-up
-- buffs in every state, out of combat (H.preview). The made-up icons cast
-- nothing. Group buffs (GroupBuffs.lua) shows made-up buffs with it.
--
-- The icons are secure buttons, and the game doesn't let us add, move or
-- hide those in combat. So the HUD is laid out out of combat only, and a
-- change that comes in combat waits until it ends.

local _, NS = ...
local D, R, Du, Tr, B, O, T = NS.Data, NS.Roster, NS.Duties, NS.Tracking, NS.Buffer, NS.Options, NS.Theme
local classWord, andList = NS.classWord, NS.andList
local floor, ceil, max = math.floor, math.ceil, math.max
local format = string.format

local H = {}
NS.HUD = H

local WHITE = { 1, 1, 1 }
-- Up, and not here or not needed (Theme.lua's T.COLOR). Missing and running
-- out are the player's own glow colours.
local UP, IDLE = T.COLOR.up, T.COLOR.idle
local ICON_ZOOM = 0.25
local GLOW_LINES, GLOW_LENGTH, GLOW_THICKNESS_PX, GLOW_FREQUENCY = 8, 10, 2, 0.5
local DECIMALS_BELOW = 3
local LARGE_TEXT = 15
-- The countdown turns the running-out colour with this long left on a short
-- buff or a debuff. A long buff uses the rebuff setting.
local WARN_SHORT = 15
-- The HUD's opacity while nothing is due and the fade is on.
local FADED = 0.15
-- How long the HUD takes to go from one opacity to another, like fading
-- away once all is up or coming back when a buff is due. It glides rather
-- than jumps, so the change doesn't pull the eye.
local GLIDE_S = 0.6
local FLASH_FOR = 0.8
-- At most one missing sound this often.
local SOUND_EVERY = 30
-- The sounds, by the game's name with its ID for when SOUNDKIT lacks it: a
-- map ping for a buff gone missing, the raid warning for the pull check.
local SOUND_MISSING, SOUND_PULL = { "MAP_PING", 3175 }, { "RAID_WARNING", 8959 }
local LABEL_NAMES = 5

-- The key binding for the auto-buff button (Bindings.xml).
local BINDING = "CLICK BuffCoordinatorNext:LeftButton"
_G.BINDING_HEADER_BUFFCOORDINATOR = "Buff Coordinator"
_G["BINDING_NAME_" .. BINDING] = "Next buff"

-- The key bound to the Next buff button, or nil.
local function boundKey()
    local key = _G.GetBindingKey and GetBindingKey(BINDING)
    return type(key) == "string" and key ~= "" and key or nil
end

local hud, auto, label
local icons = {}
local pendingLayout = false
-- Whether Preview is on (H.preview).
local previewing = false
-- Whether we're in move mode (H.startMoving), and whether its parts were
-- added to the shared movers.
local moving, moversAdded

-- =============================================================
-- Look
-- =============================================================
local fonts = 0

-- The font flags of each "Outline" setting.
local OUTLINE = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE",
                  slug = "OUTLINE|SLUG", thickslug = "THICKOUTLINE|SLUG" }

-- What a SLUG outline falls back to on a client that doesn't draw SLUG.
local NO_SLUG = { slug = "OUTLINE", thickslug = "THICKOUTLINE" }

-- Sets font `path` on `obj` (a font string or a font object). It falls back
-- to our own font when the game can't load `path`, and to the plain outline
-- when it can't draw SLUG.
local function trySetFont(obj, path, size, key)
    local flags = OUTLINE[key] or "OUTLINE"
    local ok, set = pcall(obj.SetFont, obj, path, size, flags)
    if ok and set ~= false then return end
    if NO_SLUG[key] then
        ok, set = pcall(obj.SetFont, obj, path, size, NO_SLUG[key])
        if ok and set ~= false then return end
        flags = NO_SLUG[key]
    end
    obj:SetFont(T.FONT, size, flags)
end

local function setFont(fs, size)
    local path = O.fontPath(O.get("font"))
    local key = O.get("outline")
    if not fs.fontObject then
        fonts = fonts + 1
        fs.fontObject = CreateFont("BuffCoordinatorFont" .. fonts)
    end
    local fo = fs.fontObject
    trySetFont(fo, path, size, key)
    fo:SetShadowColor(0, 0, 0, 1)
    fo:SetShadowOffset(size < LARGE_TEXT and 0 or 1, size < LARGE_TEXT and 0 or -1)
    fs:SetFontObject(fo)
    trySetFont(fs, path, size, key)
end

-- Crops icon texture `tex` to fit `w` by `h`, zoomed in by `zoom` (ICON_ZOOM
-- when not given) so the icon's bezel doesn't show.
local function crop(tex, w, h, zoom)
    local keep = 1 - 0.5 * (zoom or ICON_ZOOM)
    local aspect = (h > 0) and w / h or 1
    local xr = aspect < 1 and aspect or 1
    local yr = aspect > 1 and 1 / aspect or 1
    local x, y = 0.5 * keep * xr, 0.5 * keep * yr
    tex:SetTexCoord(0.5 - x, 0.5 + x, 0.5 - y, 0.5 + y)
end

function H.timeText(left)
    if left >= 3600 then return format("%dh", floor(left / 3600)) end
    if left >= 60 then return format("%dm", ceil(left / 60)) end
    if left >= DECIMALS_BELOW then return format("%d", ceil(left)) end
    return format("%.1f", max(0, left))
end

-- Countdowns that show tenths of a second.
--
-- The HUD and the widgets paint twice a second, which is plenty for whole
-- seconds. But a countdown under DECIMALS_BELOW shows tenths, and painted
-- twice a second it jumps by half a second at a time. So we keep each font
-- string that shows tenths here, with when it runs out, and write its text
-- again on every frame until then.
local fresh = {}
local fresher = CreateFrame("Frame")
H.fresher = fresher

local function freshen()
    local now = GetTime()
    for fs, expires in pairs(fresh) do
        if not fs:IsVisible() then
            fresh[fs] = nil
        else
            local left = expires - now
            local text = H.timeText(left)
            if fs:GetText() ~= text then fs:SetText(text) end
            if left <= 0 then fresh[fs] = nil end
        end
    end
    if next(fresh) == nil then fresher:SetScript("OnUpdate", nil) end
end

-- Has countdown `fs`, which was just painted, count down in tenths on every
-- frame when it runs out at `expires` less than DECIMALS_BELOW from `now`.
-- With `expires` nil (no countdown shows) it stops.
function H.keepFresh(fs, expires, now)
    if expires and expires > now and expires - now < DECIMALS_BELOW then
        fresh[fs] = expires
        if not fresher:GetScript("OnUpdate") then fresher:SetScript("OnUpdate", freshen) end
    else
        fresh[fs] = nil
    end
end

-- Whether a missing buff glows where we are.
function H.glowsHere()
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    if inside and kind == "raid" then return O.get("glowRaid") end
    if inside and kind == "party" then return O.get("glowDungeon") end
    return O.get("glowWorld")
end

-- =============================================================
-- One icon
-- =============================================================
-- Has icon `f` hear clicks, and the auto-buff button drags too. The game
-- blocks both in combat, and after a login or a /reload in combat nothing
-- would ask again. So we do it on the first layout out of combat, which
-- waits for the fight to end.
local function arm(f)
    if f.armed or InCombatLockdown() then return end
    f.armed = true
    f:RegisterForClicks("AnyUp", "AnyDown")
    if f.drags then f:RegisterForDrag("LeftButton") end
end

-- An icon of the HUD. A `plain` one is for the preview pane: not a secure
-- button, and not one Buffer.lua sets up for combat.
local function newIcon(parent, name, plain)
    local f = CreateFrame("Button", name, parent, not plain and "SecureActionButtonTemplate" or nil)
    f.edge = f:CreateTexture(nil, "BACKGROUND")
    f.edge:SetColorTexture(0, 0, 0, 1)
    f.edge:SetAllPoints(f)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.over = CreateFrame("Frame", nil, f)
    f.over:SetAllPoints(f)
    -- Above the coloured ring, since the countdown sits across the top edge.
    f.over:SetFrameLevel(f:GetFrameLevel() + 6)
    f.timer = f.over:CreateFontString(nil, "OVERLAY")
    f.timer:SetPoint("CENTER", f, "TOP", 0, 0)
    f.count = f.over:CreateFontString(nil, "OVERLAY")
    f.tag = f.over:CreateFontString(nil, "OVERLAY")
    f.tag:Hide()
    f.hl = f:CreateTexture(nil, "HIGHLIGHT")
    f.hl:SetColorTexture(1, 1, 1, 0.12)
    f.flash = f.over:CreateTexture(nil, "OVERLAY")
    f.flash:SetColorTexture(1, 1, 1, 1)
    f.flash:SetBlendMode("ADD")
    f.flash:SetAllPoints(f)
    f.flash:Hide()
    if plain then return f end
    B.buttons = B.buttons or {}
    table.insert(B.buttons, f)
    return f
end

-- The coloured ring around icon `f` for the "Coloured border" glow, and the
-- thin one of an icon that casts on our mouseover in combat. We make it when
-- the HUD is laid out, out of combat, since the thin one first shows in
-- combat.
local function ringOf(f)
    if not f.ring then
        f.ring = CreateFrame("Frame", nil, f)
        f.ring:SetAllPoints(f)
        f.ring:SetFrameLevel(f:GetFrameLevel() + 5)
        T.border(f.ring, WHITE, 1, "OVERLAY")
        f.ring:Hide()
    end
    return f.ring
end

-- Sizes icon `f` to `w` by `h` screen pixels, with a 1 pixel border.
local function fit(f, w, h)
    ringOf(f)
    local p = T.pixel(f)
    local edge = O.get("border") and 1 or 0
    f:SetSize(w * p, h * p)
    f.edge:SetShown(edge > 0)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", edge * p, -edge * p)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -edge * p, edge * p)
    crop(f.icon, w - 2 * edge, h - 2 * edge)
    -- The highlight draws over everything, so it stays inside the border.
    f.hl:ClearAllPoints()
    f.hl:SetAllPoints(f.icon)
    setFont(f.timer, O.get("timerSize"))
    if f.liveTimer then setFont(f.liveTimer, O.get("timerSize")) end
    setFont(f.count, O.get("countSize"))
    f.timerEdge = nil
    -- The game wants a font before any text.
    setFont(f.tag, max(6, O.get("countSize") - 3))
    f.tag:SetText("backup")
    f.tag:SetTextColor(0.8, 0.8, 0.8, 1)
    f.tag:ClearAllPoints()
    f.tag:SetPoint("TOP", f, "TOP", 0, -2 * p)
    local corner = O.get("countAnchor")
    local dx = corner:find("LEFT") and 1 or corner:find("RIGHT") and -1 or 0
    local dy = corner:find("TOP") and -1 or 1
    f.count:ClearAllPoints()
    f.count:SetPoint(corner, f, corner, dx * 2 * p, dy * 2 * p)
    f.count:SetJustifyH(dx > 0 and "LEFT" or dx < 0 and "RIGHT" or "CENTER")
    f.w, f.h = w, h
end

-- The width and height of the auto-buff button, in screen pixels.
local function autoSize()
    return O.get("nextWidth"), O.get("nextHeight")
end

-- The border of the auto-buff button `btn`, in place of the glow the icons
-- have. It's the "Border colour" setting, and the "Hover colour" one while
-- the mouse is over the button. We make it when the button is made, out of
-- combat.
local function markOf(btn)
    if not btn.mark then
        btn.mark = CreateFrame("Frame", nil, btn)
        btn.mark:SetAllPoints(btn)
        btn.mark:SetFrameLevel(btn:GetFrameLevel() + 5)
        T.border(btn.mark, WHITE, 1, "OVERLAY")
    end
    return btn.mark
end

local function mark(btn)
    markOf(btn)
    local px = O.get("nextBorder")
    local key = btn.hover and "nextHoverColor" or "nextBorderColor"
    local look = key .. O.get(key) .. px
    if btn.markLook == look then return end
    btn.markLook, btn.markColor = look, O.get(key)
    T.paint(btn.mark, O.color(key), 1)
    T.edgeWidth(btn.mark, px)
    btn.mark:SetShown(px > 0)
end

-- Sizes the auto-buff button `btn` like fit, and then insets its icon
-- inside its border and gives it its own count size.
local function fitAuto(btn, w, h)
    fit(btn, w, h)
    local p = T.pixel(btn)
    local edge = max(O.get("border") and 1 or 0, O.get("nextBorder"))
    btn.icon:ClearAllPoints()
    btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", edge * p, -edge * p)
    btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -edge * p, edge * p)
    crop(btn.icon, w - 2 * edge, h - 2 * edge, O.get("nextZoom"))
    setFont(btn.count, O.get("nextCountSize"))
    local corner = O.get("countAnchor")
    local dx = corner:find("LEFT") and 1 or corner:find("RIGHT") and -1 or 0
    local dy = corner:find("TOP") and -1 or 1
    btn.count:ClearAllPoints()
    btn.count:SetPoint(corner, btn, corner, dx * (edge + 2) * p, dy * (edge + 2) * p)
    btn.markLook = nil
    mark(btn)
end

-- The mouse goes over the auto-buff button `btn` or leaves it.
local function hoverAuto(btn, on)
    btn.hover = on or nil
    mark(btn)
end

-- Glows icon `f` in the colour of setting `colorKey` ("glowColor" or
-- "warnColor"), or stops its glow when that's nil. `style` is the glow
-- style setting's, or "thin" for the 1 pixel ring of an icon that casts on
-- our mouseover in combat. That one stays off when the setting is "none".
local function glow(f, colorKey, style)
    local setting = O.get("glowStyle")
    if style == "thin" and setting == "none" then style = nil end
    if style ~= "thin" then style = setting end
    local want = colorKey and style or nil
    local color = colorKey and O.get(colorKey) or nil
    if f.glowing == want and f.glowHue == color then return end
    if f.glowing == "pixel" then NS.Glow.stop(f, "hud") end
    if (f.glowing == "border" or f.glowing == "thin") and f.ring then f.ring:Hide() end
    f.glowing, f.glowHue = want, color
    if want == "pixel" then
        local p = T.pixel(f)
        local edge = O.get("border") and 1 or 0
        NS.Glow.start(f, O.color(colorKey), GLOW_LINES, GLOW_FREQUENCY, GLOW_LENGTH,
                      GLOW_THICKNESS_PX * p, -edge * p, -edge * p, "hud")
    elseif want == "border" or want == "thin" then
        ringOf(f)
        T.paint(f.ring, O.color(colorKey), 1)
        -- The ring fits its edges again each time it shows (T.border), so
        -- it keeps the width rather than being sized once.
        T.edgeWidth(f.ring, want == "thin" and 1 or 2)
        f.ring:Show()
    end
end

H.setFont, H.crop, H.glow = setFont, crop, glow

-- =============================================================
-- The game's own aura display, for debuffs in combat
-- =============================================================
-- In combat the game hides the target's debuffs from us. Its own aura
-- display can still draw one by spell ID, so a debuff icon has one behind
-- its countdown. It's the AuraContainer EllesmereUI's AuraKit uses.
local watchBroken = false

local function newWatch(f)
    local load = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
    if load and not NS.loaded("Blizzard_AuraContainer") then load("Blizzard_AuraContainer") end
    local w = CreateFrame("AuraContainer", nil, f, "CustomAuraContainerTemplate")
    w:SetPoint("TOPLEFT", f.icon, "TOPLEFT", 0, 0)
    w:SetSize(1, 1)
    w:SetFrameLevel(f:GetFrameLevel() + 1)
    if w.EnableMouse then w:EnableMouse(false) end
    local p = T.pixel(f)
    local edge = O.get("border") and 1 or 0
    local iw, ih = (f.w - 2 * edge) * p, (f.h - 2 * edge) * p
    w:AddAuraGroup("one", "HARMFUL", {
        maxFrameCount = 1,
        candidateFilters = { includeSpellIDs = {} },
        layout = { elementWidth = iw, elementHeight = ih, elementSpacing = 0, lineSpacing = 0 },
        initializeFrame = function(button)
            if button.EnableMouse then button:EnableMouse(false) end
            local tex = button:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(button)
            crop(tex, f.w - 2 * edge, f.h - 2 * edge)
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetAllPoints(button)
            cd:SetDrawEdge(false)
            cd:SetReverse(true)
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
            local carrier = CreateFrame("Frame", nil, button)
            carrier:SetAllPoints(button)
            carrier:SetFrameLevel(cd:GetFrameLevel() + 1)
            local stack = carrier:CreateFontString(nil, "OVERLAY")
            setFont(stack, O.get("countSize"))
            stack:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2 * p, 2 * p)
            button:SetIcon(tex)
            button:SetDurationCooldown(cd)
            button:SetApplicationCount(stack, {})
        end,
    })
    w:SetUnit("target")
    return w
end

local function watch(f, b)
    if f.watch and (f.watchW ~= f.w or f.watchH ~= f.h) then
        pcall(f.watch.SetUnit, f.watch, nil)
        f.watch:Hide()
        f.watch = nil
    end
    if b and not f.watch and not watchBroken then
        local ok, w = pcall(newWatch, f)
        if ok then
            f.watch, f.watchW, f.watchH = w, f.w, f.h
        else
            watchBroken = true
        end
    end
    f.watching = false
    if not f.watch then return end
    local ok = pcall(function()
        if b then
            f.watch:SetAuraGroupCandidateFilters("one", { includeSpellIDs = Tr.spellIds(b) })
            f.watch:Show()
        else
            f.watch:Hide()
        end
    end)
    f.watching = ok and b ~= nil
end
H.watch = watch

-- =============================================================
-- What each icon shows
-- =============================================================
-- Our duties as HUD icons: { list (assignments), icon, title, fixed, backup }.
-- Every blessing assignment of ours is one icon.
local function duties()
    local t, bless = {}, nil
    for _, a in ipairs(Du.mine()) do
        if a.spare then
            t[#t + 1] = { list = { a }, title = "Backup blessings", backup = true }
        elseif a.bless then
            if not bless then
                bless = { list = {}, title = "Blessings" }
                t[#t + 1] = bless
            end
            table.insert(bless.list, a)
        else
            t[#t + 1] = { list = { a }, title = Tr.title(a.buff), b = a.buff, backup = a.backup,
                          fixed = not B.walks(a) and a.buff or nil }
        end
    end
    return t
end

-- Made-up icons for the previews, as a raid would give a player of our
-- class: each buff and debuff of the class, one of each family (all the
-- blessings are one icon, as on the real HUD) and one totem of each
-- element, up to MAX_SAMPLES. They go through the states an icon can be
-- in, missing first. A class with nothing to give, like a rogue, gets a
-- priest's.
local MAX_SAMPLES = 6
local STATES = { "red", "orange", "fine", "fine", "dim", "fine" }

local function sampleList(class)
    local list, seen = {}, {}
    local function add(b)
        if #list >= MAX_SAMPLES or b.school or b.talent then return end
        local group = b.family or b.element
        if group then
            if seen[group] then return end
            seen[group] = true
        end
        list[#list + 1] = b
    end
    for _, b in ipairs(D.BUFFS) do
        if b.class == class and b.kind == "long" then add(b) end
    end
    for _, b in ipairs(D.BUFFS) do
        if b.class == class and b.kind ~= "long" then add(b) end
    end
    for _, b in ipairs(D.DEBUFFS) do
        if b.class == class then add(b) end
    end
    return list
end

-- What made-up icon `i` of buff `b` shows: { state, have, want, left,
-- stacks }.
local function sampleOf(b, i)
    local state = STATES[(i - 1) % #STATES + 1]
    local want = b.family == "blessing" and 10 or b.party and 5 or 40
    local have = state == "red" and want - 3 or state == "orange" and want - 1 or state == "dim" and want - 2
                 or want
    local left
    if state ~= "red" then
        if b.debuff then
            left = state == "orange" and 4 or 22
        elseif b.kind == "long" then
            left = state == "orange" and 150 or 42 * 60
        elseif not b.aura then
            left = state == "orange" and 12 or 95
        end
    end
    return { state = state, have = have, want = want, left = left,
             stacks = b.stacks and (state == "orange" and b.stacks - 2 or b.stacks) or nil }
end

local function sampleDuties()
    local class = select(2, UnitClass("player"))
    local list = sampleList(NS.readable(class) and class or "PRIEST")
    if #list == 0 then list = sampleList("PRIEST") end
    local t = {}
    local shown = false
    for i, b in ipairs(list) do
        local title = b.family == "blessing" and "Blessings" or Tr.title(b)
        local sample = sampleOf(b, i)
        -- One of them shows the DOWNRANK word, to show its look.
        if not shown and not b.debuff and not b.aura then
            sample.low, shown = true, true
        end
        t[#t + 1] = { list = {}, title = title, b = b, sample = sample }
    end
    return t
end
H.sampleDuties = sampleDuties

-- The line under the auto-buff button in the previews.
local function sampleNext()
    local first = sampleDuties()[1]
    return format("%s on %s", B.short(first and first.title or "Fortitude"), NS.classColored("Tor Grimm", "WARRIOR"))
end

local previewStart = 0

-- How icon `duty` stands, for its colour, its count and its tooltip:
--   state     "red", "orange", "mouseover", "dim", "fine" or "idle"
--             (nobody it's for). `button` is the icon, which says whether
--             it casts on our mouseover in combat (Buffer.lua).
--   have, want, unknown
--   missing   { m, b, why } for each player missing it, with why nil when a
--             click reaches them, else "running out", "downrank", "far",
--             "dead", "not in sight" or "offline"
--   expires   when the first buff runs out
--   by        { [buff id] = { have, want } }
--   low       { m, b, rank, want } for each player with too low a rank
local function standing(duty, combat, button)
    local walks = not duty.fixed
    local s = { have = 0, want = 0, unknown = 0, missing = {}, expires = 0, by = {}, low = {} }
    local red, soon, away, redSpell = 0, 0, 0, nil
    for _, a in ipairs(duty.list) do
        local st = Tr.status(a)
        s.have, s.want, s.unknown = s.have + st.have, s.want + st.want, s.unknown + st.unknown
        if st.expires > 0 and (s.expires == 0 or st.expires < s.expires) then s.expires = st.expires end
        for id, c in pairs(st.by) do
            s.by[id] = s.by[id] or { have = 0, want = 0 }
            s.by[id].have, s.by[id].want = s.by[id].have + c.have, s.by[id].want + c.want
        end
        for _, t in ipairs(st.low or {}) do s.low[#s.low + 1] = t end
        for _, t in ipairs(st.missing) do
            local spell = Tr.title(t.b)
            local why = t.low and "downrank" or t.soon and "running out" or (walks and B.why(t.m, spell)) or nil
            s.missing[#s.missing + 1] = { m = t.m, b = t.b, why = why }
            if t.soon then
                soon = soon + 1
            elseif why then
                away = away + 1
            else
                red = red + 1
                redSpell = redSpell or spell
            end
        end
        for _, t in ipairs(st.dead or {}) do
            s.missing[#s.missing + 1] = { m = t.m, b = t.b, why = "dead" }
        end
    end
    s.red, s.soon, s.away = red, soon, away
    -- Someone missing it, whether or not a click reaches them. It keeps the
    -- HUD from fading.
    s.due = red + away + soon > 0
    if s.want == 0 and #s.missing == 0 then
        s.state = "idle"
    elseif walks and combat and red + away > 0 then
        local spell = button and button.mouseover
        s.state = (spell and B.usable(spell)) and "mouseover" or "dim"
    elseif red > 0 then
        s.state = (walks and not B.usable(redSpell)) and "dim" or "red"
    elseif soon > 0 then
        s.state = "orange"
    elseif away > 0 then
        s.state = "dim"
    else
        s.state = "fine"
    end
    return s
end
H.standing = standing

local STATE_GLOW = { red = "glowColor", orange = "warnColor", mouseover = "glowColor" }

-- Whether buff `b` goes up on the pull: a shout or a totem. They last a
-- couple of minutes, so they're down between pulls. An aura stays up, so a
-- missing one matters out of combat too.
local function onPull(b)
    return b ~= nil and b.kind == "short" and not b.aura and not b.debuff
end

-- Plays sound `s`, when the client has PlaySound.
local function sound(s)
    if not _G.PlaySound then return end
    local kit = _G.SOUNDKIT
    pcall(_G.PlaySound, kit and kit[s[1]] or s[2])
end

-- The flash over an icon that just became ours, or on the pull check.
local flashing = {}
local flasher

local function flash(f)
    if not f or not f.flash then return end
    f.flash:SetAlpha(0.6)
    f.flash:Show()
    flashing[f] = GetTime()
    if not flasher then flasher = CreateFrame("Frame") end
    flasher:SetScript("OnUpdate", function()
        local now = GetTime()
        for x, at in pairs(flashing) do
            local done = (now - at) / FLASH_FOR
            if done >= 1 then
                x.flash:Hide()
                flashing[x] = nil
            else
                x.flash:SetAlpha(0.6 * (1 - done))
            end
        end
        if next(flashing) == nil then flasher:SetScript("OnUpdate", nil) end
    end)
end

-- What each icon showed last out of combat, by duty, so a sound only plays
-- when one turns red, not on every paint. We don't note what it showed in
-- combat, so a buff that went missing in the fight sounds once it ends, and
-- one that was missing before the pull doesn't sound again.
local lastState = {}
local lastSound = -SOUND_EVERY

local function dutyKey(duty)
    local first = duty.list[1]
    return duty.title .. (first and first.party and ("\1" .. first.party) or "")
        .. (duty.backup and "\1backup" or "")
end

-- Puts icon `f`'s countdown across its top edge, half on the icon and half
-- above it.
--
-- When the count is in a top corner or on top, the two would overlap there.
-- So the countdown goes across the bottom edge instead.
local function placeTimer(f, count)
    local edge = O.get("countAnchor"):find("TOP") and "BOTTOM" or "TOP"
    if f.timerEdge == edge then return end
    f.timerEdge = edge
    f.timer:ClearAllPoints()
    f.timer:SetPoint("CENTER", f, edge, 0, 0)
    if f.liveTimer then
        f.liveTimer:ClearAllPoints()
        f.liveTimer:SetPoint("CENTER", f, edge, 0, 0)
    end
end

-- Whether duty `duty` is one of our own totems, `b`, and which slot of the
-- game's it stands in. Only while the game hides our auras, which is when
-- our own countdown only guesses.
local function ourTotemSlot(duty, b)
    if not (b.element and Tr.hidden()) then return nil end
    for _, a in ipairs(duty.list) do
        if a.giver and a.giver.me and not a.backup then return Tr.liveTotem(b) end
    end
    return nil
end

-- Has the game draw the countdown of our totem in slot `slot` on icon `f`,
-- in a text of ours where our own countdown goes, orange from `warn`
-- seconds. In combat the game knows the totem's time left when we can't,
-- and we only count down from when we dropped it. With `slot` nil it stops.
-- It returns whether the game draws it.
local function liveTotem(f, slot, warn)
    if not slot then
        if f.live and f.live.on then f.live:stop() end
        f.liveFor = nil
        return false
    end
    if not f.liveTimer then
        f.liveTimer = f.over:CreateFontString(nil, "OVERLAY")
        setFont(f.liveTimer, O.get("timerSize"))
        f.liveTimer:SetTextColor(1, 1, 1, 1)
        f.liveTimer:SetPoint("CENTER", f, f.timerEdge or "TOP", 0, 0)
        f.live = NS.Live.durationText(f.liveTimer)
    end
    if not f.live then return false end
    local orange = O.color("warnColor")
    local key = format("%d|%d|%d|%s", slot, Tr.totemVersion(), warn, table.concat(orange, ","))
    if f.liveFor ~= key then
        f.liveFor = key
        local ok, colors = pcall(NS.Live.timeColors, warn, 0, WHITE, orange, orange)
        f.live:set(NS.Live.totemDuration(slot), ok and colors or nil)
    end
    return f.live.on
end

-- How far down the DOWNRANK word sits so it clears the text on the icon's top
-- edge. That's the countdown across the edge, or a count anchored to the top.
local function wordDrop(f)
    if f.timerEdge == "TOP" then return f.timerText ~= "" and ceil(O.get("timerSize") / 2) or 0 end
    return f.countText ~= "" and O.get("countSize") or 0
end

-- A made-up icon of the previews, in the state its sample says.
local function paintSample(f, duty, now, glows)
    local s, b = duty.sample, duty.b
    if f.tex ~= Tr.icon(b) then
        f.tex = Tr.icon(b)
        f.icon:SetTexture(f.tex)
    end
    local text, color, expires = "", WHITE, nil
    if s.left then
        local left = s.left - (now - previewStart) % s.left
        text, expires = H.timeText(left), now + left
        if s.state == "orange" then color = O.color("warnColor") end
    end
    local countColor = s.state == "red" and O.color("glowColor") or s.state == "orange" and O.color("warnColor")
                       or s.state == "dim" and IDLE or UP
    -- A debuff counts its stacks, and an aura has no count, as on the real
    -- icons.
    local count = format("%d/%d", s.have, s.want)
    if b.debuff then
        count = s.stacks and s.left and tostring(s.stacks) or ""
        countColor = s.stacks and s.stacks < b.stacks and O.color("warnColor") or WHITE
    elseif b.aura then
        count = ""
    end
    if not O.get("showTimer") then text = "" end
    if not O.get("showCount") then count = "" end
    f.grey = s.state == "dim"
    f.icon:SetDesaturated(f.grey)
    f.timer:SetText(text)
    f.timerText = text
    H.keepFresh(f.timer, text ~= "" and expires or nil, now)
    f.timer:SetTextColor(color[1], color[2], color[3], 1)
    f.count:SetText(count)
    f.countText = count
    f.count:SetTextColor(countColor[1], countColor[2], countColor[3], 1)
    placeTimer(f, count)
    T.downrank(f, s.low, O.color("glowColor"), nil, wordDrop(f), 1.2)
    glow(f, glows and STATE_GLOW[s.state] or nil)
    f.state = s.state
    return s.state, s.state ~= "fine"
end

local function paintIcon(f, duty, now, glows, combat)
    if duty.sample then return paintSample(f, duty, now, glows) end
    local b = duty.b or B.mainBlessing(duty.list)
    local tex = Tr.icon(b)
    if f.tex ~= tex then
        f.icon:SetTexture(tex)
        f.tex = tex
    end
    local text, color, count, countColor = "", WHITE, "", WHITE
    local grey, state, due, expires, low = false, "idle", false, nil, false
    if b.debuff then
        local st = Tr.status(duty.list[1])
        local up = st.up and not (st.expires > 0 and st.expires <= now)
        -- In combat our read of the target is hidden, and the game's own
        -- aura display draws the debuff with its real stack count (watch).
        -- Our read only knows our own casts, and what we read before the
        -- pull. Say we read no Sunder Armor before the pull and the tank put
        -- up 5 since. So we let the game's display speak, with no count of
        -- ours and no red glow. What we do know (a read before the pull, our
        -- own cast) still shows under it, with its countdown, so the icon
        -- doesn't go blank when the game's display draws nothing.
        local game = f.watching and Tr.hidden()
        if not st.wanted then
            grey = true
        elseif st.unknown or not up then
            grey = true
            state = game and "idle" or "red"
        elseif st.expires > 0 then
            local left = st.expires - now
            text, expires = H.timeText(left), st.expires
            color = left <= WARN_SHORT and O.color("warnColor") or WHITE
            state = "fine"
        end
        if b.stacks and up and not game then
            count = tostring(st.stacks or 0)
            countColor = (st.stacks or 0) >= b.stacks and WHITE or O.color("warnColor")
        end
        due = state == "red"
    else
        local s = standing(duty, combat, f)
        state, due, low = s.state, s.due, #s.low > 0
        -- A shout or a totem missing out of combat waits for the pull.
        local waits = not combat and state == "red" and onPull(duty.fixed)
        if waits then state, due = "idle", false end
        -- An aura is only ever up or off on us, so it has no count.
        count = s.want > 0 and not b.aura and format("%d/%d", s.have, s.want) or ""
        if waits then
            countColor = IDLE
        elseif state == "red" or state == "mouseover" then
            countColor = O.color("glowColor")
        elseif state == "orange" then
            countColor = O.color("warnColor")
        elseif state == "dim" then
            countColor = IDLE
        elseif s.have + #s.missing < s.want then
            -- Some we never read, so it isn't all good.
            countColor = WHITE
        else
            countColor = UP
        end
        grey = state == "idle" or state == "dim"
        local slot
        if s.expires > 0 then
            local left = s.expires - now
            text, expires = H.timeText(left), s.expires
            local warn = b.kind == "long" and Tr.rebuffAt(b) or WARN_SHORT
            color = left <= warn and O.color("warnColor") or WHITE
            slot = O.get("showTimer") and ourTotemSlot(duty, b)
            if liveTotem(f, slot, warn) then text = "" end
        end
        if not slot then liveTotem(f, nil) end
    end
    if not O.get("showTimer") then text = "" end
    if not O.get("showCount") then count = "" end
    if f.grey ~= grey then
        f.grey = grey
        f.icon:SetDesaturated(grey)
    end
    if f.timerText ~= text then
        f.timer:SetText(text)
        f.timerText = text
    end
    H.keepFresh(f.timer, text ~= "" and expires or nil, now)
    f.timer:SetTextColor(color[1], color[2], color[3], 1)
    if f.countText ~= count then
        f.count:SetText(count)
        f.countText = count
    end
    f.count:SetTextColor(countColor[1], countColor[2], countColor[3], 1)
    placeTimer(f, count)
    T.downrank(f, low, O.color("glowColor"), nil, wordDrop(f), 1.2)
    glow(f, glows and STATE_GLOW[state] or nil, state == "mouseover" and "thin" or nil)
    f.state = state
    -- Anything to red, out of combat: a short sound, now and then. A buff
    -- that runs out goes fine, then orange while it runs out, then red. We
    -- don't sound on the first paint, after a /reload or when an
    -- assignment becomes ours.
    if not combat then
        local key = dutyKey(duty)
        local was = lastState[key]
        if was ~= nil and was ~= "red" and state == "red" and not b.debuff and glows
           and O.get("missingSound")
           and now - lastSound >= SOUND_EVERY then
            lastSound = now
            sound(SOUND_MISSING)
        end
        lastState[key] = state
    end
    return state, due
end

-- The walking assignments of ours the auto-buff button goes through, as one
-- duty.
local function autoDuty()
    local list, walking = {}, {}
    for _, a in ipairs(Du.mine()) do
        if not (a.buff and a.buff.debuff) then
            list[#list + 1] = a
            if B.walks(a) then walking[#walking + 1] = a end
        end
    end
    return list, { list = walking, title = "auto" }
end

-- A player's full name (first and last), in their class colour.
local function who(m)
    return NS.classColored(m.name, m.class)
end

-- What the next press of the auto-buff button does, in a few words. Out of
-- combat paintAuto worked out the next buff (auto.nextUp).
local function nextText(combat)
    if combat then
        if auto.mouseover then
            -- The key works on our mouseover. A click puts the mouse on the
            -- button, so the macro falls through to our friendly target.
            if boundKey() then return "mouseover: " .. B.short(auto.mouseover) end
            return B.short(auto.mouseover) .. " on your friendly target"
        end
        if auto.combatFixed then return B.short(auto.combatFixed) end
        if auto.blocked then return "Bless out of combat" end
        return nil
    end
    local n = auto.nextUp
    if not n then return nil end
    local spell = B.short(n.spell)
    if n.class then return format("%s on %s", spell, classWord(n.class)) end
    if n.all then return format("%s on everyone", spell) end
    if n.m then return format("%s on %s", spell, who(n.m)) end
    return spell
end

-- "Refresh 3 Fortitude: Grom, Jaina, Uther" for each buff of ours due on
-- the pull.
local function pullLines()
    local lines = {}
    for _, d in ipairs(Tr.due()) do
        local names = {}
        for i, m in ipairs(d.names) do
            if i > LABEL_NAMES then
                names[#names + 1] = format("and %d more", #d.names - LABEL_NAMES)
                break
            end
            names[#names + 1] = NS.classColored(m.name:match("^(%S+)") or m.name, m.class)
        end
        lines[#lines + 1] = format("Refresh %d %s: %s", #d.names, B.short(Tr.title(d.b)),
                                   table.concat(names, ", "))
    end
    return lines
end

-- Our shouts and totems, as their short names. On a ready check with no long
-- buff due they're what's left to do, on the pull itself.
local function pullShorts()
    local t, seen = {}, {}
    for _, a in ipairs(Du.mine()) do
        local b = a.buff
        if onPull(b) and not a.backup and not seen[b.id] then
            seen[b.id] = true
            t[#t + 1] = B.short(Tr.title(b))
        end
    end
    return t
end

-- The line under the auto-buff button.
local function paintLabel(combat)
    local lines = {}
    if previewing then
        if O.get("nextLabel") then lines[1] = sampleNext() end
    elseif O.get("nextLabel") then
        lines[#lines + 1] = nextText(combat)
    end
    if Tr.pulling() and not combat and not previewing then
        local pull = pullLines()
        if #pull == 0 and #Du.mine() > 0 then
            local shorts = pullShorts()
            if #shorts > 0 then
                pull[1] = andList(shorts) .. " on the pull."
            else
                pull[1] = T.hex("up") .. "Your buffs last the fight.|r"
            end
        end
        for _, l in ipairs(pull) do lines[#lines + 1] = l end
    end
    local text = table.concat(lines, "\n")
    if label.text ~= text then
        label:SetText(text)
        label.text = text
        label:SetShown(text ~= "")
        -- The move mode box goes around the line too.
        if moving then H.fitMovers() end
    end
    label:SetShown(text ~= "")
end

-- The icon of spell `spell` (a name), or nil when the game doesn't say.
local function spellIcon(spell)
    local get = C_Spell and C_Spell.GetSpellTexture
    if not get or type(spell) ~= "string" then return nil end
    local ok, tex = pcall(get, spell)
    if ok and tex and not NS.secret(tex) then return tex end
    return nil
end

-- What the auto-buff button wears: the icon of the spell its next press
-- casts, or our logo when it casts nothing. A Kings icon there read as "I'm
-- on Kings" to a priest, and as a second Kings icon to a paladin who is.
local function autoIcon(combat)
    if combat then
        return spellIcon(auto.mouseover or auto.combatFixed) or NS.LOGO
    end
    local n = auto.nextUp
    if not n then return NS.LOGO end
    return spellIcon(n.spell) or (n.b and Tr.icon(n.b)) or NS.LOGO
end

-- The auto-buff button: the number of buffs still to put up, its icon, and
-- its colour like an icon's.
-- The auto-buff button `btn` in the previews: the first made-up buff is
-- next, with 3 to buff.
local function paintAutoSample(btn)
    local first = sampleDuties()[1]
    local tex = Tr.icon(first and first.b or D.BY_ID.fortitude)
    if btn.tex ~= tex then
        btn.icon:SetTexture(tex)
        btn.tex = tex
    end
    local text = O.get("showCount") and "3" or ""
    btn.count:SetText(text)
    btn.countText = text
    local c = O.color("nextMissingColor")
    btn.count:SetTextColor(c[1], c[2], c[3], 1)
    btn.icon:SetDesaturated(false)
    mark(btn)
    btn.state = "red"
    return "red", true
end


local function paintAuto(combat)
    if previewing then return paintAutoSample(auto) end
    local list, duty = autoDuty()
    auto.list = list
    auto.nextUp = not combat and B.next(list) or nil
    local tex = autoIcon(combat)
    if auto.tex ~= tex then
        auto.icon:SetTexture(tex)
        auto.tex = tex
    end
    local s = standing(duty, combat, auto)
    local missing = #s.missing
    for _, t in ipairs(s.missing) do
        if t.why == "dead" then missing = missing - 1 end
    end
    local text = missing > 0 and tostring(missing) or ""
    if not O.get("showCount") then text = "" end
    if auto.countText ~= text then
        auto.count:SetText(text)
        auto.countText = text
    end
    -- Red while anyone lacks the buff, yellow while the only ones left are
    -- running out soon.
    local c = missing > (s.soon or 0) and O.color("nextMissingColor")
              or missing > 0 and O.color("nextWarnColor") or WHITE
    auto.count:SetTextColor(c[1], c[2], c[3], 1)
    auto.countColor = c
    local state = #list == 0 and "idle" or s.state
    auto.icon:SetDesaturated(state ~= "red" and state ~= "orange" and state ~= "mouseover")
    mark(auto)
    auto.state, auto.standing = state, s
    return state, #list > 0 and s.due
end

local function paintAll()
    local now = GetTime()
    local glows = previewing and H.previewGlows() or not previewing and H.glowsHere()
    local combat = InCombatLockdown() and true or false
    -- Whether anything on the HUD wants attention, so it doesn't fade.
    -- Someone missing a buff counts even when the icon can't act on it.
    local due = Tr.pulling()
    for i, duty in ipairs(H.current or {}) do
        local f = icons[i]
        if f then
            local _, d = paintIcon(f, duty, now, glows, combat)
            due = due or d
        end
    end
    local _, d = paintAuto(combat)
    due = due or d
    paintLabel(combat)
    local alpha = combat and O.get("combatAlpha") or O.get("alpha")
    if O.get("fadeIdle") and not H.hover and not due then alpha = math.min(alpha, FADED) end
    if moving then alpha = 1 end
    T.setAlpha(hud, alpha, previewing and 0 or GLIDE_S)
    H.faded = alpha <= FADED
end

-- Paints the HUD. Each icon, the auto-buff button and the line under it
-- all look at the same assignments, so we work out each one's status once
-- for the whole paint (Tr.memoize).
function H.paint()
    if not hud or not hud:IsShown() then return end
    Tr.memoize(true)
    local ok, err = pcall(paintAll)
    Tr.memoize(false)
    if not ok then error(err, 0) end
end

-- =============================================================
-- Tooltips
-- =============================================================
-- `title`, then each player of `list` on a line of their own, at most `n`,
-- in color `c`.
local function nameLines(tip, title, list, n, c)
    tip:AddLine(title, c[1], c[2], c[3])
    for i, t in ipairs(list) do
        if i > n then
            tip:AddLine(format("and %d more", #list - n), c[1], c[2], c[3])
            break
        end
        local name = NS.who(t.m)
        tip:AddLine(t.why and format("%s (%s)", name, t.why) or name, c[1], c[2], c[3])
    end
end

-- The missing players of standing `s` as tooltip lines: who's missing it
-- (and why a click can't reach them), then who has it running out, then who
-- has too low a rank of it.
local function missingLines(tip, s)
    local missing, soon = {}, {}
    for _, t in ipairs(s.missing) do
        if t.why == "running out" then
            soon[#soon + 1] = { m = t.m }
        elseif t.why ~= "downrank" then
            missing[#missing + 1] = t
        end
    end
    local low = Tr.lowLines(s.low)
    if #missing > 0 or #soon > 0 or low or s.unknown > 0 then tip:AddLine(" ") end
    if #missing > 0 then nameLines(tip, "Missing:", missing, 12, O.color("glowColor")) end
    if #soon > 0 then nameLines(tip, "Running out:", soon, 12, O.color("warnColor")) end
    if low then
        local c = O.color("warnColor")
        for _, l in ipairs(low) do tip:AddLine(l, c[1], c[2], c[3]) end
    end
    if s.unknown > 0 then
        tip:AddLine(format("%d not seen yet.", s.unknown), 0.8, 0.8, 0.8, true)
    end
end

-- Each player a blessing icon covers, with the blessing they get, coloured by
-- whether they have it. A player we can't reach says why, like "(far)".
local MAX_BLESSED = 20
local LATE = { ["running out"] = "running out", downrank = "low rank" }

local function blessingLines(tip, duty, s)
    local why = {}
    for _, t in ipairs(s.missing) do why[t.m.name .. ":" .. t.b.id] = t.why or false end
    local rows = {}
    for _, a in ipairs(duty.list) do
        for _, t in ipairs(Du.targets(a)) do rows[#rows + 1] = { a = a, m = t.m, b = t.b } end
    end
    if #rows == 0 then return end
    tip:AddLine(" ")
    local grey = { 0.6, 0.6, 0.6 }
    for i, r in ipairs(rows) do
        if i > MAX_BLESSED then
            tip:AddLine(format("and %d more", #rows - MAX_BLESSED), 0.8, 0.8, 0.8)
            break
        end
        local w = why[r.m.name .. ":" .. r.b.id]
        local text, c = B.short(Tr.title(r.b)), UP
        if w == false then
            c = O.color("glowColor")
        elseif LATE[w] then
            text, c = format("%s (%s)", text, LATE[w]), O.color("warnColor")
        elseif w then
            text, c = format("%s (%s)", text, w), O.color("glowColor")
        elseif not Tr.standIn(r.a, r.m, r.b) then
            text, c = format("%s (not seen)", text), grey
        end
        tip:AddDoubleLine(NS.who(r.m), text, 1, 1, 1, c[1], c[2], c[3])
    end
end

-- "warriors and rogues", for a backup paladin's classes.
local function classesText(set)
    local t = {}
    for class in pairs(set or {}) do t[#t + 1] = classWord(class) end
    table.sort(t)
    return andList(t)
end

-- In combat a click on an icon puts the mouse on the icon, not on a player,
-- so the mouseover macro falls through to our friendly target. Only the key
-- can use the mouseover.
local CLICK_COMBAT_HINT = "cast on friendly target"
local KEY_COMBAT_HINT = "cast on mouseover, else friendly target"
local BLOCKED_LINE = "In combat a click can't choose between your blessings. Bless out of combat."

local function hover(on)
    H.hover = on
    H.paint()
end

local function tooltip(f)
    local duty = f.duty
    if not duty then return end
    if duty.sample then
        T.spellTip(f, nil, duty.title, { "Made up, to show the look." })
        return
    end
    hover(true)
    local tip = GameTooltip
    local combat = InCombatLockdown()
    tip:SetOwner(f, "ANCHOR_TOP")
    -- Only the buff's name: what the spell does isn't ours to say here.
    tip:SetText(duty.title, 1, 1, 1)
    local first = duty.list[1]
    if first and first.party then tip:AddLine(format("Group %d", first.party), 0.8, 0.8, 0.8) end
    if duty.backup then
        local whom = first.spare and classesText(first.classes) or "it"
        tip:AddLine(format("Backup for %s. Lights up once it's been missing %d s.",
                           whom, O.get("backupDelay")), 0.8, 0.8, 0.8, true)
    end
    if first and first.note then tip:AddLine(first.note, 0.8, 0.8, 0.8, true) end
    if duty.b and duty.b.debuff then
        tip:AddLine("On the target.", 0.8, 0.8, 0.8, true)
        tip:AddLine(" ")
        T.tipHints(tip, { { "Click", "cast it" } })
    elseif duty.b and duty.b.aura then
        local st = Tr.status(duty.list[1])
        if #st.missing > 0 then
            tip:AddLine("It's off.", IDLE[1], IDLE[2], IDLE[3])
        elseif st.have > 0 then
            tip:AddLine("It's up.", UP[1], UP[2], UP[3])
        end
        local spell = B.castOf(duty.b)
        if duty.b.how then tip:AddLine(duty.b.how, 0.8, 0.8, 0.8, true) end
        if spell then
            tip:AddLine(" ")
            T.tipHints(tip, { { "Click", duty.b.cast and spell or "turn it on" } })
        end
    else
        local s = standing(duty, combat, f)
        if duty.b then
            missingLines(tip, s)
        else
            blessingLines(tip, duty, s)
        end
        if not combat and s.red > 0 and onPull(duty.fixed) then
            tip:AddLine("It lights up in combat.", 0.8, 0.8, 0.8, true)
        end
        local note = not duty.fixed and B.reagentNote(duty.list)
        if note then
            tip:AddLine(format("%s, so one at a time.", (note:gsub("^%l", string.upper))), 0.8, 0.8, 0.8, true)
        end
        if combat and not duty.fixed and f.blocked then
            tip:AddLine(BLOCKED_LINE, IDLE[1], IDLE[2], IDLE[3], true)
        end
        local hint = duty.fixed and "cast it" or not combat and "buff the next one"
                     or f.mouseover and CLICK_COMBAT_HINT or nil
        if hint then
            tip:AddLine(" ")
            T.tipHints(tip, { { "Click", hint } })
        end
    end
    T.tipDone(tip)
end

local function autoTooltip(f)
    hover(true)
    local tip = GameTooltip
    local combat = InCombatLockdown()
    tip:SetOwner(f, "ANCHOR_TOP")
    tip:SetText("Next buff", 1, 1, 1)
    local n = not combat and B.next(auto.list or {})
    local s = auto.standing or standing(select(2, autoDuty()), combat, auto)
    local key = boundKey()
    if combat and auto.mouseover then
        tip:AddLine("Next: " .. auto.mouseover, 1, 1, 1)
    elseif combat and auto.combatFixed then
        tip:AddLine("Next: " .. auto.combatFixed, 1, 1, 1)
    elseif combat and auto.blocked then
        tip:AddLine(BLOCKED_LINE, IDLE[1], IDLE[2], IDLE[3], true)
    elseif n and n.m then
        local what = n.spell
        if n.cast and n.cast ~= n.spell and n.rank then
            what = format("%s rank %d", n.spell, n.rank)
        elseif n.low then
            what = format("%s rank %d over their rank %d", n.spell, n.rank or 0, n.low)
        end
        tip:AddLine(format("Next: %s on %s", what, NS.who(n.m)), 1, 1, 1)
    elseif n then
        tip:AddLine("Next: " .. n.spell, 1, 1, 1)
    elseif #Du.mine() == 0 then
        tip:AddLine("You have no assignments.", 0.8, 0.8, 0.8)
    elseif #s.missing == 0 then
        tip:AddLine("Everyone has their buffs.", UP[1], UP[2], UP[3])
    else
        tip:AddLine("Everyone missing a buff is out of reach.", IDLE[1], IDLE[2], IDLE[3], true)
    end
    missingLines(tip, s)
    tip:AddLine(" ")
    local hints = {}
    if not combat then
        hints[1] = { "Click", "buff the next one" }
        if key then hints[#hints + 1] = { key, "same as a click" } end
    elseif auto.mouseover then
        hints[1] = { "Click", CLICK_COMBAT_HINT }
        if key then hints[#hints + 1] = { key, KEY_COMBAT_HINT } end
    elseif auto.combatFixed then
        hints[1] = { "Click", "cast it" }
        if key then hints[#hints + 1] = { key, "same as a click" } end
    end
    if not key then hints[#hints + 1] = { "Next buff key", "not bound (Key Bindings > AddOns)" } end
    if not O.get("lock") and not combat then
        hints[#hints + 1] = { "Shift-drag", "move" }
        hints[#hints + 1] = { "Shift-click", "move with the arrow keys" }
    end
    hints[#hints + 1] = { "Right-click", "open the window" }
    T.tipHints(tip, hints)
    T.tipDone(tip)
end

local function leave()
    GameTooltip:Hide()
    hover(false)
end

-- =============================================================
-- Building and laying out
-- =============================================================
function H.shiftDown()
    return _G.IsShiftKeyDown ~= nil and IsShiftKeyDown() and true or false
end

function H.mouseDown()
    return _G.IsMouseButtonDown ~= nil and IsMouseButtonDown("LeftButton") and true or false
end

-- Puts the HUD where we keep it. The icons on it are secure buttons, so the
-- game blocks moving it in combat. Then the spot is kept, and the layout
-- after combat puts it there.
local function place()
    if InCombatLockdown() then
        pendingLayout = true
        return
    end
    hud:ClearAllPoints()
    hud:SetPoint("CENTER", UIParent, "CENTER", NS.db.hud.x or 0, NS.db.hud.y or -200)
end

-- A position kept to a thousandth of a unit, so the saved variables don't
-- fill with long fractions. A thousandth is far less than a pixel.
local function tidy(v) return floor(v * 1000 + 0.5) / 1000 end

-- Moves the HUD by `dx` and `dy` whole screen pixels (right and up are
-- positive) and keeps it there.
--
-- We count the pixels from its top left corner, rounded to the nearest
-- pixel first. So a HUD that sat between two pixels lands on one with the
-- first press, and its edges stay sharp after that. One pixel is rarely one
-- of UIParent's units, so the spot we keep is often a fraction.
--
-- We start from where the HUD really is rather than the spot we kept. They
-- differ when the screen's edge holds it back, and starting from the kept
-- spot would let it wander off screen one press at a time.
local function nudge(dx, dy)
    local p = T.pixel(UIParent)
    local x, y = NS.db.hud.x or 0, NS.db.hud.y or -200
    local l, t = hud:GetLeft(), hud:GetTop()
    local cx, cy = hud:GetCenter()
    if l and t and cx and cy then
        local r = hud:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local ux, uy = UIParent:GetCenter()
        l, t = l * r, t * r
        x = cx * r - ux + (floor(l / p + 0.5) + dx) * p - l
        y = cy * r - uy + (floor(t / p + 0.5) + dy) * p - t
    else
        x, y = x + dx * p, y + dy * p
    end
    NS.db.hud.x, NS.db.hud.y = tidy(x), tidy(y)
    place()
end

-- Keeps the spot a drag left the HUD at, on a whole pixel. The HUD's frame
-- has a name, so the game would also keep the spot in its own layout cache,
-- but we place it ourselves.
local function savePosition()
    if hud.SetUserPlaced then hud:SetUserPlaced(false) end
    nudge(0, 0)
end

-- Ends a drag of the HUD that's still going, and keeps the spot.
--
-- Combat calls it as it starts, while the game still lets us move the HUD.
-- A drag left going would end in combat, where moving the HUD is blocked.
--
-- A drag of a move mode box ends the same way, in Shared/Movers.lua, as its
-- box hides.
local function endDrag()
    if not (auto and auto.dragging) or InCombatLockdown() then return end
    auto.dragging = nil
    auto.dragEnd = GetTime()
    hud:StopMovingOrSizing()
    savePosition()
end

H.place, H.tidy = function() if hud then place() end end, tidy

-- Whether the HUD shows, outside move mode. The mock raid's players aren't
-- there to buff.
local function wanted()
    if previewing then return O.get("showHud") ~= "never" end
    local when = O.get("showHud")
    return not NS.mock and when ~= "never" and (when == "always" or R.grouped()) and true or false
end

-- =============================================================
-- Move mode
-- =============================================================
-- A Shift-click on the auto-buff button, /bbc move or Move on the HUD tab
-- puts a box around the HUD, Group buffs and Target debuffs. The boxes are
-- Shared/Movers.lua's, the same as BayovCore's movers. Drag a box to move
-- what's in it, or use the arrow keys to move the one picked last a pixel at
-- a time (Shift for ten). A held arrow key repeats. Enter, Escape or a
-- right-click finish, and so does combat.
--
-- The boxes fit themselves again after every layout, so they follow when
-- Preview or a setting changes the icons while we move them.
--
-- The box takes the mouse, so clicking while we line the HUD up never buffs
-- anyone.
local Mv = NS.Movers

-- The line under the picked box.
H.MOVE_HINT = "Drag or use the arrow keys. Shift moves 10 pixels. Enter or Right-click when done."

-- The box of the HUD goes around the auto-buff button, every icon shown and
-- the line under the button, so the box's own hint under it never covers
-- that line.
local function fitHud(box)
    box:ClearAllPoints()
    local l, r, t, b = auto:GetLeft(), auto:GetRight(), auto:GetTop(), auto:GetBottom()
    local hl, ht = hud:GetLeft(), hud:GetTop()
    if not (l and r and t and b and hl and ht) then
        box:SetAllPoints(hud)
        return
    end
    local parts = { label }
    for _, f in ipairs(icons) do parts[#parts + 1] = f end
    for _, f in ipairs(parts) do
        if f:IsShown() and f:GetLeft() and (f ~= label or (label.text or "") ~= "") then
            l, r = math.min(l, f:GetLeft()), max(r, f:GetRight())
            t, b = max(t, f:GetTop()), math.min(b, f:GetBottom())
        end
    end
    box:SetPoint("TOPLEFT", hud, "TOPLEFT", l - hl, t - ht)
    box:SetSize(r - l, t - b)
end

-- Adds the HUD, Group buffs and Target debuffs to the shared movers, in that
-- order, so the HUD's box is the one picked first. A part that isn't on show
-- (set to Never) has no box.
local function addMovers()
    if moversAdded then return end
    moversAdded = true
    Mv.add({
        key = "hud", label = "Your assignments", hint = H.MOVE_HINT,
        frame = function() return hud end,
        get = function() return NS.db.hud.x or 0, NS.db.hud.y or -200 end,
        place = function() place() end,
        nudge = function(dx, dy) nudge(dx, dy) end,
        save = function() savePosition() end,
        fit = fitHud,
        hidden = function() return not hud:IsShown() end,
    })
    for _, w in ipairs({ NS.GroupBuffs, NS.TargetDebuffs }) do
        if w and w.MOVE then
            w.MOVE.hint = H.MOVE_HINT
            Mv.add(w.MOVE)
        end
    end
end

-- Fits each box of move mode to what it moves now. A box whose part isn't
-- on show (Group buffs set to Never) hides.
function H.fitMovers()
    if moving then Mv.fit() end
end

-- Starts move mode. Out of combat and while the HUD isn't locked only. The
-- HUD shows while we move it, even when it would be hidden now (solo, say),
-- so it can be placed before a raid. "Show the HUD" on Never still hides
-- it, and then only Group buffs and Target debuffs have a box.
function H.startMoving()
    if not hud or InCombatLockdown() then return false end
    if O.get("lock") then
        NS.print("The HUD is locked. Turn off Lock in place on the HUD tab to move it.")
        return false
    end
    if moving then return true end
    addMovers()
    moving = true
    GameTooltip:Hide()
    NS.signal("moving", true)
    H.layout()
    if NS.GroupBuffs then NS.GroupBuffs.paint() end
    Mv.start(true)
    H.fitMovers()
    return true
end

-- Move mode ended, by H.stopMoving or by a box (Enter, Escape, a
-- right-click, combat). `combat` says combat is starting.
--
-- Then Buffer.lua has just set the icons to cast on our mouseover, and a
-- layout now would aim them at players again. So we leave the layout for
-- after combat. A HUD that only showed for moving (solo, say) hides now,
-- while the game still lets us.
local function stopped(combat)
    if not moving then return end
    moving = false
    NS.signal("moving", false)
    if combat or InCombatLockdown() then
        if not InCombatLockdown() and not wanted() then hud:Hide() end
        pendingLayout = true
        return
    end
    H.layout()
end
Mv.onStop(stopped)

-- Ends move mode. `combat` says combat is starting, which ends it too.
function H.stopMoving(combat)
    if not moving then return end
    if Mv.active() then Mv.stop(combat) end
    stopped(combat)
end

function H.moving() return moving == true end
H.mover = function() return Mv.box("hud") end
-- The boxes of the HUD, Group buffs and Target debuffs, in that order.
H.movers = function()
    local out = {}
    for _, d in ipairs(Mv.list()) do
        local b = Mv.box(d.key)
        if b then out[#out + 1] = b end
    end
    return out
end

-- =============================================================
-- Preview
-- =============================================================
-- Turns Preview in game on or off. It shows the HUD with made-up buffs, and
-- Group buffs and Target debuffs with it, until it's turned off, the window
-- closes or combat starts. Each follows its settings as they change, so one
-- set to Never hides. Combat ends it as combat starts, while the game still
-- lets us put the real icons back.
function H.preview(on)
    on = on and not InCombatLockdown() and true or false
    if on == previewing then return end
    previewing = on
    if on then previewStart = GetTime() end
    NS.signal("preview", on)
    if InCombatLockdown() then
        pendingLayout = true
    else
        H.layout()
    end
end

function H.previewing() return previewing end

-- Whether the preview glows: where any place glows, so the glow can be
-- seen in the open world too.
function H.previewGlows()
    return O.get("glowWorld") or O.get("glowDungeon") or O.get("glowRaid") or false
end

local function build()
    hud = CreateFrame("Frame", "BuffCoordinatorHUD", UIParent)
    hud:SetMovable(true)
    hud:SetClampedToScreen(true)
    hud:SetSize(10, 10)

    auto = newIcon(hud, "BuffCoordinatorNext")
    auto.icon:SetTexture(NS.LOGO)
    auto.tex = NS.LOGO
    markOf(auto)
    label = hud:CreateFontString(nil, "OVERLAY")
    label:SetJustifyH("LEFT")
    -- Moving the HUD is a Shift-drag. The button hears the mouse press that
    -- starts a drag as a click, and with "cast on key down" on, a plain drag
    -- would cast before it moved anything.
    auto.drags = true
    auto:SetScript("OnDragStart", function(self)
        if O.get("lock") or InCombatLockdown() or not H.shiftDown() then return end
        self.dragging = true
        hud:StartMoving()
    end)
    local function stop(self)
        if not self.dragging then return end
        self.dragging = nil
        self.dragEnd = GetTime()
        hud:StopMovingOrSizing()
        savePosition()
    end
    auto:SetScript("OnDragStop", stop)
    auto:SetScript("OnHide", stop)
    auto:SetScript("PreClick", function(self, mouse, down)
        if InCombatLockdown() then return end
        -- A Shift-click with the mouse, and the click a drag ends in, mustn't
        -- buff anyone. A key bound with Shift still buffs, which is why we
        -- check that the mouse button is down, and remember it from the
        -- press to the release. The drag's click can come just before or
        -- just after it stops, in the same frame. Nothing stays set past the
        -- next press, so it can't swallow one.
        if down then self.shiftPress = H.shiftDown() and H.mouseDown() end
        local dragged = self.dragging or self.dragEnd == GetTime()
        if mouse ~= "LeftButton" or dragged or self.shiftPress then
            self:SetAttribute("type1", nil)
            if not down then
                -- A Shift-click that didn't drag starts move mode, once
                -- the click is done (PostClick).
                self.moveClick = self.shiftPress and mouse == "LeftButton" and not dragged
                self.shiftPress = nil
            end
            return
        end
        if down ~= B.keyDown() then return end
        -- We work out the list here rather than trust the last paint. The
        -- HUD doesn't paint while it's hidden ("Show the HUD" on Never),
        -- and the key still presses the button then.
        self.list = autoDuty()
        B.aim(self, self.list, true)
    end)
    auto:SetScript("PostClick", function(self, mouse, down)
        if mouse == "RightButton" and not down and NS.Config then NS.Config.toggle() end
        if self.moveClick then
            self.moveClick = nil
            H.startMoving()
        end
        NS.soon("hudPaint", 0.1, H.paint)
    end)
    auto:SetScript("OnEnter", function(self)
        hoverAuto(self, true)
        autoTooltip(self)
    end)
    auto:SetScript("OnLeave", function(self)
        hoverAuto(self, false)
        leave()
    end)
end

-- How far below the auto-buff button's top the first row of icons starts,
-- when they grow left or right. The button can be taller than the icons, so
-- with "Icons line up with" on Bottom the row drops by the difference. When
-- it's shorter, the row starts above the button's top. More rows still go
-- down from there.
local function rowDrop(h, grow)
    if grow ~= "right" and grow ~= "left" then return 0 end
    if O.get("rowAlign") ~= "bottom" then return 0 end
    local _, ah = autoSize()
    return ah - h
end

-- The gap between the icons, and the one between the line under the
-- auto-buff button and what it sits by, in screen pixels.
--
-- Another addon can set the icons' gap (O.lookGap), like BayovCore's Flush
-- look with -1. Then neighbouring icons overlap by one pixel. Each icon draws
-- its 1 pixel black border just inside its edge, so the two borders land on
-- the same line. The auto-buff button draws its border inside its edge too,
-- so it shares a line with the first icon the same way. With "Black border"
-- off there's no border to share, and an overlap would only hide a pixel of
-- the icon, so we stop at touching. The line of text has no border at all,
-- so it never comes closer than touching either.
local function gaps()
    local gap = O.lookGap() or O.get("gap")
    if gap < 0 and not O.get("border") then gap = 0 end
    return gap, max(gap, 0)
end

-- Puts icon `f`, the `i`th, in its place from the auto-buff button `btn`
-- of `frame`, for the settings `w`, `h`, `gap`, `perRow` and `grow`.
local function position(frame, btn, f, i, w, h, gap, perRow, grow, p)
    local row, col = floor((i - 1) / perRow), (i - 1) % perRow
    local step, across = (w + gap) * p, (h + gap) * p
    local aw = autoSize()
    local x0 = (aw + gap) * p
    local y0 = -rowDrop(h, grow) * p
    f:ClearAllPoints()
    if grow == "right" then
        f:SetPoint("TOPLEFT", frame, "TOPLEFT", x0 + col * step, y0 - row * across)
    elseif grow == "left" then
        f:SetPoint("TOPRIGHT", btn, "TOPLEFT", -gap * p - col * step, y0 - row * across)
    elseif grow == "down" then
        f:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", row * step, -gap * p - col * across)
    else
        f:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", row * step, gap * p + col * across)
    end
end

-- Puts the line under the auto-buff button clear of the icons: under the
-- last row, or above the button when the icons grow down. `gap` is between
-- the icons, and `textGap` between the line and the icons or the button
-- (gaps).
local function placeLabel(n, w, h, gap, textGap, perRow, grow, p, label, auto)
    setFont(label, O.get("countSize"))
    label:ClearAllPoints()
    if grow == "down" then
        label:SetJustifyV("BOTTOM")
        label:SetPoint("BOTTOMLEFT", auto, "TOPLEFT", 0, textGap * p)
    elseif grow == "up" then
        label:SetJustifyV("TOP")
        label:SetPoint("TOPLEFT", auto, "BOTTOMLEFT", 0, -textGap * p)
    else
        local rows = math.max(1, ceil(n / perRow))
        label:SetJustifyV("TOP")
        local _, ah = autoSize()
        local below = max(rowDrop(h, grow) + rows * h + (rows - 1) * gap + textGap, ah + textGap)
        label:SetPoint("TOPLEFT", auto, "TOPLEFT", 0, -below * p)
    end
end

-- Lays the HUD out again: one icon per duty, in rows from the auto-buff
-- button. Out of combat only.
function H.layout()
    if not hud then return end
    if InCombatLockdown() then
        pendingLayout = true
        return
    end
    pendingLayout = false
    -- It fades in, but hides at once, because its buttons are secure
    -- (Theme.lua's fades say why).
    if (moving and O.get("showHud") ~= "never") or wanted() then T.appear(hud) else hud:Hide() end
    place()
    local list = previewing and sampleDuties() or duties()
    H.current = list
    -- What the key presses, even while the HUD is hidden and doesn't paint.
    auto.list = autoDuty()
    local w, h = O.get("iconWidth"), O.get("iconHeight")
    local gap, textGap = gaps()
    local perRow, grow = O.get("perRow"), O.get("grow")
    local p = T.pixel(hud)
    arm(auto)
    local aw, ah = autoSize()
    fitAuto(auto, aw, ah)
    auto:ClearAllPoints()
    auto:SetPoint("TOPLEFT", hud, "TOPLEFT", 0, 0)
    for i, duty in ipairs(list) do
        local f = icons[i] or newIcon(hud)
        icons[i] = f
        arm(f)
        fit(f, w, h)
        f.duty = duty
        f.tag:SetShown(duty.backup == true)
        f:SetScript("OnEnter", tooltip)
        f:SetScript("OnLeave", leave)
        f:SetScript("PostClick", function() NS.soon("hudPaint", 0.1, H.paint) end)
        B.setup(f, duty.list, duty.fixed)
        watch(f, not duty.sample and duty.b and duty.b.debuff and duty.b or nil)
        position(hud, auto, f, i, w, h, gap, perRow, grow, p)
        f:Show()
    end
    for i = #list + 1, #icons do
        local f = icons[i]
        glow(f, nil)
        watch(f, nil)
        f.duty = nil
        f.tag:Hide()
        B.setup(f, {}, nil)
        f:Hide()
    end
    placeLabel(#list, w, h, gap, textGap, perRow, grow, p, label, auto)
    hud:SetSize(aw * p, ah * p)
    H.paint()
    H.fitMovers()
end

-- A copy of the HUD in `parent` with the made-up icons, for the HUD tab's
-- preview pane. Its icons are plain frames that cast nothing.
-- `stage.update()` lays it out and paints it again from the settings, and
-- answers its width and height in `parent`'s units, and where the auto-buff
-- button's top left corner sits in that box (`stage.ox`, `stage.oy`), since
-- icons that grow left or up and the line under the button go outside it.
-- `stage.targets()` names its parts for the pane's clicks (Settings.lua).
function H.stage(parent)
    local frame = CreateFrame("Frame", nil, parent)
    local btn = newIcon(frame, nil, true)
    btn.icon:SetTexture(NS.LOGO)
    markOf(btn)
    btn:SetScript("OnEnter", function(self) hoverAuto(self, true) end)
    btn:SetScript("OnLeave", function(self) hoverAuto(self, false) end)
    local line = frame:CreateFontString(nil, "OVERLAY")
    line:SetJustifyH("LEFT")
    local st = { frame = frame, icons = {}, auto = btn, label = line }
    local function enter(f)
        if f.duty then T.spellTip(f, f.duty.b, f.duty.title, { "Made up, to show the look." }) end
    end
    function st.update()
        local list = sampleDuties()
        local w, h = O.get("iconWidth"), O.get("iconHeight")
        local gap, textGap = gaps()
        local perRow, grow = O.get("perRow"), O.get("grow")
        local p = T.pixel(frame)
        local now = GetTime()
        local glows = H.previewGlows()
        local aw, ah = autoSize()
        fitAuto(btn, aw, ah)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        paintAutoSample(btn)
        for i, duty in ipairs(list) do
            local f = st.icons[i] or newIcon(frame, nil, true)
            st.icons[i] = f
            fit(f, w, h)
            f.duty = duty
            f:SetScript("OnEnter", enter)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
            position(frame, btn, f, i, w, h, gap, perRow, grow, p)
            paintSample(f, duty, now, glows)
            f:Show()
        end
        for i = #list + 1, #st.icons do st.icons[i]:Hide() end
        local text = O.get("nextLabel") and sampleNext() or ""
        -- The game wants a font before any text, and placeLabel sets it.
        placeLabel(#list, w, h, gap, textGap, perRow, grow, p, line, btn)
        line:SetText(text)
        line:SetShown(text ~= "")
        frame:SetSize(aw * p, ah * p)
        -- The box around it all, in screen pixels from the button's corner.
        local n = #list
        local across, down = math.min(n, perRow), math.max(1, ceil(n / perRow))
        local width, height, ox, oy
        if grow == "right" or grow == "left" then
            -- The rows can start above the button's top when it's the
            -- shorter one (rowDrop).
            local drop = n > 0 and rowDrop(h, grow) or 0
            local top = math.min(0, drop)
            width = aw + (n > 0 and gap + across * w + (across - 1) * gap or 0)
            height = math.max(ah, n > 0 and drop + down * h + (down - 1) * gap or 0) - top
            ox, oy = grow == "left" and width - aw or 0, -top
        else
            width = math.max(aw, down * w + (down - 1) * gap)
            height = ah + (n > 0 and gap + across * h + (across - 1) * gap or 0)
            ox, oy = 0, grow == "up" and height - ah or 0
        end
        local lh = text ~= "" and (O.get("countSize") + 4) or 0
        if grow == "down" then oy = oy + lh + textGap end
        height = height + (lh > 0 and lh + textGap or 0)
        st.ox, st.oy = ox * p, oy * p
        return width * p, height * p
    end
    -- Its parts for the pane's clicks (Settings.lua), each with the setting
    -- a click goes to. The text on an icon goes to its own size, so the
    -- icons come first and their text after, on top.
    function st.targets()
        local t = { { btn, "nextWidth", "Next buff button" }, { line, "nextLabel" } }
        for _, f in ipairs(st.icons) do t[#t + 1] = { f, "iconWidth" } end
        t[#t + 1] = { btn.count, "nextCountSize" }
        for _, f in ipairs(st.icons) do
            t[#t + 1] = { f.timer, "timerSize" }
            t[#t + 1] = { f.count, "countSize" }
        end
        return t
    end
    return st
end

-- =============================================================
-- Our assignments changed, and the pull check
-- =============================================================
-- What we last saw of our assignments: { sig, set of titles }.
local lastMine
-- How long after joining a group we stay quiet, while the board settles.
local MINE_SETTLE = 10
-- When we joined the group we last told our assignments in.
local toldGroup

-- When we joined this group, to the tenth of a second, which tells one
-- group from the next.
local function joinedAt()
    return floor((GetTime() - NS.Sync.inGroupFor()) * 10 + 0.5)
end

-- Whether we're in a group that hasn't heard our assignments yet, now that
-- the board settled.
local function untold()
    return not NS.mock and R.grouped() and NS.Sync.inGroupFor() >= MINE_SETTLE and toldGroup ~= joinedAt()
end

-- Says our assignments once in each group, once the board settled. A player
-- who joins a raid would otherwise have to open the window to learn them.
-- After that it says in one line when they change, and flashes the icons
-- that are new. Backups come and go with the roster, so they don't count.
--
-- These lines go out whatever the "Print assignment changes" setting says.
-- That one is for the edits of the leader and the assistants. Our own
-- assignments are the one line every player needs.
local function checkMine()
    local titles, set = {}, {}
    for _, d in ipairs(duties()) do
        if not d.backup and not set[d.title] then
            titles[#titles + 1] = d.title
            set[d.title] = true
        end
    end
    local sig = table.concat(titles, "\1")
    local before = lastMine
    lastMine = { sig = sig, set = set }
    if NS.mock or not R.grouped() or NS.Sync.inGroupFor() < MINE_SETTLE then return end
    local words = {}
    for i, t in ipairs(titles) do words[i] = B.short(t) end
    if toldGroup ~= joinedAt() then
        toldGroup = joinedAt()
        if #words == 0 then
            NS.print("You have no assignments here.")
        else
            NS.print("Your assignments here: %s.%s", andList(words),
                     hud and hud:IsShown() and " Click their icons to buff." or "")
        end
        return
    end
    if not before or before.sig == sig or previewing then return end
    NS.print(#words > 0 and "Your assignments are now %s." or "You have no assignments now.", andList(words))
    for i, d in ipairs(H.current or {}) do
        if not before.set[d.title] and icons[i] and icons[i]:IsShown() then flash(icons[i]) end
    end
end

-- A ready check: the HUD shows at once, flashes and sounds when something
-- of ours is due on the pull, and says what (paintLabel).
local function onPullCheck()
    if not hud then return end
    if Tr.pulling() and #Tr.due() > 0 then
        flash(auto)
        for i, duty in ipairs(H.current or {}) do
            local f = icons[i]
            if f and f:IsShown() and not (duty.b and duty.b.debuff) then
                local st = standing(duty, false, f)
                for _, t in ipairs(st.missing) do
                    if t.why ~= "dead" then
                        flash(f)
                        break
                    end
                end
            end
        end
        sound(SOUND_PULL)
    end
    H.paint()
end

NS.listen("login", function()
    build()
    H.layout()
    -- Countdowns show whole seconds above 3 s, so twice a second is enough
    -- (H.keepFresh counts the last 3 s down in tenths).
    -- Nothing else happens when the board settles after we join a group, so
    -- the ticker looks for that too.
    C_Timer.NewTicker(0.5, function()
        H.paint()
        if untold() then checkMine() end
    end)
end)
NS.listen("board", function()
    NS.soon("hudLayout", 0.1, H.layout)
    NS.soon("hudMine", 1, checkMine)
end)
NS.listen("pullCheck", onPullCheck)
NS.listen("roster", function() NS.soon("hudLayout", 0.2, H.layout) end)
NS.listen("tracking", function() NS.soon("hudPaint", 0.05, H.paint) end)
NS.listen("option", function(key)
    if key == "lock" and O.get("lock") then H.stopMoving() end
    NS.soon("hudLayout", 0.05, H.layout)
end)
NS.on("PLAYER_REGEN_ENABLED", function()
    if pendingLayout then H.layout() end
    H.paint()
end)
-- Combat starts. Buffer.lua's handler ran first (it asks to run first)
-- and set the icons for combat, so nothing here lays the HUD out.
NS.on("PLAYER_REGEN_DISABLED", function()
    endDrag()
    H.stopMoving(true)
    H.preview(false)
    H.paint()
end)
NS.command("move", "move the HUD with the mouse or the arrow keys, again to stop", function()
    if H.moving() then H.stopMoving() else H.startMoving() end
end)

H.icons = icons
H.auto = function() return auto end
H.labelText = function() return label and label.text or "" end
H.frame = function() return hud end
