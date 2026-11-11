-- The assignments window: who does what in the group, and our settings.
--
-- It has a tab per page. Every page but HUD and Settings starts with the
-- plan box (Profiles.lua), one status line on who runs the board and what
-- that means for us, and the banners for our draft and the suggestions
-- waiting for us.
--   Assignments   who gives what, from Needs and Overrides, only to read.
--                 Each tooltip names the override behind what it costs:
--     Missing       what the group wants and nobody gives, in red
--     Blessings     what each class gets, in Blessings.lua
--     Totems, Buffs, Auras, Debuffs
--                   a card per assignment, with its icon, its name and who
--                   gives it
--     Party buffs   who gives each party what reaches only the giver's
--                   party, as cards in a party and a table of groups in a
--                   raid, in PartyBuffs.lua
--     Not needed    what nobody here wants, folded away
--   You           who the addon takes us for, what we give, what we get,
--                 and what we go without, whether the setup could give it
--                 or nobody here can
--   Needs         what auto aims for: what each spec and player wants,
--                 blessings first (BuffsBySpec.lua, Priority.lua), three
--                 classes at a time. It also turns assignments on or off.
--   Resistances   a row per fight that needs them (Resistances.lua)
--   Overrides     a card per override, each part of it a dropdown, and
--                 Add override for a new one (Overrides.lua). A player
--                 dragged here or onto its tab from the raid pane starts a
--                 new one.
--   HUD           how the HUD and Group buffs look, with Preview to
--                 see them on screen with made-up buffs
-- Settings and HUD are Settings.lua. The raid pane (RaidPane.lua) on the window's
-- left shows our party or raid, or a mock raid (Mock.lua), and arranges it.
-- The window can be resized from its bottom right corner.
--
-- Only the raid leader and the assistants can change assignments. Everyone
-- else may draft a suggestion for them in this window when whoever runs the
-- board lets them (Suggest.lua), or else sees the same page without Add
-- override and the dropdowns. While there is a draft, the window shows the
-- board it would make, with what it changed in blue. A draft left over
-- after suggestions close can only be discarded.

local _, NS = ...
local D, R, Du, Tr, O, T = NS.Data, NS.Roster, NS.Duties, NS.Tracking, NS.Options, NS.Theme

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local format = string.format

local C = {}
NS.Config = C

-- The window's size the first time: the raid pane, then the pages. A drag of
-- the corner can make the pages no narrower than MIN_W.
local WIDTH, HEIGHT = 720, 640
local MIN_W, MIN_H = 660, 420
local PAD = 12
-- The header is one line: the logo, the title and what the group is. The
-- tabs start HEAD_H down, under a hairline, with the page's buttons at their
-- right.
local LOGO = 20
local HEAD_H = 30
local TAB_H = 24
-- Between the tabs' line and a page's first row.
local GAP = 8
local CLASSES = D.CLASSES

local win, pages, current

-- =============================================================
-- Words
-- =============================================================
local classWord, upperFirst, andList = NS.classWord, NS.upperFirst, NS.andList
-- The game's tooltip of a buff's spell with ours under it (Theme.lua).
local spellTip = T.spellTip

-- A spec's name, or "?" when we don't know the spec.
local function specName(class, tree)
    return Du.specName(class, tree) or "?"
end
C.specName = specName

local function colored(m)
    return NS.classColored(m.name, m.class)
end

-- The colours of Theme.lua's T.COLOR: red is missing or blocked, green is up,
-- grey is not here or not needed, and blue (the accent) is changed in our
-- draft.
local RED, GREEN, GREY, BLUE = T.COLOR.bad, T.COLOR.up, T.COLOR.idle, T.COLOR.changed
local DIM, hex = T.DIM, T.hex

-- A blessing by its short name: "Kings" for Blessing of Kings.
local function shortBless(b)
    return (Tr.title(b):gsub("^Blessing of ", ""))
end

-- Whether we hold a draft that can't go anywhere: suggestions closed while
-- we drafted, and we have no rank to apply it ourselves. All we can do with
-- it then is discard it.
local function stuckDraft()
    local d = NS.draft
    return d ~= nil and not d.from and not R.canEdit() and not NS.Suggest.open()
end

-- Whether the window lets us change anything. Su.canChange says yes to any
-- draft, so we check for a stuck draft here too.
local function canChange() return NS.Suggest.canChange() and not stuckDraft() end
C.canChange = canChange

-- The tooltip hint for a click that would `what` ("change who's on it"). When
-- the assignments are locked for us there's no hint, and `lines` gets a line
-- that says why.
local function hintsFor(lines, list)
    if not canChange() then
        lines[#lines + 1] = stuckDraft() and "Suggestions are off. You can only discard your draft."
                            or "Only the leader and assistants can change it."
        return nil
    end
    local draft = NS.draft or not R.canEdit()
    local t = {}
    for i, h in ipairs(list) do t[i] = { h[1], draft and h[2] .. " in the draft" or h[2] } end
    return t
end
-- The same for the other windows, with several hints: { { "Click", what },
-- { "Right-click", what } }.
C.hints = hintsFor

local function clickHint(lines, what)
    return hintsFor(lines, { { "Click", what } })
end

-- The classes where someone gets fewer blessings than they should, in class
-- order.
local function blessWarnings(plan)
    local t = {}
    for _, class in ipairs(CLASSES) do
        local w = plan and plan.warnings and plan.warnings[class]
        if w then t[#t + 1] = w end
    end
    return t
end

-- What's wrong in a class, as sentences: "Warriors miss Kings: Pal Alpha
-- and Pal Beta both give Might."
-- Why class warning `w` (a blessings plan's) misses blessing `id`, as
-- fragments: "Pal Alpha and Pal Beta both give Kings", "Pal Gamma is set
-- to give warriors nothing", "no paladin here knows Kings". Empty when
-- every paladin just gives them something else.
local function missWhy(w, id)
    local why = {}
    if w.unknown and w.unknown[id] then
        why[1] = format("no paladin here knows %s", NS.buffText(D.BY_ID[id]))
    end
    local twice = {}
    for bid, pals in pairs(w.twice) do
        local names = {}
        for i, pal in ipairs(pals) do names[i] = NS.who(pal) end
        twice[#twice + 1] = format("%s both give %s", andList(names), NS.buffText(D.BY_ID[bid]))
    end
    table.sort(twice)
    for _, t in ipairs(twice) do why[#why + 1] = t end
    local none = {}
    for i, pal in ipairs(w.none or {}) do none[i] = NS.who(pal) end
    if #none > 0 then
        why[#why + 1] = format("%s %s set to give %s nothing", andList(none), #none == 1 and "is" or "are",
                               classWord(w.class))
    end
    return why
end
C.missWhy = missWhy

local function warningLines(w)
    local lines = {}
    for id, people in pairs(w.missing) do
        local n = #people
        local who = n == 1 and NS.who(people[1]) or NS.classText(w.class, format("%d %s", n, classWord(w.class)))
        local text = format("%s miss %s", who, NS.buffText(D.BY_ID[id]))
        if n == 1 then text = format("%s misses %s", who, NS.buffText(D.BY_ID[id])) end
        local why = missWhy(w, id)
        if #why > 0 then text = text .. ": " .. table.concat(why, ", ") end
        lines[#lines + 1] = text .. "."
    end
    table.sort(lines)
    return lines
end

-- How many miss a blessing in class `class`, or 0.
local function missingIn(plan, class)
    local w = plan and plan.warnings and plan.warnings[class]
    local n = 0
    for _, people in pairs(w and w.missing or {}) do n = n + #people end
    return n
end

-- Who gives a job's buffs, for a card: "Mira", or "Thrall (Windfury Totem),
-- Drek (Grace of Air)", then the backups in grey.
local function giversText(plan)
    if not plan.active then return DIM .. (plan.why or "") .. "|r" end
    local parts = {}
    for _, a in ipairs(plan.list) do
        local what
        if not a.bless and a.buff and #plan.job.options > 1 then what = Tr.title(a.buff) end
        if a.party and R.raid() then
            what = (what and what .. ", " or "") .. format("group %d", a.party)
        end
        parts[#parts + 1] = what and format("%s %s(%s)|r", colored(a.giver), DIM, what) or colored(a.giver)
    end
    local text = table.concat(parts, ", ")
    local spare = {}
    for _, m in ipairs(plan.backups or {}) do spare[#spare + 1] = m.name end
    if plan.job.kind == "blessing" then
        for _, r in ipairs(plan.reserve or {}) do spare[#spare + 1] = r.giver.name end
    end
    if #spare > 0 then
        text = text .. format("  %s%s %s|r", DIM, #spare == 1 and "backup" or "backups", table.concat(spare, ", "))
    end
    local short = 0
    for _, w in ipairs(blessWarnings(plan)) do short = short + missingIn(plan, w.class) end
    if short > 0 then text = format("%s%d miss a blessing|r  ", hex(RED), short) .. text end
    return text
end

-- =============================================================
-- Who runs the board
-- =============================================================
-- "Bob (leader)", in Bob's class colour.
local function whoRuns(m)
    local word = NS.rankWord(m)
    return colored(m) .. (word and format(" (%s)", word) or "")
end

local function leaderOf()
    for _, m in ipairs(R.list()) do
        if m.rank == 2 then return m end
    end
end

-- How many here run the addon, and who doesn't.
local function addonUsers()
    local S = NS.Sync
    local with, without = 0, {}
    for _, m in ipairs(R.list()) do
        if S and S.hasAddon(m.name) then
            with = with + 1
        else
            without[#without + 1] = m
        end
    end
    return with, without
end

-- The line at the top of the Assignments page: who runs the board, and what
-- that means for us, in a few plain sentences.
function C.status()
    if NS.mock then
        return "This mock raid is only yours. Your real assignments don't change."
    end
    if not R.grouped() then
        return "This is your own setup. Your group uses it when you lead."
    end
    local S = NS.Sync
    local host = S.host()
    if not host or not S.officer(host) then
        -- Whoever runs the board then can't change anything, and nobody
        -- can take a suggestion.
        local lead = leaderOf()
        local what = #Du.constraints() == 0 and "so everything is auto" or "so nobody can change the assignments"
        local text = format("No leader or assistant has the addon, %s.", what)
        if lead and not lead.me then
            text = text .. format(" Ask %s to install it, or to make you %s.", colored(lead),
                                  R.raid() and "an assistant" or "the leader")
        end
        if stuckDraft() then text = text .. " Your draft can't be sent. You can discard it." end
        return text
    end
    if S.isHost() then
        local me = R.me()
        local text = format("You're the Assignments Leader as %s.",
                            me and me.rank == 2 and "the leader" or "an assistant")
        local with, without = addonUsers()
        if #without == 0 then return text .. " Everyone here has the addon." end
        text = text .. format(" %d of %d have the addon.", with, #R.list())
        local others = #without == 1 and "The other player" or format("The other %d", #without)
        local one = #without == 1
        if O.get("whisper") then
            return text .. format(" %s %s whispers.", others, one and "gets" or "get")
        end
        return text .. format(" %s %s no whispers. Turn them on in Settings.", others, one and "gets" or "get")
    end
    local text = format("%s is the Assignments Leader.", whoRuns(host))
    if R.canEdit() then return text .. " You can change assignments too." end
    if NS.Suggest.open() then
        return text .. " You can suggest changes."
    end
    if stuckDraft() then return text .. " Suggestions are off. You can discard your draft." end
    return text .. " Suggestions are off. You can only look."
end

-- A gap of Du.gaps in two parts: what's missing ("Power Word: Fortitude")
-- and why ("No priest here"), without the full stop.
local function gapParts(g)
    return g.what, g.why and (g.why:gsub("%.$", "")) or ""
end
C.gapParts = gapParts

-- What the group wants and is given, counted as the Missing list counts it:
-- each assignment someone is on, and each gap of Du.gaps. The totems count
-- one by one, since the gaps name them one by one. Returns how many are
-- given, how many are wanted, and what's missing.
local function given()
    local n, totems = 0, {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.shown(job.id)
        if job.kind == "totem" then
            for _, a in ipairs(plan and plan.active and plan.list or {}) do
                if not totems[a.buff] then
                    totems[a.buff] = true
                    n = n + 1
                end
            end
        elseif job.kind ~= "resist" and plan and plan.active then
            n = n + 1
        end
    end
    local missing = {}
    for _, g in ipairs(Du.gaps()) do missing[#missing + 1] = (gapParts(g)) end
    return n, n + #missing, missing
end

-- The line beside the title: "18 players · 21 of 23 given".
local function summary()
    local parts = {}
    if NS.mock then parts[1] = R.raid() and "Mock raid" or "Mock party" end
    local n = #Du.shownMembers()
    if not NS.mock and not R.grouped() then
        parts[#parts + 1] = "Just you"
    else
        parts[#parts + 1] = n == 1 and "1 player" or format("%d players", n)
    end
    local ok, all = given()
    if all > 0 then parts[#parts + 1] = format("%d of %d given", ok, all) end
    return table.concat(parts, "  ·  ")
end

-- The chip beside the title, only when there's something to say: a draft
-- that isn't applied, someone missing a blessing, or that we may only look
-- or suggest. Blue is our draft, red a problem, and grey a plain fact. A
-- mock raid is a plain fact too, and blue there would read as a draft.
local function stateChip()
    if NS.mock then return R.raid() and "Mock raid" or "Mock party", T.NEUTRAL end
    if NS.draft then return "Draft", BLUE end
    local short = 0
    local plan = Du.plan("blessings")
    for _, w in ipairs(blessWarnings(plan)) do short = short + missingIn(plan, w.class) end
    if short > 0 then return format("%d miss a blessing", short), RED end
    if R.grouped() and not R.canEdit() then
        return canChange() and "Suggestions only" or "View only", T.NEUTRAL
    end
end

-- =============================================================
-- The window
-- =============================================================
local PAGES = {
    { key = "duties", title = "Assignments" },
    { key = "you", title = "You" },
    { key = "needs", title = "Needs" },
    { key = "resist", title = "Resistances" },
    { key = "overrides", title = "Overrides" },
    { key = "hud", title = "HUD" },
    { key = "settings", title = "Settings" },
}
local PAGE = {}
for _, def in ipairs(PAGES) do PAGE[def.key] = def end

-- Shows page `name`. The raid pane stays as it was drawn, unless `full`
-- asks for it too, as when the window opens.
local function showPage(name, full)
    -- Preview is for the HUD page, so it ends when we leave it.
    if name ~= "hud" and NS.HUD and NS.HUD.previewing() then NS.HUD.preview(false) end
    current = name
    NS.db.window.page = name
    for key, p in pairs(pages) do
        p.tab:light(key == name)
        p.frame:SetShown(key == name)
    end
    if full then C.refresh() else C.refreshPage() end
end

-- The window, laid out like BayovCore's config pages, with the raid pane
-- (RaidPane.lua) down its left side:
--
--   raid   │ [logo] Buff Coordinator [chip]  18 players · 21 of 23 given     ×
--   pane   │ ──────────────────────────────────────────────────────────────
--          │  Assignments  You  Needs  Overrides  Settings        [buttons]
--          │ ──────────────────────────────────────────────────────────────
--          │  the page                                                   ⋰
--
-- The buttons belong to the page on show. We drag the window by anything
-- that isn't a control, and size it by the grip in the corner.
local main

-- Keeps where the window is, by its middle, as BayovCore does, and its size
-- once the grip has sized it (`sized`). Until then it opens at the size
-- that fits the whole raid.
local function saveGeometry(sized)
    local x, y = win:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (x and ux) then return end
    local s = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local w = NS.db.window
    w.x, w.y = floor(x * s - ux + 0.5), floor(y * s - uy + 0.5)
    w.w, w.h = floor(win:GetWidth() + 0.5), floor(win:GetHeight() + 0.5)
    if sized == true then w.sized = true end
end

-- The smallest the window may be (the pane, then the narrowest pages), and
-- the largest, the screen. A window taller than the screen would put the
-- grip off it, and then there's no way to make it smaller again.
local function bounds()
    local s = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local maxW = sw and sw > 0 and floor(sw / s) or 4000
    local maxH = sh and sh > 0 and floor(sh / s) or 4000
    local minW = min(NS.RaidPane.width() + MIN_W, maxW)
    if win.SetResizeBounds then
        win:SetResizeBounds(minW, min(MIN_H, maxH), maxW, maxH)
    else
        if win.SetMinResize then win:SetMinResize(minW, min(MIN_H, maxH)) end
        if win.SetMaxResize then win:SetMaxResize(maxW, maxH) end
    end
    return minW, maxW, maxH
end

-- The pages' scroll children are as wide as the pages, so the pages lay out
-- for the width the window has.
local function fitPages()
    local w = (main and main:GetWidth() or 0)
    if w <= 0 then w = (win:GetWidth() or 0) - NS.RaidPane.width() end
    for _, p in pairs(pages or {}) do p.scroll.child:SetWidth(max(100, w - PAD - 12)) end
end

-- Moving the window by a drag, from anything that isn't a control, the raid
-- pane included.
--
-- We move it ourselves rather than with StartMoving. The window sets its own
-- points while it's open (the pane folding, the height following the raid),
-- and one of those during a StartMoving drag made the window jump away from
-- the mouse. Ours puts the top left corner where the mouse says each frame,
-- so a SetPoint in between is undone at once.
--
-- A drag starts a few pixels after the button went down. We count from
-- where it went down (GLOBAL_MOUSE_DOWN), so the spot we grabbed stays
-- under the mouse from the first frame.
local downX, downY, downAt
local mover = CreateFrame("Frame")
if pcall(mover.RegisterEvent, mover, "GLOBAL_MOUSE_DOWN") then
    mover:SetScript("OnEvent", function(_, _, button)
        if button == "LeftButton" then
            downX, downY = GetCursorPosition()
            downAt = GetTime()
        end
    end)
end

function C.startMoving()
    if not win then return end
    local l, t = win:GetLeft(), win:GetTop()
    if not (l and t) then return end
    local x, y = GetCursorPosition()
    if downAt and GetTime() - downAt < 1 then x, y = downX, downY end
    local s = win:GetEffectiveScale()
    mover:SetScript("OnUpdate", function()
        -- A drag that ended without OnDragStop, like the window hiding
        -- under it, stops here.
        if not win:IsShown() or (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then
            return C.stopMoving()
        end
        local cx, cy = GetCursorPosition()
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l + (cx - x) / s, t + (cy - y) / s)
    end)
end

function C.stopMoving()
    if not win then return end
    mover:SetScript("OnUpdate", nil)
    saveGeometry()
end

local function build()
    win = CreateFrame("Frame", "BuffCoordinatorConfig", UIParent)
    win:SetSize(NS.RaidPane.WIDTH + WIDTH, HEIGHT)
    -- On the game's own windows' layer, so the bags or the character window
    -- go in front of it when they're clicked or opened last (T.window).
    T.window(win)
    win:SetMovable(true)
    if win.SetResizable then win:SetResizable(true) end
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    T.panel(win, -6)
    T.windowEdge(win)
    local special = _G.UISpecialFrames
    local listed = false
    for _, n in ipairs(special) do
        if n == "BuffCoordinatorConfig" then listed = true end
    end
    if not listed then table.insert(special, "BuffCoordinatorConfig") end
    win:SetScript("OnDragStart", C.startMoving)
    win:SetScript("OnDragStop", C.stopMoving)

    -- The raid pane, and the rest to its right.
    local left = NS.RaidPane.attach(win)
    main = CreateFrame("Frame", nil, win)
    main:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    main:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)

    -- The header, on a darker band like BayovCORE's sidebar: a third of
    -- black over the panel, and a faint line where it ends.
    local band = T.fill(main, { 0, 0, 0 }, 0.35, "BACKGROUND", 2)
    band:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, 0)
    band:SetHeight(HEAD_H)
    -- Our logo and name, as BayovCORE's sidebar shows its own. The logo is a
    -- shape on a clear background, so it shows whole, with no edge.
    local logo = main:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO, LOGO)
    logo:SetPoint("LEFT", main, "TOPLEFT", PAD - 2, -HEAD_H / 2)
    logo:SetTexture(NS.LOGO)
    win.title = T.text(main, T.SIZE.title, false, 1)
    win.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    win.title:SetText(NS.BRAND)
    win.chip = T.chip(main)
    win.chip:SetPoint("LEFT", win.title, "RIGHT", 8, 0)
    win.chip.maxW = 200
    win.chip:Hide()
    local close = T.close(main, function() win:Hide() end)
    close:SetPoint("RIGHT", main, "TOPRIGHT", -8, -HEAD_H / 2)
    -- What the words and colours mean, while the mouse is on the "?".
    win.help = T.help(main)
    win.help:SetPoint("RIGHT", close, "LEFT", -6, 0)
    win.help:HookScript("OnEnter", function(self) C.legend(self, true) end)
    win.help:HookScript("OnLeave", function(self) C.legend(self, false) end)
    win.summary = T.text(main, T.SIZE.body, false, T.A_DIM)
    win.summary:SetPoint("RIGHT", win.help, "LEFT", -10, 0)
    win.summary:SetWordWrap(false)
    -- Where a page puts its own buttons, right to left, left of the strip's.
    win.pins = CreateFrame("Frame", nil, main)
    win.pins:SetSize(1, 20)

    local line = T.fill(main, { 1, 1, 1 }, 0.06, "BORDER")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -HEAD_H)
    line:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, -HEAD_H)

    -- The tabs, and the page's own buttons at the strip's right.
    win.strip = CreateFrame("Frame", nil, main)
    win.strip:SetHeight(TAB_H)
    win.strip:SetPoint("TOPLEFT", main, "TOPLEFT", PAD - 6, -(HEAD_H + 2))
    win.strip:SetPoint("TOPRIGHT", main, "TOPRIGHT", -PAD, -(HEAD_H + 2))
    win.pins:SetPoint("RIGHT", win.strip, "RIGHT", 0, 0)
    local under = T.fill(main, { 1, 1, 1 }, 0.07, "ARTWORK")
    under:SetHeight(1)
    under:SetPoint("TOPLEFT", main, "TOPLEFT", PAD, -(HEAD_H + 2 + TAB_H))
    under:SetPoint("TOPRIGHT", main, "TOPRIGHT", -PAD, -(HEAD_H + 2 + TAB_H))

    -- The tabs are laid out on each refresh, since Needs and Overrides may
    -- have a dot after their names.
    pages = {}
    for _, def in ipairs(PAGES) do
        local key = def.key
        local tab = T.tab(win.strip, def.title, TAB_H)
        tab.pageKey = key
        tab:SetScript("OnClick", function() showPage(key) end)
        local frame = CreateFrame("Frame", nil, main)
        frame:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -(HEAD_H + 2 + TAB_H + 1))
        frame:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
        local sf = T.scroll(frame)
        sf:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -GAP)
        sf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, PAD + 8)
        sf.child:SetWidth(WIDTH - PAD - 12)
        T.scrollShadow(sf)
        pages[key] = { tab = tab, frame = frame, scroll = sf, body = sf.child, pins = {}, strip = {} }
    end

    -- A player dragged from the raid pane onto the Overrides tab starts a
    -- new override there, as on the page.
    NS.RaidPane.addDropTarget(pages.overrides.tab, function(m)
        if not canChange() then return end
        showPage("overrides")
        NS.Overrides.add(m.name)
    end)

    -- The grip in the corner. The pages lay out again for the new width as
    -- it changes, a moment after the last change.
    T.grip(win, function() saveGeometry(true) end, function()
        -- Back to the size it first opens at, from the same top left corner.
        local l, t = win:GetLeft(), win:GetTop()
        win:SetSize(NS.RaidPane.width() + WIDTH, max(HEIGHT, NS.RaidPane.HEIGHT))
        if l and t then
            win:ClearAllPoints()
            win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
        end
        NS.db.window.sized = nil
        saveGeometry()
    end)
    win:SetScript("OnSizeChanged", function()
        fitPages()
        NS.soon("configResize", 0.05, C.refresh)
    end)
    win:SetScript("OnShow", function()
        -- The window counts every assignment's buff, and the HUD only reads
        -- ours.
        Tr.readAll()
        C.refresh()
    end)
    win:SetScript("OnHide", function()
        T.hush(function()
            if NS.HUD.previewing() then NS.HUD.preview(false) end
            if C.legendFrame then C.legendFrame:Hide() end
            if NS.Constraints and NS.Constraints.hide then NS.Constraints.hide() end
        end)
    end)
    -- It opens and closes with the game's window sounds, and starts hidden.
    T.windowSounds(win)
end

-- The pane folded or opened (RaidPane.lua): the rest of the window now sits
-- right of `left`, and the window is `delta` wider. It grows or shrinks at
-- its left edge, so the pages stay where they are on the screen.
function C.repane(left, delta)
    main:ClearAllPoints()
    main:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    main:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
    local right, top = win:GetRight(), win:GetTop()
    bounds()
    win:SetWidth(max(NS.RaidPane.width() + MIN_W, (win:GetWidth() or 0) + delta))
    if right and top and right > 0 then
        win:ClearAllPoints()
        win:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    end
    saveGeometry()
    fitPages()
    C.refresh()
end

-- The raid pane shows another number of parties (RaidPane.lua's P.fit). A
-- window the grip hasn't sized opens as tall as they need, so it follows
-- them, and keeps its top where it is.
function C.fitHeight()
    if not win or NS.db.window.sized then return end
    local _, _, maxH = bounds()
    local h = max(min(MIN_H, maxH), min(max(HEIGHT, NS.RaidPane.HEIGHT), maxH))
    if math.abs((win:GetHeight() or 0) - h) < 1 then return end
    local l, t = win:GetLeft(), win:GetTop()
    win:SetHeight(h)
    if l and t then
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end
    saveGeometry()
end

-- Shows the buttons of the page on show: `list` in the header, `stripList`
-- at the right of the tab strip. Each is { label, onClick, tip = fn,
-- main = true for the one accent button }. They're made once per page and
-- label. The header and strip are the window's, not the page's, so hiding a
-- page doesn't hide its buttons. We hide them all here instead.
local function headButtons(page, list, stripList)
    -- Every page's, since they all sit in the same header and strip.
    for _, p in pairs(pages) do
        for _, holder in ipairs({ p.pins, p.strip }) do
            for _, b in pairs(holder) do b:Hide() end
        end
    end
    local function lay(holder, specs, parent, gap)
        local prev
        for i = #specs, 1, -1 do
            local s = specs[i]
            local b = holder[s[1]]
            if not b then
                b = T.button(parent, s[1], nil, 20)
                holder[s[1]] = b
            end
            b:setAccent(s.main)
            b:SetScript("OnClick", s[2])
            b.tip = s.tip
            b:ClearAllPoints()
            if prev then
                b:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
            else
                b:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
            end
            b:Show()
            prev = b
        end
        return prev
    end
    local first = lay(page.strip, stripList or {}, win.strip, 6)
    win.pins:ClearAllPoints()
    win.pins:SetPoint("RIGHT", first or win.strip, first and "LEFT" or "RIGHT", first and -6 or 0, 0)
    lay(page.pins, list or {}, win.pins, 6)
end
C.headButtons = headButtons

local function place()
    win:SetScale(O.get("windowScale"))
    local _, maxW, maxH = bounds()
    local g = NS.db.window
    local minW = NS.RaidPane.width() + MIN_W
    local w = g.sized and tonumber(g.w) or (NS.RaidPane.width() + WIDTH)
    local h = g.sized and tonumber(g.h) or max(HEIGHT, NS.RaidPane.HEIGHT)
    win:SetSize(max(minW, min(w, maxW)), max(min(MIN_H, maxH), min(h, maxH)))
    -- We keep the spot in UIParent's units, but a SetPoint offset is in the
    -- window's own units. At Window scale 1.5 the same offset lands 1.5
    -- times farther out, so we divide by the scale or the window drifts
    -- outwards each time it opens.
    local s = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if not (s and s > 0) then s = 1 end
    win:ClearAllPoints()
    win:SetPoint("CENTER", UIParent, "CENTER", (g.x or 0) / s, (g.y or 40) / s)
    fitPages()
end

function C.toggle()
    if not win then build() end
    if win:IsShown() then
        win:Hide()
        return
    end
    place()
    win:Show()
    win:Raise()
    showPage(PAGE[NS.db.window.page] and NS.db.window.page or "duties", true)
end

-- Opening it brings it in front of the other windows, also when it's open
-- already behind them.
function C.open(page)
    if not win then build() end
    place()
    win:Show()
    win:Raise()
    showPage(page or current or "duties", true)
end

function C.shown() return win ~= nil and win:IsShown() end

-- The page on show: "duties", "you", "needs", "resist", "overrides", "hud"
-- or "settings".
function C.current() return current end
-- The key flashing on the page that shows, for the tests.
function C.flashing() return pages and current and pages[current] and pages[current].flashKey end

-- For other addons, like BayovCore's Quick Menu: opens the window on `page`
-- ("duties", "you", "needs", "overrides", "hud" or "settings"), or closes it
-- when it shows that page already.
-- A bare /bbc opens on the page we had last, and /bbc assignments always
-- opens, so a button that should open the assignments and close again on a
-- second click needs this.
function NS.API.toggle(page)
    if C.shown() and current == (page or "duties") then
        win:Hide()
        return
    end
    C.open(page)
end

-- =============================================================
-- Pools
-- =============================================================
-- Each page draws its rows again on every refresh, from frames it keeps.
-- `pool(page, kind, make)` hands out the next unused one of `kind`, and
-- `release(page)` hides every one before a page draws again.
local function pool(page, kind, make)
    page.pools = page.pools or {}
    local p = page.pools[kind] or { used = 0 }
    page.pools[kind] = p
    p.used = p.used + 1
    local f = p[p.used]
    if not f then
        f = make(page.body)
        p[p.used] = f
    end
    f:Show()
    return f
end

local function release(page)
    for _, p in pairs(page.pools or {}) do
        for i = 1, #p do p[i]:Hide() end
        p.used = 0
    end
end
C.pool, C.release = pool, release

-- A section's heading, with room before it unless it's the page's first.
-- Across the page, or `w` wide from `x` for a column.
local function heading(page, label, y, x, w)
    if y > 0 then y = y + 8 end
    local h = pool(page, "heading", function(parent) return T.heading(parent, "") end)
    h.label:SetText(label:upper())
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", page.body, "TOPLEFT", x or 0, -y)
    if w then
        h:SetWidth(w)
    else
        h:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -y)
    end
    return y + 24 + 6
end
C.heading = heading

-- `right` keeps the note clear of buttons on the right, and `left` starts it
-- further in.
local function note(page, text, y, alpha, right, left)
    local f = pool(page, "note", function(parent)
        local n = CreateFrame("Frame", nil, parent)
        n.text = T.text(n, T.SIZE.body, false, T.A_DIM)
        n.text:SetPoint("TOPLEFT", n, "TOPLEFT", 0, 0)
        n.text:SetPoint("TOPRIGHT", n, "TOPRIGHT", 0, 0)
        n.text:SetWordWrap(true)
        return n
    end)
    f.text:SetText(text)
    f.text:SetTextColor(1, 1, 1, alpha or T.A_DIM)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", page.body, "TOPLEFT", left or 0, -y)
    f:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8 - (right or 0), -y)
    local h = max(13, f.text:GetStringHeight())
    f:SetHeight(h)
    return y + h + 4
end
C.note = note

-- A small button at the right of a heading drawn at `y`, like "Edit
-- blessings".
-- `right` keeps it that far in from the page's right, for a column's heading.
local function headingButton(page, y, label, onClick, tip, right)
    if y > 0 then y = y + 8 end
    local b = pool(page, "headingButton", function(parent) return T.button(parent, "", nil, 18) end)
    b:SetText(label)
    b:setAccent(false)
    b:SetScript("OnClick", onClick)
    b.tip = tip
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8 - (right or 0), -(y + 2))
    return b
end

-- The width a page lays its rows out in.
local function pageWidth(page)
    return max(100, (page.body:GetWidth() or 0) - 8)
end

-- =============================================================
-- Showing an assignment
-- =============================================================
-- Where each assignment is on its page, so the Missing list can take us
-- there: { [key] = { frame, y } }, the first frame drawn for the key. A key
-- is a job's ID on Assignments, or one setting's own place: "order" for
-- Blessings on Needs and "onoff:<job>" for the job's row there,
-- "assign" for the first paladin's override card and "landed" for a new
-- override's card on Overrides, and "totem:<shaman>:<element>" for a
-- party's totem.
--
-- The frame we go to flashes: its `flash` texture pulses twice in the
-- accent, quickly, and goes. It's found again each frame, since the page
-- may draw again meanwhile and hand the key another frame.
local FLASH = 0.8

local flasher = CreateFrame("Frame")

local function mark(page, key, frame, y)
    page.anchors = page.anchors or {}
    if not page.anchors[key] then page.anchors[key] = { frame = frame, y = y } end
    if frame.flash and page.flashKey ~= key then frame.flash:Hide() end
end

local function makeFlash(f)
    f.flash = T.fill(f, T.ACCENT, 0.35, "OVERLAY")
    f.flash:SetAllPoints(f)
    f.flash:Hide()
end

local function flash(page, key)
    page.flashKey, page.flashAt = key, GetTime()
    local at = page.anchors and page.anchors[key]
    if at and at.frame.flash then
        at.frame.flash:SetAlpha(0)
        at.frame.flash:Show()
    end
    flasher:SetScript("OnUpdate", function()
        local at = page.anchors and page.anchors[page.flashKey]
        local f = at and at.frame.flash
        local t = (GetTime() - page.flashAt) / FLASH
        if t >= 1 or not f then
            if f then f:Hide() end
            page.flashKey = nil
            flasher:SetScript("OnUpdate", nil)
            return
        end
        -- Two pulses, the second fainter.
        f:SetAlpha(math.abs(math.sin(t * math.pi * 2)) * (1 - t * 0.5))
        f:Show()
    end)
end

-- The key on the page for override `item` (Du.constraints), or nil when its
-- assignment's card is the place.
local function itemKey(item)
    if not item then return nil end
    if item.kind == "order" then return "order" end
    if item.kind == "assign" or item.kind == "bless" then return "assign" end
    if item.kind == "totem" then return format("totem:%s:%s", tostring(item.a), tostring(item.b)) end
end

-- Shows job `jobId` on Assignments, or where override `item` is set when
-- given, scrolls to it and flashes it.
function C.focus(jobId, item)
    if not jobId or not D.JOB[jobId] then return end
    -- One turned off is nowhere on Assignments. We go to where it's turned
    -- back on.
    local key = itemKey(item) or (not Du.enabled(D.JOB[jobId]) and "onoff:" .. jobId or nil)
    local name = "duties"
    if key == "order" then
        name = "needs"
        -- The order's class shows, so its column is there.
        local a = tostring(item.a or "")
        local m = a:match("^name:(.+)$") and R.byName(a:sub(6))
        local class = m and m.class or a:match("^(%u+)")
        if class and D.SPECS[class] then C.showClass(class) end
    elseif key and key:find("^onoff:") then
        name = "needs"
    elseif key == "assign" then
        name = "overrides"
    end
    local page = pages and pages.duties
    local fold = name == "duties" and page and page.idle and page.idle[jobId]
    if fold and not NS.db.window[fold] then NS.db.window[fold] = true end
    if not C.shown() then
        C.open(name)
    elseif current ~= name then
        showPage(name)
    else
        C.refreshPage()
    end
    page = pages[name]
    -- The fold may only be known now that Assignments has drawn.
    fold = name == "duties" and page.idle and page.idle[jobId]
    if fold and not NS.db.window[fold] then
        NS.db.window[fold] = true
        C.refreshPage()
    end
    local at = page.anchors and (key and page.anchors[key] or page.anchors[jobId])
    if not at then return end
    page.scroll:setScroll(max(0, at.y - 40))
    flash(page, key and page.anchors[key] and key or jobId)
end

NS.listen("focus", C.focus)

-- =============================================================
-- Going where an assignment is set
-- =============================================================
-- A click on an icon on Assignments takes us to where what it shows is
-- set, and flashes it there. A fight's resistance is set on Resistances,
-- an override on its card in Overrides, and the rest on Needs, on the
-- buff's row.
--
-- A place is { name, keys, class }: a page, the keys on it to try in turn,
-- and for Needs the class whose column it needs. A page only knows its keys
-- once it has drawn, so when an override's card isn't there we go on to the
-- next place. Needs is always last.

-- The places for an icon of job `job`: the assignment `a` it shows, or its
-- buff `b`, and for a blessing the class `class` it goes to.
function C.whereSet(job, a, b, class)
    local places = {}
    local function add(name, keys, cls) places[#places + 1] = { name = name, keys = keys, class = cls } end
    if a and a.school then
        add("resist", { format("resist:%s:%s", tostring(Du.fight()), a.school), "resistances" })
        return places
    end
    if job.kind == "blessing" then
        local list = a and Du.assignsFor(a.giver) or Du.assigns()
        if #list > 0 then
            local keys = { "assign" }
            if a then table.insert(keys, 1, "pal:" .. (list[1].holder or a.giver.name)) end
            add("overrides", keys)
        end
        add("needs", { "order" }, class)
        return places
    end
    if job.kind == "totem" then
        local holder = a and a.buff.element and select(2, Du.totemFor(a.giver, a.buff.element))
        if holder then add("overrides", { "ov:" .. Du.itemKey("totem", holder, a.buff.element) }) end
    elseif Du.custom(job.id) then
        local keys = { "job:" .. job.id }
        if a then table.insert(keys, 1, format("job:%s:%s", job.id, a.giver.name)) end
        add("overrides", keys)
    end
    b = b or (a and a.buff)
    local keys = { "onoff:" .. job.id }
    if b then table.insert(keys, 1, "buff:" .. b.id) end
    add("needs", keys)
    return places
end

-- Goes to the first of `places` (C.whereSet) whose page has one of its
-- keys, scrolls to it and flashes it.
function C.goTo(places)
    for _, p in ipairs(places) do
        if p.class and D.SPECS[p.class] then C.showClass(p.class) end
        if not C.shown() then
            C.open(p.name)
        elseif current ~= p.name then
            showPage(p.name)
        else
            C.refreshPage()
        end
        local page = pages[p.name]
        for _, key in ipairs(p.keys) do
            local at = page.anchors and page.anchors[key]
            if at then
                page.scroll:setScroll(max(0, at.y - 40))
                flash(page, key)
                return
            end
        end
    end
end

-- The hint for a click that goes to `places`: "set it in Overrides".
function C.goHint(places)
    return { "Click", "set it in " .. PAGE[places[1].name].title }
end

-- =============================================================
-- The legend
-- =============================================================
-- What the words mean, from NS.GLOSSARY, and the colours, from T.LEGEND, in
-- a small panel under the "?" beside the close cross, while the mouse is on
-- it. A colour's swatch is a dot in it.
local LEGEND_W = 320
local DOT = "Interface\\AddOns\\BuffCoordinator\\Media\\Dot"

local function buildLegend()
    local f = CreateFrame("Frame", "BuffCoordinatorLegend", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    T.popup(f)
    table.insert(_G.UISpecialFrames, "BuffCoordinatorLegend")
    f.title = T.text(f, T.SIZE.label, true, 1)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    f.title:SetText("What the words and colours mean")
    f:SetWidth(LEGEND_W)
    f.rows = {}
    local entries = {}
    for _, g in ipairs(NS.GLOSSARY) do
        if not g.ring then entries[#entries + 1] = g end
    end
    for _, g in ipairs(T.LEGEND) do entries[#entries + 1] = g end
    local y = 34
    for i, g in ipairs(entries) do
        -- A little more room before the colours.
        if g.color and entries[i - 1] and not entries[i - 1].color then y = y + 6 end
        local r = CreateFrame("Frame", nil, f)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -y)
        r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -y)
        r.word = T.text(r, T.SIZE.body, true, 1)
        r.word:SetPoint("TOPLEFT", r, "TOPLEFT", g.color and 14 or 0, 0)
        r.word:SetText(g.word)
        if g.color then
            r.swatch = r:CreateTexture(nil, "ARTWORK")
            r.swatch:SetTexture(DOT)
            r.swatch:SetSize(9, 9)
            r.swatch:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
            r.colorKey = g.color
        end
        r.text = T.text(r, T.SIZE.body, false, T.A_TEXT)
        r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 100, 0)
        r.text:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
        r.text:SetWordWrap(true)
        -- Its width now, before it's laid out, so a long one measures as
        -- the lines it wraps to rather than as one.
        r.text:SetWidth(LEGEND_W - 20 - 100)
        r.text:SetText(g.text)
        local h = max(14, r.text:GetStringHeight() or 14)
        r:SetHeight(h)
        f.rows[i] = r
        y = y + h + 8
    end
    f:SetHeight(y + 6)
    return f
end

-- Opens or closes the legend beside `anchor`.
-- Shows the legend under `anchor`, or hides it when `show` is false.
function C.legend(anchor, show)
    local f = C.legendFrame or buildLegend()
    C.legendFrame = f
    if show == false then
        f:Hide()
        return
    end
    -- Blue is the accent, which may have changed since.
    for _, r in ipairs(f.rows) do
        local c = r.colorKey and T.COLOR[r.colorKey]
        if c then r.swatch:SetVertexColor(c[1], c[2], c[3], 1) end
    end
    f:ClearAllPoints()
    if anchor and anchor.GetEffectiveScale then
        local s, u = anchor:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if s and u and u > 0 then f:SetScale(s / u) end
        f:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    f:Show()
end

-- =============================================================
-- The status line
-- =============================================================
-- A faint box across the top of the page: C.status's sentences on the left,
-- buttons on the right. The sentences wrap when the page is narrow, and the
-- box grows with them. The text hangs from its top corners, level with the
-- buttons' tops. A middle anchor like RIGHT would pin its middle to the
-- buttons' middle and squeeze it to one line.
local function makeStatus(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = T.fill(f, { 1, 1, 1 }, 0.035)
    f.bg:SetAllPoints(f)
    T.border(f, { 1, 1, 1 }, 0.07)
    f.text = T.text(f, T.SIZE.body, false, T.A_TEXT)
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -9)
    f.text:SetWordWrap(true)
    f.buttons = {}
    for i = 1, 5 do f.buttons[i] = T.button(f, "", nil, 20) end
    return f
end

local function statusLine(page, y)
    local f = pool(page, "status", makeStatus)
    local list = {}
    if stuckDraft() then
        list[#list + 1] = { "Discard", function() NS.Suggest.discard() end,
                            tip = "Throw your draft away. It can't be sent while suggestions are off." }
    end
    local prev
    for i = #f.buttons, 1, -1 do
        local b, spec = f.buttons[i], list[i]
        b:SetShown(spec ~= nil)
        if spec then
            b:SetText(spec[1])
            b:setAccent(spec.main)
            b:SetScript("OnClick", spec[2])
            if spec.off then b:Disable() else b:Enable() end
            b.tip = function(self) T.tip(self, spec[1], spec.tips or { spec.tip }) end
            b:ClearAllPoints()
            if prev then
                b:SetPoint("RIGHT", prev, "LEFT", -6, 0)
            else
                b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
            end
            prev = b
        end
    end
    f.statusText = C.status()
    f.text:SetText(f.statusText)
    f.text:ClearAllPoints()
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -9)
    if prev then
        f.text:SetPoint("TOPRIGHT", prev, "TOPLEFT", -10, -4)
    else
        f.text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -9)
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
    f:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -y)
    local h = max(30, (f.text:GetStringHeight() or 14) + 18)
    f:SetHeight(h)
    return y + h + 8
end

-- =============================================================
-- You
-- =============================================================
-- The You page: a card of who the addon takes us for (our spec's icon, our
-- name, spec, level, party, role and rank, and where the spec came from)
-- with how many buffs we give, get and miss, then a part with icons each,
-- in a 2 by 2 grid, for:
--   Give        our own assignments, with the backups we are after them,
--               dimmed
--   Get         what reaches us and who gives it, the debuffs on the target
--               we gain from included
--   Could get   what we want and someone here could give us, but this setup
--               doesn't, and why
--   Can't get   what we want and nobody here can give
-- Each icon's tooltip says it in the words the whispers use, or who gives
-- it, or why we go without (Du.player). A click goes to its assignment.
-- The buff an assignment of ours shows: the blessing we give the most
-- players, a backup's first, or its buff.
local function buffOf(a)
    if a.bless then
        local n, best = {}, nil
        for _, id in pairs(a.bless) do
            n[id] = (n[id] or 0) + 1
            if not best or n[id] > n[best] or (n[id] == n[best] and id < best) then best = id end
        end
        return D.BY_ID[best or "kings"]
    end
    if a.spare and a.spare[1] then return a.spare[1].b end
    return a.buff
end

local function iconOf(a)
    local b = buffOf(a)
    return b and Tr.icon(b) or nil
end

-- A backup of ours in words: "Backup for Fortitude", or "Backup blessings
-- for warriors and mages".
local function backupText(a)
    if a.classes then
        local list = {}
        for class in pairs(a.classes) do list[#list + 1] = classWord(class) end
        table.sort(list)
        return "Backup blessings for " .. andList(list)
    end
    return "Backup for " .. (a.buff and Tr.title(a.buff) or Du.title(a.job))
end

-- Our own assignments on the board the window shows, so a draft that moves
-- us shows here as it does on the cards. Without a draft it's Du.mine. With
-- one we gather them from the draft's board as Duties.lua does for its own:
-- our assignments in job order, then the backups we are.
local function shownMine()
    if not NS.draft then return Du.mine() or {} end
    local t = {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.shown(job.id)
        for _, a in ipairs(plan and plan.list or {}) do
            if a.giver.me then t[#t + 1] = a end
        end
    end
    if O.get("backups") then
        for _, job in ipairs(D.JOBS) do
            local plan = Du.shown(job.id)
            for _, a in ipairs(plan and plan.active and plan.reserve or {}) do
                if a.giver.me then t[#t + 1] = a end
            end
        end
    end
    return t
end

-- The rows below are icons with no names. Raiders know the icons,
-- and each one's tooltip says what it is.
local ICON, ICON_GAP = 30, 4

local function makeIconButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON, ICON)
    b.icon = T.icon(b, nil, ICON)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b:SetScript("OnEnter", function(self) if self.tipFn then self.tipFn(self) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) if self.click then self.click() end end)
    return b
end

-- Lays out `list` as icons from `x`, wrapping at `w`, and returns the y under
-- them. Each item is { tex, tip = function(self), dim, click, key, what },
-- and `key` goes on the button as its `kind` field. A `dim` icon is at
-- `dim` alpha.
local function iconRow(page, kind, x, w, y, list)
    local perRow = max(1, floor((w + ICON_GAP) / (ICON + ICON_GAP)))
    for i, it in ipairs(list) do
        local b = pool(page, kind, makeIconButton)
        local col, row = (i - 1) % perRow, floor((i - 1) / perRow)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", page.body, "TOPLEFT", x + col * (ICON + ICON_GAP), -(y + row * (ICON + ICON_GAP)))
        b.icon:SetTexture(it.tex)
        b.icon:SetAlpha(it.dim or 1)
        b.tipFn, b.click, b.what = it.tip, it.click, it.what
        b[kind] = it.key
    end
    if #list == 0 then return y end
    return y + ceil(#list / perRow) * (ICON + ICON_GAP) + 2
end

-- Where the addon learned our spec, as the end of "Spec from ...".
local SPEC_FROM = { set = "an override", talents = "your talents", told = "your addon", fojji = "FojjiCore",
                    role = "your raid role" }

-- Our spec and class, with the level: "Discipline Priest · Level 60".
local function youSpec(m)
    local t = (m.spec and specName(m.class, m.spec) .. " " or "") .. NS.className(m.class)
    if m.level and m.level > 0 then t = t .. format("  ·  Level %d", m.level) end
    return t
end

-- Where we are and what we are in the group: "Group 1 · Healer · Assistant".
local function youPlace(m)
    local t = {}
    if R.raid() then t[1] = format("Group %d", m.group) end
    if m.role then t[#t + 1] = upperFirst(m.role) end
    local rank = NS.rankWord(m)
    if rank then t[#t + 1] = upperFirst(rank) end
    return table.concat(t, "  ·  ")
end

-- Where the addon learned our spec. In orange when an override set it
-- unlike our talents.
local function youSource(m)
    if not m.spec then return hex(T.COLOR.low) .. "Spec unknown.|r" end
    if m.specFrom == "set" and m.learned and m.learned ~= m.spec then
        return hex(T.COLOR.low) .. format("Spec set by an override. Your talents say %s.|r", specName(m.class, m.learned))
    end
    return format("Spec from %s.", SPEC_FROM[m.specFrom] or "?")
end

-- The card at the top of the page: our spec's icon, our name in our
-- class's colour, then our spec and level, where we are in the group, and
-- where the spec came from.
--
-- At its right, our own blessing order: a title, the blessings left to
-- right, most wanted first (Priority.lua's Pr.ownRow), and Back to auto
-- when it's set. Anyone may change their own, even when only the leader
-- and the assistants change everything else, so this works for everyone.
-- Who set it is in the icons' tooltips.
local CARD_PAD, YOU_ICON, YOU_H = 12, 48, 84
-- The blessing part's width and its icon size. Its title, the line under
-- the title and the icons fill the card's height inside its padding.
local BLESS_W, BLESS_ICON = 200, 28

-- The art behind the card: Retail's talent art for our spec when the game
-- has it, else our class's, which Forever's own talent window shows. Retail
-- calls two of our specs by other names. nil when the game has neither.
local ART_SPEC = { combat = "outlaw", feralcombat = "feral" }
-- How dark the veil over the art is, so the words on it read.
local ART_VEIL = 0.6

local function artFor(class, tree)
    local info = _G.C_Texture and C_Texture.GetAtlasInfo
    if not info or not class then return nil end
    local cls = class:lower()
    local spec = tree and D.SPECS[class] and D.SPECS[class][tree]
    local names = {}
    if spec then names[1] = format("talents-background-%s-%s", cls, ART_SPEC[spec.key] or spec.key) end
    names[#names + 1] = "talent-background-" .. cls
    for _, name in ipairs(names) do
        local a = info(name)
        if a and a.file then return a end
    end
    return nil
end

-- Shows the card's art across it: the art's full width, and as much of its
-- middle as fits the card's shape, since the card is far wider than tall.
local function fitArt(f)
    local a = f.artInfo
    local w, h = f:GetWidth(), f:GetHeight()
    if not a or not w or w <= 0 or not h or h <= 0 then
        f.art:Hide()
        f.veil:Hide()
        return
    end
    local t, b = a.topTexCoord, a.bottomTexCoord
    local part = min(1, (a.width or 1) / max(1, a.height or 1) * h / w)
    local mid, half = (t + b) / 2, (b - t) * part / 2
    f.art:SetTexture(a.file)
    f.art:SetTexCoord(a.leftTexCoord, a.rightTexCoord, mid - half, mid + half)
    f.art:Show()
    f.veil:Show()
end

local function makeYouBox(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(YOU_H)
    f.youCard = true
    f.bg = T.fill(f, { 1, 1, 1 }, 0.04)
    f.bg:SetAllPoints(f)
    f.art = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.art:SetAllPoints(f)
    f.art:Hide()
    f.veil = T.fill(f, { 0, 0, 0 }, ART_VEIL, "BACKGROUND", 2)
    f.veil:SetAllPoints(f)
    f.veil:Hide()
    f:SetScript("OnSizeChanged", fitArt)
    T.border(f, { 1, 1, 1 }, 0.09)
    f.icon = T.icon(f, nil, YOU_ICON)
    f.icon:SetPoint("LEFT", f, "LEFT", CARD_PAD, 0)

    local bl = CreateFrame("Frame", nil, f)
    bl:SetSize(BLESS_W, YOU_H - 2 * CARD_PAD)
    bl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CARD_PAD, -CARD_PAD)
    f.bless = bl
    f.blessTitle = T.text(bl, T.SIZE.caption, true, T.A_DIM)
    f.blessTitle:SetPoint("TOPLEFT", bl, "TOPLEFT", 0, 0)
    f.blessTitle:SetText("YOUR DESIRED BLESSING PRIORITY")
    f.blessSub = T.text(bl, T.SIZE.body, false, T.A_DIM)
    f.blessSub:SetPoint("TOPLEFT", f.blessTitle, "BOTTOMLEFT", 0, -3)
    f.blessSub:SetText("Drag to change")
    f.blessRow = NS.Priority.ownRow(bl, BLESS_ICON)
    f.blessRow:ClearAllPoints()
    f.blessRow:SetPoint("BOTTOMLEFT", bl, "BOTTOMLEFT", 0, 0)
    f.back = T.button(bl, "Back to auto", nil, 20)
    f.back:setAccent(false)
    f.back:SetScript("OnClick", function() Du.setOwnBlessOrder(nil) end)
    f.back.tip = function(self) T.tip(self, "Back to auto", { "Go back to what your spec wants." }) end
    f.back:SetPoint("LEFT", f.blessRow, "RIGHT", 10, 0)

    local x = CARD_PAD + YOU_ICON + 12
    f.name = T.text(f, T.SIZE.title, true, 1)
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", x, -CARD_PAD + 1)
    f.spec = T.text(f, T.SIZE.label, false, T.A_TEXT)
    f.spec:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
    f.place = T.text(f, T.SIZE.body, false, T.A_DIM)
    f.place:SetPoint("TOPLEFT", f.spec, "BOTTOMLEFT", 0, -3)
    f.source = T.text(f, T.SIZE.body, false, T.A_DIM)
    f.source:SetPoint("TOPLEFT", f.place, "BOTTOMLEFT", 0, -3)
    for _, k in ipairs({ "name", "spec", "place", "source" }) do
        f[k]:SetPoint("RIGHT", bl, "LEFT", -10, 0)
        f[k]:SetJustifyH("LEFT")
        f[k]:SetWordWrap(false)
    end
    return f
end

-- One part of the page under the card, `w` wide from `x`: its heading, a
-- line on what it is, then its icons, or `empty` when there are none.
local function youPart(page, part, x, w, y)
    local title, about, kind, list, empty = unpack(part)
    local right = pageWidth(page) - x - w
    y = heading(page, title, y, x, w)
    y = note(page, about, y, nil, right, x) + 4
    if #list == 0 then return note(page, empty, y, 0.45, right, x) + 4 end
    return iconRow(page, kind, x, w, y, list) + 4
end

-- Fills card `box`'s blessing part for us (`me`).
local function youBlessings(box, me)
    NS.Priority.ownRow(box.bless, BLESS_ICON)
    box.back:SetShown(Du.blessOrderOf("name:" .. me.name) ~= nil)
end

-- The parts in a 2 by 2 grid, or one under another when the page is too
-- narrow for two.
local PART_GAP = 20

local function youParts(page, parts, y)
    local W = pageWidth(page)
    if W < 420 then
        for _, part in ipairs(parts) do y = youPart(page, part, 0, W, y) end
        return y
    end
    local w = floor((W - PART_GAP) / 2)
    for i = 1, #parts, 2 do
        local left = youPart(page, parts[i], 0, w, y)
        local right = parts[i + 1] and youPart(page, parts[i + 1], w + PART_GAP, w, y) or left
        y = max(left, right) + 4
    end
    return y
end

-- The card at `y` and the parts under it, as wide as the page, and the y
-- under them.
local function youBox(page, y)
    local me = R.me()
    if not me then return y end
    for _, m in ipairs(Du.shownMembers()) do
        if m.me then me = m end
    end
    local W = NS.Whisper
    local p = Du.player(me)
    local give = {}
    for _, a in ipairs(shownMine()) do
        local text = a.backup and backupText(a)
                     or upperFirst(W and W.assignmentText(a) or Du.title(a.job)) .. "."
        local title = a.buff and Tr.title(a.buff) or Du.title(a.job)
        give[#give + 1] = { tex = iconOf(a), dim = a.backup and 0.45, key = text,
                            click = function() NS.signal("focus", a.job.id) end, tip = function(self)
            spellTip(self, buffOf(a), title, { text }, { { "Click", "show it" } })
        end }
    end
    local get = {}
    for _, g in ipairs(p.got) do
        local mine = g.from.name == me.name
        local who = mine and "you" or colored(g.from)
        local name = g.b.family == "blessing" and shortBless(g.b) or Tr.title(g.b)
        get[#get + 1] = { tex = Tr.icon(g.b), key = format("%s (%s)", name, who),
                          click = function() NS.signal("focus", g.b.job) end, tip = function(self)
            local from = mine and "you" or NS.who(g.from)
            -- The rank they put on us.
            local _, spell = Du.rankFor(g.b, g.from.level, not g.target and me.level or nil)
            spellTip(self, g.b, nil, { g.target and format("On the target, from %s.", from)
                                       or format("From %s.", from) }, { { "Click", "show it" } }, spell)
        end }
    end
    local function without(list, dim)
        local t = {}
        for _, x in ipairs(list) do
            t[#t + 1] = { tex = Tr.icon(x.b), dim = dim, key = format("%s: %s", Tr.title(x.b), x.why),
                          click = function() NS.signal("focus", x.b.job) end, tip = function(self)
                local lines = { x.level and T.line(x.why, x.level) or x.why }
                if x.b.debuff then table.insert(lines, 1, "On the target.") end
                spellTip(self, x.b, nil, lines, { { "Click", "show it" } })
            end }
        end
        return t
    end
    local wont, cant = without(p.wont, 0.6), without(p.cant, 0.3)

    local box = pool(page, "youBox", makeYouBox)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
    box:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -y)
    local spec = me.spec and D.SPECS[me.class] and D.SPECS[me.class][me.spec]
    box.icon:SetTexture(spec and spec.icon or T.classIcon(me.class))
    box.artInfo = artFor(me.class, me.spec)
    fitArt(box)
    box.name:SetText(colored(me))
    box.spec:SetText(youSpec(me))
    box.place:SetText(youPlace(me))
    box.source:SetText(youSource(me))
    youBlessings(box, me)
    y = y + YOU_H + 6
    return youParts(page, {
        { "Give", "What you put up. Faded ones you only back up.", "you", give, "No assignments." },
        { "Get", "What reaches you, and who gives it.", "got", get, "Nobody buffs you yet." },
        { "Could get", "Someone here could give it, but this setup doesn't.", "wont", wont, "Nothing." },
        { "Can't get", "Nobody here can give it.", "cant", cant, "Nothing." },
    }, y) + 4
end

-- =============================================================
-- Missing
-- =============================================================
-- What nobody here can give: Du.gaps as faded icons. The tooltip says why
-- ("No druid here."), and a click goes to the assignment.

-- A gap's buff: the totem it names, else its job's first buff.
local function gapBuff(g)
    local b = g.buff and D.BY_ID[g.buff]
    local job = D.JOB[g.jobId]
    return b or job and D.BY_ID[job.options[1]]
end

local function gapIcon(g)
    local b = gapBuff(g)
    return b and Tr.icon(b) or nil
end

local function missingSection(page, y, gaps)
    if #gaps == 0 then return y end
    y = heading(page, "Missing", y)
    local list = {}
    for _, g in ipairs(gaps) do
        local what, why = gapParts(g)
        list[#list + 1] = { tex = gapIcon(g), dim = 0.4, key = g.jobId, what = what,
                            click = function() NS.signal("focus", g.jobId) end,
                            tip = function(self)
                                local lines = why ~= "" and { upperFirst(why) .. "." } or nil
                                spellTip(self, gapBuff(g), what, lines, { { "Click", "show it" } })
                            end }
    end
    return iconRow(page, "gap", 0, pageWidth(page), y, list) + 6
end

-- =============================================================
-- Dropping a player on the page
-- =============================================================
-- Lets frame `f` of `page` take a player dragged from the raid pane, with
-- `f.onDrop(m, shift)`. A frame scrolled out of sight still answers to the
-- mouse where it would be, so the drop must land inside the page too.
local function takeDrops(page, f)
    if not NS.RaidPane then return end
    NS.RaidPane.addDropTarget(f, function(m, shift)
        if page.scroll.IsMouseOver and page.scroll:IsMouseOver() == false then return end
        f.onDrop(m, shift)
    end)
end

-- =============================================================
-- Cards
-- =============================================================
-- An assignment is a card: its icon, its name, and who gives it in class
-- colours with the backups in grey after them. A gold dot after the name
-- says it's set by hand. The card's edge is red when it needs fixing (a pick
-- that can't be done, someone missing a blessing, or nobody to give it),
-- grey when who was picked isn't here, and blue when the draft changed it.
-- A red or grey card says why at the start of its who line: "Blocked", "Not
-- here" or "Missing". The count at the top right says how many have the
-- buff. Cards sit in as many columns as fit.
local ROW_BG, ROW_HOVER = 0.03, 0.06
local ICON, ICON_GAP = 28, 6
local CARD_H, CARD_MIN, CARD_GAP = 40, 200, 6

C.spellTip = spellTip

-- The overrides that cost someone one of buffs `ids` (a list), next to
-- auto alone, as "Caused by: Mira gives Divine Spirit" lines added to
-- `lines`. Their own cards in Overrides say what each costs.
function C.causeLines(lines, ids)
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    local found = {}
    for _, cost in pairs(Du.costs().byKey) do
        local level
        for id, l in pairs(cost.ids or {}) do
            if want[id] and level ~= "bad" then level = l end
        end
        if level then found[#found + 1] = { text = cost.text, level = level } end
    end
    table.sort(found, function(a, b) return a.text < b.text end)
    for _, f in ipairs(found) do
        lines[#lines + 1] = T.line(format("Caused by: %s", f.text), f.level)
    end
end

-- What an assignment's tooltip says under the spell: what the picks mean,
-- who's on it and why, the backups, and what went wrong.
local function jobLines(job, plan)
    local lines = {}
    if job.kind ~= "totem" and job.kind ~= "resist" then
        local c = Du.custom(job.id) and T.COLOR.hand or { 0.8, 0.8, 0.8 }
        lines[#lines + 1] = { Du.pickText(job.id), c[1], c[2], c[3] }
    end
    local fight = Du.shown("resistances")
    if plan and plan.active and not Du.enabled(job) and fight and fight.fight then
        lines[#lines + 1] = { format("For %s.", fight.fight), 1, 1, 1 }
    end
    if plan and plan.active then
        for _, a in ipairs(plan.list) do
            local what = a.buff and NS.buffText(a.buff) or "blessings"
            if a.party and R.raid() then what = format("%s, group %d", what, a.party) end
            lines[#lines + 1] = { format("%s: %s", NS.who(a.giver), what), 1, 1, 1 }
            if a.why then lines[#lines + 1] = a.why end
        end
        if plan.backups and #plan.backups > 0 then
            local t = {}
            for _, m in ipairs(plan.backups) do t[#t + 1] = NS.who(m) end
            lines[#lines + 1] = "Backups: " .. table.concat(t, ", ")
        elseif job.kind == "blessing" and plan.reserve and #plan.reserve > 0 then
            local t = {}
            for _, a in ipairs(plan.reserve) do
                local classes = {}
                for class in pairs(a.classes) do classes[#classes + 1] = classWord(class) end
                table.sort(classes)
                t[#t + 1] = format("%s (%s)", NS.who(a.giver), table.concat(classes, ", "))
            end
            lines[#lines + 1] = "Backups: " .. table.concat(t, ", ")
        end
        if job.kind == "totem" then
            local t = {}
            for _, id in ipairs(D.TOTEM_ORDER) do t[#t + 1] = Tr.title(D.BY_ID[id]) end
            lines[#lines + 1] = "Priority: " .. table.concat(t, ", ") .. "."
        end
    elseif plan then
        local bad = plan.code == "nobody" or plan.code == "absent"
        local c = bad and RED or { 0.8, 0.8, 0.8 }
        lines[#lines + 1] = { plan.why, c[1], c[2], c[3] }
    end
    local warns = blessWarnings(plan)
    if #warns > 0 then
        lines[#lines + 1] = " "
        for _, w in ipairs(warns) do
            for _, l in ipairs(warningLines(w)) do lines[#lines + 1] = T.line(l, "bad") end
        end
    end
    C.causeLines(lines, job.options)
    local p = plan and plan.picked
    if p and p.status ~= "applied" and p.reason then
        local c = p.status == "absent" and GREY or RED
        lines[#lines + 1] = { p.reason, c[1], c[2], c[3] }
    end
    if NS.draft and NS.Suggest.jobChanged(job.id) then
        lines[#lines + 1] = T.line("Changed in the draft.", "changed")
    end
    return lines
end

-- Why the pick of a grey or red card isn't on it, short enough for the
-- card: "Mira isn't here", "Mira is busy (Divine Spirit)". nil when the
-- plan doesn't say.
local function pickedWhy(plan)
    local p = plan and plan.picked
    if not p or p.status == "applied" then return nil end
    local why = p.status == "blocked" and p.why
    if why and why.who and why.holder then
        local what
        for _, a in ipairs((Du.shown(why.holder) or {}).list or {}) do
            if a.giver.name == why.who and a.buff then what = Tr.title(a.buff) end
        end
        local holder = D.JOB[why.holder]
        what = what or (holder and Du.title(holder))
        if what then return format("%s is busy (%s)", why.who, what) end
    end
    local text = p.reason or (why and why.text)
    return text and (text:gsub("%.$", "")) or nil
end

-- The state of an assignment that isn't plain auto, as a word and its
-- colour. Whether the draft changed it is apart from this, in changedCard.
local function stateOf(job, plan)
    -- A fight turns Shadow Protection on while it's on, though it's off.
    if not Du.enabled(job) and not (plan and plan.active) then return "Off", GREY end
    if plan and plan.fallback then
        if plan.picked and plan.picked.status == "blocked" then return "Blocked", RED end
        return "Not here", GREY
    end
    if #blessWarnings(plan) > 0 then return "Fix", RED end
    -- An override that leaves the raid worse off than auto alone.
    local cost = Du.costs().byJob[job.id]
    if cost then return "Costs", cost == "bad" and RED or T.COLOR.low end
    if Du.custom(job.id) then return "Set", T.COLOR.hand end
end

-- =============================================================
-- What the draft changed
-- =============================================================
-- What our draft changes, item by item (Du.diff from the group's settings to
-- the draft's), as of the page's last drawing. Each part of the page marks
-- what an item of its own changed, in blue: a card, a party's cell, a cell
-- of the blessing table, a class's order, a fight and its schools. So one
-- totem changed in the draft marks that totem's card, not every totem's.
local changes = {}

local function readChanges()
    local d = NS.draft
    changes = d and d.base and Du.diff(d.base.duty, d.duty) or {}
end

-- Whether the draft changes an item `test(it)` says yes to.
local function changedWhere(test)
    for _, it in ipairs(changes) do
        if test(it) then return true end
    end
    return false
end
C.changedWhere = changedWhere

-- The party of the player a pick names ("name:Bob"), or nil for a class or
-- spec pick or a player who isn't here.
local function pickParty(pick)
    local name = type(pick) == "string" and pick:match("^name:(.+)$")
    local m = name and R.byName(name)
    return m and m.group
end

-- Whether item `it` of a party assignment reaches party `g`: a pick of a
-- player in it, a choice or totem of one, and anything that isn't about a
-- player, like turning it off or a class pick.
local function reachesParty(it, g)
    if it.kind == "totem" then return pickParty("name:" .. (it.a or "")) == g end
    if it.kind == "choice" then return pickParty("name:" .. (it.b or "")) == g end
    if it.kind == "never" then
        local p = pickParty(it.b)
        return p == nil or p == g
    end
    if it.kind == "picks" then
        for _, list in ipairs({ it.v or {}, it.w or {} }) do
            for _, pick in ipairs(list) do
                local p = pickParty(pick)
                if p == nil or p == g then return true end
            end
        end
        return false
    end
    return true
end

-- Whether the draft changed what card `item` shows: one shaman's totem of an
-- element for a totem's card, else anything of its assignment.
local function changedCard(item)
    if not NS.draft then return false end
    local a = item.a
    if a then
        return changedWhere(function(it)
            if it.job ~= item.job.id then return false end
            if it.kind == "resist" then return it.b == a.school end
            if it.kind ~= "totem" then return true end
            return (it.a == a.giver.name or it.a == Du.specKey(a.giver)) and it.b == a.buff.element
        end)
    end
    return changedWhere(function(it) return it.job == item.job.id end)
end

-- How many have the buffs of assignments `list`, as text and a colour, or
-- nil when we can't tell. A debuff says whether it's up on the target.
--
-- The mock raid shows no count. Its made-up players aren't in our group, so
-- we can never read their buffs, and every card would say "?".
local function countOf(list)
    if NS.mock then return nil end
    local have, want, unknown = 0, 0, 0
    for _, a in ipairs(list) do
        local st = Tr.status(a)
        if st.debuff then
            if not st.wanted then return nil end
            if st.unknown then return "?", GREY end
            return st.up and "up" or "off", st.up and GREEN or RED
        end
        have, want, unknown = have + st.have, want + st.want, unknown + st.unknown
    end
    if want == 0 then return nil end
    if unknown == want then return "?", GREY end
    return format("%d/%d", have, want), have + unknown >= want and GREEN or RED
end

-- A plain icon with a ring, for a fight's schools.
local function makeTile(parent)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(ICON, ICON)
    t.icon = T.icon(t, nil, ICON)
    t.icon:SetPoint("CENTER", t, "CENTER", 0, 0)
    -- The highlight draws over everything, so it stays inside the icon's
    -- black edge rather than lighten it.
    t.hl = t:CreateTexture(nil, "HIGHLIGHT")
    t.hl:SetColorTexture(1, 1, 1, 0.15)
    local function inset()
        local px = T.pixel(t)
        t.hl:ClearAllPoints()
        t.hl:SetPoint("TOPLEFT", t, "TOPLEFT", px, -px)
        t.hl:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -px, px)
    end
    inset()
    t:HookScript("OnShow", inset)
    -- The ring sits just outside the icon's black edge.
    t.ring = CreateFrame("Frame", nil, t)
    t.ring:SetPoint("TOPLEFT", t, "TOPLEFT", -2, 2)
    t.ring:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 2, -2)
    T.border(t.ring, { 1, 1, 1 }, 1, "OVERLAY")
    for _, e in ipairs(t.ring.edges) do
        if e:GetHeight() < 2 then e:SetHeight(2) end
        if e:GetWidth() < 2 then e:SetWidth(2) end
    end
    t.over = CreateFrame("Frame", nil, t)
    t.over:SetAllPoints(t)
    t.count = T.text(t.over, T.SIZE.caption, true)
    t.count:SetFont(T.BOLD, T.SIZE.caption, "OUTLINE")
    t.count:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -1, 2)
    t.count:SetJustifyH("RIGHT")
    t:SetScript("OnEnter", function(self) if self.tipFn then self.tipFn(self) end end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return t
end

-- Shows texture `tex` on icon `t`, grey when it isn't `active`, with a ring
-- of `ring`'s colour and the count `count` in `ccolor`.
local function dress(t, tex, active, ring, count, ccolor)
    t.icon:SetTexture(tex)
    t.icon:SetDesaturated(not active)
    t.icon:SetAlpha(active and 1 or 0.5)
    t.ring:SetShown(ring ~= nil)
    if ring then T.paint(t.ring, ring, 1) end
    t.count:SetText(count or "")
    if ccolor then t.count:SetTextColor(ccolor[1], ccolor[2], ccolor[3], 1) end
end

local function makeCard(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(CARD_H)
    c.bg = T.fill(c, { 1, 1, 1 }, ROW_BG)
    c.bg:SetAllPoints(c)
    T.border(c, { 1, 1, 1 }, 0.08)
    makeFlash(c)
    c.icon = T.icon(c, nil, ICON)
    c.icon:SetPoint("LEFT", c, "LEFT", 6, 0)
    c.count = T.text(c, T.SIZE.caption, true, 1)
    c.count:SetPoint("TOPRIGHT", c, "TOPRIGHT", -6, -6)
    c.count:SetJustifyH("RIGHT")
    -- Each line hangs from its two top corners at the same height. A RIGHT
    -- anchor would put the line's middle at the card's (or the count's)
    -- middle, above the who line's top, and squash it to nothing.
    c.name = T.text(c, T.SIZE.label, true, 1)
    c.name:SetPoint("TOPLEFT", c, "TOPLEFT", ICON + 13, -5)
    c.name:SetPoint("TOPRIGHT", c.count, "TOPLEFT", -4, 1)
    c.name:SetWordWrap(false)
    c.who = T.text(c, T.SIZE.body, false, T.A_TEXT)
    c.who:SetPoint("TOPLEFT", c, "TOPLEFT", ICON + 13, -22)
    c.who:SetPoint("TOPRIGHT", c, "TOPRIGHT", -6, -22)
    c.who:SetWordWrap(false)
    -- A click goes to where it's set (C.goTo), when the card says where.
    c:SetScript("OnEnter", function(self) if self.tipFn then self.tipFn(self) end end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetScript("OnClick", function(self) if self.places then C.goTo(self.places) end end)
    T.hoverEdge(c, function(self) return self.places ~= nil end)
    return c
end

-- Fills card `c` for `item`: { job } for an assignment, { job, a } for one
-- shaman's raid-wide totem, with `gap` (why, from Du.gaps) when nobody gives
-- it, and for a totem `buff`, the first totem missing. Or `idle` when nobody
-- here needs it.
local function paintCard(c, item)
    local job, a = item.job, item.a
    local plan = Du.shown(job.id) or { active = false, list = {}, job = job }
    local list = a and { a } or (plan.active and plan.list or {})
    local b = a and a.buff or (plan.list[1] and plan.list[1].buff) or D.BY_ID[job.options[1]]
    if job.kind == "blessing" and not (plan.list[1] and plan.list[1].buff) then b = D.BY_ID.kings end
    local active = a ~= nil or plan.active
    local title = a and Tr.title(a.buff) or Du.title(job)
    local word, wordColor
    if a and job.kind == "resist" then
        -- A fight's giver set by hand on the Resistances tab.
        if a.hand then word = "Set" end
    elseif a then
        local set, holder = Du.totemFor(a.giver, a.buff.element)
        if set then
            word = "Set"
            local cost = Du.costs().byKey[Du.itemKey("totem", holder, a.buff.element)]
            if cost then word, wordColor = "Costs", cost.level == "bad" and RED or T.COLOR.low end
        end
    else
        word, wordColor = stateOf(job, plan)
    end
    if item.gap then word = "Missing" end
    local changed = changedCard(item)
    -- Nobody here can give a missing one. That's not something to fix on
    -- the card, so it gets a grey edge and orange words rather than red.
    local bad = word == "Fix" or word == "Blocked"
    c.icon:SetTexture(Tr.icon(b))
    c.icon:SetDesaturated(not active)
    c.icon:SetAlpha(active and 1 or 0.5)
    local hand = word == "Set" or word == "Costs" or (not a and Du.custom(job.id) and word ~= "Off")
    c.name:SetText(title .. (hand and " " .. T.MARK or ""))
    c.name:SetTextColor(1, 1, 1, active and 1 or T.A_DIM)
    local count, ccolor = countOf(list)
    c.count:SetText(count or "")
    if ccolor then c.count:SetTextColor(ccolor[1], ccolor[2], ccolor[3], 1) end
    local low = {}
    for _, x in ipairs(list) do
        for _, t in ipairs(Tr.status(x).low or {}) do low[#low + 1] = t end
    end
    local who
    if a then
        who = colored(a.giver)
    elseif item.idle then
        who = DIM .. (plan.code == "off" and "Turned off" or "Nobody here needs it") .. "|r"
    elseif item.gap then
        who = hex(T.COLOR.gap) .. "Missing" .. (item.gap ~= "" and ": " .. item.gap or "") .. "|r"
    else
        who = giversText(plan)
    end
    -- A card that went wrong says how first, about who was picked, then who
    -- auto put on it instead: "Mira isn't here · auto: Bob".
    if word == "Blocked" or word == "Not here" then
        local lead = hex(word == "Blocked" and RED or GREY) .. (pickedWhy(plan) or word) .. "|r"
        if plan.active and #list > 0 then
            who = format("%s %s\194\183 auto:|r %s", lead, DIM, who)
        else
            who = lead .. "  " .. who
        end
    end
    -- First on the line, so a long list of givers doesn't cut it off.
    c.who:SetText(#low > 0 and format("%s%s|r  %s", hex(T.COLOR.low), Tr.DOWNRANK, who) or who)
    -- Missing because of an override is red, since the override can be
    -- taken back. Missing because nobody here can give it is grey.
    local overridden = item.gap and not a and item.cost == "bad"
    if bad or overridden then
        T.paint(c, RED, 0.9)
    elseif word == "Costs" and not changed then
        T.paint(c, wordColor, 0.9)
    elseif item.gap then
        T.paint(c, GREY, 0.9)
    elseif changed then
        T.paint(c, BLUE, 0.9)
    elseif word == "Not here" then
        T.paint(c, GREY, 0.9)
    else
        T.paint(c, { 1, 1, 1 }, item.idle and 0.05 or 0.08)
    end
    c.job, c.a, c.idle = job, a, item.idle
    c.places = C.whereSet(job, a, b)
    -- What it shows, in words, for the tooltip and the tests.
    c.titleText = title
    c.whoText = a and colored(a.giver) or who
    c.stateText = word
    c.changed = changed
    c.tipFn = function(self)
        local verb = a and not a.buff.element and "puts it up" or "puts it down"
        local lines = a and { { format("%s %s", NS.who(a.giver), verb), 1, 1, 1 } } or jobLines(job, plan)
        if a and a.why then lines[#lines + 1] = a.why end
        if a and a.note then lines[#lines + 1] = a.note end
        if a and a.except then
            lines[#lines + 1] = format("Only for those without %s.", Tr.title(a.except))
        end
        -- An assignment set by hand says "Override." as its why already.
        local said = false
        for _, l in ipairs(lines) do
            said = said or l == "Override." or type(l) == "table" and l[1] == "Override."
        end
        if (word == "Set" or word == "Costs") and not said then table.insert(lines, 1, T.line("Override.", "hand")) end
        if a and word == "Costs" then
            local _, holder = Du.totemFor(a.giver, a.buff.element)
            local cost = Du.costs().byKey[Du.itemKey("totem", holder or a.giver.name, a.buff.element)]
            for _, l in ipairs(cost and cost.lines or {}) do
                lines[#lines + 1] = T.line(l, cost.level)
            end
        end
        if item.gap then
            lines[#lines + 1] = T.line("Missing" .. (item.gap ~= "" and ": " .. item.gap or "") .. ".", "gap")
        end
        local lowLine = Tr.lowLine(low)
        if lowLine then lines[#lines + 1] = T.line(lowLine, "low") end
        if a then
            C.causeLines(lines, { a.buff.id })
            if changed then lines[#lines + 1] = T.line("Changed in the draft.", "changed") end
        end
        spellTip(self, b, title, lines, { C.goHint(c.places) })
    end
end

-- `items` as cards from `y`, in as many columns as fit. Returns the y
-- under them.
local function cards(page, items, y)
    if #items == 0 then return y end
    local width = pageWidth(page)
    local cols = max(1, floor((width + CARD_GAP) / (CARD_MIN + CARD_GAP)))
    local w = floor((width - (cols - 1) * CARD_GAP) / cols)
    for i, item in ipairs(items) do
        local col, row = (i - 1) % cols, floor((i - 1) / cols)
        local c = pool(page, "card", makeCard)
        paintCard(c, item)
        c:SetWidth(w)
        c:ClearAllPoints()
        local cy = y + row * (CARD_H + CARD_GAP)
        c:SetPoint("TOPLEFT", page.body, "TOPLEFT", col * (w + CARD_GAP), -cy)
        mark(page, item.job.id, c, cy)
    end
    local rows = floor((#items - 1) / cols) + 1
    return y + rows * (CARD_H + CARD_GAP)
end

-- The page's groups of cards, by the sections of Data.lua. Battle Shout is
-- the only short buff, so it goes with the long ones.
local GROUPS = {
    { title = "Totems", sections = { Totems = true } },
    { title = "Buffs", sections = { ["Long buffs"] = true, ["Short buffs"] = true } },
    { title = "Auras", sections = { Auras = true } },
    { title = "Debuffs", sections = { Debuffs = true } },
}

-- The heading section `section` of the data is under on the page, for the
-- other windows to say the same: "Long buffs" is under Buffs.
function C.headingOf(section)
    for _, g in ipairs(GROUPS) do
        if g.sections[section] then return g.title end
    end
    return section
end

-- Whether an override causes each job's gap, "bad" or "low" (Du.gaps), as
-- the page last drew it.
local gapCost = {}

-- Sorts every assignment into what the page shows: cards for what's needed,
-- by group, `off` for what's turned off and `idle` for what nobody here
-- needs. `gapWhy` is why Du.gaps says each job is missing, and `totemGaps`
-- every totem it says is, each a card of its own. Party assignments are in
-- the party table, so only an idle one gets a card.
local function sortJobs(gapWhy, totemGaps)
    local byGroup, idle, off = {}, {}, {}
    for _, g in ipairs(GROUPS) do byGroup[g.title] = {} end
    for _, job in ipairs(D.JOBS) do
        local plan = Du.shown(job.id)
        local needed = job.kind == "resist" or (plan and plan.active) or gapWhy[job.id] ~= nil
        if job.kind == "resist" then
            -- Only while a fight is on: each resistance it needs is a card
            -- where its kind of buff goes, a totem among the totems and the
            -- hunter's aspect among the auras. A paladin's resistance aura
            -- reaches only their party, so it's in the party table instead.
            for _, a in ipairs(plan and plan.active and plan.list or {}) do
                local into = a.buff.element and byGroup.Totems
                             or a.buff.family ~= "paladinAura" and byGroup.Auras or nil
                if into then into[#into + 1] = { job = job, a = a } end
            end
        elseif not needed and not Du.enabled(job) then
            off[#off + 1] = { job = job, idle = true }
        elseif not needed then
            idle[#idle + 1] = { job = job, idle = true }
        elseif job.scope ~= "party" and job.kind ~= "blessing" then
            local into
            for _, g in ipairs(GROUPS) do
                if g.sections[job.section] then into = byGroup[g.title] end
            end
            if into and job.kind == "totem" then
                for _, a in ipairs(plan and plan.active and plan.list or {}) do
                    if not a.party then into[#into + 1] = { job = job, a = a } end
                end
                for _, g in ipairs(totemGaps) do
                    into[#into + 1] = { job = job, gap = g.why, buff = g.buff, cost = g.cost }
                end
            elseif into then
                local gap = not (plan and plan.active) and gapWhy[job.id] or nil
                into[#into + 1] = { job = job, gap = gap, cost = gap and gapCost[job.id] }
            end
        end
    end
    return byGroup, idle, off
end

-- =============================================================
-- The page's pieces, for its sections in other files
-- =============================================================
-- Resistances.lua, Blessings.lua and PartyBuffs.lua draw their sections
-- with these, the same as the sections here.
C.kit = {
    BLUE = BLUE,
    RED = RED,
    GREY = GREY,
    DIM = DIM,
    hex = hex,
    ICON = ICON,
    ICON_GAP = ICON_GAP,
    ROW_BG = ROW_BG,
    ROW_HOVER = ROW_HOVER,
    CARD_H = CARD_H,
    CARD_MIN = CARD_MIN,
    CARD_GAP = CARD_GAP,
    CLASSES = CLASSES,
    canChange = canChange,
    changedWhere = changedWhere,
    clickHint = clickHint,
    colored = colored,
    countOf = countOf,
    dress = dress,
    heading = heading,
    makeCard = makeCard,
    makeFlash = makeFlash,
    makeTile = makeTile,
    mark = mark,
    pool = pool,
    spellTip = spellTip,
    cards = cards,
    headingButton = headingButton,
    missingIn = missingIn,
    shortBless = shortBless,
    specName = specName,
    warningLines = warningLines,
    note = note,
    pageWidth = pageWidth,
    reachesParty = reachesParty,
    takeDrops = takeDrops,
}

-- =============================================================
-- Not needed here
-- =============================================================
-- The assignments nobody here wants, folded into a line at the bottom of
-- Assignments: "Not needed here (6)". Opened, each is a dim card. What's
-- turned off isn't on Assignments at all. Buffs by Spec turns it on again.
local function makeFold(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.text = T.text(b, T.SIZE.caption + 1, true, T.A_DIM)
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1, 1)
        if self.tipFn then self.tipFn(self) end
    end)
    b:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 1, 1, T.A_DIM)
        GameTooltip:Hide()
    end)
    return b
end

-- The folds: the key in db.window that keeps each one open, its words and
-- its tooltip.
local FOLDS = {
    idle = { key = "idleOpen", title = "Not needed here",
             tip = "Assignments nobody here needs." },
}

local function foldSection(page, y, items, which)
    if #items == 0 then return y end
    local f = FOLDS[which]
    y = y + 12
    local open = NS.db.window[f.key] == true
    local b = pool(page, "fold", makeFold)
    b.text:SetText(format("%s  %s (%d)", open and T.DOWN or "\226\128\186", f.title:upper(), #items))
    b.idleCount, b.fold = #items, which
    b:SetWidth(240)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
    b:SetScript("OnClick", function()
        NS.db.window[f.key] = not open
        C.refreshPage()
    end)
    b.tipFn = function(self)
        T.tip(self, f.title, { f.tip }, { { "Click", open and "fold them away" or "show them" } })
    end
    y = y + 26
    if open then y = cards(page, items, y) end
    return y
end

-- =============================================================
-- Banners
-- =============================================================
-- A banner across the page, like BayovCore's: a tinted bar with a stripe of
-- its colour at the left, a few words, and buttons on the right. It's for
-- our draft and for a suggestion waiting for us, in blue (changes, as on
-- the cards), or red for a draft that can't be sent.
local BANNER_H = 28

local function makeBanner(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(BANNER_H)
    f.bg = T.fill(f, T.ACCENT, 0.10)
    f.bg:SetAllPoints(f)
    f.bar = T.fill(f, T.ACCENT, 0.9, "ARTWORK")
    f.bar:SetWidth(3)
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.text = T.text(f, T.SIZE.body, true, 1)
    f.text:SetPoint("LEFT", f, "LEFT", 10, 0)
    f.text:SetWordWrap(false)
    f.buttons = {}
    for i = 1, 3 do f.buttons[i] = T.button(f, "", nil, 20) end
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self) if self.tipFn then self.tipFn(self) end end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

-- `buttons` is a list of { label, fn, main = true for the accent one },
-- shown left to right.
local function banner(page, y, text, buttons, tipFn, color)
    local f = pool(page, "banner", makeBanner)
    color = color or T.ACCENT
    f.bg:SetColorTexture(color[1], color[2], color[3], 0.10)
    f.bar:SetColorTexture(color[1], color[2], color[3], 0.9)
    f.text:SetText(text)
    f.tipFn = tipFn
    local prev
    for i = #f.buttons, 1, -1 do
        local b = f.buttons[i]
        local spec = buttons[i]
        b:SetShown(spec ~= nil)
        if spec then
            b:SetText(spec[1])
            b:setAccent(spec.main)
            b:SetScript("OnClick", spec[2])
            b:ClearAllPoints()
            if prev then
                b:SetPoint("RIGHT", prev, "LEFT", -6, 0)
            else
                b:SetPoint("RIGHT", f, "RIGHT", -4, 0)
            end
            prev = b
        end
    end
    f.text:SetPoint("RIGHT", prev or f, prev and "LEFT" or "RIGHT", -6, 0)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
    f:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -y)
    return y + BANNER_H + 6
end

local function changesWord(n)
    return n == 1 and "1 change" or format("%d changes", n)
end

-- A tooltip listing what `changes` would do.
local function changesTip(title, changes)
    return function(self)
        local lines = {}
        for _, p in ipairs(NS.Suggest.describe(changes)) do
            lines[#lines + 1] = { upperFirst(p), 1, 1, 1 }
        end
        if #lines == 0 then lines[1] = "No changes." end
        T.tip(self, title, lines)
    end
end

-- Applies `name`'s suggestion from its banner. When we changed some of what
-- it changes after it was made, applying it undoes our changes, and only the
-- Review says so change by change. So we ask first.
local function acceptSuggestion(name)
    local Su = NS.Suggest
    local since = 0
    for _, l in ipairs(Su.lines(name)) do
        if l.since then since = since + 1 end
    end
    if since == 0 then return Su.accept(name) end
    T.confirm(format("This undoes %d %s made since. Apply anyway?", since, since == 1 and "change" or "changes"),
              function() Su.accept(name) end)
end

-- The bar for our draft, and one for each suggestion waiting for us. Only
-- one button in sight is the accent one: the draft's, else the first
-- suggestion's Review.
local function banners(page, y)
    local Su = NS.Suggest
    local d = NS.draft
    local mainShown = false
    if d then
        local changes, n = Su.changes(d)
        local text, buttons
        local color = T.ACCENT
        if d.from then
            text = format("%s's suggestion: %s, shown in %sblue|r.",
                          NS.classColored(d.from, (R.byName(d.from) or {}).class), changesWord(n), hex(BLUE))
            buttons = { { "Close", Su.discard } }
            if R.canEdit() then
                buttons = { { "Apply", Su.apply, main = true }, { "Turn down", function() Su.decline(d.from) end },
                            { "Close", Su.discard } }
            end
        elseif R.canEdit() then
            text = format("Your draft: %s.", changesWord(n))
            buttons = { { "Apply", Su.apply, main = true }, { "Discard", Su.discard } }
        elseif stuckDraft() then
            -- The status line says so and has the Discard button.
            text = format("Your draft: %s. It can't be sent while suggestions are off.", changesWord(n))
            buttons = {}
            color = RED
        elseif Su.sent() then
            text = "Suggestion sent. Waiting for an answer."
            buttons = { { "Discard", Su.discard } }
        elseif n == 0 then
            text = "Your draft has no changes yet."
            buttons = { { "Discard", Su.discard } }
        else
            text = d.answer and format("%s turned down your suggestion.", d.answer)
                   or format("Your suggestion: %s, not sent yet.", changesWord(n))
            buttons = { { "Send", function() NS.Constraints.send() end, main = true }, { "Discard", Su.discard } }
        end
        for _, b in ipairs(buttons) do mainShown = mainShown or b.main == true end
        y = banner(page, y, text, buttons, changesTip(d.from and d.from .. "'s suggestion" or "Your draft", changes),
                   color)
    end
    if R.canEdit() and not NS.mock then
        for _, p in ipairs(Su.pending()) do
            if not (d and d.from == p.from) then
                local who = NS.classColored(p.from, p.class)
                -- Review opens the change by change review beside the window,
                -- which can also open it on the page as a draft.
                y = banner(page, y, format("%s suggests %s.", who, changesWord(p.n)), {
                    { "Review", function() NS.Constraints.review(p.from, win) end, main = not mainShown },
                    { "Apply", function() acceptSuggestion(p.from) end },
                    { "Turn down", function() Su.decline(p.from) end },
                }, changesTip(p.from .. "'s suggestion", p.changes), BLUE)
                mainShown = true
            end
        end
    end
    return y
end

-- =============================================================
-- The pages
-- =============================================================
-- Every page but Settings starts the same way: the plan, the status line
-- and the banners. Returns the y under them.
local function top(page)
    release(page)
    page.anchors = {}
    readChanges()
    page.planBox = page.planBox or NS.Profiles.box(page.body)
    local y = page.planBox:place(page.body, 0, 0, pageWidth(page)) + 8
    y = statusLine(page, y)
    return banners(page, y)
end

local function finish(page, y)
    page.body:SetHeight(y + 8)
    page.scroll:update()
end

-- "Everything to auto", at the right of the tab strip on Needs and
-- Overrides, where Settings has its "Reset all". It goes into a draft like
-- any other edit.
local function resetButton()
    return { "Everything to auto", function()
        T.confirm("Remove every override and every change to what people need? Turned off buffs stay off.",
                  function() Du.resetAll() end)
    end, tip = function(self)
        T.tip(self, "Everything to auto", { "Remove every override and every change to what people need.",
                                            "Turned off buffs stay off." })
    end }
end

-- The Overrides page's whole area, which takes a player dragged from the
-- raid pane. It takes no clicks, so the cards in it work as ever.
local function dropZone(page)
    return pool(page, "dropZone", function(parent) return CreateFrame("Frame", nil, parent) end)
end

-- Whether an assignment is turned on or off unlike how it starts.
local function onOffChanged()
    for _, job in ipairs(D.JOBS) do
        if job.kind ~= "resist" and Du.enabled(job) == (job.optional == true) then return true end
    end
    return false
end

-- =============================================================
-- Needs
-- =============================================================
-- What auto aims for: what each spec and player wants, blessings first
-- (BuffsBySpec.lua), under a filter of three classes at a time. Add
-- player override is beside the filter. The Needs tab has the gold
-- dot while something here is set by hand or turned on or off.
local function needsChanged()
    return next(Du.wantKeys()) ~= nil or Du.anyBlessOrder() or onOffChanged()
end

-- The classes Needs shows together, three at a time, by the filter's key.
local CLASS_GROUPS = {
    { key = "g1", "WARRIOR", "ROGUE", "PALADIN" },
    { key = "g2", "DRUID", "SHAMAN", "HUNTER" },
    { key = "g3", "MAGE", "WARLOCK", "PRIEST" },
}

-- The key of the group class `class` is in.
local function groupOf(class)
    for _, g in ipairs(CLASS_GROUPS) do
        for _, c in ipairs(g) do
            if c == class then return g.key end
        end
    end
end

-- What Needs shows: a group of three classes ("g1"), "players" or "all"
-- (db.window.specFilter). Our own class's group until we pick another. A
-- save from when it went by one class shows that class's group.
function C.specFilter()
    local f = NS.db.window.specFilter
    if f == "all" or f == "players" then return f end
    for _, g in ipairs(CLASS_GROUPS) do
        if g.key == f then return f end
    end
    local me = R.me()
    return groupOf(f or "") or me and groupOf(me.class) or "all"
end

-- Whether filter `f` shows class `class`'s specs.
function C.filterShows(f, class)
    return f == "all" or f == groupOf(class)
end

-- Shows class `class` on Needs, for C.focus.
function C.showClass(class)
    NS.db.window.specFilter = groupOf(class) or NS.db.window.specFilter
end

-- A player of `class` was just given a column. The filter moves to Per
-- Player unless it shows their class already, so we see it.
function C.showPlayer(class)
    local f = C.specFilter()
    if f ~= "players" and not C.filterShows(f, class) then NS.db.window.specFilter = "players" end
    C.refresh()
end

-- The filter: "Show", then a segment per group with its classes' icons,
-- then All and Overrides (the players with needs of their own), joined
-- into one strip. A group with something set by hand has a gold dot.
local FILTER_H, FILTER_ICON = 22, 16
local FILTER_TIP = "Only changes what this page shows."

local function makeClassSeg(parent)
    local b = T.segment(parent, "", 3 * (FILTER_ICON + 2) + 14, FILTER_H)
    b.icons = {}
    for i = 1, 3 do
        b.icons[i] = T.icon(b, nil, FILTER_ICON)
        b.icons[i]:SetPoint("LEFT", b, "LEFT", 6 + (i - 1) * (FILTER_ICON + 2), 0)
    end
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetTexture(DOT)
    b.dot:SetSize(6, 6)
    b.dot:SetVertexColor(1, 209 / 255, 0, 1)
    b.dot:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
    b:SetScript("OnEnter", function(self) if self.tipFn then self.tipFn(self) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function makeTextSeg(parent)
    local b = T.segment(parent, "", 40, FILTER_H)
    b:SetScript("OnEnter", function(self) if self.tipFn then self.tipFn(self) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- The label in front of the filter, so it reads as a view and not a
-- setting.
local function makeFilterLabel(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(1, FILTER_H)
    f.text = T.text(f, T.SIZE.label, true, T.A_DIM)
    f.text:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text:SetText("Show")
    f:SetWidth(floor((f.text:GetStringWidth() or 30) + 8))
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self) T.tip(self, "Show", { FILTER_TIP }) end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

local function filterRow(page, y)
    local cur, Bs = C.specFilter(), NS.BuffsBySpec
    local label = pool(page, "filterLabel", makeFilterLabel)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
    local prev = label
    local function put(b, key, tipFn)
        b.filterKey = key
        b:show(cur == key, true)
        b.tipFn = tipFn
        b:SetScript("OnClick", function()
            NS.db.window.specFilter = key
            C.refreshPage()
        end)
        b:ClearAllPoints()
        -- The segments share their edges, so they read as one control. They
        -- overlap by one screen pixel, the width of their edges. One UI unit
        -- is more than a pixel at most UI scales, and then two edges showed
        -- side by side between some of them.
        b:SetPoint("LEFT", prev, "RIGHT", prev == label and 0 or -T.pixel(b), 0)
        prev = b
    end
    for _, g in ipairs(CLASS_GROUPS) do
        local b = pool(page, "filterClass", makeClassSeg)
        local marked, names = false, {}
        for i, class in ipairs(g) do
            b.icons[i]:SetTexture(T.classIcon(class))
            b.icons[i]:SetDesaturated(cur ~= g.key)
            b.icons[i]:SetAlpha(cur == g.key and 1 or 0.6)
            marked = marked or Bs.marked(class)
            names[i] = NS.classColored(upperFirst(classWord(class)), class)
        end
        b.dot:SetShown(marked)
        put(b, g.key, function(self)
            T.tip(self, andList(names), { "Show what they need.", marked and T.line("Has overrides.", "hand") or nil })
        end)
    end
    for _, t in ipairs({ { "all", "All", "Show what every spec and player needs." },
                         { "players", "Overrides", "Show players with needs of their own." } }) do
        local b = pool(page, "filterText", makeTextSeg)
        b.label:SetText(t[2])
        b:SetWidth(floor((b.label:GetStringWidth() or 30) + 20))
        put(b, t[1], function(self) T.tip(self, t[2], { t[3] }) end)
    end
    if canChange() then
        local add = pool(page, "addPlayer", function(parent) return T.button(parent, "Add player override", nil, FILTER_H) end)
        add:setAccent(false)
        add:SetScript("OnClick", function(self) Bs.addMenu(self) end)
        add.tip = function(self) T.tip(self, "Add player override", { "Give one player needs of their own." }) end
        add:ClearAllPoints()
        add:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    end
    return y + FILTER_H + 10
end

-- A button at the right of a page's line at `y`, from pool `kind`, and the
-- room the line leaves for it.
local function lineButton(page, kind, label, y, onClick, tip)
    local b = pool(page, kind, function(parent) return T.button(parent, label, nil, 20) end)
    b:setAccent(false)
    b:SetScript("OnClick", onClick)
    b.tip = function(self) T.tip(self, label, { tip }) end
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -y)
    return b:GetWidth() + 8
end

local function drawNeeds(page)
    headButtons(page, nil, canChange() and { resetButton() } or nil)
    if page.grid then page.grid:Hide() end
    local y = top(page)
    y = note(page, "What each spec and player wants. A lit icon is wanted. Click one to change it. The box at a row's left turns that buff off for everyone.", y) + 6
    y = filterRow(page, y)
    if C.specFilter() == "players" and not NS.BuffsBySpec.hasPlayers() then
        return finish(page, note(page, "No player overrides yet. Add one to give a player needs of their own.", y) + 4)
    end
    page.grid = page.grid or CreateFrame("Frame", nil, page.body)
    page.grid:Show()
    local h, scale = NS.BuffsBySpec.draw(page.grid, pageWidth(page), page.scroll)
    page.grid:ClearAllPoints()
    page.grid:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y / (scale or 1))
    -- Where C.focus goes: the Blessings section ("order") and each job's
    -- first row ("onoff:<job>").
    for k, at in pairs(NS.BuffsBySpec.marks()) do mark(page, k, at.frame, y + at.y * scale) end
    finish(page, y + h + 4)
end

-- =============================================================
-- Resistances
-- =============================================================
local function drawResist(page)
    headButtons(page)
    local y = top(page)
    local room = canChange() and lineButton(page, "addFight", "Add fight", y, function() C.newFight() end,
        "For a boss that needs resistances, like Ragnaros and fire.") or 0
    y = max(note(page, "A row per boss that needs resistances. Click a school to need it, and turn the fight on before the pull.", y + 3, nil, room) + 6, y + 30)
    finish(page, C.resistSection(page, y))
end

-- =============================================================
-- Overrides
-- =============================================================
-- Whether an override goes wrong: it can't be done, or it costs someone a
-- buff. The Overrides tab has a red dot then, since its cards say why.
local function overridesWarn()
    for _, st in ipairs(Du.constraints()) do
        if st.status == "blocked" or st.status == "costly" then return true end
    end
    return false
end

local function drawOverrides(page)
    headButtons(page, nil, canChange() and { resetButton() } or nil)
    local y = top(page)
    local add
    if canChange() then
        add = pool(page, "addOverride", function(parent) return T.button(parent, "Add override", nil, 20) end)
        add:setAccent(true)
        add:SetScript("OnClick", function() NS.Overrides.add() end)
        add.tip = function(self)
            T.tip(self, "Add override", { "Choose a player and what they do. Auto works around it.",
                                          "Or drag a player here from the raid." })
        end
        add:ClearAllPoints()
        add:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -y)
    end
    local locked = not canChange() and (stuckDraft() and "Suggestions are off. You can only discard your draft."
                                        or "Only the leader and assistants can change them.")
    local start = y
    y = note(page, "What a player is set to do, whatever auto would pick." .. (locked and " " .. locked or ""), y + 3,
             nil, add and add:GetWidth() + 8 or 0)
    y = max(y + 6, start + 30)
    local zone = dropZone(page)
    local flashed
    y, flashed = NS.Overrides.draw(page, y, zone)
    -- The zone reaches the bottom of the page, so a drop under the last
    -- card lands too.
    local bottom = max(y, (page.scroll:GetHeight() or 0) - 8)
    zone:ClearAllPoints()
    zone:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -start)
    zone:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -start)
    zone:SetHeight(max(1, bottom - start))
    zone:SetShown(canChange())
    if canChange() then takeDrops(page, zone) end
    finish(page, y)
    if flashed then flash(page, "landed") end
end

-- The Overrides page, for Overrides.lua.
function C.page() return pages and pages.overrides end

-- =============================================================
-- You
-- =============================================================
local function drawYou(page)
    headButtons(page)
    finish(page, youBox(page, top(page)))
end

-- =============================================================
-- Assignments
-- =============================================================
-- Who gives what, from Needs and Overrides, only to read. Each tooltip
-- names the override behind what it costs.
local function drawDuties(page)
    -- Whispering in the header, for those who may change assignments and
    -- for whoever runs the board. It shows only while someone here lacks the
    -- addon.
    local pins = {}
    local _, lacking = addonUsers()
    if (R.canEdit() or NS.Sync.isHost()) and R.grouped() and NS.Whisper and not NS.mock and #lacking > 0 then
        pins[#pins + 1] = { "Whisper assignments", function() NS.Whisper.request() end, tip = function(self)
            T.tip(self, "Whisper assignments", { "Whisper players without the addon their assignments." })
        end }
    end
    headButtons(page, pins)

    local gaps = Du.gaps()
    -- Du.gaps by job: why each is missing ("no priest here"), and for the
    -- totems the first one missing.
    local gapWhy, totemGaps = {}, {}
    gapCost = {}
    for _, g in ipairs(gaps) do
        local _, why = gapParts(g)
        if not gapWhy[g.jobId] then
            gapWhy[g.jobId] = why
            gapCost[g.jobId] = g.cost
        end
        if g.jobId == "totems" then totemGaps[#totemGaps + 1] = { why = why, buff = g.buff, cost = g.cost } end
    end
    local byGroup, idle = sortJobs(gapWhy, totemGaps)
    -- Which fold each folded assignment is in, by the db.window key that
    -- opens it, for C.focus.
    page.idle = {}
    for _, item in ipairs(idle) do page.idle[item.job.id] = FOLDS.idle.key end

    local y = top(page)
    y = note(page, "Who gives what, from Needs and Overrides.", y) + 6
    y = missingSection(page, y, gaps)
    y = C.blessSection(page, y, gapWhy, gapCost)
    for _, g in ipairs(GROUPS) do
        local items = byGroup[g.title]
        if #items > 0 then
            y = heading(page, g.title, y)
            y = cards(page, items, y)
        end
    end
    y = C.partySection(page, y, gapWhy)
    y = foldSection(page, y, idle, "idle")
    finish(page, y)
end

local DRAW = { duties = drawDuties, you = drawYou, needs = drawNeeds, resist = drawResist, overrides = drawOverrides }

-- The tabs' names, with the gold dot on Needs while it holds a change and
-- a red one on Overrides while one goes wrong, laid out again for them.
local RED_MARK = format("|TInterface\\AddOns\\BuffCoordinator\\Media\\Dot:7:7:0:0:64:64:0:64:0:64:%d:%d:%d|t",
                        floor(RED[1] * 255), floor(RED[2] * 255), floor(RED[3] * 255))

local function paintTabs()
    local x = 0
    for _, def in ipairs(PAGES) do
        local tab = pages[def.key].tab
        local dot = def.key == "needs" and needsChanged() and T.MARK
                    or def.key == "overrides" and overridesWarn() and RED_MARK
        tab.label:SetText(def.title .. (dot and " " .. dot or ""))
        tab:SetWidth(floor((tab.label:GetStringWidth() or 40) + 24))
        tab:ClearAllPoints()
        tab:SetPoint("BOTTOMLEFT", win.strip, "BOTTOMLEFT", x, 0)
        x = x + tab:GetWidth() + 2
    end
end

function C.refresh()
    if not win or not win:IsShown() then return end
    NS.RaidPane.draw()
    C.refreshPage()
end

-- Draws all but the raid pane: the header, the tabs and the page.
--
-- It's for a click that changes only what the page shows, like another
-- tab, a fold or a filter on Needs. The pane doesn't depend on the page,
-- and every change it shows (the roster, the board, a plan, a proposal)
-- already draws it. With a 40 player raid the pane was most of a draw, so
-- each such click stuttered when it drew the pane again.
function C.refreshPage()
    if not win or not win:IsShown() then return end
    win.summary:SetText(summary())
    local text, color = stateChip()
    if text then win.chip:show(text, color) else win.chip:Hide() end
    -- The summary takes the room between the title (or its chip) and the
    -- close button.
    win.summary:SetPoint("LEFT", text and win.chip or win.title, "RIGHT", 12, 0)
    win.summary:SetJustifyH("LEFT")
    paintTabs()
    local draw = DRAW[current]
    if draw then
        draw(pages[current])
    elseif NS.Settings then
        local hud = current == "hud"
        NS.Settings.draw(hud and pages.hud or pages.settings, hud and "hud" or nil)
    end
end

local function refreshSoon() NS.soon("configRefresh", 0.1, C.refresh) end
NS.listen("board", refreshSoon)
NS.listen("draft", refreshSoon)
NS.listen("plans", refreshSoon)
NS.listen("roster", refreshSoon)
-- The HUD tab's Preview and Move buttons say Stop Preview and Stop Move
-- while on.
NS.listen("preview", refreshSoon)
NS.listen("moving", refreshSoon)
NS.listen("tracking", function() NS.soon("configRefresh", 0.5, C.refresh) end)
-- A new accent or font reaches the frames we have through T.restyle
-- (Theme.lua), so the window stays the one frame it always was, and only
-- draws again.
NS.listen("option", function(key)
    if not win then return end
    if key == nil or key == "windowScale" then place() end
    refreshSoon()
end)

NS.command("assignments", "open the assignments page", function() C.open("duties") end)
NS.command("settings", "open the settings page", function() C.open("settings") end)
NS.command("hud", "open the HUD page", function() C.open("hud") end)
