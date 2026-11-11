-- Group buffs: everyone's long buffs at a glance, one icon per buff.
--
-- Each icon is a long buff the assignments put on players (Fortitude, each
-- blessing, Mark of the Wild), with how many have it of how many get it
-- ("17/20") in the corner. The count is red while someone is missing it,
-- the running out colour while it only runs out soon, and green when all is
-- up. The tooltip names who is missing it and who gives it.
--
-- A click whispers each giver who's missing their buff (Whisper.lua's
-- nudge), out of combat. A Shift-click says it in the group's chat. A
-- buff we give ourselves is on our HUD already, so a click doesn't whisper
-- us.
--
-- It came from BayovCore's Raid Buffs, where it was "The group's long
-- buffs". That one worked out who wants what from each player's spec. This
-- one reads the assignments, so it shows what the plan gives and who gives
-- it, the same as the assignments window.
--
-- The row of icons, its settings, Preview and move mode are Widget.lua's.
-- Reading everyone's buffs is many more reads than our own, so we only do
-- that while it shows (Tr.readsAll).

local _, NS = ...
local D, Du, Tr, O, T, Wd = NS.Data, NS.Duties, NS.Tracking, NS.Options, NS.Theme, NS.Widget
local max = math.max
local format = string.format

local G

local WHITE = { 1, 1, 1 }
local UP = T.COLOR.up
local NAMES = 12

-- =============================================================
-- What it shows
-- =============================================================
-- Where each buff comes in the data, so the icons keep the data's order.
local rank = {}
for i, b in ipairs(D.BUFFS) do rank[b.id] = i end

-- The cells: { b, have, want, unknown, expires, missing = { m, a, soon },
-- assigns (the assignments that give it) } for each long buff the active
-- assignments put on players. Backups don't count, since the players they
-- cover are counted under the assignment they back up.
local function cells()
    local byId, list = {}, {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.plan(job.id)
        if plan and plan.active and job.scope ~= "target" then
            for _, a in ipairs(plan.list) do
                local long = a.bless or (a.buff and a.buff.kind == "long" and not a.buff.debuff)
                if long and not a.backup and not a.spare then
                    local st = Tr.status(a)
                    local missingOf = {}
                    for _, t in ipairs(st.missing) do
                        missingOf[t.b.id] = (missingOf[t.b.id] or 0) + 1
                    end
                    for id, by in pairs(st.by) do
                        local c = byId[id]
                        if not c then
                            c = { b = D.BY_ID[id], have = 0, want = 0, unknown = 0, expires = 0,
                                  missing = {}, assigns = {}, low = {} }
                            byId[id] = c
                            list[#list + 1] = c
                        end
                        c.have, c.want = c.have + by.have, c.want + by.want
                        c.unknown = c.unknown + max(0, by.want - by.have - (missingOf[id] or 0))
                        c.assigns[#c.assigns + 1] = a
                    end
                    for _, t in ipairs(st.missing) do
                        local c = byId[t.b.id]
                        c.missing[#c.missing + 1] = { m = t.m, a = a, soon = t.soon, low = t.low }
                    end
                    for _, t in ipairs(st.low) do
                        local c = byId[t.b.id]
                        c.low[#c.low + 1] = t
                    end
                    -- The first to run out, for a blessing too, since a
                    -- paladin's blessings all go up together.
                    if st.expires > 0 then
                        for id in pairs(st.by) do
                            local c = byId[id]
                            if c.expires == 0 or st.expires < c.expires then c.expires = st.expires end
                        end
                    end
                end
            end
        end
    end
    table.sort(list, function(x, y) return (rank[x.b.id] or 999) < (rank[y.b.id] or 999) end)
    return list
end

-- How many of cell `c` are missing it, and how many have it running out.
local function counts(c)
    local missing, soon = 0, 0
    for _, t in ipairs(c.missing) do
        if t.soon then soon = soon + 1 else missing = missing + 1 end
    end
    return missing, soon
end

-- =============================================================
-- Made-up buffs: a 40 player raid
-- =============================================================
local SAMPLE_MISSING = {
    { name = "Tor Greymane", class = "WARRIOR", group = 2 },
    { name = "Lia Brightwater", class = "MAGE", group = 3 },
    { name = "Odo Barrelhand", class = "ROGUE", group = 4 },
    { name = "Sela Moonwhisper", class = "PRIEST", group = 6 },
}
local SAMPLE_GIVER = {
    PRIEST = { name = "Mira Dawnsong", class = "PRIEST" },
    DRUID = { name = "Fen Mossbrook", class = "DRUID" },
    MAGE = { name = "Ilsa Frostwick", class = "MAGE" },
    PALADIN = { name = "Aldren Brightshield", class = "PALADIN" },
}
-- How many of a 40 player raid get each one, and how many have it. `soon`
-- of the rest have it running out, and `left` is the time on the first to
-- run out.
local SAMPLES = {
    { b = "fortitude", want = 40, have = 40, left = 48 * 60 },
    { b = "spirit", want = 22, have = 20, left = 31 * 60 },
    { b = "shadowprot", want = 40, have = 40, left = 35 * 60 },
    { b = "motw", want = 40, have = 37, left = 22 * 60 },
    { b = "thorns", want = 3, have = 3, left = 6 * 60 },
    { b = "intellect", want = 22, have = 21, soon = 1, left = 150 },
    { b = "kings", want = 40, have = 39, left = 41 * 60 },
    { b = "might", want = 15, have = 15, left = 44 * 60 },
    { b = "wisdom", want = 22, have = 19, left = 38 * 60 },
}

local function samples()
    local now, start, list = GetTime(), G.sampleStart(), {}
    for _, s in ipairs(SAMPLES) do
        local b = D.BY_ID[s.b]
        if b then
            local giver = SAMPLE_GIVER[b.class] or SAMPLE_GIVER.PRIEST
            local c = { b = b, have = s.have, want = s.want, unknown = 0, missing = {}, sample = true,
                        assigns = { { giver = giver } }, expires = Wd.loop(s.left, start, now) }
            for i = 1, s.want - s.have do
                c.missing[i] = { m = SAMPLE_MISSING[(i - 1) % #SAMPLE_MISSING + 1], soon = i <= (s.soon or 0) }
            end
            -- One of them shows the DOWNRANK word, to show its look.
            if s.b == "wisdom" then c.low = { { m = SAMPLE_MISSING[1], b = b, rank = 4, want = 6 } } end
            list[#list + 1] = c
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
    local missing, soon = counts(c)
    local color
    if missing > 0 then
        color = O.color("glowColor")
    elseif soon > 0 then
        color = O.color("warnColor")
    elseif c.have < c.want then
        -- Some we never read, so it isn't all good.
        color = WHITE
    else
        color = UP
    end
    f.icon:SetDesaturated(c.want == 0)
    local tcolor = c.expires > 0 and c.expires - now <= Tr.rebuffAt(c.b) and O.color("warnColor") or WHITE
    G.texts(f, c.want > 0 and format("%d/%d", c.have, c.want) or "", color, c.expires, tcolor, now)
    T.downrank(f, c.low ~= nil and #c.low > 0, O.color("glowColor"), nil, nil, 1.2)
    local key = G.glows(glows) and (missing > 0 and "glowColor" or soon > 0 and "warnColor") or nil
    NS.HUD.glow(f, key)
end

-- `title`, then each player of `list` on a line of their own, onto `lines`
-- in color `c`.
local function nameLines(lines, title, list, c)
    lines[#lines + 1] = { title, c[1], c[2], c[3] }
    for i, t in ipairs(list) do
        if i > NAMES then
            lines[#lines + 1] = { format("and %d more", #list - NAMES), c[1], c[2], c[3] }
            break
        end
        lines[#lines + 1] = { NS.who(t.m), c[1], c[2], c[3] }
    end
end

local function tip(f)
    local c = f.cell
    local lines = { format("%d of %d have it.", c.have, c.want) }
    local missing, soon = {}, {}
    for _, t in ipairs(c.missing) do
        if t.low then
            -- The DOWNRANK line below says it.
        elseif t.soon then
            soon[#soon + 1] = t
        else
            missing[#missing + 1] = t
        end
    end
    if #missing > 0 then nameLines(lines, "Missing:", missing, O.color("glowColor")) end
    if #soon > 0 then nameLines(lines, "Running out:", soon, O.color("warnColor")) end
    local low = Tr.lowLines(c.low)
    if low then
        local orange = O.color("warnColor")
        for _, l in ipairs(low) do lines[#lines + 1] = { l, orange[1], orange[2], orange[3] } end
    end
    if c.unknown > 0 then lines[#lines + 1] = format("%d not seen yet.", c.unknown) end
    lines[#lines + 1] = Wd.fromLine(c.assigns)
    if c.sample then lines[#lines + 1] = "Made up, to show the look." end
    local hints = {}
    if #missing > 0 and not c.sample then
        hints[#hints + 1] = { "Click", "whisper who gives it" }
        hints[#hints + 1] = { "Shift-click", "say it in group chat" }
    end
    if not O.get("lock") and not c.sample then hints[#hints + 1] = { "Drag", "move" } end
    T.spellTip(f, c.b, Tr.title(c.b), lines, hints)
end

-- Says what's missing of cell `c`: whispers each giver who's missing their
-- buff, or with `loud` one line in the group's chat.
local function click(c, loud)
    if InCombatLockdown() then return end
    local missing = {}
    for _, t in ipairs(c.missing) do
        if not t.soon then missing[#missing + 1] = t end
    end
    local what = NS.Buffer.short(Tr.title(c.b))
    if #missing == 0 then
        NS.print("Everyone has %s.", what)
        return
    end
    if c.sample then
        NS.print("This one is made up. A click whispers who gives it.")
        return
    end
    if loud then
        local list = {}
        for _, t in ipairs(missing) do list[#list + 1] = t.m.name end
        Wd.say(format("[BC] Missing %s: %s", what, table.concat(list, ", ")))
        return
    end
    local done, sent, waits = {}, {}, {}
    for _, t in ipairs(missing) do
        local a = t.a
        if a and not a.giver.me and not done[a] then
            done[a] = true
            local ok, wait = NS.Whisper.nudge(a)
            local who = NS.classColored(a.giver.name, a.giver.class)
            if ok then sent[#sent + 1] = who elseif wait then waits[#waits + 1] = who end
        end
    end
    if #sent > 0 then NS.print("Whispered %s what's missing.", NS.andList(sent)) end
    if #waits > 0 then NS.print("You whispered %s a moment ago.", NS.andList(waits)) end
    if #sent == 0 and #waits == 0 then NS.print("You give %s yourself.", what) end
end

G = Wd.new({
    key = "group", show = "groupBuffs", name = "Group buffs", frame = "BuffCoordinatorGroupBuffs",
    db = "groupBuffs",
    -- Where BayovCore had it.
    home = { -249, 393 },
    cells = cells, samples = samples, paint = paint, tip = tip, click = click,
    missing = function(c) return #c.missing > 0 end,
})
G.cells, G.counts, G.ask = cells, counts, click
NS.GroupBuffs = G
