-- Our settings: what each one is, and reading and writing them.
--
-- Each setting is a row below. The Settings and HUD pages (Settings.lua)
-- draw one control per row, in sections, so a new setting is a new row here and
-- nothing else. A value equal to its default isn't stored, so when we change
-- a default it reaches everyone who never touched that setting.
--
--   default   the value nobody has set, or a function that returns it (the
--             icon font, which depends on EllesmereUI being loaded)
--   kind      "bool", "number" or "enum"
--   min, max, step
--             for a number
--   values    for an enum: a list, or a function that returns one (the fonts
--             come from LibSharedMedia when another addon loaded it)
--   labels    for an enum: what each value is called on the page
--   section   the section it goes under on the page (O.SECTIONS), which
--             also says whether it's on the Settings tab or the HUD tab
--   order     where it goes in its section
--   name, desc
--             what the page calls it, and the tooltip
--   inherit   for one of the three's own copy of a setting on All three
--             (the icons' sizes): that setting's key. Until it's overridden
--             it goes by All three's (O.override).
--   group, sub
--             the tab and the HUD tab's subtab it's on, copied from its
--             section (O.SECTIONS) below
--
-- The rows are read and written by the settings engine BayovCore uses too
-- (Shared/Options.lua, which says more about each field). This file holds
-- our rows, the sections they go in, our colours and fonts, and the names the
-- rest of the addon calls them by (O.get, O.set and the rest).

local _, NS = ...

local Engine = NS.Options
local O = {}
NS.Options = O

-- Colours a setting can pick, by name. The house style's red and orange are
-- the defaults for missing and running out.
O.COLORS = {
    red = { 1, 0.247, 0.216 },
    orange = { 1, 0.718, 0.278 },
    yellow = { 1, 0.9, 0.3 },
    green = { 0.36, 0.86, 0.56 },
    blue = { 0.30, 0.72, 1.00 },
    purple = { 0.70, 0.52, 1.00 },
    pink = { 1, 0.45, 0.75 },
    white = { 1, 1, 1 },
    black = { 0, 0, 0 },
}
O.COLOR_NAMES = { "red", "orange", "yellow", "green", "blue", "purple", "pink", "white" }
-- For a border, black too. A glow or a text in black wouldn't show.
O.EDGE_COLOR_NAMES = { "black" }
for _, n in ipairs(O.COLOR_NAMES) do O.EDGE_COLOR_NAMES[#O.EDGE_COLOR_NAMES + 1] = n end

local function colorLabels(names)
    local t = {}
    for _, n in ipairs(names or O.COLOR_NAMES) do t[n] = NS.upperFirst(n) end
    return t
end

-- The fonts we can draw text in: ours, the game's, and every font
-- LibSharedMedia knows when another addon loaded it.
--
-- Adventor is TeX Gyre Adventor, a free font in the style of Avant Garde
-- that we ship (Fonts/Adventor Manifest.txt). EllesmereUI's Avant Garde is
-- ParaType's, which we may not ship, so Adventor stands in for it.
local BUILT_IN_FONTS = {
    ["PT Sans Narrow"] = [[Interface\AddOns\BuffCoordinator\Fonts\PTSansNarrow-Regular.ttf]],
    ["PT Sans Narrow Bold"] = [[Interface\AddOns\BuffCoordinator\Fonts\PTSansNarrow-Bold.ttf]],
    ["Adventor"] = [[Interface\AddOns\BuffCoordinator\Fonts\Adventor-Regular.ttf]],
    ["Adventor Bold"] = [[Interface\AddOns\BuffCoordinator\Fonts\Adventor-Bold.ttf]],
    ["Friz Quadrata"] = [[Fonts\FRIZQT__.TTF]],
    ["Arial Narrow"] = [[Fonts\ARIALN.TTF]],
    ["Morpheus"] = [[Fonts\MORPHEUS.TTF]],
    ["Skurri"] = [[Fonts\SKURRI.TTF]],
}

local function sharedMedia()
    local LS = _G.LibStub
    return LS and LS("LibSharedMedia-3.0", true) or nil
end

function O.fonts()
    local list, seen = {}, {}
    for name in pairs(BUILT_IN_FONTS) do
        list[#list + 1] = name
        seen[name] = true
    end
    local LSM = sharedMedia()
    if LSM then
        for _, name in ipairs(LSM:List("font") or {}) do
            if not seen[name] then
                list[#list + 1] = name
                seen[name] = true
            end
        end
    end
    table.sort(list)
    return list
end

-- The file of font `name`, or PT Sans Narrow when it isn't there. The user's
-- own style is EllesmereUI's Avant Garde, which only exists when EUI loaded
-- it into LibSharedMedia. Without EUI it's our Adventor Bold, the nearest
-- in weight.
function O.fontPath(name)
    if BUILT_IN_FONTS[name] then return BUILT_IN_FONTS[name] end
    local LSM = sharedMedia()
    local path = LSM and LSM:Fetch("font", name, true)
    if not path and name == "Avant Garde" then return BUILT_IN_FONTS["Adventor Bold"] end
    return path or BUILT_IN_FONTS["PT Sans Narrow"]
end

-- The icons' font when nobody picked one. That's EllesmereUI's Avant Garde
-- when EUI is loaded, since it only exists then.
local function iconFont()
    return NS.loaded("EllesmereUI") and "Avant Garde" or "Adventor Bold"
end

-- A Gap row is greyed while another addon sets the gap for us (O.lookGap).
local function gapFree()
    if O.lookGap() then return false, "Set by another addon." end
    return true
end

O.DECLS = {
    -- When we run the board: what reaches the rest of the group
    whisper = { default = true, kind = "bool", section = "Board", order = 1,
        name = "Whisper assignments",
        desc = "Whisper players without the addon when their assignments change." },
    whisperReady = { default = true, kind = "bool", section = "Board", order = 2,
        name = "Whisper on ready checks",
        desc = "Nearby players without the addon hear who's missing their long buffs or blessings." },
    whisperExpiry = { default = true, kind = "bool", section = "Board", order = 3,
        name = "Whisper missing buffs",
        desc = "Nearby players without the addon hear when their long buffs or blessings are missing or run out soon." },
    suggest = { default = true, kind = "bool", section = "Board", order = 4,
        name = "Let players suggest changes",
        desc = "Players without rank can send you changes to apply or turn down. When off, they can only look." },
    planHint = { default = true, kind = "bool", section = "Board", order = 5,
        name = "Say when an instance has a plan (leader)",
        desc = "As leader, say in chat when you enter an instance that has a plan." },

    -- Chat: lines only we see. Printing changes is here and not under the
    -- board, since an assistant who doesn't run it looks for it here.
    logEdits = { default = true, kind = "bool", section = "Chat", order = 1,
        name = "Print assignment changes",
        desc = "A chat line when the leader or an assistant changes an assignment. Without rank, only changes to yours." },

    -- Buffing
    rebuffMinutes = { default = 5, kind = "number", min = 0, max = 30, step = 1,
        section = "Buffing", order = 1, name = "Rebuff under (min)",
        desc = "Long buffs with less time left count as missing, so you rebuff early." },
    backups = { default = true, kind = "bool", section = "Buffing", order = 2,
        name = "Show what you back up",
        desc = "Add HUD icons for others' long buffs and blessings you can cover." },
    backupDelay = { default = 30, kind = "number", min = 0, max = 300, step = 5,
        section = "Buffing", order = 3, name = "Backups wait (s)",
        desc = "Backup icons light up once a buff has been missing this long." },
    debuffBossesOnly = { default = true, kind = "bool", section = "Buffing", order = 4,
        name = "Debuffs on bosses only in raids",
        desc = "In a raid instance, debuff icons light up on bosses only, not on every elite." },
    pullCheck = { default = true, kind = "bool", section = "Buffing", order = 5,
        name = "Pull check",
        desc = "On ready checks, list your buffs that would drop mid-fight." },
    fightMinutes = { default = 8, kind = "number", min = 1, max = 20, step = 1,
        section = "Buffing", order = 6, name = "Fight length (min)",
        desc = "The pull check flags buffs with less time left than this." },

    -- The HUD, and the coverage strip that goes with it
    showHud = { default = "group", kind = "enum", values = { "always", "group", "never" },
        labels = { always = "Always", group = "In groups", never = "Never" },
        section = "HUD", order = 1, name = "Show the HUD",
        desc = "Your assignments as icons. Click one to buff the next player missing it." },
    lock = { default = false, kind = "bool", section = "All", order = 1,
        name = "Lock in place",
        desc = "Stops all three from moving. Unlocked, Shift-drag the Next buff button, or drag a group buff or a debuff." },
    nextLabel = { default = false, kind = "bool", section = "HUD", order = 3,
        name = "Say what's next",
        desc = "A line by the Next buff button says what the next click or key press does." },
    iconWidth = { inherit = "allWidth", kind = "number", min = 16, max = 160, step = 1,
        section = "HUDIcons", order = 1, name = "Icon width",
        desc = "The width of each icon, in screen pixels." },
    iconHeight = { inherit = "allHeight", kind = "number", min = 16, max = 160, step = 1,
        section = "HUDIcons", order = 2, name = "Icon height",
        desc = "The height of each icon, in screen pixels." },
    gap = { inherit = "allGap", kind = "number", min = 0, max = 40, step = 1,
        section = "HUDIcons", order = 3, name = "Gap",
        desc = "The space between icons, in screen pixels.", needs = gapFree },
    perRow = { default = 6, kind = "number", min = 1, max = 20, step = 1,
        section = "HUD", order = 7, name = "Icons per row",
        desc = "How many icons go in a row before a new row starts." },
    grow = { default = "right", kind = "enum", values = { "right", "left", "down", "up" },
        labels = { right = "Right", left = "Left", down = "Down", up = "Up" },
        section = "HUD", order = 8, name = "Icons grow",
        desc = "Which way new icons go from the Next buff button." },
    rowAlign = { default = "bottom", kind = "enum", values = { "top", "bottom" },
        labels = { top = "Top", bottom = "Bottom" },
        section = "HUD", order = 9, name = "Icons line up with",
        desc = "When icons grow left or right: the top or the bottom of the Next buff button." },

    -- The Next buff button (HUD.lua), which looks unlike the icons
    nextWidth = { default = 68, kind = "number", min = 16, max = 160, step = 1,
        section = "Next", order = 1, name = "Width",
        desc = "The width of the Next buff button, in screen pixels." },
    nextHeight = { default = 68, kind = "number", min = 16, max = 160, step = 1,
        section = "Next", order = 2, name = "Height",
        desc = "The height of the Next buff button, in screen pixels." },
    nextBorder = { default = 2, kind = "number", min = 0, max = 8, step = 1,
        section = "Next", order = 3, name = "Border",
        desc = "The border's width, in screen pixels. 0 for none." },
    nextBorderColor = { default = "black", kind = "enum", values = O.EDGE_COLOR_NAMES,
        labels = colorLabels(O.EDGE_COLOR_NAMES), swatches = O.COLORS, section = "Next", order = 4, name = "Border colour",
        desc = "The border's colour." },
    nextHoverColor = { default = "blue", kind = "enum", values = O.EDGE_COLOR_NAMES,
        labels = colorLabels(O.EDGE_COLOR_NAMES), swatches = O.COLORS, section = "Next", order = 5, name = "Hover colour",
        desc = "The border's colour under the mouse." },
    -- 0.4 cuts a tenth off each side, past the bezel a square spell icon
    -- has drawn into it.
    nextZoom = { default = 0.4, kind = "number", min = 0, max = 0.8, step = 0.05,
        section = "Next", order = 6, name = "Zoom",
        desc = "How far the icon is zoomed in, so its bezel doesn't show." },
    nextCountSize = { default = 18, kind = "number", min = 6, max = 40, step = 1,
        section = "Next", order = 7, name = "Count size",
        desc = "The size of the count, how many are still to buff." },
    nextMissingColor = { default = "red", kind = "enum", values = O.COLOR_NAMES, labels = colorLabels(), swatches = O.COLORS,
        section = "Next", order = 8, name = "Missing colour",
        desc = "The count's colour when someone is missing a buff." },
    nextWarnColor = { default = "yellow", kind = "enum", values = O.COLOR_NAMES, labels = colorLabels(), swatches = O.COLORS,
        section = "Next", order = 9, name = "Running out colour",
        desc = "The count's colour when buffs only run out soon." },
    border = { default = true, kind = "bool", section = "All", order = 2,
        name = "Black border",
        desc = "A 1 pixel black border around each icon." },
    alpha = { inherit = "allAlpha", kind = "number", min = 0.1, max = 1, step = 0.05,
        section = "HUDIcons", order = 6, name = "Opacity",
        desc = "Out of combat. 1 is fully solid." },
    combatAlpha = { inherit = "allCombatAlpha", kind = "number", min = 0.1, max = 1, step = 0.05,
        section = "HUDIcons", order = 7, name = "Opacity in combat",
        desc = "1 is fully solid." },
    fadeIdle = { default = true, kind = "bool", section = "HUD", order = 12,
        name = "Fade when all is up",
        desc = "Fade the HUD while your buffs are up. It comes back when one is due." },
    missingSound = { default = true, kind = "bool", section = "HUD", order = 13,
        name = "Sound when a buff goes missing",
        desc = "Play a sound when one of your buffs drops. Out of combat only." },
    coverage = { default = "raid", kind = "enum", values = { "raid", "group", "never" },
        labels = { raid = "In raids", group = "In groups", never = "Never" },
        section = "HUD", order = 14, name = "Coverage strip",
        desc = "For the leader and players promoted to assistant by hand. Shows how many have each buff. Click one to whisper its giver." },

    -- The text on the HUD's icons
    font = { default = iconFont, kind = "enum", values = O.fonts,
        section = "All", order = 3, name = "Font",
        desc = "For counts and countdowns. Without EllesmereUI, Avant Garde shows as Adventor Bold." },
    -- SLUG is the client's newer text drawing, from the letters' vector
    -- shapes. Its edges are smoother than the plain outline's, and it's what
    -- ForeverAuras calls "Outline SLUG".
    outline = { default = "outline", kind = "enum",
        values = { "slug", "thickslug", "outline", "thick", "none" },
        labels = { slug = "Slug", thickslug = "Thick slug", outline = "Outline",
                   thick = "Thick", none = "None" },
        section = "All", order = 4, name = "Outline",
        desc = "The outline around counts and countdowns. Slug draws smoother letters." },
    countSize = { inherit = "allCountSize", kind = "number", min = 6, max = 30, step = 1,
        section = "HUDIcons", order = 4, name = "Count size",
        desc = "The size of the count in the corner, like 14/15." },
    countAnchor = { default = "BOTTOMRIGHT", kind = "enum",
        values = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT", "BOTTOM", "TOP" },
        labels = { BOTTOMRIGHT = "Bottom right", BOTTOMLEFT = "Bottom left",
                   TOPRIGHT = "Top right", TOPLEFT = "Top left", BOTTOM = "Bottom", TOP = "Top" },
        section = "Text", order = 3, name = "Count position",
        desc = "Where on the icon the count goes." },
    showCount = { default = true, kind = "bool", section = "Text", order = 4,
        name = "Show counts",
        desc = "How many of the players you buff have it, like 14/15." },
    timerSize = { inherit = "allTimerSize", kind = "number", min = 6, max = 40, step = 1,
        section = "HUDIcons", order = 5, name = "Countdown size",
        desc = "The size of the time left, on the top edge of an icon." },
    showTimer = { default = true, kind = "bool", section = "Text", order = 6,
        name = "Show countdowns",
        desc = "The time left on the buff that runs out first." },

    -- The glow on the HUD's icons
    glowStyle = { default = "pixel", kind = "enum", values = { "pixel", "border", "none" },
        labels = { pixel = "Moving lines", border = "Coloured border", none = "None" },
        section = "Glow", order = 1, name = "Glow style",
        desc = "How an icon shows that someone needs your buff." },
    glowColor = { default = "red", kind = "enum", values = O.COLOR_NAMES, labels = colorLabels(), swatches = O.COLORS,
        section = "Glow", order = 2, name = "Missing colour",
        desc = "The glow when someone is missing the buff." },
    warnColor = { default = "orange", kind = "enum", values = O.COLOR_NAMES, labels = colorLabels(), swatches = O.COLORS,
        section = "Glow", order = 3, name = "Running out colour",
        desc = "The glow when a buff is about to run out." },
    glowWorld = { default = false, kind = "bool", section = "Glow", order = 4,
        name = "Glow in the open world",
        desc = "Glow outside dungeons and raids too." },
    glowDungeon = { default = true, kind = "bool", section = "Glow", order = 5,
        name = "Glow in dungeons", desc = "Glow inside dungeons." },
    glowRaid = { default = true, kind = "bool", section = "Glow", order = 6,
        name = "Glow in raids", desc = "Glow inside raids." },

    -- The icons' sizes and opacity, which all three go by unless one of
    -- them overrides it (`inherit` above)
    allWidth = { default = 68, kind = "number", min = 16, max = 160, step = 1,
        section = "Icons", order = 1, name = "Icon width",
        desc = "The width of each icon, in screen pixels." },
    allHeight = { default = 48, kind = "number", min = 16, max = 160, step = 1,
        section = "Icons", order = 2, name = "Icon height",
        desc = "The height of each icon, in screen pixels." },
    allGap = { default = 4, kind = "number", min = 0, max = 40, step = 1,
        section = "Icons", order = 3, name = "Gap",
        desc = "The space between icons, in screen pixels.", needs = gapFree },
    allCountSize = { default = 12, kind = "number", min = 6, max = 30, step = 1,
        section = "Icons", order = 4, name = "Count size",
        desc = "The size of the count on an icon." },
    allTimerSize = { default = 15, kind = "number", min = 6, max = 40, step = 1,
        section = "Icons", order = 5, name = "Countdown size",
        desc = "The size of the time left on an icon." },
    allAlpha = { default = 1, kind = "number", min = 0.1, max = 1, step = 0.05,
        section = "Icons", order = 6, name = "Opacity",
        desc = "Out of combat. 1 is fully solid." },
    allCombatAlpha = { default = 1, kind = "number", min = 0.1, max = 1, step = 0.05,
        section = "Icons", order = 7, name = "Opacity in combat",
        desc = "1 is fully solid." },

    -- This window, and the minimap button that opens it
    windowScale = { default = 1, kind = "number", min = 0.5, max = 2, step = 0.05,
        section = "Window", order = 1, name = "Window scale",
        desc = "The size of this window." },
    accent = { default = "blue", kind = "enum", values = O.COLOR_NAMES, labels = colorLabels(), swatches = O.COLORS,
        section = "Window", order = 2, name = "Accent colour",
        desc = "The colour of the headings, switches and the chosen tab in this window." },
    windowFont = { default = "PT Sans Narrow", kind = "enum", values = O.fonts,
        section = "Window", order = 3, name = "Window font",
        desc = "The font of this window." },
    minimap = { default = true, kind = "bool", section = "Window", order = 4,
        name = "Minimap button",
        desc = "A minimap button that opens this window." },
}

-- The settings of a widget (Widget.lua): Group buffs and Target debuffs.
-- Each has the same rows, named from `key` ("group" makes groupWidth and
-- the rest), in section `section`, with `show` its "Show ..." row. `d`
-- holds the defaults that differ between them.
local function widget(key, show, section, label, d)
    local rows = {
        [show] = { default = "group", kind = "enum", values = { "always", "group", "raid", "never" },
            labels = { always = "Always", group = "In groups", raid = "In raids", never = "Never" },
            name = "Show " .. label, desc = d.showDesc },
        Combat = { default = true, kind = "bool", name = "Show in combat", desc = "Off hides them until combat ends." },
        MissingOnly = { default = false, kind = "bool", name = "Only what's missing", desc = d.missingDesc },
        Width = { default = 68, kind = "number", min = 16, max = 160, step = 1,
            name = "Icon width", desc = "The width of each icon, in screen pixels." },
        Height = { default = 48, kind = "number", min = 16, max = 160, step = 1,
            name = "Icon height", desc = "The height of each icon, in screen pixels." },
        Gap = { default = 4, kind = "number", min = 0, max = 40, step = 1,
            name = "Gap", desc = "The space between icons, in screen pixels.", needs = gapFree },
        PerRow = { default = d.perRow, kind = "number", min = 1, max = 20, step = 1,
            name = "Icons per row", desc = "How many icons go in a row before a new row starts." },
        Align = { default = d.align, kind = "enum", values = { "left", "center", "right" },
            labels = { left = "Left", center = "Middle", right = "Right" },
            name = "Row alignment", desc = "Where a row that isn't full sits." },
        Grow = { default = d.grow, kind = "enum", values = { "down", "up" },
            labels = { down = "Down", up = "Up" },
            name = "Rows grow", desc = "Which way new rows go. The first row stays put." },
        CountSize = { default = 12, kind = "number", min = 6, max = 30, step = 1,
            name = "Count size", desc = d.countDesc },
        Timer = { default = d.timer, kind = "bool", name = "Show countdowns", desc = d.timerDesc },
        TimerSize = { default = 15, kind = "number", min = 6, max = 40, step = 1,
            name = "Countdown size", desc = "The size of the time left, in the middle of an icon." },
        Glow = { default = d.glow, kind = "bool", name = "Glow when missing", desc = "Glow like your own icons do." },
        Alpha = { default = 1, kind = "number", min = 0.1, max = 1, step = 0.05,
            name = "Opacity", desc = "Out of combat. 1 is fully solid." },
        CombatAlpha = { default = 1, kind = "number", min = 0.1, max = 1, step = 0.05,
            name = "Opacity in combat", desc = "1 is fully solid." },
    }
    local ORDER = { show, "Combat", "MissingOnly", "Width", "Height", "Gap", "PerRow", "Align", "Grow",
                    "CountSize", "Timer", "TimerSize", "Glow", "Alpha", "CombatAlpha" }
    for i, k in ipairs(ORDER) do
        local row = rows[k]
        row.section, row.order = section, i
        -- The ones All three has too go under their own heading.
        if O.DECLS["all" .. k] then row.inherit, row.default, row.section = "all" .. k, nil, section .. "Icons" end
        O.DECLS[k == show and k or key .. k] = row
    end
end

-- Group buffs: everyone's long buffs (GroupBuffs.lua)
widget("group", "groupBuffs", "Group", "group buffs", {
    showDesc = "Everyone's long buffs. Click one to whisper who gives it.",
    missingDesc = "Hide a buff everyone has.",
    countDesc = "The size of the count, like 17/20.",
    timerDesc = "The time left on the first to run out.",
    perRow = 8, align = "center", grow = "down", timer = false, glow = false,
})

-- Target debuffs: the debuffs on the target (TargetDebuffs.lua)
widget("debuff", "targetDebuffs", "Debuffs", "target debuffs", {
    showDesc = "The debuffs your target should have. Click one to whisper who puts it up.",
    missingDesc = "Hide a debuff that's up.",
    countDesc = "The size of the stack count, like 3 of Sunder Armor.",
    timerDesc = "The time left on each debuff.",
    perRow = 6, align = "left", grow = "up", timer = true, glow = true,
})

-- The sections of the Settings page, in order. `title` is the heading when
-- it isn't the id, and `note` a line under it. `children` are the sections
-- that go under this one with a smaller heading of their own, and `full` is
-- the heading a child gets when it starts a column. A section with
-- `group = "hud"` is on the HUD tab instead, and so are its children, on the
-- subtab `sub` says ("hud", "group", "debuff" or "all" for the settings all
-- three share). A child's `note` goes under its heading too.
--
-- Each of the three has a child with its copies of All three's Icons
-- settings, so the rows that can go by All three are together.
local function iconsSub(id)
    return { id = id, title = "Icons", full = "Icons", note = "Shared by all HUDs. Override any of them here." }
end
O.SECTIONS = {
    { id = "Board", title = "When you're Assignments Leader",
      note = "Whispers and suggestions for your group." },
    { id = "Chat", note = "Lines in your chat that only you see." },
    { id = "Buffing", note = "When a buff counts as missing, and what you cover for others." },
    { id = "Window", note = "This window, and the minimap button that opens it." },
    { id = "HUD", title = "Your assignments", note = "Icons that buff with a click.", group = "hud", sub = "hud",
      children = { iconsSub("HUDIcons"), { id = "Next", title = "Next buff button" }, { id = "Text" } } },
    { id = "Group", title = "Group buffs",
      note = "Everyone's long buffs, and who's missing one.", group = "hud",
      sub = "group", children = { iconsSub("GroupIcons") } },
    { id = "Debuffs", title = "Target debuffs",
      note = "The debuffs your target should have.", group = "hud",
      sub = "debuff", children = { iconsSub("DebuffsIcons") } },
    { id = "All", title = "All three", note = "These apply to your assignments, group buffs and target debuffs.",
      group = "hud", sub = "all" },
    { id = "Icons", note = "All three go by these, unless one overrides it on its own tab.", group = "hud",
      sub = "all" },
    { id = "Glow", group = "hud", sub = "all" },
}

-- The keys of section `section`, in order.
function O.keys(section)
    local t = {}
    for k, d in pairs(O.DECLS) do
        if d.section == section then t[#t + 1] = k end
    end
    table.sort(t, function(a, b)
        local oa, ob = O.DECLS[a].order or 99, O.DECLS[b].order or 99
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    return t
end

-- The sections in O.SECTIONS and their children, and after them any section
-- a setting names that isn't there, so no setting is ever left off the page.
-- Each is { id, title, note, parent, group, sub }, where `parent` is the
-- section it is a child of, `group` is "hud" for the HUD tab's, and `sub` its
-- subtab.
function O.sections()
    local list, seen = {}, {}
    for _, s in ipairs(O.SECTIONS) do
        list[#list + 1] = { id = s.id, title = s.title or s.id, note = s.note, group = s.group, sub = s.sub }
        seen[s.id] = true
        for _, child in ipairs(s.children or {}) do
            list[#list + 1] = { id = child.id, title = child.title or child.id, full = child.full or child.id,
                                note = child.note, parent = s.id, group = s.group, sub = s.sub }
            seen[child.id] = true
        end
    end
    local extra = {}
    for _, d in pairs(O.DECLS) do
        if d.section and not seen[d.section] then
            extra[#extra + 1] = d.section
            seen[d.section] = true
        end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do list[#list + 1] = { id = id, title = id } end
    return list
end

-- Each row's tab and subtab, from its section, so the settings engine's
-- page can find it. A row whose section isn't in O.SECTIONS is on the
-- Settings tab.
local SUB_TITLES = { hud = "Yours", group = "Group", debuff = "Debuffs", all = "All three" }
local sectionTitles, sectionNotes = {}, {}
for i, sec in ipairs(O.sections()) do
    if sec.title ~= sec.id then sectionTitles[sec.id] = sec.title end
    sectionNotes[sec.id] = sec.note
    for j, k in ipairs(O.keys(sec.id)) do
        local d = O.DECLS[k]
        d.group, d.sub = sec.group or "settings", sec.sub
        -- The page lists a tab's rows by `order` alone, so each section's
        -- rows come after the ones of the sections before it.
        d.order = i * 100 + j
        -- The HUD's sizes and opacity are worth trying across their whole
        -- range, so they get a slider beside their box, and so does the
        -- window's scale.
        if d.kind == "number" and (d.group == "hud" or k == "windowScale") then d.slide = true end
    end
end

-- Our settings live in NS.db.opts, and NS.db is there only once we've
-- loaded the saved variables, so the engine asks for it each time. Numbers
-- are clamped, so a slider dragged past its end lands on the end. Each
-- change tells everyone through the "option" signal, so the HUD and the
-- window redraw.
local o = Engine.new({
    name = "buffco",
    decls = O.DECLS,
    groups = { "settings", "hud" },
    titles = { settings = "Settings", hud = "HUD" },
    subTitles = SUB_TITLES,
    sectionTitles = sectionTitles,
    sectionNotes = sectionNotes,
    store = function() return NS.db end,
    clamp = true,
    apply = function(key, v) NS.signal("option", key, v) end,
})
O.engine = o
-- What the settings engine's page draws from.
O.adapter = o.adapter
O.get, O.default, O.values = o.get, o.default, o.values

-- The gap between the HUD's icons that another addon asks for, in screen
-- pixels, or nil when none does.
--
-- BayovCore's Looks presets publish one at _G.BayovCore.looks.get("bc"). Its
-- Flush preset answers { gap = -1 }, so neighbouring icons overlap by one
-- pixel and their 1 pixel borders share one line. We ship on our own too, so
-- every step is checked and an error in there means we use our own setting.
-- We ask each time we lay out rather than once at load, because the other
-- addon may load after us. Its answer only changes on a /reload.
function O.lookGap()
    local core = rawget(_G, "BayovCore")
    local looks = type(core) == "table" and core.looks
    local get = type(looks) == "table" and looks.get
    if type(get) ~= "function" then return nil end
    local okay, t = pcall(get, "bc")
    if not okay or type(t) ~= "table" then return nil end
    return type(t.gap) == "number" and t.gap or nil
end

function O.label(key, value)
    local d = O.DECLS[key]
    return d and d.labels and d.labels[value] or tostring(value)
end

local function stored(key)
    return NS.db and NS.db.opts and NS.db.opts[key]
end

-- Whether `key` holds something other than its default. For one that goes
-- by All three's, that's whether it's overridden.
function O.changed(key)
    return stored(key) ~= nil
end

-- Whether `key` is one of the three's own copy of an All three setting that
-- still goes by All three's.
function O.shared(key)
    return o.inherits(key)
end

-- Gives `key`, which goes by All three's, a value of its own: All three's
-- for now, so nothing moves until it's changed. O.reset puts it back. A
-- value set on one that follows is stored even when it's the same, so it
-- stays an override.
function O.override(key)
    if not O.shared(key) or not NS.db then return end
    o.set(key, o.get(key))
    NS.signal("option", key, O.get(key))
end

-- Sets `key` to `value`, clamped to its range. It does nothing when the
-- value is the one it has.
function O.set(key, value)
    if not NS.db then return end
    o.write(key, value)
end

function O.reset(key)
    if stored(key) == nil then return end
    o.commitReset(key)
end

-- The tab setting `key` is on: "hud", or nil for the Settings tab.
function O.tabOf(key)
    local d = O.DECLS[key]
    return d and d.group == "hud" and "hud" or nil
end

-- Every setting back to its default, or with `tab` only that tab's ("hud",
-- or "settings" for the Settings tab's).
function O.resetAll(tab)
    if not NS.db then return end
    for k in pairs(NS.db.opts) do
        if not tab or (O.tabOf(k) or "settings") == tab then NS.db.opts[k] = nil end
    end
    NS.signal("option", nil)
end

-- A named colour setting as { r, g, b }.
function O.color(key)
    return O.COLORS[O.get(key)] or O.COLORS.white
end

-- Before All three had the icons' sizes, each of the three had its own. A
-- size that's the same on all three becomes All three's, and the rest stay
-- overrides, so nothing moves. NS.loadDB does it once.
function O.shareSame(opts)
    local copies = {}
    for k, d in pairs(O.DECLS) do
        if d.inherit then
            copies[d.inherit] = copies[d.inherit] or {}
            table.insert(copies[d.inherit], k)
        end
    end
    for common, keys in pairs(copies) do
        local v = opts[keys[1]]
        local same = v ~= nil and opts[common] == nil
        for _, k in ipairs(keys) do
            if opts[k] ~= v then same = false end
        end
        if same then
            for _, k in ipairs(keys) do opts[k] = nil end
            if v ~= O.DECLS[common].default then opts[common] = v end
        end
    end
end
