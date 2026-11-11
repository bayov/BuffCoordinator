-- The mock raid: a pretend raid to plan and play with while we're not in a
-- group.
--
-- While it's on, the roster is a raid we make up (us, plus anyone we add),
-- and the assignments and specs are the mock's own. So everything on the
-- Assignments page works as in a real raid: auto picks who does what, and
-- we can change any of it to see what auto does around it. The raid pane
-- (RaidPane.lua) changes it like a real raid: groups, assistants, main tanks
-- and roles. Nothing reaches anyone: we send nothing, whisper nobody, and
-- our real assignments stay as they were. The HUD hides, since its buttons
-- would cast at players who aren't there.
--
-- Joining a group ends it, since the real group is what the window shows
-- then.
--
-- Its made-up players have Forever's "First Last" names, everyone in it is
-- level 60 (Roster.lua), and what it makes up has 3 tanks at most.
--
-- The mock raid and what we changed in it are kept (db.mock), so the next
-- time we open it, it's as we left it. The first time, it starts as a copy
-- of our own assignments, with as many players as the raid pane asked for.
-- A saved plan (Plans.lua) is a copy of it, and loading one makes it the
-- mock raid again.
--
-- `db.mock` is
--   members  { name, class, group, rank, mark, role, real } for everyone but
--            us. `real` marks a real player (one we remember, or a name the
--            leader typed), whom a plan can invite.
--   self     our own { group, rank, mark, role }
--   duty     the assignments, like db.duty
--   specs    the specs, like db.specs. Each made-up player's spec is here.
--   allAssist  true when everyone is an assistant
--   size     how many the raid is for, 5 to 40
--   pins     { [name] = true } for players kept in their party (Arrange.lua)
--   plan     the name of the saved plan it was loaded from or saved as
--   learned  { [name] = tree } for the real players whose spec loading a
--            plan filled in from what we learned of them (Plans.lua)
-- `db.mockOn` is set while it's on, so a reload keeps it on.
-- `rank` is 2 for the leader and 1 for an assistant, `mark` is "MAINTANK" or
-- "MAINASSIST", and `role` is the raid role, "TANK", "HEALER" or "DAMAGER".

local _, NS = ...
local D, R = NS.Data, NS.Roster

local format = string.format

local M = {}
NS.Mock = M

-- Made-up players get Forever's "First Last" names, the first one not
-- taken. Each first name goes with the surname at the same place, and when
-- every pair is taken, with the ones after it.
local FIRST = {
    "Aldric", "Brakka", "Cyndra", "Dorn", "Elowen", "Faelin", "Garrick", "Hilde", "Ivo", "Jorra",
    "Kael", "Liora", "Mordain", "Nyssa", "Orrin", "Pella", "Quill", "Rhea", "Sorin", "Tamsin",
    "Ulric", "Vesna", "Wren", "Xander", "Yara", "Zeph", "Ansel", "Brenna", "Corvin", "Dalia",
    "Edric", "Fiora", "Gideon", "Halla", "Isolde", "Jareth", "Kira", "Lucan", "Mira", "Nolan",
    "Oona", "Perrin", "Rook", "Selka", "Thorne", "Una", "Varis", "Wynn",
}
local LAST = {
    "Brightwood", "Stonehelm", "Ashvale", "Ironbrook", "Duskwhisper", "Thornfield", "Emberly", "Frostmere",
    "Oakhart", "Ravenholt", "Silverleaf", "Blackmoor", "Windrider", "Goldmane", "Hollowell", "Stormcrest",
    "Fairbrook", "Grimward", "Moonfall", "Redfern", "Coldwater", "Highcliff", "Mossgrove", "Dawnstar",
    "Wolfsbane", "Brambleton", "Greyhaven", "Sunridge", "Deepwell", "Hearthstone", "Marrow", "Swiftbrook",
    "Kettleby", "Longstride", "Nightingale", "Copperfield", "Elmsworth", "Fallowmere", "Glimmerdale",
    "Hawkridge", "Larkspur", "Mistvale", "Northcote", "Pinecrest", "Quarryman", "Rowan", "Saltmarsh",
    "Tallowby",
}

-- A group's classes and specs (talent trees), in the order a preset takes
-- them: a 10 takes the first 9, since we're the 10th. The first four make a
-- party with us: a tank, a healer and two who deal damage.
local LINEUP = {
    { "WARRIOR", 3 }, { "PRIEST", 2 }, { "MAGE", 3 }, { "ROGUE", 2 }, { "PALADIN", 1 },
    { "SHAMAN", 3 }, { "WARLOCK", 1 }, { "HUNTER", 2 }, { "DRUID", 3 },
    { "WARRIOR", 2 }, { "WARRIOR", 3 }, { "PRIEST", 2 }, { "PALADIN", 3 }, { "SHAMAN", 2 },
    { "MAGE", 3 }, { "WARLOCK", 3 }, { "ROGUE", 2 }, { "DRUID", 2 }, { "HUNTER", 1 },
    { "WARRIOR", 2 }, { "ROGUE", 1 }, { "MAGE", 2 }, { "PRIEST", 3 }, { "PALADIN", 1 },
    { "SHAMAN", 1 }, { "DRUID", 1 }, { "WARLOCK", 2 }, { "WARRIOR", 1 }, { "PRIEST", 1 },
    { "MAGE", 1 }, { "ROGUE", 3 }, { "HUNTER", 3 }, { "PALADIN", 2 }, { "SHAMAN", 3 },
    { "WARRIOR", 2 }, { "PRIEST", 2 }, { "DRUID", 3 }, { "WARLOCK", 1 }, { "MAGE", 3 },
}

-- Forever's raids come in every size from 10 to 40 in steps of 5, and a
-- party is 5.
M.SIZES = { 5, 10, 15, 20, 25, 30, 35, 40 }

local function data(n)
    local db = NS.db
    if type(db.mock) ~= "table" then
        db.mock = { members = {}, self = { group = 1, rank = 2 }, duty = NS.copy((NS.remote or db).duty) or {},
                    specs = {}, pins = {} }
        M.fill(n or 20)
    end
    return db.mock
end

function M.on() return NS.mock == true end

-- Whether there's a mock raid yet. The first one asks how big it is.
function M.exists() return type(NS.db.mock) == "table" end

-- How many the raid is for: the size it was made or filled to, else as many
-- as are in it, up to the next size Forever has.
function M.raidSize()
    local sb = data()
    local n = tonumber(sb.size)
    if n then return n end
    local have = #sb.members + 1
    for _, size in ipairs(M.SIZES) do
        if size >= have then return size end
    end
    return 40
end

-- The made-up players, as { name, class, group, rank, mark, role }.
function M.members() return data().members end
-- Our own { group, rank, mark, role } in it.
function M.self() return data().self end
function M.allAssist() return data().allAssist == true end

local function myName() return R.me() and R.me().name end

-- The record of `name` in the mock: ours, or a made-up player's.
local function entry(name)
    local sb = data()
    if name == myName() then return sb.self end
    for _, p in ipairs(sb.members) do
        if p.name == name then return p end
    end
end

local function taken(name)
    return name == myName() or entry(name) ~= nil
end

local function newName()
    for shift = 0, #LAST - 1 do
        for i, first in ipairs(FIRST) do
            local n = first .. " " .. LAST[(i - 1 + shift) % #LAST + 1]
            if not taken(n) then return n end
        end
    end
end

-- A mock raid never has more than this many tanks of its own making.
local MAX_TANKS = 3

local function tanks(sb)
    local n = 0
    for _, p in ipairs(sb.members) do
        local s = D.SPECS[p.class] and D.SPECS[p.class][sb.specs[p.name]]
        if p.role == "TANK" or (p.role == nil and s and s.role == "tank") then n = n + 1 end
    end
    return n
end

-- The talent tree a made-up player of lineup entry `c` gets: its own, or
-- one that deals damage when the raid has its tanks already.
local function lineupTree(sb, c)
    local s = D.SPECS[c[1]] and D.SPECS[c[1]][c[2]]
    if not (s and s.role == "tank") or tanks(sb) < MAX_TANKS then return c[2] end
    for tree, x in ipairs(D.SPECS[c[1]]) do
        if x.role ~= "tank" and x.role ~= "healer" then return tree end
    end
    return c[2]
end

-- How many are in party `g`, us included.
local function size(g)
    local sb = data()
    local n = sb.self.group == g and 1 or 0
    for _, p in ipairs(sb.members) do
        if p.group == g then n = n + 1 end
    end
    return n
end

-- The first party with room, from 1.
local function room()
    for g = 1, 8 do
        if size(g) < 5 then return g end
    end
end

local function changed()
    if not M.on() then return end
    R.scan()
    NS.Duties.update()
end

-- Adds a player of `class` and talent tree `tree` to party `group`, or the
-- first with room. Returns their name, or nil when the raid is full.
function M.add(class, tree, group)
    local sb = data()
    group = group and size(group) < 5 and group or room()
    if not group then return nil end
    local name = newName()
    sb.members[#sb.members + 1] = { name = name, class = class, group = group, rank = 0 }
    sb.specs[name] = tree
    changed()
    return name
end

-- Adds a real player we remember, `p` from R.remembered. Returns their
-- name, or nil when they're in already or the raid is full.
function M.addReal(p, group)
    local sb = data()
    if taken(p.name) then return nil end
    group = group and size(group) < 5 and group or room()
    if not group then return nil end
    sb.members[#sb.members + 1] = { name = p.name, class = p.class, group = group, rank = 0, real = true }
    sb.specs[p.name] = p.spec
    changed()
    return p.name
end

-- Takes `name` out of the mock's assignments: their picks, a choice job's
-- giver, the blessing and totem tables, their own blessing order, the
-- players a job never goes to, and a fight's giver, which goes back to auto.
-- Made-up names come back, since newName takes the first free one. Without
-- this, the next made-up player to get the name would get their
-- assignments too.
local function forget(duty, name)
    local key = "name:" .. name
    for id, e in pairs(duty) do
        if type(e) == "table" then
            for _, k in ipairs({ "picks", "never", "order" }) do
                if type(e[k]) == "table" then e[k][key] = nil end
            end
            for _, k in ipairs({ "choice", "matrix" }) do
                if type(e[k]) == "table" then e[k][name] = nil end
            end
            for _, f in pairs(type(e.fights) == "table" and e.fights or {}) do
                for school, v in pairs(f) do
                    if type(v) == "table" and v.giver == name then f[school] = true end
                end
            end
            for _, k in ipairs({ "picks", "never", "order", "choice", "matrix" }) do
                if type(e[k]) == "table" and next(e[k]) == nil then e[k] = nil end
            end
            if next(e) == nil then duty[id] = nil end
        end
    end
end

-- Takes player `p` out of the mock: their spec, their pin and their
-- assignments go with them.
local function drop(sb, p)
    sb.specs[p.name], sb.pins[p.name] = nil, nil
    forget(sb.duty, p.name)
end

function M.remove(name)
    local sb = data()
    for i, p in ipairs(sb.members) do
        if p.name == name then
            table.remove(sb.members, i)
            drop(sb, p)
            break
        end
    end
    changed()
end

-- Renames `old` to `new` everywhere the mock's assignments name them: the
-- picks, the players a job never goes to, a choice job's givers, the
-- blessing and totem tables, the blessing orders and a fight's givers.
local function renameIn(duty, old, new)
    local function move(t, from, to)
        if type(t) == "table" and t[from] ~= nil then t[to], t[from] = t[from], nil end
    end
    for _, e in pairs(duty) do
        if type(e) == "table" then
            move(e.picks, "name:" .. old, "name:" .. new)
            move(e.never, "name:" .. old, "name:" .. new)
            move(e.choice, old, new)
            move(e.matrix, old, new)
            move(e.order, "name:" .. old, "name:" .. new)
            for _, f in pairs(type(e.fights) == "table" and e.fights or {}) do
                for _, v in pairs(f) do
                    if type(v) == "table" and v.giver == old then v.giver = new end
                end
            end
        end
    end
end

-- Gives made-up player `old` the name `new`, which makes them a real
-- player a plan can invite. Their assignments go with them. `class` and
-- `tree` change them too when given, for a remembered player taking their
-- place. Returns whether it changed.
function M.rename(old, new, class, tree)
    local sb = data()
    new = type(new) == "string" and new:match("^%s*(.-)%s*$") or ""
    local e = old ~= myName() and entry(old)
    if not e or new == "" or (new ~= old and taken(new)) then return false end
    e.name, e.real = new, true
    if class then e.class = class end
    sb.specs[new], sb.specs[old] = tree or sb.specs[old], nil
    if new ~= old then sb.pins[new], sb.pins[old] = sb.pins[old], nil end
    renameIn(sb.duty, old, new)
    changed()
    return true
end

-- Puts remembered player `p` (from R.remembered) in made-up player
-- `name`'s place.
function M.replace(name, p)
    return M.rename(name, p.name, p.class, p.spec)
end

-- Makes `name` a player of `class` and talent tree `tree`.
function M.setClass(name, class, tree)
    local sb = data()
    for _, p in ipairs(sb.members) do
        if p.name == name then
            p.class = class
            sb.specs[name] = tree
        end
    end
    changed()
end

-- Whether the mock is a party: five at most, all in party 1. A player in
-- party 2 makes it a raid.
function M.party()
    local sb = data()
    if (sb.self.group or 1) ~= 1 or #sb.members > 4 then return false end
    for _, p in ipairs(sb.members) do
        if p.group ~= 1 then return false end
    end
    return true
end

-- Moves `name` to party `group` when it has room.
function M.move(name, group)
    local e = entry(name)
    if not e or e.group == group or size(group) >= 5 then return false end
    e.group = group
    changed()
    return true
end

-- Swaps the parties of `a` and `b`.
function M.swap(a, b)
    local ea, eb = entry(a), entry(b)
    if not (ea and eb) then return false end
    ea.group, eb.group = eb.group, ea.group
    changed()
    return true
end

-- Moves everyone to their party in `want` ({ [name] = party }) at once.
-- A layout that would put more than 5 in a party changes nothing. Returns
-- whether it moved anyone.
function M.arrange(want)
    local sb = data()
    local after = {}
    local function place(name, e)
        local g = tonumber(want[name]) or e.group
        after[g] = (after[g] or 0) + 1
        return g
    end
    local plan = { [sb.self] = place(myName(), sb.self) }
    for _, p in ipairs(sb.members) do plan[p] = place(p.name, p) end
    for g, n in pairs(after) do
        if n > 5 or g < 1 or g > 8 then return false end
    end
    local moved = false
    for e, g in pairs(plan) do
        if e.group ~= g then
            e.group = g
            moved = true
        end
    end
    if moved then changed() end
    return moved
end

-- Makes `name` the leader, an assistant (1) or neither (0). A new leader
-- makes the old one an assistant, as the game does in a raid.
function M.setRank(name, rank)
    local e = entry(name)
    if not e then return end
    if rank == 2 then
        local sb = data()
        if sb.self.rank == 2 then sb.self.rank = 1 end
        for _, p in ipairs(sb.members) do
            if p.rank == 2 then p.rank = 1 end
        end
    end
    e.rank = rank
    changed()
end

-- Marks `name` as the main tank or main assist (`mark`), or clears it.
function M.setMark(name, mark, on)
    local e = entry(name)
    if not e then return end
    if on then
        e.mark = mark
    elseif e.mark == mark then
        e.mark = nil
    end
    changed()
end

-- The raid role of `name`: "TANK", "HEALER", "DAMAGER", or nil for none.
function M.setRole(name, role)
    local e = entry(name)
    if not e then return end
    e.role = role
    changed()
end

function M.setAllAssist(on)
    data().allAssist = on and true or nil
    changed()
end

-- Starts over with a preset group of `n` with us in it, from the lineup,
-- five to a party. The assignments stay, and we lead it.
function M.fill(n)
    if type(NS.db.mock) ~= "table" then
        data(n)
        return
    end
    local sb = NS.db.mock
    sb.members, sb.specs, sb.self, sb.pins, sb.size = {}, {}, { group = 1, rank = 2 }, {}, n
    for i = 1, n - 1 do
        local c = LINEUP[i]
        if not c then break end
        local name = newName()
        sb.members[#sb.members + 1] = { name = name, class = c[1], group = math.floor(i / 5) + 1, rank = 0 }
        sb.specs[name] = lineupTree(sb, c)
    end
    changed()
end

-- Makes the raid `n` big and keeps who is in it: made-up players from the
-- lineup join, or leave from the last party first. Real players leave only
-- when the made-up ones aren't enough.
function M.resize(n)
    local sb = data()
    sb.size = n
    local function last(real)
        local at
        for i, p in ipairs(sb.members) do
            if (p.real and true or false) == real
               and (not at or p.group > sb.members[at].group or p.group == sb.members[at].group) then
                at = i
            end
        end
        return at
    end
    while #sb.members + 1 > n do
        local i = last(false) or last(true)
        if not i then break end
        drop(sb, table.remove(sb.members, i))
    end
    local i = #sb.members
    while #sb.members + 1 < n do
        i = i + 1
        local c = LINEUP[(i - 1) % #LINEUP + 1]
        local g = room()
        if not g then break end
        local name = newName()
        sb.members[#sb.members + 1] = { name = name, class = c[1], group = g, rank = 0 }
        sb.specs[name] = lineupTree(sb, c)
    end
    changed()
end

function M.clear()
    local sb = data()
    for _, p in ipairs(sb.members) do forget(sb.duty, p.name) end
    sb.members, sb.self, sb.pins, sb.size = {}, { group = 1, rank = 2 }, {}, nil
    for name in pairs(sb.specs) do sb.specs[name] = nil end
    changed()
end

-- What a plan keeps of the mock raid: a copy of all of it.
local KEPT = { "members", "self", "duty", "specs", "allAssist", "size", "pins" }

function M.snapshot()
    local sb, copy = data(), NS.copy
    local t = {}
    for _, k in ipairs(KEPT) do t[k] = copy(sb[k]) end
    return t
end

-- Made-up players had one name before they had Forever's "First Last".
-- Gives each one in mock raid or plan `t` a new name, the first free one in
-- it, and their spec, pin and assignments go with them.
function M.fixNames(t)
    if type(t.members) ~= "table" then return end
    for _, k in ipairs({ "duty", "specs", "pins" }) do
        if type(t[k]) ~= "table" then t[k] = {} end
    end
    local used = { [myName() or ""] = true }
    for _, p in ipairs(t.members) do
        if type(p.name) == "string" then used[p.name] = true end
    end
    local function free()
        for shift = 0, #LAST - 1 do
            for i, first in ipairs(FIRST) do
                local n = first .. " " .. LAST[(i - 1 + shift) % #LAST + 1]
                if not used[n] then return n end
            end
        end
    end
    for _, p in ipairs(t.members) do
        if not p.real and type(p.name) == "string" and not p.name:find(" ", 1, true) then
            local old, new = p.name, free()
            if not new then return end
            used[new] = true
            p.name = new
            t.specs[new], t.specs[old] = t.specs[old], nil
            t.pins[new], t.pins[old] = t.pins[old], nil
            renameIn(t.duty, old, new)
        end
    end
end

-- Makes the mock raid a copy of `t` (a plan, or M.snapshot's), as plan
-- `name`.
function M.load(t, name)
    local sb, copy = data(), NS.copy
    for _, k in ipairs(KEPT) do sb[k] = copy(t[k]) end
    for _, k in ipairs({ "members", "duty", "specs", "pins" }) do
        if type(sb[k]) ~= "table" then sb[k] = {} end
    end
    if type(sb.self) ~= "table" then sb.self = { group = 1, rank = 2 } end
    M.fixNames(sb)
    sb.plan = name
    changed()
end

-- Puts the mock raid back as copy `t` (M.snapshot's), for an undo or a
-- redo. It stays the same plan.
function M.restore(t)
    local sb, copy = data(), NS.copy
    for _, k in ipairs(KEPT) do sb[k] = copy(t[k]) end
    changed()
    NS.signal("arrange")
end

-- Each change to the mock raid is one step to undo (Duties.lua): a copy of
-- the raid before it and after it. What `text` returns names it, from the
-- change's arguments: "move Aldric Brightwood to group 3".
local function tracked(name, text)
    local fn = M[name]
    M[name] = function(...)
        local Du = NS.Duties
        if not M.on() or Du.replaying() then return fn(...) end
        local before = M.snapshot()
        local a, b = Du.untracked(fn, ...)
        Du.keepMock(text(...), before, M.snapshot())
        return a, b
    end
end

local function rankText(name, rank)
    if rank == 2 then return format("make %s the leader", name) end
    if rank == 1 then return format("make %s an assistant", name) end
    return format("take %s's assistant away", name)
end

local function markText(name, mark, on)
    local what = mark == "MAINTANK" and "main tank" or "main assist"
    return on and format("make %s %s", name, what) or format("take %s's %s away", name, what)
end

tracked("add", function(class) return format("add a %s", NS.className(class)) end)
tracked("addReal", function(p) return format("add %s", p.name) end)
tracked("remove", function(name) return format("remove %s", name) end)
tracked("rename", function(old, new) return format("rename %s to %s", old, tostring(new)) end)
tracked("replace", function(name, p) return format("put %s in %s's place", p.name, name) end)
tracked("setClass", function(name, class) return format("make %s a %s", name, NS.className(class)) end)
tracked("move", function(name, group) return format("move %s to group %d", name, group) end)
tracked("swap", function(a, b) return format("swap %s and %s", a, b) end)
tracked("arrange", function() return "arrange the raid" end)
tracked("setRank", rankText)
tracked("setMark", markText)
tracked("setRole", function(name) return format("set %s's role", name) end)
tracked("setAllAssist", function(on) return on and "make everyone an assistant" or "take everyone's assistant away" end)
tracked("fill", function(n) return format("start over with %d players", n) end)
tracked("resize", function(n) return format("make the raid %d", n) end)
tracked("clear", function() return "empty the raid" end)

-- Turns the mock raid on or off. Only while we're not in a group: a real
-- group is always what the window shows, and the HUD, the whispers and
-- what we send read the mock's roster while it's on. A draft of ours waits
-- outside it, and comes back when we leave. The first mock raid is `n`
-- players, or 20.
local stash

function M.set(on, n)
    on = on and R.real and not R.real.grouped() or false
    if on == M.on() then return end
    data(n)
    if on then
        stash, NS.draft = NS.draft, nil
        NS.mock = true
    else
        NS.mock = nil
        NS.draft, stash = stash, nil
    end
    NS.db.mockOn = on or nil
    R.scan()
    NS.Duties.update()
    NS.signal("draft")
end

function M.toggle() M.set(not M.on()) end

NS.listen("loaded", function()
    -- It was called the sandbox for a day, and then the planner.
    local db = NS.db
    if db.mock == nil then
        db.mock = type(db.planner) == "table" and db.planner or type(db.sandbox) == "table" and db.sandbox or nil
    end
    db.planner, db.sandbox = nil, nil
    local sb = db.mock
    if type(sb) ~= "table" then return end
    for _, k in ipairs({ "members", "duty", "specs", "pins" }) do
        if type(sb[k]) ~= "table" then sb[k] = {} end
    end
    if type(sb.self) ~= "table" then sb.self = { group = tonumber(sb.me) or 1, rank = 2 } end
    sb.me = nil
    for _, p in ipairs(sb.members) do p.rank = tonumber(p.rank) or 0 end
    for id in pairs(sb.duty) do
        if not D.JOB[id] then sb.duty[id] = nil end
    end
    M.fixNames(sb)
    for _, plan in pairs(type(db.plans) == "table" and db.plans or {}) do
        if type(plan) == "table" then M.fixNames(plan) end
    end
end)

-- A mock raid that was on when we logged out or reloaded is on again, as
-- long as we're still not in a group.
NS.listen("login", function()
    if NS.db.mockOn and M.exists() and not R.real.grouped() then
        M.set(true)
    else
        NS.db.mockOn = nil
    end
end)

-- Joining a group ends the mock raid.
NS.on("GROUP_ROSTER_UPDATE", function()
    if M.on() and R.real.grouped() then M.set(false) end
end)

NS.command("mock", "start or end a mock raid of a size, like mock 25", function(rest)
    if not M.on() and R.real.grouped() then
        NS.print("Leave your group to start a mock raid.")
        return
    end
    local n, fits = tonumber(rest), false
    for _, size in ipairs(M.SIZES) do fits = fits or size == n end
    if n and not fits then
        NS.print("A mock raid is 5, or 10 to 40 in steps of 5.")
        return
    elseif n and not M.exists() then
        M.set(true, n)
    elseif n then
        M.set(true)
        M.resize(n)
    elseif not M.on() and not M.exists() then
        NS.print("Give a size, like %s mock 25.", NS.SLASH)
        return
    else
        M.toggle()
    end
    if M.on() and NS.Config then NS.Config.open("duties") end
end)
