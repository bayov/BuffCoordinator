-- Arranging the parties: who sits in which party, for the buffs that reach
-- only a party.
--
-- A paladin's aura, a shaman's Mana Spring and a warlock's Blood Pact reach
-- only the giver's own party, so where each player sits decides who gets
-- them. We score a layout by the party buffs each player gets from someone
-- in their party, weighted by how much they want it. A tank wants Devotion
-- Aura and Blood Pact most, healers and casters want Mana Spring, and a
-- Retribution paladin's aura is for melee. Then we look for a better layout
-- by swapping two players, or moving one into a party with room, for as long
-- as that raises the score.
--
-- The score only says who could give each buff, never who auto picked, so
-- a proposal doesn't change with the board it's about to change.
--
-- The leader can keep a player in their party (a pin), and the proposal
-- never moves them. The pins of a mock raid are the mock's own, so a plan
-- keeps them. The real raid's are in db.pins, and they last until we leave
-- the group, since the next raid is another one.

local _, NS = ...
local D, R, Du = NS.Data, NS.Roster, NS.Duties
local format = string.format

local Ar = {}
NS.Arrange = Ar

local EPS = 1e-6
local MAX_ROUNDS = 100

-- =============================================================
-- Pins
-- =============================================================
function Ar.pins()
    if NS.mock then
        local sb = NS.db.mock
        if type(sb.pins) ~= "table" then sb.pins = {} end
        return sb.pins
    end
    if type(NS.db.pins) ~= "table" then NS.db.pins = {} end
    return NS.db.pins
end

function Ar.pinned(name) return Ar.pins()[name] == true end

-- In a mock raid a pin is part of the plan, so it's a step to undo.
function Ar.pin(name, on)
    local M = NS.Mock
    local before = NS.mock and not Du.replaying() and M.snapshot()
    Ar.pins()[name] = on and true or nil
    if before then
        Du.keepMock(on and format("keep %s in their group", name) or format("let %s move", name), before, M.snapshot())
    end
    NS.signal("arrange")
end

local function unpinAll()
    if type(NS.db.pins) == "table" and next(NS.db.pins) then
        NS.db.pins = {}
        NS.signal("arrange")
    end
end
NS.on("GROUP_LEFT", unpinAll)
NS.listen("groupLeft", unpinAll)

-- =============================================================
-- The score
-- =============================================================
-- The players weighed so far, by name, while Ar.weighOnce runs.
local weighed

-- What each player gives their party and how much they want each party
-- buff, worked out once per proposal.
--
-- None of it reads the player's party, so a stand-in from `shifted` weighs
-- the same as the player, and a party's score depends only on who is in it.
local function weigh(m)
    local w = weighed and weighed[m.name]
    if w then return w end
    local by = D.BY_ID
    local tank, melee = m.tags.tank, m.tags.melee
    w = {
        name = m.name,
        aura = Du.canGive(m, by.devotion),
        ret = Du.canGive(m, by.devotion) and m.spec == 3,
        water = Du.canGive(m, by.manaspring),
        pact = Du.canGive(m, by.bloodpact),
        wAura = tank and 3 or 1,
        wRet = melee and 1 or 0,
        wSecond = (Du.wants(m, by.retribution) or Du.wants(m, by.concentration)) and 0.5 or 0,
        wWater = Du.wants(m, by.manaspring) and (m.tags.healer and 2 or 1.5) or 0,
        wPact = tank and 2 or 0.5,
    }
    if weighed then weighed[m.name] = w end
    return w
end

local function leaveWeighing(ok, ...)
    weighed = nil
    if not ok then error((...), 0) end
    return ...
end

-- Runs `fn()` weighing each player only once, however often it scores them.
--
-- Weighing asks Duties what each player can give and wants, and that's most
-- of what scoring costs. A raid pane draw asks moveGain and swapGain about
-- the same roster hundreds of times. With a 40 player raid that took about
-- 80 ms a draw, and every click in the window draws it again.
--
-- Nothing a draw does changes what anyone can give or wants, so the
-- weights hold until it ends. We forget them right after, since the next
-- draw may come after a spec or a want changed.
function Ar.weighOnce(fn)
    if weighed then return fn() end
    weighed = {}
    return leaveWeighing(pcall(fn))
end

-- The score of one party, a list of weighed players.
local function partyScore(list)
    local auras, ret, water, pact = 0, false, false, false
    for _, w in ipairs(list) do
        if w.aura then auras = auras + 1 end
        ret = ret or w.ret
        water = water or w.water
        pact = pact or w.pact
    end
    local s = 0
    for _, w in ipairs(list) do
        if auras > 0 then s = s + w.wAura end
        if auras > 1 then s = s + w.wSecond end
        if ret then s = s + w.wRet end
        if water then s = s + w.wWater end
        if pact then s = s + w.wPact end
    end
    return s
end

-- The weighed players by party, and the party of each by name.
local function layout(members)
    local parties, groupOf, byName = {}, {}, {}
    for g = 1, 8 do parties[g] = {} end
    for _, m in ipairs(members) do
        local w = weigh(m)
        byName[m.name] = w
        groupOf[m.name] = m.group
        table.insert(parties[m.group], w)
    end
    return parties, groupOf, byName
end

local function without(list, w)
    local t = {}
    for _, x in ipairs(list) do
        if x ~= w then t[#t + 1] = x end
    end
    return t
end

local function with(list, w)
    local t = { w }
    for _, x in ipairs(list) do t[#t + 1] = x end
    return t
end

-- How much moving `m` to party `g` would raise the raid's score, or lower
-- it when below 0. It doesn't ask whether `g` has room.
function Ar.moveGain(m, g, members)
    if m.group == g then return 0 end
    local parties, _, byName = layout(members or R.list())
    local w = byName[m.name]
    local from, to = parties[m.group], parties[g]
    if not (w and to) then return 0 end
    return partyScore(without(from, w)) + partyScore(with(to, w)) - partyScore(from) - partyScore(to)
end

-- How much swapping `m` and `x` would raise the raid's score, or lower it
-- when below 0. It's what gainOf says of the same swap, from only the two
-- parties that change. The other parties score the same before and after.
function Ar.swapGain(m, x, members)
    if m.group == x.group then return 0 end
    local parties, _, byName = layout(members or R.list())
    local wm, wx = byName[m.name], byName[x.name]
    local pm, px = parties[m.group], parties[x.group]
    if not (wm and wx and pm and px) then return 0 end
    return partyScore(with(without(pm, wm), wx)) + partyScore(with(without(px, wx), wm))
           - partyScore(pm) - partyScore(px)
end

-- The whole raid's score.
function Ar.score(members)
    local parties = layout(members or R.list())
    local s = 0
    for g = 1, 8 do s = s + partyScore(parties[g]) end
    return s
end

-- `members` as they'd be in layout `want` ({ [name] = party }). Each one who
-- moves is a stand-in that reads everything but the party from their own
-- record.
local function shifted(members, want)
    local t = {}
    for i, m in ipairs(members) do
        local g = want[m.name]
        t[i] = g and g ~= m.group and setmetatable({ group = g }, { __index = m }) or m
    end
    return t
end

-- How much layout `want` would raise the raid's score, or lower it when
-- below 0. Unlike moveGain it can say what a swap does, which is what a
-- drop on a player in a full party makes.
function Ar.gainOf(members, want)
    members = members or R.list()
    return Ar.score(shifted(members, want)) - Ar.score(members)
end

-- =============================================================
-- What a layout changes
-- =============================================================
-- The party buffs a party can be without, in the order of a party's
-- header: a paladin's aura, Mana Spring and Blood Pact.
Ar.SLOTS = { "aura", "water", "pact" }
local WANT = { aura = "wAura", water = "wWater", pact = "wPact" }

-- The slots someone in `list` (weighed players) gives.
local function given(list)
    local give = {}
    for _, w in ipairs(list) do
        for _, slot in ipairs(Ar.SLOTS) do
            if w[slot] then give[slot] = true end
        end
    end
    return give
end

-- What layout `want` does to the party buffs, as a list of { g, slot, gain }
-- in party order. `gain` is true when someone who ends up in party `g` gets
-- a buff they want and didn't have in their old party, and false when they
-- lose one. So moving a tank to the paladin is "+aura" for the paladin's
-- party, and moving the paladin away from the rogues is "-aura" for theirs.
--
-- The second value is the slots each party has after the moves that
-- someone there wants, as { [g] = { [slot] = true } }, so a preview can show
-- the headers the parties would have.
function Ar.changes(members, want)
    members = members or R.list()
    local moved = shifted(members, want)
    local before, groupOf, byName = layout(members)
    local after = layout(moved)
    local hb, ha = {}, {}
    for g = 1, 8 do hb[g], ha[g] = given(before[g]), given(after[g]) end
    local state, has = {}, {}
    for g = 1, 8 do state[g], has[g] = {}, {} end
    for _, m in ipairs(moved) do
        local w, g, o = byName[m.name], m.group, groupOf[m.name]
        for _, slot in ipairs(Ar.SLOTS) do
            if w and w[WANT[slot]] > 0 then
                if ha[g][slot] then
                    has[g][slot] = true
                    if not hb[o][slot] then state[g][slot] = true end
                elseif hb[o][slot] then
                    state[g][slot] = false
                end
            end
        end
    end
    local list = {}
    for g = 1, 8 do
        for _, slot in ipairs(Ar.SLOTS) do
            if state[g][slot] ~= nil then list[#list + 1] = { g = g, slot = slot, gain = state[g][slot] } end
        end
    end
    return list, has
end

-- =============================================================
-- A proposal
-- =============================================================
-- A better layout of `members` (the roster), as
--   { want = { [name] = party }, moved = { [name] = old party }, n, gain }
-- `n` is how many players move and `gain` how much the score rises. Pinned
-- players stay put.
function Ar.propose(members)
    members = members or R.list()
    local parties, groupOf, byName = layout(members)
    local names, top = {}, math.ceil(#members / 5)
    for _, m in ipairs(members) do
        if not Ar.pinned(m.name) then names[#names + 1] = m.name end
        top = math.max(top, m.group)
    end
    table.sort(names)
    local total = 0
    for _ = 1, MAX_ROUNDS do
        local best, bestGain = nil, EPS
        for i, a in ipairs(names) do
            local wa, ga = byName[a], groupOf[a]
            local pa = parties[ga]
            local before = partyScore(pa)
            local paLess = without(pa, wa)
            -- Moving `a` into a party with room.
            for g = 1, top do
                local pg = parties[g]
                if g ~= ga and #pg < 5 then
                    local gain = partyScore(paLess) + partyScore(with(pg, wa)) - before - partyScore(pg)
                    if gain > bestGain then best, bestGain = { a, g }, gain end
                end
            end
            -- Swapping `a` with `b`.
            for j = i + 1, #names do
                local b = names[j]
                local wb, gb = byName[b], groupOf[b]
                if gb ~= ga then
                    local pb = parties[gb]
                    local gain = partyScore(with(paLess, wb)) + partyScore(with(without(pb, wb), wa))
                                 - before - partyScore(pb)
                    if gain > bestGain then best, bestGain = { a, gb, b }, gain end
                end
            end
        end
        if not best then break end
        local a, g, b = best[1], best[2], best[3]
        local ga = groupOf[a]
        parties[ga] = without(parties[ga], byName[a])
        if b then
            parties[g] = without(parties[g], byName[b])
            table.insert(parties[ga], byName[b])
            groupOf[b] = ga
        end
        table.insert(parties[g], byName[a])
        groupOf[a] = g
        total = total + bestGain
    end
    local moved, n = {}, 0
    for _, m in ipairs(members) do
        if groupOf[m.name] ~= m.group then
            moved[m.name] = m.group
            n = n + 1
        end
    end
    return { want = groupOf, moved = moved, n = n, gain = total }
end
