-- Target debuffs: the debuffs the assignments put on the target, one icon
-- each (Sunder Armor, Faerie Fire, the curses, the judgements).
--
-- It shows while we target an enemy worth debuffing (Tr.targetWanted: a
-- boss, or an elite outside raids). An icon is in colour with its time left
-- while the debuff is up, and its stacks in the corner (orange until it has
-- them all). A missing one is grey and glows.
--
-- In combat the game hides the target's debuffs from us. Each icon has the
-- game's own aura display behind it (HUD.lua's watch), which draws the
-- debuff in colour, with its own swipe and stacks, while it's there. Our
-- icon under it is grey then, so the colour is only ever the game saying
-- it's up.
--
-- A click whispers who puts it up that it's missing, in combat too. A
-- Shift-click says it in the group's chat.
--
-- It came from BayovCore's Raid Buffs, where it was "Debuffs on the
-- target". This one reads the assignments, so it shows what the plan puts
-- on the target and who does. The row of icons, its settings, Preview and
-- move mode are Widget.lua's.

local _, NS = ...
local D, Du, Tr, O, T, Wd = NS.Data, NS.Duties, NS.Tracking, NS.Options, NS.Theme, NS.Widget
local format = string.format

local TD

local WHITE = { 1, 1, 1 }
-- The countdown turns the running out colour with this long left.
local WARN = 5

local rank = {}
for i, b in ipairs(D.DEBUFFS) do rank[b.id] = i end

-- The cells: { b, st (Tr.status), assigns } for each debuff the active
-- assignments put on the target.
local function cells()
    local byId, list = {}, {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.plan(job.id)
        if plan and plan.active and job.scope == "target" then
            for _, a in ipairs(plan.list) do
                local b = a.buff
                if b and b.debuff and not a.backup then
                    local c = byId[b.id]
                    if not c then
                        c = { b = b, st = Tr.status(a), assigns = {} }
                        byId[b.id] = c
                        list[#list + 1] = c
                    end
                    c.assigns[#c.assigns + 1] = a
                end
            end
        end
    end
    table.sort(list, function(x, y) return (rank[x.b.id] or 999) < (rank[y.b.id] or 999) end)
    return list
end

-- Whether debuff cell `c` needs attention: missing, or short of stacks.
local function missing(c)
    local st = c.st
    if st.unknown then return false end
    if not st.up then return true end
    return c.b.stacks ~= nil and (st.stacks or 0) < c.b.stacks
end

-- =============================================================
-- Made-up debuffs: a boss in a 40 player raid
-- =============================================================
local SAMPLE_GIVER = {
    WARRIOR = { name = "Brakk Ironhide", class = "WARRIOR" },
    DRUID = { name = "Fen Mossbrook", class = "DRUID" },
    WARLOCK = { name = "Vex Ashborn", class = "WARLOCK" },
    PALADIN = { name = "Aldren Brightshield", class = "PALADIN" },
    HUNTER = { name = "Kael Swiftarrow", class = "HUNTER" },
}
-- `left` is its time left, counting down and starting over. One without is
-- missing.
local SAMPLES = {
    { b = "sunder", left = 26, stacks = 5 },
    { b = "faeriefire" },
    { b = "elements", left = 240 },
    { b = "weakness", left = 95 },
    { b = "jowisdom", left = 8 },
    { b = "jocrusader", left = 17 },
    { b = "huntersmark", left = 110 },
    { b = "demoshout", left = 4 },
    { b = "thunderclap", left = 21 },
    { b = "insectswarm", left = 11 },
}

local function samples()
    local now, start, list = GetTime(), TD.sampleStart(), {}
    for _, s in ipairs(SAMPLES) do
        local b = D.BY_ID[s.b]
        if b then
            local st = { debuff = true, wanted = true, up = s.left ~= nil, unknown = false,
                         expires = Wd.loop(s.left, start, now), duration = s.left or 0,
                         stacks = s.stacks or 0 }
            list[#list + 1] = { b = b, st = st, sample = true,
                                assigns = { { giver = SAMPLE_GIVER[b.class] or SAMPLE_GIVER.WARRIOR } } }
        end
    end
    return list
end

-- =============================================================
-- An icon
-- =============================================================
local function paint(f, c, now, glows)
    local tex = Tr.icon(c.b)
    if f.tex ~= tex then
        f.icon:SetTexture(tex)
        f.tex = tex
    end
    local st = c.st
    local up = st.up and not (st.expires > 0 and st.expires <= now)
    -- In combat our read is hidden, and the game's own display draws the
    -- debuff with its real stacks. So the game speaks then, with no count
    -- of ours and no glow. What we know from before the pull and from our
    -- own casts still shows under it, so the icon doesn't go grey when the
    -- game's display draws nothing.
    local game = f.watching and Tr.hidden()
    local grey = st.unknown or not up or false
    f.icon:SetDesaturated(grey)
    local count, color = "", WHITE
    if c.b.stacks and up and not game then
        count = tostring(st.stacks or 0)
        if (st.stacks or 0) < c.b.stacks then color = O.color("warnColor") end
    end
    local expires = up and st.expires or 0
    local tcolor = expires > 0 and expires - now <= WARN and O.color("warnColor") or WHITE
    TD.texts(f, count, color, expires, tcolor, now)
    local red = not up and not st.unknown and not game
    NS.HUD.glow(f, TD.glows(glows) and red and "glowColor" or nil)
end

local function targetName()
    local name = UnitName and UnitName("target")
    return NS.readable(name) and name or "the target"
end

local function tip(f)
    local c = f.cell
    local st = c.st
    local lines = {}
    if c.sample then
        lines[1] = "On the boss."
    else
        lines[1] = format("On %s.", targetName())
    end
    local now = GetTime()
    if st.unknown then
        lines[#lines + 1] = "Hidden in combat. In colour while the game shows it."
    elseif st.up and st.expires > now then
        lines[#lines + 1] = T.line(format("Up, %s left.", NS.HUD.timeText(st.expires - now)), "up")
    elseif st.up then
        lines[#lines + 1] = T.line("Up.", "up")
    else
        local red = O.color("glowColor")
        lines[#lines + 1] = { "Missing.", red[1], red[2], red[3] }
    end
    if c.b.stacks and st.up then lines[#lines + 1] = format("%d of %d stacks.", st.stacks or 0, c.b.stacks) end
    lines[#lines + 1] = Wd.fromLine(c.assigns)
    if c.sample then lines[#lines + 1] = "Made up, to show the look." end
    local hints = {}
    if missing(c) and not c.sample then
        hints[#hints + 1] = { "Click", "whisper who puts it up" }
        hints[#hints + 1] = { "Shift-click", "say it in group chat" }
    end
    if not O.get("lock") and not c.sample then hints[#hints + 1] = { "Drag", "move" } end
    T.spellTip(f, c.b, Tr.title(c.b), lines, hints)
end

-- "Sunder Armor is missing on Ragnaros", or short of its stacks.
local function missingText(c)
    local what, on = Tr.title(c.b), targetName()
    if c.st.up and c.b.stacks then
        return format("%s has %d of %d stacks on %s", what, c.st.stacks or 0, c.b.stacks, on)
    end
    return format("%s is missing on %s", what, on)
end

local function click(c, loud)
    if c.sample then
        NS.print("This one is made up. A click whispers who puts it up.")
        return
    end
    if not missing(c) then
        NS.print("%s is up.", Tr.title(c.b))
        return
    end
    if loud then
        Wd.say("[BC] " .. missingText(c) .. ".")
        return
    end
    local sent, waits = {}, {}
    for _, a in ipairs(c.assigns) do
        if not a.giver.me then
            local ok, wait = NS.Whisper.nudge(a, "[BC] " .. missingText(c) .. ".")
            local who = NS.classColored(a.giver.name, a.giver.class)
            if ok then sent[#sent + 1] = who elseif wait then waits[#waits + 1] = who end
        end
    end
    if #sent > 0 then NS.print("Whispered %s.", NS.andList(sent)) end
    if #waits > 0 then NS.print("You whispered %s a moment ago.", NS.andList(waits)) end
    if #sent == 0 and #waits == 0 then NS.print("You put up %s yourself.", Tr.title(c.b)) end
end

TD = Wd.new({
    key = "debuff", show = "targetDebuffs", name = "Target debuffs", frame = "BuffCoordinatorTargetDebuffs",
    db = "targetDebuffs",
    -- Where BayovCore had it.
    home = { 314, -175.5 },
    cells = cells, samples = samples, paint = paint, tip = tip, click = click, missing = missing,
    wanted = function() return Tr.targetWanted() end,
    -- Each icon on the screen watches its debuff with the game's display,
    -- for combat. It follows the cell the icon shows. The preview pane's
    -- icons don't need it.
    painted = function(icons)
        for _, f in ipairs(icons) do
            local b = f:IsShown() and f.cell and not f.cell.sample and f.cell.b or nil
            if f.watched ~= b or f.watchW ~= f.w then
                f.watched = b
                NS.HUD.watch(f, b)
            end
        end
    end,
    clear = function(f)
        f.watched = nil
        NS.HUD.watch(f, nil)
    end,
})
TD.cells, TD.missing = cells, missing
NS.TargetDebuffs = TD

NS.on("PLAYER_TARGET_CHANGED", function() NS.soon("debuffWidgetPaint", 0.05, TD.paint) end)
