-- The raid pane: our party or raid, on the left of the assignments window.
--
-- It's laid out like the game's raid window, two parties side by side, in
-- our own look. It shows the parties the raid uses and one empty one to move
-- players into. Each player shows their spec's icon, their name and an icon
-- for each of their assignments, with "+2" when more don't fit. A crown on
-- top of the spec's icon marks the leader and a star an assistant, and a small
-- icon in the spec's corner says the raid role they were given. After the
-- name, a "?" says we don't know their spec, a dot that it was set by hand,
-- and a pin that they're kept in their party.
--
-- A party's header shows the buffs that reach only that party: a paladin's
-- aura, a shaman's party totems and Blood Pact. An empty place says the
-- party has players who want one that nobody there gives, while someone in
-- the raid could. It's red when moving someone fixes it, and grey when the
-- raid has too few to go round, like 2 paladins for 5 parties.
--
-- It can stand in for the game's raid window. Dragging a player onto another
-- party moves them, and dropping them on a player swaps the two. While we
-- drag, each party turns green or red for whether the party buffs would be
-- better or worse with them there. Over a player, their party takes the
-- colour of that exact swap, and the dragged name says what it gives and
-- takes ("+aura for group 3"). While Arrange or a plan shows its parties,
-- the headers show what each party would get in blue and lose in red. A
-- click opens a menu with their spec,
-- what to assign them to, their role, main tank and
-- main assist, assistant and leader, keeping them in their party, and
-- removing them. Group.lua does what these ask, and says what we may do. In
-- combat the game blocks raid changes, and the pane says so.
--
-- Above the parties are "everyone is an assistant", how many tanks, healers
-- and damage dealers there are against what the raid's size wants, a ready
-- check, Arrange (Arrange.lua), and a strip of every buff and debuff the raid
-- wants, lit when someone here can give it and red when nobody can.
-- Arrange's tooltip says who it would move, and its moves slide each row to
-- its new party, slowly, so we can follow them. A plan
-- picked on the Assignments page's PLAN row (Profiles.lua) shows its parties
-- here before it's applied.
--
-- When we're not in a group, a button in the header starts a mock raid
-- (Mock.lua), which the pane changes in the same way, and which adds players
-- and sets their class too. A mock raid's controls take the header's place
-- of the title, across its whole width: its sizes as one strip, Empty, Reset
-- and End mock raid.
--
-- The pane folds away to a thin rail, and the window gets narrower by as
-- much, so the assignments stay where they are on the screen.
--
-- A drag anywhere else in the pane moves the window, and so does a drag on a
-- player when we may not move players.

local _, NS = ...
local D, R, Du, Tr, T, G = NS.Data, NS.Roster, NS.Duties, NS.Tracking, NS.Theme, NS.Group
local C, Mo, Pl, Ar = NS.Config, NS.Mock, NS.Plans, NS.Arrange

local floor, max, min = math.floor, math.max, math.min
local format = string.format
local unpack = unpack or table.unpack

local P = {}
NS.RaidPane = P

local PAD = 10
-- The header is a line as tall as the window's, and the controls sit level
-- with its tabs.
local HEAD_H = 30
local BOX_W, BOX_GAP = 186, 6
local ROW_H = 22
local BOX_HEAD = 20
local BOX_H = BOX_HEAD + 5 * (ROW_H + 1) + 4
-- Up to four assignment icons. With five or more we show three and then "+2"
-- for the rest, because a "+1" takes about as much room as the icon it hides.
-- Forever's names are "First Last", and they need the room more than a fifth
-- icon does.
local ICONS, ICON, MORE = 4, 18, 16
-- The party buffs in a party's header, as large as the icons on its rows.
local BUFFS, BUFF = 6, ICON
-- The strip of the raid's buffs and debuffs.
local STRIP, STRIP_GAP = 16, 2
-- One size of a mock raid's strip of sizes.
local SIZE_W = 23
-- The rows over the parties: the controls, the tools (Arrange, or what a
-- preview or the move queue is doing) and the strip.
local LINE, LINE_GAP = 20, 6
-- The pane's width: two parties, the gaps, and the scroll bar.
P.WIDTH = 2 * PAD + 2 * BOX_W + BOX_GAP + 8
-- Where the parties start, under all the rows there can be, and the
-- height that shows `boxes` parties without scrolling.
local TOP = HEAD_H + 4 + 2 * (LINE + LINE_GAP) + STRIP + LINE_GAP + 4
local function heightFor(boxes)
    return TOP + math.ceil(boxes / 2) * (BOX_H + BOX_GAP) + PAD
end
-- The height that shows the parties the pane shows now (P.fit). The window
-- opens this tall, until its grip sizes it.
P.HEIGHT = heightFor(2)
P.RAIL = 22

local ROLE_TEX = [[Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES]]
local ROLE_COORDS = {
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
-- The round role icons of the game's own group finder, else the smaller
-- ones, else the old portrait icons, whichever this client has.
local ROLE_ATLAS = {
    TANK = { "UI-LFG-RoleIcon-Tank-Micro-GroupFinder", "roleicon-tiny-tank" },
    HEALER = { "UI-LFG-RoleIcon-Healer-Micro-GroupFinder", "roleicon-tiny-healer" },
    DAMAGER = { "UI-LFG-RoleIcon-DPS-Micro-GroupFinder", "roleicon-tiny-dps" },
}
local ROLE_NAME = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
local RANK_TEX = { [[Interface\GroupFrame\UI-Group-AssistantIcon]], [[Interface\GroupFrame\UI-Group-LeaderIcon]] }
local MARK_TEX = { MAINTANK = [[Interface\GroupFrame\UI-Group-MainTankIcon]],
                   MAINASSIST = [[Interface\GroupFrame\UI-Group-MainAssistIcon]] }
local MARK_NAME = { MAINTANK = "Main tank", MAINASSIST = "Main assist" }
local CLASSES = D.CLASSES
local DOT = [[Interface\AddOns\BuffCoordinator\Media\Dot]]
local LOCK_TEX = [[Interface\LFGFrame\UI-LFG-ICON-LOCK]]
local DIM = T.DIM
local LOCKED = "Raid changes are blocked in combat"
local PIN = [[Interface\AddOns\BuffCoordinator\Media\Pin]]

-- How many tanks and healers a raid of each size wants, as { fewest, most }.
local ROLE_TARGET = {
    [5] = { TANK = { 1, 1 }, HEALER = { 1, 1 } },
    [10] = { TANK = { 1, 2 }, HEALER = { 2, 3 } },
    [15] = { TANK = { 2, 2 }, HEALER = { 3, 4 } },
    [20] = { TANK = { 2, 3 }, HEALER = { 4, 5 } },
    [25] = { TANK = { 2, 3 }, HEALER = { 6, 7 } },
    [30] = { TANK = { 3, 4 }, HEALER = { 7, 8 } },
    [35] = { TANK = { 3, 4 }, HEALER = { 8, 9 } },
    [40] = { TANK = { 4, 5 }, HEALER = { 9, 11 } },
}

local pane, rail, win
-- A layout Arrange proposed, or what a plan would do, until it's applied
-- or cancelled. A plan's has `auto` when Auto picked it.
local proposal
local shownAssignments

local function colored(m) return NS.classColored(m.name, m.class) end

local function roleIcon(tex, role)
    local atlas = _G.C_Texture and C_Texture.GetAtlasInfo
    for _, name in ipairs(ROLE_ATLAS[role]) do
        if tex.SetAtlas and atlas and atlas(name) then
            tex:SetAtlas(name)
            return
        end
    end
    tex:SetTexture(ROLE_TEX)
    tex:SetTexCoord(unpack(ROLE_COORDS[role]))
end
local function canChange() return NS.Suggest.canChange() end

-- The raid role `m` counts as: the one they were given, else their spec's,
-- or nil when we don't know their spec and their class has more than one
-- role.
local function roleOf(m)
    if m.assigned then return m.assigned end
    if m.role == "tank" then return "TANK" end
    if m.role == "healer" then return "HEALER" end
    if m.role then return "DAMAGER" end
    return nil
end
P.roleOf = roleOf

-- "a" or "an" before `word`.
local article = NS.article

-- The icon of a spec, or of the class when we don't know the spec.
function P.specIcon(tex, class, tree)
    local s = R.spec(class, tree)
    if s and s.icon then
        tex:SetTexture(s.icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        tex:SetTexture(T.classIcon(class))
    end
end

-- "Fury warrior", or "warrior" when we don't know the spec.
local function specWords(class, tree)
    local cls = NS.className(class):lower()
    if not R.spec(class, tree) then return cls end
    return C.specName(class, tree) .. " " .. cls
end

-- =============================================================
-- What the raid has
-- =============================================================
-- Player `m`'s assignments on the board the window shows, in page order,
-- as { b, title }: a blessing paladin's most given blessing, and one for
-- each other assignment.
function P.assignmentsOf(m)
    local t = {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.shown(job.id)
        for _, a in ipairs(plan and plan.active and plan.list or {}) do
            if a.giver.name == m.name then
                if a.bless then
                    local n, best = {}, nil
                    for _, id in pairs(a.bless) do
                        n[id] = (n[id] or 0) + 1
                        if not best or n[id] > n[best] or (n[id] == n[best] and id < best) then best = id end
                    end
                    if best then t[#t + 1] = { b = D.BY_ID[best], title = "Blessings", a = a } end
                elseif a.buff then
                    local title = Tr.title(a.buff)
                    if a.party and R.raid() then title = format("%s, group %d", title, a.party) end
                    t[#t + 1] = { b = a.buff, title = title, a = a }
                end
            end
        end
    end
    return t
end

-- `m`'s assignments for their row and tooltip. While a preview shows, a
-- party buff is for the party they're in now, not the one the preview
-- draws them in, so those wait until the moves are made.
function shownAssignments(m)
    local list = P.assignmentsOf(m)
    if not proposal then return list end
    local t = {}
    for _, x in ipairs(list) do
        if not x.a.party then t[#t + 1] = x end
    end
    return t
end

-- The buffs that reach only party `g` (a paladin's aura, a shaman's party
-- totems, Blood Pact), in page order, as { b, list } with everyone who
-- gives it there. While a fight is on, a paladin's resistance aura reaches
-- only their party too, so it's there in place of their usual one.
function P.partyBuffsOf(g)
    local t, at = {}, {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.shown(job.id)
        for _, a in ipairs(plan and plan.active and plan.list or {}) do
            local party = a.party or job.kind == "resist" and a.buff.family == "paladinAura" and a.giver.group or nil
            if party == g and a.buff then
                local x = at[a.buff.id]
                if not x then
                    x = { b = a.buff, list = {} }
                    at[a.buff.id] = x
                    t[#t + 1] = x
                end
                x.list[#x.list + 1] = a
            end
        end
    end
    return t
end

-- The places for a party buff in a party's header that can be empty: a
-- paladin's aura, the water totem (Mana Spring) and Blood Pact. `want` is
-- the buff a player there wants, `who` says how many want it, and `short`
-- names it in a line of what moves change ("+aura for group 4").
local SLOTS = {
    { id = "aura", want = "devotion", word = "paladin aura", short = "aura", who = "%d here want an aura." },
    { id = "water", want = "manaspring", word = "Mana Spring", short = "Mana Spring", who = "%d here use mana." },
    { id = "pact", want = "bloodpact", word = "Blood Pact", short = "Blood Pact", who = "%d here want Blood Pact." },
}
local SLOT = {}
for _, slot in ipairs(SLOTS) do SLOT[slot.id] = slot end

local function slotOf(b)
    if b.family == "paladinAura" then return "aura" end
    if b.id == "bloodpact" then return "pact" end
    return b.element
end

-- How much putting `m` in party `g` would raise Arrange's score, or lower
-- it when below 0. A party with room takes them by a move. A full one
-- takes them only by a swap, so it's the best swap with someone there.
-- `count` is how many each party has.
local function partyGain(m, g, members, count)
    if g == m.group or (count[g] or 0) < 5 then return Ar.moveGain(m, g, members) end
    local best
    for _, x in ipairs(members) do
        if x.group == g then
            local v = Ar.swapGain(m, x, members)
            best = max(best or v, v)
        end
    end
    return best or 0
end

-- Whether moving one of `givers` into party `g` gives it the buff without
-- costing the raid more: a party has two who give it, or Arrange's score
-- says the raid is better off. `by` is how many givers each party has.
local function movable(g, givers, by, members)
    local count
    for _, m in ipairs(givers) do
        if m.group ~= g and not Ar.pinned(m.name) then
            if by[m.group] >= 2 then return true end
            if not count then
                count = {}
                for _, x in ipairs(members) do count[x.group] = (count[x.group] or 0) + 1 end
            end
            if partyGain(m, g, members, count) > 1e-6 then return true end
        end
    end
    return false
end

-- The party buffs party `g` wants and doesn't get, as { slot, b, n, fix,
-- givers, parties, here }: `n` players there want it, nobody there gives it,
-- and someone in the raid could. `fix` is true when moving someone fixes
-- it. With 2 paladins for 5 parties, three parties go without an aura
-- whatever we do, and only a party that could get one says so in red.
-- `givers` is how many could give it, `parties` how many parties the raid
-- uses, and `here` true when one of them is in the party but not assigned
-- it. `list` is who is in the party, and `given` what partyBuffsOf says
-- they get.
function P.partyGaps(list, given, members)
    local have, t = {}, {}
    for _, x in ipairs(given) do have[slotOf(x.b)] = true end
    local g = list[1] and list[1].group
    local used, parties = {}, 0
    for _, m in ipairs(members) do
        if not used[m.group] then
            used[m.group] = true
            parties = parties + 1
        end
    end
    for _, slot in ipairs(SLOTS) do
        local b = D.BY_ID[slot.want]
        local job = D.JOB[b.job]
        if not have[slot.id] and Du.enabled(job) then
            local n, givers, by, here = 0, {}, {}, false
            for _, m in ipairs(list) do
                if m.online and Du.wants(m, b) then n = n + 1 end
            end
            for _, m in ipairs(members) do
                if Du.canGive(m, b) then
                    givers[#givers + 1] = m
                    by[m.group] = (by[m.group] or 0) + 1
                    here = here or m.group == g
                end
            end
            if n > 0 and #givers > 0 then
                t[#t + 1] = { slot = slot, b = b, n = n, givers = #givers, parties = parties, here = here,
                              fix = not here and movable(g, givers, by, members) }
            end
        end
    end
    return t
end

-- What layout changes `list` (Arrange's) do, in a line: "+Mana Spring for
-- party 3, -aura for party 1". What a party gets comes first. Past `most`
-- of them it says how many more. nil when nothing changes.
function P.changeWords(list, most)
    local sorted = {}
    for _, x in ipairs(list or {}) do sorted[#sorted + 1] = x end
    table.sort(sorted, function(a, b)
        if a.gain ~= b.gain then return a.gain end
        return a.g < b.g
    end)
    local parts = {}
    for i, x in ipairs(sorted) do
        if most and i > most then
            parts[#parts + 1] = format("%d more", #sorted - most)
            break
        end
        parts[#parts + 1] = format("%s%s for group %d", x.gain and "+" or "-", SLOT[x.slot].short, x.g)
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- What layout changes `list` do, a tooltip line each with the buff's icon.
--
-- When a buff leaves one party for another, like the shaman whose Mana
-- Spring goes from party 1 to party 3, that's one line: "Mana Spring: party
-- 1 -> party 3". What's left is what a party only gets, in blue, then what
-- one only loses, in red.
local function changeLines(list)
    local sorted = {}
    for _, x in ipairs(list or {}) do sorted[#sorted + 1] = x end
    table.sort(sorted, function(a, b)
        if a.gain ~= b.gain then return a.gain end
        return a.g < b.g
    end)
    local function text(x, words)
        local slot = SLOT[x.slot]
        local b = D.BY_ID[slot.want]
        local word = slot.word:sub(1, 1):upper() .. slot.word:sub(2)
        return NS.iconText(b and Tr.icon(b), format(words, word))
    end
    -- Each loss pairs with a gain of the same buff, in party order.
    local lost, paired = {}, {}
    for _, x in ipairs(sorted) do
        if not x.gain then
            lost[x.slot] = lost[x.slot] or {}
            table.insert(lost[x.slot], x)
        end
    end
    local moves, gains = {}, {}
    for _, x in ipairs(sorted) do
        if x.gain then
            local from = lost[x.slot] and table.remove(lost[x.slot], 1)
            if from then
                paired[from] = true
                moves[#moves + 1] = text(x, format("%%s: group %d -> group %d", from.g, x.g))
            else
                gains[#gains + 1] = { "+ " .. text(x, format("%%s for group %d", x.g)), T.ACCENT[1], T.ACCENT[2],
                                      T.ACCENT[3] }
            end
        end
    end
    local lines = {}
    for _, l in ipairs(moves) do lines[#lines + 1] = l end
    for _, l in ipairs(gains) do lines[#lines + 1] = l end
    for _, x in ipairs(sorted) do
        if not x.gain and not paired[x] then
            lines[#lines + 1] = T.line("- " .. text(x, format("%%s for group %d", x.g)), "bad")
        end
    end
    return lines
end
P.changeLines = changeLines

-- Whether anyone online in `list` wants party buff `x`. Any aura the party
-- wants will do, but Concentration Aura set by hand on a melee party is red.
function P.partyWants(list, x)
    for _, m in ipairs(list) do
        if m.online and Du.wants(m, x.b) then return true end
    end
    return false
end

-- The tooltip of a party buff in party `g`'s header, `x` from
-- partyBuffsOf: who gives it there and why.
function P.partyBuffTip(owner, g, x)
    local lines = {}
    if x.unwanted then lines[1] = T.line("Nobody here wants it.", "bad") end
    for _, a in ipairs(x.list) do
        lines[#lines + 1] = { "From " .. NS.who(a.giver), 1, 1, 1 }
        if a.why then lines[#lines + 1] = a.why end
        if a.note then lines[#lines + 1] = a.note end
    end
    C.spellTip(owner, x.b, Tr.title(x.b), lines)
end

local function gapTip(owner, gap)
    local s = gap.slot
    local class = NS.className(gap.b.class):lower()
    local lines = { format(s.who, gap.n) }
    if gap.here then
        lines[2] = format("The %s here isn't giving it.", class)
    elseif gap.fix then
        lines[2] = T.line(format("Nobody in this group gives it. Move %s here.", article(class)), "bad")
    else
        lines[2] = format("%d %s for %d %s.", gap.givers, gap.givers == 1 and class or NS.classWord(gap.b.class),
                          gap.parties, gap.parties == 1 and "group" or "groups")
        lines[3] = "Moving one would take it from another group."
    end
    T.tip(owner, "No " .. s.word, lines)
end

-- The tooltip of a party buff in a preview's header: `it` is { slot, b,
-- state }, and `state` says whether party `g` gets it, keeps it or loses it
-- with the moves.
local PREVIEW_SAYS = { gain = "Group %d gets it with the moves.", keep = "Group %d keeps it.",
                       lose = "Group %d loses it with the moves." }

local function previewTip(owner, g, it)
    local word = it.slot.word:sub(1, 1):upper() .. it.slot.word:sub(2)
    local sign = it.state == "gain" and "+" or it.state == "lose" and "-" or ""
    local line = format(PREVIEW_SAYS[it.state], g)
    T.tip(owner, sign .. word, { it.state == "gain" and { line, T.ACCENT[1], T.ACCENT[2], T.ACCENT[3] }
                                 or it.state == "lose" and T.line(line, "bad") or line })
end

-- The spec of `class` a buff is best from, for the strip's tips: the
-- talent tree it needs, else the first the job prefers.
local BEST = { windfury = "enhancement", strengthofearth = "enhancement", graceofair = "enhancement" }

local function bestTree(job, b)
    if b.talent then return b.talent, true end
    local key = BEST[b.id]
    if key then return R.treeOfKey(b.class, key), false end
    -- A job that prefers every spec of the class has no best.
    local first, n = nil, 0
    for _, p in ipairs(job.prefer or {}) do
        local tree = R.treeOfKey(b.class, p)
        if tree then
            first = first or tree
            n = n + 1
        end
    end
    if n < #(D.SPECS[b.class] or {}) then return first, false end
end

-- The buffs and debuffs the raid wants, for the strip over the parties, in
-- page order (the buffs before the debuffs), as { job, list, title, ok,
-- debuff }. A job of options from different classes (Sunder Armor or
-- Expose Armor) is one, and lit when anyone can give any of them. Party buffs are in each party's header instead, and an
-- optional buff, a resistance or a job that's off isn't here.
--
-- Two buffs that exclude each other are one icon, the first of the job's.
-- Windfury and Flametongue Totem never both apply, so the icon is Windfury.
-- But while no shaman is level 32 for Windfury, it's Flametongue, which the
-- melee take until then.
function P.coverage(members)
    members = members or R.list()
    local function gives(b)
        for _, m in ipairs(members) do
            if Du.canGive(m, b) then return true end
        end
        return false
    end
    local t, seen = {}, {}
    for _, job in ipairs(D.JOBS) do
        if job.kind ~= "resist" and job.scope ~= "party" and Du.enabled(job) then
            local together = job.scope == "target" and #job.options > 1
            local sets = {}
            for _, id in ipairs(job.options) do
                local b = D.BY_ID[id]
                local other = b.excludes and seen[b.excludes]
                if other and not b.optional and not gives(other[1]) and gives(b) then
                    other[1] = b
                elseif not b.optional and not b.party and not other then
                    if together then
                        sets[1] = sets[1] or {}
                        table.insert(sets[1], b)
                    else
                        sets[#sets + 1] = { b }
                    end
                    seen[id] = sets[#sets]
                end
            end
            for _, list in ipairs(sets) do
                local wanted, ok = false, false
                for _, m in ipairs(members) do
                    for _, b in ipairs(list) do
                        wanted = wanted or (m.online and Du.wants(m, b))
                        ok = ok or Du.canGive(m, b)
                    end
                end
                if wanted then
                    t[#t + 1] = { job = job, list = list, ok = ok, debuff = list[1].debuff,
                                  title = together and Du.title(job) or Tr.title(list[1]) }
                end
            end
        end
    end
    -- The buffs come first and the debuffs after them, each in the order
    -- of the assignments, so the strip can show them on rows of their own.
    local buffs, debuffs = {}, {}
    for _, x in ipairs(t) do table.insert(x.debuff and debuffs or buffs, x) end
    for _, x in ipairs(debuffs) do buffs[#buffs + 1] = x end
    return buffs
end

-- Where each icon of the strip goes, as { col, row } from 0, with `per`
-- icons to a row. The buffs fill rows of their own, and the debuffs start
-- on the row under them. Also returns how many rows that takes.
function P.stripSpots(cover, per)
    local spots, col, row = {}, 0, 0
    for i, x in ipairs(cover) do
        if col >= per or (i > 1 and x.debuff and not cover[i - 1].debuff) then
            col, row = 0, row + 1
        end
        spots[i] = { col, row }
        col = col + 1
    end
    return spots, #cover > 0 and row + 1 or 1
end

-- What a red icon of the strip says to do: "Add a shaman (Enhancement is
-- best)", or "Add a Marksmanship hunter" for a talent.
-- When the class is here but too low, it says so instead: "No shaman here
-- is level 32 yet."
function P.coverageHint(x)
    local classes, seen, ids = {}, {}, {}
    for _, b in ipairs(x.list) do
        ids[#ids + 1] = b.id
        if not seen[b.class] then
            seen[b.class] = true
            classes[#classes + 1] = article(NS.className(b.class):lower())
        end
    end
    local low = Du.lowWhy(seen, R.list(), ids)
    if low then return low end
    local b = x.list[1]
    local tree, needed = bestTree(x.job, b)
    if needed and #classes == 1 then return format("Add %s.", article(specWords(b.class, tree))) end
    local text = "Add " .. table.concat(classes, " or ")
    if tree and #classes == 1 then text = format("%s (%s is best)", text, C.specName(b.class, tree)) end
    return text .. "."
end

local function coverageTip(owner, x)
    local lines = {}
    if x.ok then
        local who = {}
        for _, m in ipairs(R.list()) do
            for _, b in ipairs(x.list) do
                if Du.canGive(m, b) and not who[m.name] then
                    who[m.name] = true
                    who[#who + 1] = NS.who(m)
                end
            end
        end
        lines[1] = "Can give it: " .. table.concat(who, ", ")
        C.spellTip(owner, x.list[1], x.title, lines)
    else
        T.tip(owner, "No " .. x.title, { T.line(P.coverageHint(x), "bad") })
    end
end

-- How many tanks and healers a raid of `size` wants, as { fewest, most }.
function P.roleTarget(size, role)
    local t = ROLE_TARGET[size]
    if not t then
        for _, n in ipairs(Mo.SIZES) do
            if n >= size then
                t = ROLE_TARGET[n]
                break
            end
        end
    end
    t = t or ROLE_TARGET[40]
    -- A mock raid never wants more than 3 tanks (Mock.lua).
    if NS.mock and role == "TANK" then return { min(t.TANK[1], 3), min(t.TANK[2], 3) } end
    return t[role]
end

-- =============================================================
-- A player's menu and tooltip
-- =============================================================
-- The tree of `class` with the role `role`, else its first: for a player
-- who changes class and should keep tanking or healing.
local function treeFor(class, role)
    for tree, s in ipairs(D.SPECS[class] or {}) do
        if s.role == role then return tree end
    end
    return 1
end

-- The remembered players in a submenu, by class, each calling `fn(p)`.
local function rememberedEntries(menu, fn)
    local away = R.remembered()
    table.sort(away, function(a, b)
        if a.class ~= b.class then return (a.class or "") < (b.class or "") end
        return a.name < b.name
    end)
    local last
    for _, p in ipairs(away) do
        if p.class and D.SPECS[p.class] then
            if p.class ~= last then
                menu:CreateTitle(NS.classText(p.class, NS.className(p.class)))
                last = p.class
            end
            local spec = R.spec(p.class, p.spec) and " " .. DIM .. C.specName(p.class, p.spec) .. "|r" or ""
            menu:CreateButton(NS.who(p) .. spec, function() fn(p) end)
        end
    end
    return #away
end

-- The assignments `m` can give, under "Assign to": a check for each, on
-- when it's set by hand to them. They change the board the way the
-- Assignments page does, so a player who may only suggest drafts them.
local function assignEntries(menu, m)
    local key, section, any = "name:" .. m.name, nil, false
    local function head(job)
        if job.section ~= section then
            section = job.section
            menu:CreateTitle(section)
        end
        any = true
    end
    local function picked(job)
        local p = Du.picks(job.id)
        return p ~= nil and p[key] == true
    end
    -- What auto has them give now says so, since it isn't ticked.
    local function label(job, b)
        local plan = Du.shown(job.id)
        for _, a in ipairs(plan and plan.active and plan.list or {}) do
            if a.giver.name == m.name and a.buff == b and not a.hand then
                return NS.buffText(b) .. " " .. T.DIM .. "(auto)|r"
            end
        end
        return NS.buffText(b)
    end
    for _, job in ipairs(D.JOBS) do
        if job.kind == "totem" then
            for _, id in ipairs(job.options) do
                local b = D.BY_ID[id]
                if Du.canGive(m, b) then
                    head(job)
                    menu:CreateCheckbox(label(job, b), function() return Du.totem(m.name, b.element) == id end,
                                        function()
                                            local on = Du.totem(m.name, b.element) == id
                                            Du.setTotem(m.name, b.element, not on and id or nil)
                                        end)
                end
            end
        elseif job.kind == "choice" then
            for _, id in ipairs(job.options) do
                local b = D.BY_ID[id]
                if Du.canGive(m, b) then
                    head(job)
                    local function on() return picked(job) and Du.choice(job.id, m.name) == id end
                    menu:CreateCheckbox(label(job, b), on, function()
                        if on() then
                            Du.setChoice(job.id, m.name, nil)
                            Du.setPick(job.id, key, false)
                        else
                            Du.setPick(job.id, key, true)
                            Du.setChoice(job.id, m.name, id)
                        end
                    end)
                end
            end
        elseif job.kind == "cover" or job.kind == "single" then
            for _, id in ipairs(job.options) do
                local b = D.BY_ID[id]
                if Du.canGive(m, b) then
                    head(job)
                    menu:CreateCheckbox(label(job, b), function() return picked(job) end,
                                        function() Du.setPick(job.id, key, not picked(job)) end)
                    break
                end
            end
        end
    end
    return any
end

-- What we learned of `m`'s spec, in words: "Their addon says Fury." nil
-- when it's what they have.
local SAYS = { told = "Their addon says %s.", fojji = "FojjiCore says %s.", talents = "Your talents say %s.",
               role = "Their raid role says %s." }

local function learnedText(m)
    if m.specFrom ~= "set" or not m.learned or m.learned == m.spec then return nil end
    return format(SAYS[m.learnedFrom] or "Detected as %s.", C.specName(m.class, m.learned))
end

-- The items of the group that combat blocks, greyed, so the menu says
-- they're there.
local function lockedEntries(root, m)
    root:CreateTitle(LOCKED)
    root:CreateButton(DIM .. "Move to|r")
    if not m.me and R.raid() then root:CreateButton(DIM .. "Remove from group|r") end
end

-- Whether player `m`'s menu would have anything in it but their name.
local function hasMenu(m)
    if canChange() or (NS.mock and not m.me) then return true end
    return G.canRole(m) or G.canMark() or (G.canPromote() and not m.me and (m.rank or 0) < 2) or G.canArrange()
           or (G.mayArrange() and R.raid()) or G.canRemove(m) or (G.locked() and G.mayArrange())
end

-- Everything we may change about player `m`: who they are (their spec, and
-- in a mock raid their class and name), what they're assigned to, and
-- their place in the group. A raider who may change
-- none of it gets no menu, rather than one with only the name.
function P.menu(owner, m)
    if not hasMenu(m) then return nil end
    local specOK = canChange()
    return T.menu(owner, function(_, root)
        root:CreateTitle(NS.who(m))
        local made = NS.mock and not m.me
        if made or specOK then
            local spec = root:CreateButton("Spec: " .. specWords(m.class, m.spec))
            if not made then
                spec:CreateRadio("Auto",
                                 function() return NS.edited().specs[m.name] == nil end,
                                 function() R.setSpec(m.name, nil) end)
            end
            for tree = 1, 3 do
                spec:CreateRadio(NS.specText(m.class, tree, C.specName(m.class, tree)),
                                 function() return NS.edited().specs[m.name] == tree end,
                                 function()
                                     if made then Mo.setClass(m.name, m.class, tree) else R.setSpec(m.name, tree) end
                                 end)
            end
            local theirs = learnedText(m)
            if theirs and specOK then
                root:CreateButton("Back to auto: " .. C.specName(m.class, m.learned), function() R.setSpec(m.name, nil) end)
            end
        end
        if made then
            local class = root:CreateButton("Change class")
            -- A radio reads the roster again, since a change makes new members.
            local function now() return R.byName(m.name) or m end
            for _, c in ipairs(CLASSES) do
                class:CreateRadio(NS.classText(c, NS.classColored(NS.className(c), c)),
                                  function() return now().class == c end,
                                  function() Mo.setClass(m.name, c, treeFor(c, now().role)) end)
            end
            root:CreateButton("Rename", function()
                T.ask("Name this player, as \"First Last\":", m.name, function(name)
                    if not Mo.rename(m.name, name) then NS.print("%s is in the raid already.", name) end
                end)
            end)
            local swap = root:CreateButton("Replace with")
            if rememberedEntries(swap, function(p) Mo.replace(m.name, p) end) == 0 then
                swap:CreateTitle("Nobody remembered")
            end
        end
        if specOK then
            local assign = root:CreateButton("Assign to")
            if not assignEntries(assign, m) then assign:CreateTitle("Nothing they can give") end
        end

        local group = {}
        if G.canRole(m) then
            group[#group + 1] = function()
                local role = root:CreateButton("Role: " .. (m.assigned and ROLE_NAME[m.assigned] or "none"))
                for _, r in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
                    role:CreateRadio(ROLE_NAME[r], function() return m.assigned == r end, function() G.role(m, r) end)
                end
                role:CreateRadio("None", function() return m.assigned == nil end, function() G.role(m, nil) end)
            end
        end
        if G.canMark() then
            group[#group + 1] = function()
                for _, mark in ipairs({ "MAINTANK", "MAINASSIST" }) do
                    root:CreateCheckbox(format("|T%s:14:14|t %s", MARK_TEX[mark], MARK_NAME[mark]),
                                        function() return m.mark == mark end,
                                        function() G.mark(m, mark, m.mark ~= mark) end)
                end
            end
        end
        if G.canPromote() and not m.me and (m.rank or 0) < 2 then
            group[#group + 1] = function()
                -- A party has no assistants.
                if R.raid() then
                    root:CreateCheckbox("Assistant", function() return (m.rank or 0) >= 1 end,
                                        function() G.assist(m, (m.rank or 0) < 1) end)
                end
                root:CreateButton("Make leader", function() G.lead(m) end)
            end
        end
        if G.canArrange() then
            group[#group + 1] = function()
                -- A full party takes them only by a swap, so it opens a menu
                -- of who is there to swap with.
                local move = root:CreateButton("Move to")
                local count = {}
                for _, x in ipairs(R.list()) do count[x.group] = (count[x.group] or 0) + 1 end
                for g = 1, 8 do
                    if (count[g] or 0) >= 5 and m.group ~= g then
                        move:CreateButton(format("Group %d  %s(full, swap)|r", g, DIM),
                                          function() P.swapMenu(owner, m, g) end)
                    else
                        move:CreateRadio(format("Group %d", g), function() return m.group == g end,
                                         function() G.move(m, g) end)
                    end
                end
            end
        end
        if G.mayArrange() and R.raid() then
            group[#group + 1] = function()
                root:CreateCheckbox("Keep in this group", function() return Ar.pinned(m.name) end,
                                    function() Ar.pin(m.name, not Ar.pinned(m.name)) end)
            end
        end
        if G.canRemove(m) then
            group[#group + 1] = function()
                root:CreateButton(NS.mock and "Remove" or "Remove from group", function() G.remove(m) end)
            end
        end
        if G.locked() and G.mayArrange() then
            group[#group + 1] = function() lockedEntries(root, m) end
        end
        if #group > 0 and (specOK or NS.mock) then root:CreateDivider() end
        for _, add in ipairs(group) do add() end
    end)
end

-- Who `m` can swap with in full party `g`, in a menu of its own.
function P.swapMenu(owner, m, g)
    local list = {}
    for _, x in ipairs(R.list()) do
        if x.group == g then list[#list + 1] = x end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return T.menu(owner, function(_, root)
        root:CreateTitle(format("Swap with someone in group %d", g))
        for _, x in ipairs(list) do
            root:CreateButton(NS.who(x), function() G.swap(m, x) end)
        end
    end)
end

local FROM = { set = "an override", talents = "your talents", told = "their addon",
               fojji = "FojjiCore", role = "their raid role" }

function P.tip(owner, m)
    local lines = {}
    local who = (m.spec and C.specName(m.class, m.spec) .. " " or "") .. NS.className(m.class)
    if m.level then who = format("Level %d %s", m.level, who) end
    lines[1] = { who .. (m.me and ", you" or ""), 1, 1, 1 }
    local theirs = learnedText(m)
    if theirs and not NS.mock then
        lines[#lines + 1] = T.line(format("Overridden to %s. %s", C.specName(m.class, m.spec), theirs), "hand")
    elseif m.spec and not NS.mock then
        lines[#lines + 1] = format("Spec from %s", FROM[m.specFrom] or "?")
    end
    if not m.spec then lines[#lines + 1] = "Spec unknown" end
    local place = {}
    if (m.rank or 0) >= 2 then place[#place + 1] = "Leader" elseif (m.rank or 0) == 1 then place[#place + 1] = "Assistant" end
    if m.mark then place[#place + 1] = MARK_NAME[m.mark] end
    if m.assigned then place[#place + 1] = ROLE_NAME[m.assigned] .. " role" end
    if #place > 0 then lines[#lines + 1] = table.concat(place, ", ") end
    if Ar.pinned(m.name) and R.raid() then lines[#lines + 1] = "Kept in this group." end
    if proposal and proposal.moved[m.name] then
        lines[#lines + 1] = { format("Moves here from group %d.", proposal.moved[m.name]), T.ACCENT[1], T.ACCENT[2],
                              T.ACCENT[3] }
    end
    local match = proposal and proposal.matchOf and proposal.matchOf[m.name]
    if match then
        lines[#lines + 1] = { format("In the plan as %s (%s).", match.from, match.what), T.ACCENT[1], T.ACCENT[2],
                              T.ACCENT[3] }
    end
    if not m.online then lines[#lines + 1] = T.line("Offline", "idle") end
    if m.dead then lines[#lines + 1] = T.line("Dead", "bad") end
    if m.zone then lines[#lines + 1] = m.zone end
    if NS.Suggest.specChanged(m.name) then lines[#lines + 1] = T.line("The draft changes their spec.", "changed") end
    if not NS.mock and not m.me then
        local addon = NS.Sync and NS.Sync.hasAddon(m.name)
        lines[#lines + 1] = addon and "Has the addon." or "Gets assignments by whisper."
    end
    local list = shownAssignments(m)
    for i, x in ipairs(list) do
        lines[#lines + 1] = { (i == 1 and "Assigned: " or "            ") .. NS.buffText(x.b, x.title), 1, 1, 1 }
    end
    if #list == 0 then lines[#lines + 1] = "No assignments." end
    local hints = {}
    if hasMenu(m) then hints[#hints + 1] = { "Click", "change them" } end
    if G.canArrange() then
        hints[#hints + 1] = { "Drag", R.raid() and "move or swap (green gains party buffs)" or "move or swap" }
    end
    if G.locked() and G.mayArrange() then lines[#lines + 1] = T.line(LOCKED .. ".", "bad") end
    T.tip(owner, NS.who(m), lines, #hints > 0 and hints or nil)
end

-- The tooltip of one of `m`'s assignment icons, `x` from assignmentsOf:
-- the spell, then what it covers and why they have it. `x.more` is the
-- assignments that didn't fit.
function P.assignmentTip(owner, m, x)
    if x.more then
        local lines = {}
        for _, y in ipairs(x.more) do lines[#lines + 1] = { NS.buffText(y.b, y.title), 1, 1, 1 } end
        T.tip(owner, format("%d more", #x.more), lines)
        return
    end
    local a, lines = x.a, {}
    if a.bless then
        local list, hand = {}, {}
        for class, id in pairs(a.byClass or {}) do
            list[#list + 1] = { NS.className(class) .. "s", Tr.title(D.BY_ID[id]) }
            if Du.blessing(m.name, class) then hand[#hand + 1] = NS.classWord(class) end
        end
        table.sort(list, function(p, q) return p[1] < q[1] end)
        for _, l in ipairs(list) do lines[#lines + 1] = { l[1] .. ": " .. l[2], 1, 1, 1 } end
        local singles = 0
        for name, id in pairs(a.bless) do
            local who = R.byName(name)
            if not (who and a.byClass and a.byClass[who.class] == id) then singles = singles + 1 end
        end
        if singles > 0 then lines[#lines + 1] = { format("Plus %d single blessings", singles), 1, 1, 1 } end
        table.sort(hand)
        lines[#lines + 1] = #hand > 0 and format("Overridden for %s.", table.concat(hand, ", "))
                            or "Auto: the paladins share out the classes."
    else
        if a.party and R.raid() then lines[#lines + 1] = { format("For group %d", a.party), 1, 1, 1 } end
        if a.why then lines[#lines + 1] = a.why end
        if a.except then lines[#lines + 1] = format("Only for those without %s.", Tr.title(a.except)) end
        if a.note then lines[#lines + 1] = a.note end
    end
    C.spellTip(owner, x.b, x.title, lines)
end

-- =============================================================
-- Dragging
-- =============================================================
-- What a drop of `m` on `target` does: onto a player in another party it
-- swaps the two, and onto a party with room it moves them there. Returns
-- whether anything changed.
function P.drop(m, target)
    if not (m and target) then return false end
    if (target.m or target.g) and G.locked() then
        NS.print(LOCKED .. ".")
        return false
    end
    if target.m then
        if target.m == m or target.m.group == m.group then return false end
        return G.swap(m, target.m) and true or false
    end
    if target.g and target.g ~= m.group then
        if G.move(m, target.g) then return true end
        NS.print("Group %d is full. Drop them on a player to swap.", target.g)
    end
    return false
end

-- Frames outside the pane that take a dragged player, like an assignment's
-- tile: { frame, fn }. A drop on one calls `fn(m, shift)`. The parties
-- come first, so a drop on a party is always a move.
local targets = {}

function P.addDropTarget(frame, fn)
    for _, t in ipairs(targets) do
        if t.frame == frame then
            t.fn = fn
            return
        end
    end
    targets[#targets + 1] = { frame = frame, fn = fn }
end

local function dropTarget()
    for _, t in ipairs(targets) do
        local f = t.frame
        if f:IsVisible() and f:IsMouseOver() then return t end
    end
end

-- Whether a drag on a player picks them up: when we may move players
-- (now or after combat), or when something else takes them.
local function canDrag()
    return G.mayArrange() or (#targets > 0 and canChange())
end

local dragging, ghost, moving
-- While we drag, how much each party's score would change with the
-- dragged player in it (Arrange.lua). A full party takes them only by a
-- swap, so it has the best swap's.
local gains = {}

-- What's under the mouse: a player's row, else a party's box.
local function hovered()
    local page = pane and pane.page
    if not page or not page.pools then return nil end
    for _, r in ipairs(page.pools.paneRow or {}) do
        if r:IsShown() and r.m and r:IsMouseOver() then return { m = r.m, box = r.box } end
    end
    for _, b in ipairs(page.pools.paneBox or {}) do
        if b:IsShown() and b:IsMouseOver() then return { g = b.g, box = b } end
    end
end

-- What dropping the dragged player on `h` (from hovered) would do, as
-- { gain, words }: a swap with the player under the mouse, or a move into a
-- party with room. nil when the drop does nothing.
local function dropEffect(h)
    if not (h and dragging and R.raid() and G.canArrange()) then return nil end
    local m, want = dragging, nil
    if h.m then
        if h.m ~= m and h.m.group ~= m.group then want = { [m.name] = h.m.group, [h.m.name] = m.group } end
    elseif h.g and h.g ~= m.group then
        local n = 0
        for _, x in ipairs(R.list()) do
            if x.group == h.g then n = n + 1 end
        end
        if n < 5 then want = { [m.name] = h.g } end
    end
    if not want then return nil end
    local members = R.list()
    return { gain = Ar.gainOf(members, want), words = P.changeWords(Ar.changes(members, want), 2) }
end

-- The ghost's words: who we drag, and what the drop under the mouse does
-- to the party buffs.
local function ghostText(effect)
    local text = colored(dragging) .. (G.locked() and "  " .. DIM .. LOCKED .. "|r" or "")
    if effect and effect.words then text = text .. "  " .. DIM .. effect.words .. "|r" end
    ghost.text:SetText(text)
    ghost:SetWidth(max(BOX_W - 8, (ghost.text:GetStringWidth() or 0) + 14))
end

-- Paints the parties while we drag. The party under the mouse (`lit`)
-- takes the colour of what the drop there does, `effect` from dropEffect.
local function paintBoxes(lit, effect)
    for _, b in ipairs(pane.page.pools and pane.page.pools.paneBox or {}) do
        local gain = dragging and gains[b.g] or 0
        if b == lit then
            local v = effect and effect.gain or 0
            T.paint(b, v > 1e-6 and T.COLOR.up or v < -1e-6 and T.COLOR.bad or T.ACCENT, 0.9)
        elseif gain > 1e-6 then
            T.paint(b, T.COLOR.up, 0.6)
        elseif gain < -1e-6 then
            T.paint(b, T.COLOR.bad, 0.6)
        else
            T.paint(b, { 1, 1, 1 }, 0.08)
        end
    end
end

local function makeGhost()
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(BOX_W - 8, ROW_H)
    ghost.bg = T.fill(ghost, { 0.08, 0.09, 0.11 }, 0.92)
    ghost.bg:SetAllPoints(ghost)
    T.border(ghost, T.ACCENT, 0.9)
    ghost.text = T.text(ghost, T.SIZE.body, false)
    ghost.text:SetPoint("LEFT", ghost, "LEFT", 6, 0)
    ghost:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / s + 8, y / s)
        local h = hovered()
        -- What a drop does only changes when the mouse goes to another
        -- player or party, so we work it out then.
        local key = h and (h.m or h.g) or nil
        if key ~= self.key then
            self.key = key
            self.effect = dropEffect(h)
            ghostText(self.effect)
        end
        paintBoxes(h and h.box, self.effect)
    end)
    ghost:Hide()
end

local function dragStart(row)
    if not row.m or not canDrag() then
        moving = true
        C.startMoving()
        return
    end
    -- While a proposal shows, the boxes show its parties, not the raid's, and
    -- a drop would act on parties we can't see. So picking a player up
    -- cancels it.
    if proposal then P.cancelProposal() end
    dragging = row.m
    gains = {}
    if R.raid() and not G.locked() then
        local members, count = R.list(), {}
        for _, x in ipairs(members) do count[x.group] = (count[x.group] or 0) + 1 end
        Ar.weighOnce(function()
            for g = 1, 8 do gains[g] = partyGain(row.m, g, members, count) end
        end)
    end
    if not ghost then makeGhost() end
    ghost.key, ghost.effect = nil, nil
    ghostText(nil)
    ghost:SetAlpha(G.locked() and 0.45 or 1)
    ghost:Show()
    GameTooltip:Hide()
end

local function dragStop()
    if moving then
        moving = nil
        C.stopMoving()
    end
    if not dragging then return end
    local m = dragging
    dragging = nil
    if ghost then ghost:Hide() end
    paintBoxes(nil)
    local h = hovered()
    if h then
        if G.mayArrange() then P.drop(m, h) end
        return
    end
    local t = dropTarget()
    if t then t.fn(m, _G.IsShiftKeyDown and IsShiftKeyDown() and true or false) end
end

-- =============================================================
-- Frames
-- =============================================================
local function makeBox(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(BOX_W, BOX_H)
    b.bg = T.fill(b, { 1, 1, 1 }, 0.025)
    b.bg:SetAllPoints(b)
    T.border(b, { 1, 1, 1 }, 0.08)
    b.title = T.text(b, T.SIZE.label, false, T.A_TEXT)
    b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -4)
    b.add = T.button(b, "+", 18, 16)
    b.add:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -2)
    -- How many are in the party, right after the title: "Group 1 (3/5)".
    b.count = T.text(b, T.SIZE.caption, false, T.A_DIM)
    b.count:SetPoint("LEFT", b.title, "RIGHT", 4, 0)
    -- The party buffs, on the header's right side, and the empty places for
    -- those it wants. Each has its own tooltip, and a drag on one moves the window,
    -- like a drag on the box.
    b.buffs = {}
    for i = 1, BUFFS do
        local f = CreateFrame("Button", nil, b)
        f:SetSize(BUFF, BUFF)
        f.tex = T.icon(f, nil, BUFF)
        f.tex:SetPoint("CENTER", f, "CENTER", 0, 0)
        T.border(f, T.COLOR.bad, 0, "OVERLAY")
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnEnter", function(self)
            if dragging then return end
            if self.gap then
                gapTip(self, self.gap)
            elseif self.pv then
                previewTip(self, b.g, self.pv)
            elseif self.x then
                P.partyBuffTip(self, b.g, self.x)
            end
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:SetScript("OnDragStart", function() C.startMoving() end)
        f:SetScript("OnDragStop", function() C.stopMoving() end)
        b.buffs[i] = f
    end
    return b
end

local function rowColor(r, hover)
    local c = r.tint
    if c then
        r.bg:SetColorTexture(c[1], c[2], c[3], hover and 0.30 or 0.18)
    else
        r.bg:SetColorTexture(1, 1, 1, hover and 0.07 or 0.03)
    end
end

local function makeRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(BOX_W - 6, ROW_H)
    r.bg = T.fill(r, { 1, 1, 1 }, 0.03)
    r.bg:SetAllPoints(r)
    -- The spec's icon, with the raid role they were given in its corner.
    r.spec = T.icon(r, nil, ICON)
    r.spec:SetPoint("LEFT", r, "LEFT", 3, 0)
    -- The leader's crown or an assistant's star, on top of the spec icon and
    -- a little into it, so the rows keep no room for it.
    --
    -- It reaches up into the row above, so it lives on a frame of its own a
    -- few levels up. Otherwise the row above could draw over it.
    r.over = CreateFrame("Frame", nil, r)
    r.over:SetAllPoints(r)
    r.over:SetFrameLevel(r:GetFrameLevel() + 5)
    r.rank = r.over:CreateTexture(nil, "OVERLAY", nil, 7)
    r.rank:SetSize(10, 10)
    r.rank:SetPoint("BOTTOM", r.spec, "TOP", 0, -4)
    r.role = r:CreateTexture(nil, "OVERLAY", nil, 7)
    r.role:SetSize(12, 12)
    r.role:SetPoint("CENTER", r.spec, "BOTTOMRIGHT", -1, 2)
    r.name = T.text(r, T.SIZE.body, false)
    r.name:SetPoint("LEFT", r.spec, "RIGHT", 5, 0)
    r.name:SetWordWrap(false)
    r.name:SetJustifyH("LEFT")
    -- Small marks after the name: main tank or assist, a "?" when we don't
    -- know their spec, a dot when it was set by hand, and a pin when they're
    -- kept in their party.
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetSize(12, 12)
    r.unknown = T.text(r, T.SIZE.label, true, T.A_DIM)
    r.unknown:SetText("?")
    r.set = r:CreateTexture(nil, "ARTWORK")
    r.set:SetTexture(DOT)
    r.set:SetSize(6, 6)
    r.pin = r:CreateTexture(nil, "ARTWORK")
    r.pin:SetTexture(PIN)
    r.pin:SetSize(11, 11)
    r.pin:SetVertexColor(1, 1, 1, T.A_DIM)
    -- The assignment icons, from the right. Each has its own tooltip, and
    -- clicks and drags go on to the row. "+2" after them says there are
    -- more than fit, and its tooltip has them.
    local function slot(w)
        local b = CreateFrame("Button", nil, r)
        b:SetSize(w, ICON)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnEnter", function(self)
            rowColor(r, true)
            if self.x and r.m and not dragging then P.assignmentTip(self, r.m, self.x) end
        end)
        b:SetScript("OnLeave", function()
            rowColor(r, false)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function() if r.m then P.menu(r, r.m) end end)
        b:SetScript("OnDragStart", function() dragStart(r) end)
        b:SetScript("OnDragStop", dragStop)
        T.dragCursor(b, function() return r.m ~= nil and canDrag() end)
        return b
    end
    r.icons = {}
    for i = 1, ICONS do
        local b = slot(ICON)
        b.tex = T.icon(b, nil, ICON)
        b.tex:SetPoint("CENTER", b, "CENTER", 0, 0)
        r.icons[i] = b
    end
    r.more = slot(MORE)
    r.more:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.more.text = T.text(r.more, T.SIZE.caption, true, T.A_TEXT)
    r.more.text:SetPoint("CENTER", r.more, "CENTER", 0, 0)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnEnter", function(self)
        rowColor(self, true)
        if self.m and not dragging then P.tip(self, self.m) end
    end)
    r:SetScript("OnLeave", function(self)
        rowColor(self, false)
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self) if self.m then P.menu(self, self.m) end end)
    r:SetScript("OnDragStart", dragStart)
    r:SetScript("OnDragStop", dragStop)
    T.dragCursor(r, function(self) return self.m ~= nil and canDrag() end)
    return r
end

-- Paints row `r` for player `m`. `from` is the party a proposal moves them
-- from.
local function paintRow(r, m, from)
    r.m = m
    r.tint = from and T.ACCENT or nil
    rowColor(r, false)
    r:SetAlpha(m.online and 1 or 0.45)
    local rank = m.rank or 0
    r.rank:SetTexture(rank > 0 and RANK_TEX[min(rank, 2)] or nil)
    r.rank:SetShown(rank > 0)
    P.specIcon(r.spec, m.class, m.spec)
    r.spec:SetDesaturated(m.dead and true or false)
    if m.assigned and ROLE_ATLAS[m.assigned] then roleIcon(r.role, m.assigned) end
    r.role:SetShown(m.assigned ~= nil and ROLE_ATLAS[m.assigned] ~= nil)

    -- The assignments: the first sits leftmost, so the row reads in page
    -- order, and "+2" comes last.
    local list = shownAssignments(m)
    local over = #list > ICONS
    local shown = over and ICONS - 1 or #list
    local right = 2
    if over then
        local rest = {}
        for j = shown + 1, #list do rest[#rest + 1] = list[j] end
        r.more.x = { more = rest }
        r.more.text:SetText(format("+%d", #rest))
        right = right + MORE + 1
    else
        r.more.x = nil
    end
    r.more:SetShown(over)
    for i, t in ipairs(r.icons) do
        local x = i <= shown and list[shown - i + 1] or nil
        t.x = x
        t.tex:SetTexture(x and Tr.icon(x.b) or nil)
        t:SetShown(x ~= nil)
        t:ClearAllPoints()
        t:SetPoint("RIGHT", r, "RIGHT", -right - (i - 1) * (ICON + 1), 0)
    end
    right = right + shown * (ICON + 1)

    -- The marks after the name, and what they leave the name.
    local marks = {}
    r.mark:SetShown(m.mark ~= nil)
    if m.mark then
        r.mark:SetTexture(MARK_TEX[m.mark])
        marks[#marks + 1] = { r.mark, 12 }
    end
    r.unknown:SetShown(m.spec == nil)
    if m.spec == nil then marks[#marks + 1] = { r.unknown, 6 } end
    -- A dot on a spec set by hand, red when what we learned says otherwise.
    -- A mock raid's made-up players are all set by hand, so it says nothing
    -- there.
    local set = m.specFrom == "set" and not NS.mock
    r.set:SetShown(set)
    if set then
        local c = learnedText(m) and T.COLOR.bad or T.COLOR.hand
        r.set:SetVertexColor(c[1], c[2], c[3], 1)
        marks[#marks + 1] = { r.set, 6 }
    end
    local pinned = R.raid() and Ar.pinned(m.name)
    r.pin:SetShown(pinned)
    if pinned then marks[#marks + 1] = { r.pin, 11 } end
    local tail = 0
    for _, x in ipairs(marks) do tail = tail + x[2] + 3 end

    r.name:SetText(colored(m))
    local room = max(20, r:GetWidth() - 26 - 4 - right - tail)
    r.name:SetWidth(room)
    local at = min(r.name:GetStringWidth() or 0, room) + 3
    for _, x in ipairs(marks) do
        x[1]:ClearAllPoints()
        x[1]:SetPoint("LEFT", r.name, "LEFT", at, 0)
        at = at + x[2] + 3
    end
end

-- A glyph that brightens under the mouse, like the close button's x.
local function glyph(parent, text, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b.label = T.text(b, 15, true, T.A_DIM)
    b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
    b.label:SetText(text)
    b:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 1, 1, 1)
        T.tip(self, tip)
    end)
    b:SetScript("OnLeave", function(self)
        self.label:SetTextColor(1, 1, 1, T.A_DIM)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function tipOn(b, title, lines)
    b:SetScript("OnEnter", function(self) T.tip(self, title, lines) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- One icon of the strip of the raid's buffs and debuffs.
local function makeStripIcon(parent)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(STRIP, STRIP)
    f.tex = T.icon(f, nil, STRIP)
    f.tex:SetPoint("CENTER", f, "CENTER", 0, 0)
    T.border(f, T.COLOR.bad, 0, "OVERLAY")
    f:SetScript("OnEnter", function(self) if self.x then coverageTip(self, self.x) end end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

local function build()
    pane = CreateFrame("Frame", nil, win)
    pane:SetWidth(P.WIDTH)
    pane:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
    pane:EnableMouse(true)
    pane:RegisterForDrag("LeftButton")
    pane:SetScript("OnDragStart", C.startMoving)
    pane:SetScript("OnDragStop", C.stopMoving)
    -- A darker strip than the page, like BayovCore's sidebar, and a line
    -- where it ends.
    local shade = T.fill(pane, { 0, 0, 0 }, 0.22, "BACKGROUND", 1)
    shade:SetAllPoints(pane)
    local band = T.fill(pane, { 0, 0, 0 }, 0.35, "BACKGROUND", 2)
    band:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
    band:SetHeight(HEAD_H)
    local edge = T.fill(pane, { 1, 1, 1 }, 0.06, "BORDER")
    edge:SetWidth(1)
    edge:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
    local fold = glyph(pane, "\194\171", "Fold away", function() P.fold(true) end)
    fold:SetPoint("RIGHT", pane, "TOPRIGHT", -6, -HEAD_H / 2)
    pane.title = T.text(pane, T.SIZE.title, false, 1)
    pane.title:SetPoint("LEFT", pane, "TOPLEFT", PAD + 2, -HEAD_H / 2)
    pane.sub = T.text(pane, T.SIZE.body, false, T.A_DIM)
    pane.sub:SetPoint("LEFT", pane.title, "RIGHT", 10, 0)
    pane.sub:SetPoint("RIGHT", fold, "LEFT", -6, 0)
    pane.sub:SetWordWrap(false)
    -- A click on the heading picks the raid's size.
    pane.size = CreateFrame("Button", nil, pane)
    pane.size:SetAllPoints(pane.sub)
    pane.size:SetScript("OnClick", function(self) P.sizeMenu(self) end)
    pane.size:SetScript("OnEnter", function(self)
        T.tip(self, "Raid size", { "What the role counts go by.",
                                   Pl.pickedSize() and format("You picked %d.", Pl.pickedSize())
                                   or "Auto: from the instance, the plan or the group size." },
              { { "Click", "pick a size" } })
    end)
    pane.size:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pane.size:RegisterForDrag("LeftButton")
    pane.size:SetScript("OnDragStart", C.startMoving)
    pane.size:SetScript("OnDragStop", C.stopMoving)

    -- The header's buttons at the right, Mock raid or End mock raid
    -- (pane.mockButtons). A mock raid hides the title for the rest of its
    -- row: its sizes, 5 to 40, as one strip of segments with the size it is
    -- lit, then Empty and Reset.
    pane.mockRow = CreateFrame("Frame", nil, pane)
    pane.mockRow:SetHeight(LINE)
    pane.mockRow:SetPoint("LEFT", pane, "TOPLEFT", PAD, -HEAD_H / 2)
    pane.mockRow:SetPoint("RIGHT", fold, "LEFT", -6, 0)
    pane.mockButtons = {}
    pane.sizes = {}
    for _, n in ipairs(Mo.SIZES) do
        local b = T.segment(pane.mockRow, tostring(n), SIZE_W, LINE)
        b.size = n
        b:SetScript("OnClick", function() Mo.resize(n) end)
        tipOn(b, n == 5 and "A party of 5" or format("A raid of %d", n),
              { format("Add or remove made-up players to reach %d. The rest stay.", n) })
        pane.sizes[#pane.sizes + 1] = b
    end
    local empty = T.button(pane.mockRow, "Empty", nil, LINE)
    empty:SetScript("OnClick", function()
        if #R.list() <= 1 then return end
        T.confirm("Take everyone but you out of the mock raid?", Mo.clear)
    end)
    tipOn(empty, "Empty", { "Just you, in a party." })
    pane.empty = empty
    local reset = T.button(pane.mockRow, "Reset", nil, LINE)
    empty:SetPoint("RIGHT", reset, "LEFT", -4, 0)
    reset:SetScript("OnClick", function() P.resetMock() end)
    tipOn(reset, "Reset", { "Start over with made-up players. Assignments stay." })
    pane.reset = reset

    -- The row of controls: everyone an assistant, the roles, and buttons on
    -- the right.
    pane.controls = CreateFrame("Frame", nil, pane)
    pane.controls:SetHeight(LINE)
    pane.allAssist = T.toggle(pane.controls)
    pane.allAssist:SetPoint("LEFT", pane.controls, "LEFT", 0, 0)
    pane.allAssist:SetScript("OnClick", function() G.setAllAssist(not G.allAssist()) end)
    pane.allAssistLabel = T.text(pane.controls, T.SIZE.body, false, T.A_TEXT)
    pane.allAssistLabel:SetPoint("LEFT", pane.allAssist, "RIGHT", 6, 0)
    pane.allAssistLabel:SetText("All assistants")
    pane.roles = {}
    -- Players whose role we can't tell aren't counted here. The red "? 1"
    -- after the counts says how many there are.
    for i, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        local f = CreateFrame("Frame", nil, pane.controls)
        f:SetSize(36, 20)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(18, 18)
        f.icon:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        roleIcon(f.icon, role)
        f.text = T.text(f, T.SIZE.label, true, T.A_TEXT)
        f.text:SetPoint("RIGHT", f.icon, "LEFT", -3, 0)
        f:EnableMouse(true)
        f.role = role
        pane.roles[i] = f
    end
    pane.buttons = {}

    -- The row of tools: Plans and Arrange, or a proposal's Apply and
    -- Cancel, how many specs we don't know, and the combat lock.
    pane.tools = CreateFrame("Frame", nil, pane)
    pane.tools:SetHeight(LINE)
    pane.toolButtons = {}
    pane.toolText = T.text(pane.tools, T.SIZE.body, false, T.A_TEXT)
    pane.toolText:SetWordWrap(false)
    -- The line may not fit what a preview does, so its tooltip has all of it.
    pane.toolHover = CreateFrame("Frame", nil, pane.tools)
    pane.toolHover:SetAllPoints(pane.toolText)
    pane.toolHover:EnableMouse(true)
    pane.toolHover:SetScript("OnEnter", function(self) P.proposalTip(self) end)
    pane.toolHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pane.toolHover:RegisterForDrag("LeftButton")
    pane.toolHover:SetScript("OnDragStart", C.startMoving)
    pane.toolHover:SetScript("OnDragStop", C.stopMoving)
    -- How many specs we don't know, as "? 1" in red after the role counts,
    -- since those players aren't in them.
    pane.unknown = CreateFrame("Frame", nil, pane.controls)
    pane.unknown:SetHeight(20)
    pane.unknown.text = T.text(pane.unknown, T.SIZE.label, true, 1)
    pane.unknown.text:SetPoint("LEFT", pane.unknown, "LEFT", 0, 0)
    pane.unknown.text:SetTextColor(T.COLOR.bad[1], T.COLOR.bad[2], T.COLOR.bad[3], 1)
    pane.unknown:EnableMouse(true)
    pane.unknown:SetScript("OnMouseUp", function(self) P.unknownMenu(self) end)
    pane.unknown:SetScript("OnEnter", function(self)
        local n = self.count or 0
        T.tip(self, format("%d %s unknown", n, n == 1 and "spec" or "specs"), { "Spec decides what they need and can give.",
                                      "They aren't in the role counts.",
                                      "Click to set them or ask again." })
    end)
    pane.unknown:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pane.lock = CreateFrame("Frame", nil, pane.tools)
    pane.lock:SetSize(150, LINE)
    pane.lock.icon = pane.lock:CreateTexture(nil, "ARTWORK")
    pane.lock.icon:SetSize(14, 14)
    pane.lock.icon:SetPoint("RIGHT", pane.lock, "RIGHT", 0, 0)
    pane.lock.icon:SetTexture(LOCK_TEX)
    pane.lock.text = T.text(pane.lock, T.SIZE.caption, false, 1)
    pane.lock.text:SetPoint("RIGHT", pane.lock.icon, "LEFT", -3, 0)
    pane.lock.text:SetText("In combat")
    pane.lock.text:SetTextColor(T.COLOR.bad[1], T.COLOR.bad[2], T.COLOR.bad[3], 1)
    pane.lock:EnableMouse(true)
    tipOn(pane.lock, "In combat", { LOCKED .. ".", "Moves resume after combat." })

    -- The strip of the raid's buffs and debuffs.
    pane.strip = CreateFrame("Frame", nil, pane)
    pane.strip:SetHeight(STRIP)
    pane.stripIcons = {}

    pane.note = T.text(pane, T.SIZE.body, false, T.A_DIM)
    pane.note:SetWordWrap(true)
    pane.note:SetJustifyH("LEFT")

    local sf = T.scroll(pane)
    sf.child:SetWidth(P.WIDTH - PAD - 12)
    T.scrollShadow(sf)
    pane.scroll = sf
    pane.page = { body = sf.child, scroll = sf }

    -- The thin rail the pane folds into.
    rail = CreateFrame("Frame", nil, win)
    rail:SetWidth(P.RAIL)
    rail:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    rail:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
    rail:EnableMouse(true)
    rail:RegisterForDrag("LeftButton")
    rail:SetScript("OnDragStart", C.startMoving)
    rail:SetScript("OnDragStop", C.stopMoving)
    local rshade = T.fill(rail, { 0, 0, 0 }, 0.30, "BACKGROUND", 1)
    rshade:SetAllPoints(rail)
    local redge = T.fill(rail, { 1, 1, 1 }, 0.06, "BORDER")
    redge:SetWidth(1)
    redge:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)
    redge:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)
    local open = glyph(rail, "\194\187", "Show the raid", function() P.fold(false) end)
    open:SetPoint("TOP", rail, "TOP", 0, -6)
    rail.count = T.text(rail, T.SIZE.caption, true, T.A_DIM)
    rail.count:SetPoint("TOP", open, "BOTTOM", 0, -4)
end

-- Whether the pane is folded away.
function P.folded() return NS.db.window.raidFolded == true end

-- How wide the pane is now, open or folded.
function P.width() return P.folded() and P.RAIL or P.WIDTH end

-- Puts the pane in window `w`, open or folded as it was. Returns the frame
-- the rest of the window sits to the right of.
function P.attach(w)
    win = w
    build()
    pane:SetShown(not P.folded())
    rail:SetShown(P.folded())
    return P.folded() and rail or pane
end

-- Folds the pane away (`on`) or opens it. The window narrows or widens by
-- the difference, at its left, so the assignments don't move.
function P.fold(on)
    on = on and true or false
    if on == P.folded() then return end
    local before = P.width()
    NS.db.window.raidFolded = on or nil
    pane:SetShown(not on)
    rail:SetShown(on)
    C.repane(on and rail or pane, P.width() - before)
end

-- The words over the parties: what the group is, how many it has against
-- how many it's for, and who leads it. Which plan it is, and whether a mock
-- raid has changes its plan doesn't have yet, is the PLAN row's to say.
local function heading(members)
    if NS.mock then
        return R.raid() and "Mock raid" or "Mock party",
               format("%d of %d, only you see it", #members, Pl.raidSize())
    end
    if not R.grouped() then return "Not in a group", "" end
    local lead
    for _, m in ipairs(members) do
        if (m.rank or 0) >= 2 then lead = m end
    end
    local parts = { format("%d of %d", #members, R.raid() and Pl.raidSize(proposal and proposal.plan) or 5) }
    if lead then parts[#parts + 1] = lead.me and "you lead" or colored(lead) .. " leads" end
    return R.raid() and "Raid" or "Party", table.concat(parts, "  ·  ")
end

-- The sizes a real raid can be for, picked by a click on the heading. A
-- raid forming in town has no instance to say, so the head count alone
-- would make a 25 with 12 in it "12 of 15".
function P.sizeMenu(owner)
    return T.menu(owner, function(_, root)
        root:CreateTitle("What size is this raid for?")
        root:CreateRadio("Auto", function() return Pl.pickedSize() == nil end, function() Pl.pickSize(nil) end)
        for _, n in ipairs(Mo.SIZES) do
            if n > 5 then
                root:CreateRadio(format("A raid of %d", n), function() return Pl.pickedSize() == n end,
                                 function() Pl.pickSize(n) end)
            end
        end
    end)
end

-- The first mock raid asks how big it is.
local function startMock(owner)
    if Mo.exists() then return Mo.set(true) end
    T.menu(owner, function(_, root)
        root:CreateTitle("How many is it for?")
        for _, n in ipairs(Mo.SIZES) do
            root:CreateButton(n == 5 and "A party of 5" or format("A raid of %d", n), function() Mo.set(true, n) end)
        end
    end)
end
P.startMock = startMock

-- The buttons at the right of the header: { label, fn, tip, main }.
local function mockButtonsNow()
    if NS.mock then
        return { { "End mock raid", function() Mo.set(false) end,
                   "Back to your real group. The mock raid is kept." } }
    elseif not R.grouped() then
        return { { "Mock raid", startMock, "Plan with a made-up raid. Only you see it.", main = true } }
    end
    return {}
end

-- The buttons at the right of the controls.
local function buttonsNow()
    local list = {}
    if G.canConvert() then
        list[#list + 1] = { "Make a raid", G.convert, "Turn the party into a raid." }
    end
    if G.canReadyCheck() then
        list[#list + 1] = { "Ready check", G.readyCheck, "Ask everyone whether they're ready." }
    end
    return list
end

local function layButtons(parent, store, list, fromRight)
    for _, b in ipairs(store) do b:Hide() end
    local prev
    for i, spec in ipairs(list) do
        local b = store[i]
        if not b then
            b = T.button(parent, "", nil, LINE)
            store[i] = b
        end
        b:SetText(spec[1])
        b:setAccent(spec.main)
        b:SetScript("OnClick", function(self) spec[2](self) end)
        b.tip = function(self)
            T.tip(self, spec[1], type(spec[3]) == "function" and spec[3]() or { spec[3] })
        end
        b:ClearAllPoints()
        if fromRight then
            if prev then b:SetPoint("RIGHT", prev, "LEFT", -6, 0) else b:SetPoint("RIGHT", parent, "RIGHT", 0, 0) end
        else
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT", parent, "LEFT", 0, 0) end
        end
        b:Show()
        prev = b
    end
    return prev
end

-- The tools: Arrange, or what a proposal or the move queue is doing, with
-- its own buttons. A plan's preview has its Use it and Back on the PLAN row,
-- so here it only says what it changes, and offers to invite who's missing.
local function toolsNow()
    local left = G.arranging()
    if left then
        local text = G.locked() and format("%d to move after combat", left) or format("Moving players, %d left", left)
        return text, { { "Stop", G.stopArranging, "Leave everyone where they are now." } }
    end
    if proposal and proposal.plan then
        local name = proposal.plan
        local list = {}
        if proposal.missing > 0 and G.canInvite() then
            list[#list + 1] = { format("Invite %d", proposal.missing), function() P.inviteMissing(name) end,
                                "Invite the plan's players who aren't here. They get their place when they join." }
        end
        return P.planLine(proposal), list
    end
    if proposal then
        return P.arrangeLine(proposal), {
            { "Apply", function() P.applyProposal() end,
              "Move them. In a real raid they move one at a time.", main = true },
            { "Cancel", function() P.cancelProposal() end, "Keep the groups as they are." },
        }
    end
    local list = {}
    if G.mayArrange() and R.raid() then
        list[#list + 1] = { "Arrange", function() P.propose() end, P.arrangeTip }
    end
    return nil, list
end

local function layControls(members)
    -- The header: Mock raid or End mock raid at the right, and a mock
    -- raid's sizes, Empty and Reset where the title was.
    local mr = pane.mockRow
    local leftmost = layButtons(mr, pane.mockButtons, mockButtonsNow(), true)
    local mock = NS.mock == true
    pane.title:SetShown(not mock)
    pane.sub:SetShown(not mock)
    pane.empty:SetShown(mock)
    pane.reset:SetShown(mock)
    for _, b in ipairs(pane.sizes) do b:SetShown(mock) end
    if mock then
        pane.reset:ClearAllPoints()
        pane.reset:SetPoint("RIGHT", leftmost, "LEFT", -6, 0)
        -- The sizes stretch to fill what the buttons leave, so the row spans
        -- the header. The row ends 6 left of the fold glyph, which is 20 wide
        -- and 6 from the edge, and the sizes keep a gap of 6 before Empty.
        local room = P.WIDTH - PAD - (6 + 20 + 6) - 6
        for _, b in ipairs(pane.mockButtons) do
            if b:IsShown() then room = room - b:GetWidth() - 6 end
        end
        room = room - pane.reset:GetWidth() - 4 - pane.empty:GetWidth()
        -- The segments share their edges, so they read as one control. We
        -- place them in whole screen pixels, and they overlap by exactly the
        -- one pixel of their edge. At a UI scale where a pixel isn't one unit,
        -- an overlap of one unit drew a thicker line between two segments
        -- than at the ends, and widths that fell between pixels rounded
        -- differently, so the end segments looked wider than the middle ones.
        local px = T.pixel(mr)
        local n = #pane.sizes
        local w = math.max(2, floor((room + (n - 1) * px) / n / px)) * px
        local now = Mo.raidSize()
        for i, b in ipairs(pane.sizes) do
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("LEFT", mr, "LEFT", (i - 1) * (w - px), 0)
            b:show(b.size == now, true)
        end
    end

    -- The controls come before anything else that comes and goes, so their
    -- buttons keep their place. Out of a group they have nothing to show and
    -- take no room.
    local y = HEAD_H + 4
    local c = pane.controls
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -y)
    c:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -PAD, -y)

    local raid = R.raid()
    pane.allAssist:SetShown(raid)
    pane.allAssistLabel:SetShown(raid)
    if raid then pane.allAssist:show(G.allAssist(), G.canPromote()) end
    local lines = { "Everyone in the raid is an assistant." }
    if not G.canPromote() then lines[2] = G.locked() and LOCKED .. "." or "Only the leader can change it." end
    tipOn(pane.allAssist, "All assistants", lines)

    -- How many of each role, after the toggle in a raid, against what the
    -- raid's size wants.
    local count = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for _, m in ipairs(members) do
        local role = roleOf(m)
        if role then count[role] = count[role] + 1 end
    end
    local size = Pl.raidSize(proposal and proposal.plan)
    -- The counts start just after the label, each as wide as its number.
    local x = 0
    if raid then
        x = pane.allAssist:GetWidth() + 6 + math.ceil(pane.allAssistLabel:GetStringWidth() or 70) + 12
    end
    for _, f in ipairs(pane.roles) do
        local n = count[f.role]
        f:SetShown(R.grouped())
        f.text:SetText(n)
        local want = f.role ~= "DAMAGER" and P.roleTarget(size, f.role)
        local short = want and n < want[1]
        f.text:SetTextColor(short and T.COLOR.bad[1] or 1, short and T.COLOR.bad[2] or 1, short and T.COLOR.bad[3] or 1, T.A_TEXT)
        f:SetWidth(math.ceil(f.text:GetStringWidth() or 12) + 3 + 18)
        f:ClearAllPoints()
        f:SetPoint("LEFT", c, "LEFT", x, 0)
        x = x + f:GetWidth() + 10
        local tip = { "Counted by raid role, else by spec." }
        if want then
            local range = want[1] == want[2] and tostring(want[1]) or format("%d to %d", want[1], want[2])
            table.insert(tip, 1, { format("%s wanted in a %s of %d.", range, size == 5 and "party" or "raid", size),
                                   short and T.COLOR.bad[1] or 1, short and T.COLOR.bad[2] or 1, short and T.COLOR.bad[3] or 1 })
        end
        tipOn(f, format("%d %s", n, f.role == "DAMAGER" and "damage" or ROLE_NAME[f.role]:lower() .. "s"), tip)
    end
    -- Arrange goes on this row too, left of the other buttons, while the
    -- tools have nothing to say. That saves the pane a row.
    local text, list = toolsNow()
    local right = buttonsNow()
    if not text then
        for _, spec in ipairs(list) do right[#right + 1] = spec end
        list = {}
    end
    layButtons(c, pane.buttons, right, true)
    if R.grouped() or #right > 0 then y = y + LINE + LINE_GAP end

    local unknown = 0
    for _, m in ipairs(members) do
        if not m.spec then unknown = unknown + 1 end
    end
    pane.unknown:SetShown(unknown > 0 and R.grouped())
    pane.unknown.count = unknown
    pane.unknown.text:SetText("? " .. unknown)
    pane.unknown:SetWidth(math.ceil(pane.unknown.text:GetStringWidth() or 20))
    pane.unknown:ClearAllPoints()
    pane.unknown:SetPoint("LEFT", c, "LEFT", x, 0)

    -- The tools.
    local t = pane.tools
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -y)
    t:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -PAD, -y)
    pane.toolText:SetShown(text ~= nil)
    pane.toolText:SetText(text or "")
    pane.toolHover:SetShown(proposal ~= nil and text ~= nil)
    pane.toolText:ClearAllPoints()
    if text then
        -- The buttons first, like Arrange where they take its place, then
        -- the line of what it does.
        local rightmost = layButtons(t, pane.toolButtons, list, false)
        if rightmost then
            pane.toolText:SetPoint("LEFT", rightmost, "RIGHT", 8, 0)
        else
            pane.toolText:SetPoint("LEFT", t, "LEFT", 0, 0)
        end
        pane.toolText:SetPoint("RIGHT", t, "RIGHT", 0, 0)
        pane.toolText:SetJustifyH("LEFT")
    else
        layButtons(t, pane.toolButtons, list, false)
    end
    pane.lock:ClearAllPoints()
    pane.lock:SetPoint("RIGHT", t, "RIGHT", 0, 0)
    pane.lock:SetShown(G.locked() and G.mayArrange() and not text)
    -- With nothing to show, like in a party we don't lead, the row takes no
    -- room.
    if text or #list > 0 or pane.lock:IsShown() then
        y = y + LINE + LINE_GAP
    end

    -- The strip.
    local s = pane.strip
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -y)
    s:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -PAD, -y)
    for _, f in ipairs(pane.stripIcons) do f:Hide() end
    local cover = R.grouped() and P.coverage(members) or {}
    local per = floor((P.WIDTH - 2 * PAD + STRIP_GAP) / (STRIP + STRIP_GAP))
    local spots, rows = P.stripSpots(cover, per)
    for i, x in ipairs(cover) do
        local f = pane.stripIcons[i]
        if not f then
            f = makeStripIcon(s)
            pane.stripIcons[i] = f
        end
        f.x = x
        f.tex:SetTexture(Tr.icon(x.list[1]))
        f.tex:SetDesaturated(not x.ok)
        f.tex:SetAlpha(x.ok and 1 or 0.5)
        T.paint(f, T.COLOR.bad, x.ok and 0 or 1)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", s, "TOPLEFT", spots[i][1] * (STRIP + STRIP_GAP), -spots[i][2] * (STRIP + STRIP_GAP))
        f:Show()
    end
    s:SetHeight(rows * (STRIP + STRIP_GAP) - STRIP_GAP)
    s:SetShown(#cover > 0)
    if #cover > 0 then y = y + rows * (STRIP + STRIP_GAP) - STRIP_GAP + LINE_GAP end

    return y + 4
end

local function drawPane()
    if not pane then return end
    local members = R.list()
    rail.count:SetText(R.grouped() and tostring(#members) or "")
    if not pane:IsShown() then return end
    -- A proposal is for the raid it was made for. Anyone joining, leaving
    -- or changing party since drops Arrange's, which is for a raid only. A
    -- plan's may be for a party, where it only changes assignments, and we
    -- work it out again for the raid as it is now. Late joiners are what a
    -- plan expects while the raid forms.
    if proposal then
        local same = (R.raid() or proposal.plan ~= nil) and not (NS.mock and proposal.plan)
        local n = 0
        for _ in pairs(proposal.groups) do n = n + 1 end
        same = same and n == #members
        for _, m in ipairs(members) do same = same and proposal.groups[m.name] == m.group end
        if not same then
            local auto = proposal.auto
            proposal = proposal.plan and not NS.mock and P.withGroups(Pl.preview(proposal.plan)) or nil
            if proposal then proposal.auto = auto end
        end
    end
    local title, sub = heading(members)
    pane.title:SetText(title)
    pane.sub:SetText(sub)
    pane.size:SetShown(not NS.mock and R.raid() and G.mayArrange())
    local top = layControls(members)

    local page = pane.page
    C.release(page)
    pane.note:SetShown(not R.grouped())
    local sf = pane.scroll
    sf:ClearAllPoints()
    if not R.grouped() then
        pane.note:ClearAllPoints()
        pane.note:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -top)
        pane.note:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
        pane.note:SetText("Start a mock raid to plan one, or pick a plan above.")
        sf:Hide()
        return
    end
    sf:Show()
    sf:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -top)
    sf:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, PAD)

    local byGroup = {}
    for _, m in ipairs(members) do
        local g = proposal and proposal.want[m.name] or m.group
        byGroup[g] = byGroup[g] or {}
        table.insert(byGroup[g], m)
    end
    local _, slots = P.proposalChanges()
    local boxes = P.boxes(members)
    P.fit(members)
    for g = 1, boxes do
        local col, row = (g - 1) % 2, floor((g - 1) / 2)
        local x, y = col * (BOX_W + BOX_GAP), row * (BOX_H + BOX_GAP)
        local list = byGroup[g] or {}
        table.sort(list, function(a, b)
            if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
            return a.name < b.name
        end)
        local b = C.pool(page, "paneBox", makeBox)
        b.g = g
        T.paint(b, { 1, 1, 1 }, 0.08)
        b.title:SetText((R.raid() or g > 1) and format("Group %d", g) or "Party")
        local addable = NS.mock and #list < 5 and not proposal
        b.add:SetShown(addable)
        b.add:SetScript("OnClick", function(self) P.addMenu(self, g) end)
        b.count:SetText(format("(%d/5)", #list))
        -- As many party buffs as fit between the count and the header's right
        -- side (or the + button), then
        -- the empty places of those the party wants. A gap a move could
        -- fix is red, and one nobody can is grey. A proposal's parties
        -- aren't on the board yet, so they show what Arrange's score says
        -- they'd have: what they get in blue and what they lose in red.
        local all = {}
        if proposal then
            for _, it in ipairs(slots[g] or {}) do all[#all + 1] = { pv = it } end
        else
            local buffs = P.partyBuffsOf(g)
            for _, x in ipairs(buffs) do
                x.unwanted = not P.partyWants(list, x)
                all[#all + 1] = { x = x }
            end
            for _, gap in ipairs(P.partyGaps(list, buffs, members)) do all[#all + 1] = { gap = gap } end
        end
        local titleW = (b.title:GetStringWidth() or 0) + 4 + (b.count:GetStringWidth() or 0)
        local right = BOX_W - (addable and 25 or 5)
        local room = right - (6 + titleW) - 6
        local fit = min(#all, BUFFS, max(0, floor((room + 1) / (BUFF + 1))))
        -- Where the first buff starts, from the title's right edge, so the
        -- last one ends at the right side.
        local first = right - fit * (BUFF + 1) + 1 - (6 + (b.title:GetStringWidth() or 0))
        for i, f in ipairs(b.buffs) do
            local it = i <= fit and all[i] or nil
            f.x, f.gap, f.pv = it and it.x, it and it.gap, it and it.pv
            local b0 = f.x and f.x.b or f.gap and f.gap.b or f.pv and f.pv.b
            local dim = f.gap ~= nil or (f.pv and f.pv.state == "lose")
            f.tex:SetTexture(b0 and Tr.icon(b0) or nil)
            f.tex:SetDesaturated(dim and true or false)
            f.tex:SetAlpha(dim and 0.3 or 1)
            if f.gap then
                T.paint(f, f.gap.fix and T.COLOR.bad or T.COLOR.idle, 1)
            elseif f.x and f.x.unwanted then
                T.paint(f, T.COLOR.bad, 1)
            elseif f.pv and f.pv.state ~= "keep" then
                T.paint(f, f.pv.state == "gain" and T.ACCENT or T.COLOR.bad, 1)
            else
                T.paint(f, T.COLOR.bad, 0)
            end
            f:SetShown(it ~= nil)
            f:ClearAllPoints()
            f:SetPoint("LEFT", b.title, "RIGHT", first + (i - 1) * (BUFF + 1), 0)
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", page.body, "TOPLEFT", x, -y)
        local ry = BOX_HEAD
        for _, m in ipairs(list) do
            local r = C.pool(page, "paneRow", makeRow)
            r.box = b
            r:SetFrameLevel(b:GetFrameLevel() + 2)
            -- Where it sits on the parties' page, for a slide to end at.
            r.ax, r.ay = x + 3, y + ry
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", page.body, "TOPLEFT", r.ax, -r.ay)
            paintRow(r, m, proposal and proposal.moved[m.name])
            ry = ry + ROW_H + 1
        end
    end
    page.body:SetHeight(floor((boxes - 1) / 2 + 1) * (BOX_H + BOX_GAP))
    page.scroll:update()
    P.slideRows()
end

-- The PLAN row on the Assignments page says what the pane previews, so it
-- follows each draw.
function P.draw()
    Ar.weighOnce(drawPane)
    if NS.Profiles.repaint then NS.Profiles.repaint() end
end

local function redraw() NS.soon("paneDraw", 0.05, P.draw) end

-- =============================================================
-- How many parties
-- =============================================================
-- How many party boxes the pane shows: the parties the raid uses, and one
-- empty one after them to move players into. A mock raid shows the parties
-- its size needs and one more, so a mock party can become a raid. A real
-- party is one box. A proposal counts the parties it moves players into.
function P.boxes(members)
    members = members or R.list()
    if not NS.mock and not R.raid() then return 1 end
    local top = 0
    for _, m in ipairs(members) do
        top = max(top, m.group or 1, proposal and proposal.want[m.name] or 0)
    end
    if NS.mock then top = max(top, math.ceil(Pl.raidSize() / 5)) end
    return min(8, top + 1)
end

-- Makes P.HEIGHT fit the parties the pane shows now. A window still at the
-- size it opens at grows or shrinks with it.
function P.fit(members)
    local h = heightFor(R.grouped() and P.boxes(members) or 2)
    if h == P.HEIGHT then return end
    P.HEIGHT = h
    if C.fitHeight then C.fitHeight() end
end

-- =============================================================
-- Arrange
-- =============================================================
-- Notes on `p` (a proposal) the parties of everyone now, so the pane can
-- tell when the raid changed under it. Returns `p`.
function P.withGroups(p)
    if not p then return nil end
    p.groups = {}
    for _, m in ipairs(R.list()) do p.groups[m.name] = m.group end
    return p
end

-- Below, with the rows' slide.
local startSlide

-- Proposes parties where more players get the party buffs they want, for
-- the pane to show until it's applied or cancelled. Returns the proposal,
-- or nil when there's nothing to gain.
function P.propose()
    local p = Ar.propose(R.list())
    if p.n == 0 then
        proposal = nil
        NS.print("No moves would get anyone more party buffs.")
    else
        startSlide()
        proposal = P.withGroups(p)
    end
    redraw()
    return proposal
end

function P.proposal() return proposal end

-- The Arrange button's tooltip: how many it would move, which party buffs
-- move, come or go, a line each, then who moves, a line each
-- ("Grom Hellscream: group 2 to 4"), the first MOVES of them.
local MOVES = 8

function P.arrangeTip()
    local members = R.list()
    local p = Ar.propose(members)
    if p.n == 0 then return { "No moves would get anyone more party buffs." } end
    local lines = { { format("Move %d %s for more party buffs.", p.n, p.n == 1 and "player" or "players"), 1, 1, 1 } }
    local changes = changeLines(Ar.changes(members, p.want))
    if #changes > 0 then
        lines[#lines + 1] = " "
        for _, l in ipairs(changes) do lines[#lines + 1] = l end
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = { "Who moves", 1, 1, 1 }
    local names = {}
    for name in pairs(p.moved) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if p.moved[a] ~= p.moved[b] then return p.moved[a] < p.moved[b] end
        return a < b
    end)
    for i, name in ipairs(names) do
        if i > MOVES then
            lines[#lines + 1] = format("and %d more", #names - MOVES)
            break
        end
        local m = R.byName(name)
        lines[#lines + 1] = format("%s: group %d to %d", m and NS.who(m) or name, p.moved[name], p.want[name])
    end
    return lines
end

-- When the parties change under us by Arrange, each row slides from where
-- it was to where it goes, over SLIDE seconds, easing in and out, so we can
-- follow who moves where. A row that stays put doesn't move.
local SLIDE = 0.7
-- { from = { [name] = { x, y } }, t } while rows slide.
local slide
local slider = CreateFrame("Frame")

local function rowsShown()
    local p = pane and pane.page.pools and pane.page.pools.paneRow
    local t = {}
    for i = 1, p and p.used or 0 do
        if p[i].m and p[i].ax then t[#t + 1] = p[i] end
    end
    return t
end

local function slideStep(_, elapsed)
    if not slide then
        slider:SetScript("OnUpdate", nil)
        return
    end
    slide.t = slide.t + (elapsed or 0)
    local k = min(1, slide.t / SLIDE)
    local e = k * k * (3 - 2 * k)
    for _, r in ipairs(rowsShown()) do
        local from = slide.from[r.m.name]
        if from then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", pane.page.body, "TOPLEFT", from[1] + (r.ax - from[1]) * e,
                       -(from[2] + (r.ay - from[2]) * e))
        end
    end
    if k >= 1 then
        slide = nil
        slider:SetScript("OnUpdate", nil)
    end
end

-- Starts the rows sliding from where they are now. The pane draws them in
-- their new places next, and P.slideRows takes them back to the start.
startSlide = function()
    local from = {}
    for _, r in ipairs(rowsShown()) do
        if r:IsShown() then from[r.m.name] = { r.ax, r.ay } end
    end
    slide = { from = from, t = 0 }
    slider:SetScript("OnUpdate", slideStep)
end

-- Puts the sliding rows where they are in their slide, after a draw put
-- them in their new places.
function P.slideRows()
    if slide then slideStep(nil, 0) end
end

-- Ends every slide now, for the tests.
function P.finishSlides()
    if slide then slideStep(nil, math.huge) end
end

-- What the proposal's moves do to the party buffs: Arrange.lua's list of
-- changes, and the party buffs each party would have, as { [g] = { { slot,
-- b, state } } } where `state` is "gain", "keep" or "lose". Worked out once
-- for each proposal.
local SLOT_BUFF = { aura = "devotion", water = "manaspring", pact = "bloodpact" }

function P.proposalChanges()
    if not proposal then return {}, {} end
    if not proposal.slots then
        local list, has = Ar.changes(R.list(), proposal.want)
        local state = {}
        for _, x in ipairs(list) do
            state[x.g] = state[x.g] or {}
            state[x.g][x.slot] = x.gain and "gain" or "lose"
        end
        local slots = {}
        for g = 1, 8 do
            slots[g] = {}
            for _, id in ipairs(Ar.SLOTS) do
                local st = state[g] and state[g][id] or (has[g][id] and "keep") or nil
                if st then slots[g][#slots[g] + 1] = { slot = SLOT[id], b = D.BY_ID[SLOT_BUFF[id]], state = st } end
            end
        end
        proposal.buffChanges, proposal.slots = list, slots
    end
    return proposal.buffChanges, proposal.slots
end

-- What Arrange's proposal does, in a line: "Move 3 players: +Mana Spring
-- for party 3, +aura for party 4".
function P.arrangeLine(p)
    local who = format("Move %d %s", p.n, p.n == 1 and "player" or "players")
    local words = P.changeWords(p == proposal and P.proposalChanges() or Ar.changes(R.list(), p.want), 2)
    return words and who .. ": " .. words or who .. " for more party buffs"
end

-- What we did when a plan went to the raid, in the chat frame. A raider
-- who may only suggest put it in their draft.
local function applied(name, drafted, _, moving)
    if drafted then
        NS.print("Plan %s is in your draft. Send it as a suggestion.", name)
        return
    end
    local missing = #Pl.missing(name)
    NS.print("Applied plan %s.%s", name, moving and " Players move into their groups." or "")
    if missing > 0 then
        NS.print("%d of its players %s here. They get their place when they join.", missing,
                 missing == 1 and "isn't" or "aren't")
    end
end

-- Moves the players as the proposal says, or applies the plan it shows.
function P.applyProposal()
    local p = proposal
    proposal = nil
    if p and p.plan then
        local drafted = Pl.drafting()
        applied(p.plan, drafted, Pl.apply(p.plan, p.auto))
    elseif p then
        G.arrange(p.want)
    end
    redraw()
end

-- What applying plan `p` (Pl.preview's) does, in a line: "12 assignments
-- change, 9 players move, 3 aren't here." Then what the moves do to the
-- party buffs.
function P.planLine(p)
    local parts = {}
    if p.changes > 0 then
        parts[#parts + 1] = format("%d %s", p.changes, p.changes == 1 and "assignment changes" or "assignments change")
    end
    if p.n > 0 then parts[#parts + 1] = format("%d %s", p.n, p.n == 1 and "player moves" or "players move") end
    if #(p.matches or {}) > 0 then parts[#parts + 1] = format("%d matched", #p.matches) end
    if (p.unmatched or 0) > 0 then
        parts[#parts + 1] = format("%d %s no match", p.unmatched, p.unmatched == 1 and "has" or "have")
    end
    if p.missing > 0 then parts[#parts + 1] = format("%d %s", p.missing, p.missing == 1 and "isn't here" or "aren't here") end
    local words = p.n > 0 and P.changeWords(p == proposal and P.proposalChanges() or Ar.changes(R.list(), p.want), 2)
    if #parts == 0 then return "Nothing changes." end
    return table.concat(parts, ", ") .. "." .. (words and " " .. words .. "." or "")
end

-- The tooltip of the preview's line: all of what it does, the raiders who
-- take a made-up player's place, and who has no match.
function P.proposalTip(owner)
    local p = proposal
    if not p then return end
    local lines = { p.plan and P.planLine(p) or P.arrangeLine(p) }
    for _, l in ipairs(changeLines(P.proposalChanges())) do lines[#lines + 1] = l end
    if p.plan and #p.matches > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = { "In the plan's places:", 1, 1, 1 }
        for _, x in ipairs(p.matches) do
            local m = R.byName(x.to)
            lines[#lines + 1] = format("%s (%s): %s", x.from, x.what, m and NS.who(m) or x.to)
        end
    end
    if p.plan and p.unmatched > 0 then
        lines[#lines + 1] = T.line(format("%d %s no match here.", p.unmatched,
                                          p.unmatched == 1 and "player has" or "players have"), "bad")
    end
    if p.plan and p.missing > 0 then
        lines[#lines + 1] = format("%d %s here. They get their place when they join.", p.missing,
                                   p.missing == 1 and "isn't" or "aren't")
    end
    T.tip(owner, p.plan and "Plan " .. p.plan or "Arrange", lines)
end

-- Shows what applying plan `name` would do, like Arrange's proposal: the
-- plan's parties with the players who move marked, and a line of what
-- changes. The PLAN row has Use it and Back. `auto` says Auto picked it, as
-- the plan for the instance. Returns the preview.
function P.previewPlan(name, auto)
    if not Pl.canApply() then
        NS.print("Only the leader and assistants can apply a plan.")
        return nil
    end
    proposal = P.withGroups(Pl.preview(name))
    if proposal then proposal.auto = auto and true or nil end
    redraw()
    return proposal
end

function P.cancelProposal()
    if proposal and not proposal.plan then startSlide() end
    proposal = nil
    redraw()
end

-- =============================================================
-- Menus of the pane
-- =============================================================
-- The menu of the + on party `g` of a mock raid: a class, then its spec,
-- or a real player we remember.
function P.addMenu(owner, g)
    return T.menu(owner, function(_, root)
        root:CreateTitle(format("Add to group %d", g))
        for _, class in ipairs(CLASSES) do
            local sub = root:CreateButton(NS.classText(class, NS.classColored(NS.className(class), class)))
            for tree = 1, 3 do
                sub:CreateButton(NS.specText(class, tree, C.specName(class, tree)),
                                 function() Mo.add(class, tree, g) end)
            end
        end
        if #R.remembered() > 0 then
            root:CreateDivider()
            rememberedEntries(root:CreateButton("Remembered"), function(p) Mo.addReal(p, g) end)
        end
    end)
end

-- The players whose spec we don't know, each with their three specs to
-- pick, and asking the group again.
function P.unknownMenu(owner)
    return T.menu(owner, function(_, root)
        root:CreateTitle("Specs unknown")
        local ok = canChange()
        for _, m in ipairs(R.list()) do
            if not m.spec then
                if ok then
                    local sub = root:CreateButton(NS.who(m))
                    for tree = 1, 3 do
                        sub:CreateButton(NS.specText(m.class, tree, C.specName(m.class, tree)),
                                         function() R.setSpec(m.name, tree) end)
                    end
                else
                    root:CreateButton(NS.who(m))
                end
            end
        end
        if not NS.mock and R.real.grouped() then
            root:CreateDivider()
            root:CreateButton("Ask again", function()
                if R.askSpecs() then NS.print("Asked the group for their specs.") end
            end)
        end
    end)
end

-- What inviting a plan's missing players did, in the chat frame.
local function invited(name, n)
    local left = G.invitesLeft()
    if n > 0 then NS.print("Invited %d from %s.", n, name) end
    if left > 0 then
        NS.print("%d more get an invite once the group is a raid.", left)
    elseif n == 0 then
        NS.print("Couldn't invite anyone from %s.", name)
    end
end

-- Invites plan `name`'s players who aren't here, and says what it did.
function P.inviteMissing(name)
    invited(name, Pl.invite(name))
end

-- The Reset button of a mock raid: start over with made-up players at the
-- size that's picked in the strip. The assignments stay, so a plan can be
-- tried again from scratch.
function P.resetMock()
    local n = Mo.raidSize()
    T.confirm(format("Start over as %s? The made-up players are replaced. Assignments stay.",
                     NS.Profiles.sizeName(n):lower()), function() Mo.fill(n) end)
end

NS.listen("arrange", redraw)
NS.listen("roster", function() P.fit() end)
NS.listen("plans", redraw)
NS.on("PLAYER_REGEN_DISABLED", redraw)
NS.on("PLAYER_REGEN_ENABLED", redraw)
