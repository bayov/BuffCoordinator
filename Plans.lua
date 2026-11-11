-- Saved plans: raids set up ahead of time, kept by name.
--
-- A plan is a copy of a mock raid (Mock.lua): its players and their parties,
-- specs, ranks, marks and roles, the players kept in their party, and its
-- assignments. The PLAN row at the top of the Assignments page (Profiles.lua)
-- saves the mock raid as a plan, loads a plan back into it, and makes one
-- from the raid we're in. Plans sort into folders, and a plan goes to
-- another player as a line of text (Pl.export, Pl.import).
--
-- A plan reaches a real raid when it's picked there. The raid pane shows
-- what it would do first (Pl.preview), and on Use it the specs, and the
-- assignments that name players who are here, go into the group's state
-- through the same edits the Assignments page makes, so a player who may
-- only suggest gets them in their draft. Then everyone moves to their
-- planned party, one move at a time (Group.lua), and the plan's real players
-- who aren't here can be invited.
--
-- The made-up players of a plan from a mock raid aren't in any real raid,
-- so a raider of the same class and spec takes each one's place, with
-- their party and assignments. What the board has set by hand for a raider
-- the plan doesn't have stays.
--
-- The plan we applied stays in use, across a reload and after we leave the
-- group. A player who joins later gets their place and their assignments
-- then, so a plan can be applied while the raid is still forming, or solo
-- before it forms. Its players who aren't here keep what it sets for them,
-- and the pages show them dimmed.
--
-- We never run the mock raid while we're in a group, because the HUD, the
-- whispers and what we send would go by its made-up roster. So applying a
-- plan works on the real group, and loading one waits until we're solo.
--
-- A plan can be the one for an instance, set while we're there or ahead of
-- time for one we zoned into lately. When we zone into it as the leader, we
-- print a line that says so.
--
-- `db.plans[name]` is like db.mock: { members, self, duty, specs, allAssist,
-- size, pins, saved }. `db.planInUse` is the plan we applied (below). `db.planFor[instance ID]` is the name of the plan for
-- that instance, and `db.instances` the last instances we zoned into, as
-- { id, name, size }, newest first. `db.planFolders` is the folders in
-- order, and `db.planFolder[name]` the folder a plan is in.

local _, NS = ...
local D, R, Du, G, M = NS.Data, NS.Roster, NS.Duties, NS.Group, NS.Mock
local copy, ser = NS.copy, NS.Sync.ser

local Pl = {}
NS.Plans = Pl

local function plans()
    if type(NS.db.plans) ~= "table" then NS.db.plans = {} end
    return NS.db.plans
end

local function changed() NS.signal("plans") end

-- The plan we applied last (below), and the raid size the leader picked.
-- Both last until we leave the group.
local active, picked

-- Makes `t` the plan in use, kept for the next session.
local function setActive(t)
    active = t
    NS.db.planInUse = t
end

-- The names of the plans, in order.
function Pl.list()
    local t = {}
    for name in pairs(plans()) do t[#t + 1] = name end
    table.sort(t)
    return t
end

function Pl.get(name) return name and plans()[name] or nil end

-- The plan the mock raid was loaded from or saved as, while it's on.
function Pl.current()
    if not M.on() then return nil end
    local name = NS.db.mock.plan
    return plans()[name] and name or nil
end

-- The mock raid as a plan keeps it. A spec that loading the plan filled in
-- from what we learned of a real player stays out, as it does when we save
-- a plan of a real raid (Pl.fromRaid).
local function snapshot()
    local snap = M.snapshot()
    local learned = type(NS.db.mock.learned) == "table" and NS.db.mock.learned or {}
    for name, tree in pairs(learned) do
        if snap.specs and snap.specs[name] == tree then snap.specs[name] = nil end
    end
    return snap
end

-- Whether the mock raid has changes its plan doesn't have yet, or isn't a
-- plan at all.
function Pl.dirty()
    if not M.on() then return false end
    local plan = Pl.get(Pl.current())
    if not plan then return true end
    local snap = snapshot()
    snap.saved = plan.saved
    return ser(snap) ~= ser(plan)
end

-- =============================================================
-- Making, saving and loading
-- =============================================================
-- A new plan for `n` players: a preset mock raid with every assignment on
-- auto, and no name until it's saved. Only while we're not in a group.
function Pl.new(n)
    if R.real.grouped() then return false end
    if M.exists() then M.set(true) else M.set(true, n) end
    if not M.on() then return false end
    M.load({ duty = {}, size = n })
    NS.db.mock.learned = nil
    M.fill(n)
    -- Undo works inside one plan. A step from before would change a raid
    -- that isn't there anymore.
    Du.forgetSteps()
    changed()
    return true
end

-- Saves the mock raid as plan `name`.
function Pl.save(name)
    if not M.on() or type(name) ~= "string" or name == "" then return false end
    local snap = snapshot()
    snap.saved = time()
    plans()[name] = snap
    NS.db.mock.plan = name
    changed()
    return true
end

-- Makes the mock raid plan `name`. Only while we're not in a group.
--
-- A plan of a real raid keeps only the specs set by hand. So a real player
-- whose spec it doesn't have gets the one we learned of them when we last
-- grouped (db.people), as when we add them to a mock raid by hand.
function Pl.load(name)
    local plan = Pl.get(name)
    if not plan or R.real.grouped() then return false end
    if M.exists() then M.set(true) else M.set(true, plan.size) end
    if not M.on() then return false end
    local t, learned = copy(plan), {}
    t.specs = type(t.specs) == "table" and t.specs or {}
    for _, p in ipairs(type(t.members) == "table" and t.members or {}) do
        local known = p.real and NS.db.people and NS.db.people[p.name]
        if known and t.specs[p.name] == nil and known.class == p.class and R.spec(p.class, known.spec) then
            t.specs[p.name], learned[p.name] = known.spec, known.spec
        end
    end
    M.load(t, name)
    NS.db.mock.learned = learned
    Du.forgetSteps()
    changed()
    return true
end

-- A copy goes in the same folder as the plan it copies.
function Pl.duplicate(name, new)
    local plan = Pl.get(name)
    if not plan or type(new) ~= "string" or new == "" or plans()[new] then return false end
    plans()[new] = copy(plan)
    Pl.setFolder(new, Pl.folderOf(name))
    changed()
    return true
end

-- Renames plan `old` to `new`, and everything that names it goes with it:
-- the mock raid, the active plan, the instances it's set for and its folder.
function Pl.rename(old, new)
    new = type(new) == "string" and new:match("^%s*(.-)%s*$") or ""
    if not plans()[old] or new == "" or new == old or plans()[new] then return false end
    plans()[new], plans()[old] = plans()[old], nil
    if type(NS.db.mock) == "table" and NS.db.mock.plan == old then NS.db.mock.plan = new end
    if active and active.name == old then active.name = new end
    for id, p in pairs(NS.db.planFor or {}) do
        if p == old then NS.db.planFor[id] = new end
    end
    local of = NS.db.planFolder
    if type(of) == "table" then of[new], of[old] = of[old], nil end
    changed()
    return true
end

function Pl.delete(name)
    if not plans()[name] then return false end
    plans()[name] = nil
    if active and active.name == name then setActive(nil) end
    if type(NS.db.mock) == "table" and NS.db.mock.plan == name then NS.db.mock.plan = nil end
    for id, p in pairs(NS.db.planFor or {}) do
        if p == name then NS.db.planFor[id] = nil end
    end
    if type(NS.db.planFolder) == "table" then NS.db.planFolder[name] = nil end
    changed()
    return true
end

-- `base` when no plan has that name, else the first of "base 2", "base 3"
-- and so on that's free.
function Pl.freeName(base)
    base = base or "Plan"
    if not plans()[base] then return base end
    local i = 2
    while plans()[base .. " " .. i] do i = i + 1 end
    return base .. " " .. i
end

-- =============================================================
-- Folders
-- =============================================================
-- Folders only sort the list of plans. A plan is in one folder or none, and
-- deleting a folder leaves its plans out of any.
local function folders()
    if type(NS.db.planFolders) ~= "table" then NS.db.planFolders = {} end
    return NS.db.planFolders
end

local function folderMap()
    if type(NS.db.planFolder) ~= "table" then NS.db.planFolder = {} end
    return NS.db.planFolder
end

local function folderIndex(name)
    for i, f in ipairs(folders()) do
        if f == name then return i end
    end
end

-- The folders, in order, empty ones too.
function Pl.folders()
    local t = {}
    for i, f in ipairs(folders()) do t[i] = f end
    return t
end

function Pl.folderOf(name)
    local f = name and folderMap()[name]
    return f and folderIndex(f) and f or nil
end

-- Puts plan `name` in folder `folder`, or in none (nil).
function Pl.setFolder(name, folder)
    if not plans()[name] or (folder ~= nil and not folderIndex(folder)) then return false end
    folderMap()[name] = folder
    changed()
    return true
end

function Pl.addFolder(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" or folderIndex(name) then return false end
    table.insert(folders(), name)
    changed()
    return true
end

function Pl.renameFolder(old, new)
    new = type(new) == "string" and new:match("^%s*(.-)%s*$") or ""
    local i = folderIndex(old)
    if not i or new == "" or folderIndex(new) then return false end
    folders()[i] = new
    for plan, f in pairs(folderMap()) do
        if f == old then folderMap()[plan] = new end
    end
    changed()
    return true
end

function Pl.deleteFolder(name)
    local i = folderIndex(name)
    if not i then return false end
    table.remove(folders(), i)
    for plan, f in pairs(folderMap()) do
        if f == name then folderMap()[plan] = nil end
    end
    changed()
    return true
end

-- =============================================================
-- Sharing a plan as text
-- =============================================================
-- A plan goes to another player as one line they paste into Import:
-- "BuffCoordinator plan 1:" and then the plan and its name, written the way
-- we send a board (Sync.ser). A "|" starts a colour or a link in the game's
-- text boxes, so it and "%" go as "%7C" and "%25", like any control
-- character.
local EXPORT = "BuffCoordinator plan 1:"

-- What every plan has, whatever an old save or a pasted line left out.
-- Jobs we don't know any more go.
local function tidyPlan(p)
    for _, k in ipairs({ "members", "duty", "specs", "pins" }) do
        if type(p[k]) ~= "table" then p[k] = {} end
    end
    for id in pairs(p.duty) do
        if not D.JOB[id] then p.duty[id] = nil end
    end
    return p
end

function Pl.export(name)
    local plan = Pl.get(name)
    if not plan then return nil end
    local text = ser({ name = name, plan = plan })
    return EXPORT .. (text:gsub("[%%|%c]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- Makes a plan of a line from Pl.export. Answers its name, which is the one
-- it was exported as unless a plan has that name already, or nil and why.
-- Players who aren't of a class we know, and parties that aren't 1 to 8,
-- don't come in.
function Pl.import(text)
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    local body = text:sub(1, #EXPORT) == EXPORT and text:sub(#EXPORT + 1) or nil
    if not body then return nil, "That isn't a Buff Coordinator plan." end
    body = body:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    local t = NS.Sync.deser(body)
    local plan = type(t) == "table" and type(t.plan) == "table" and t.plan or nil
    if not plan then return nil, "That plan is cut short. Copy all of it." end
    tidyPlan(plan)
    local members = {}
    for _, p in ipairs(plan.members) do
        if type(p) == "table" and type(p.name) == "string" and p.name ~= "" and D.SPECS[p.class] then
            p.group = tonumber(p.group)
            if not p.group or p.group < 1 or p.group > 8 then p.group = 1 end
            members[#members + 1] = p
        end
    end
    plan.members = members
    if type(plan.self) ~= "table" then plan.self = { group = 1, rank = 2 } end
    plan.size = tonumber(plan.size)
    local name = Pl.freeName(type(t.name) == "string" and t.name:match("^%s*(.-)%s*$") ~= "" and t.name
                             or "Imported plan")
    plans()[name] = plan
    changed()
    return name
end

-- The size Forever has that fits `n` players.
local function sizeFor(n)
    for _, size in ipairs(M.SIZES) do
        if size >= n then return size end
    end
    return 40
end

-- Saves the raid we're in as plan `name`: who is here, their parties,
-- ranks, marks and roles, the specs set by hand, and the group's
-- assignments.
--
-- A spec we learned (from their talents, their addon, FojjiCore or their
-- raid role) stays out of it. A plan's specs are set by hand when it's
-- applied, so a learned one would freeze there, and be wrong after the
-- player respecs.
function Pl.fromRaid(name)
    if NS.mock or not R.real.grouped() or type(name) ~= "string" or name == "" then return false end
    local plan = { members = {}, specs = {}, pins = {}, duty = copy(NS.groupState().duty) or {},
                   allAssist = _G.IsEveryoneAssistant and IsEveryoneAssistant() and true or nil,
                   size = sizeFor(#R.real.list()), saved = time() }
    for _, m in ipairs(R.real.list()) do
        local p = { group = m.group, rank = m.rank or 0, mark = m.mark, role = m.assigned }
        if m.me then
            plan.self = p
        else
            p.name, p.class, p.real = m.name, m.class, true
            plan.members[#plan.members + 1] = p
            if m.spec and m.specFrom == "set" then plan.specs[m.name] = m.spec end
        end
        if NS.Arrange.pinned(m.name) then plan.pins[m.name] = true end
    end
    plan.self = plan.self or { group = 1, rank = 2 }
    plans()[name] = plan
    changed()
    return true
end

-- =============================================================
-- Matching a plan to the raid
-- =============================================================
-- A plan made in a mock raid names made-up players, like Aldric, and
-- nobody in a real raid has their names. So each made-up player who isn't
-- here takes a raider in their place: one of the same class and spec, else
-- the same class and role, else the same class, who the plan doesn't name
-- and who doesn't have a place in it yet. We go through both in name order,
-- so the same raid always gets the same matches.
--
-- A real player of the plan isn't matched, since we can invite them. They
-- get their own place when they join.

-- The raid roles of the game, as a spec's role.
local ROLE = { TANK = "tank", HEALER = "healer" }

-- The role plan player `p` plays: the raid role they were given, else their
-- spec's.
local function planRole(p, tree)
    if ROLE[p.role] then return ROLE[p.role] end
    local s = R.spec(p.class, tree)
    return s and s.role or nil
end

-- "Protection warrior", or "warrior" when the plan doesn't know the spec.
local function describe(class, tree)
    local cls = NS.className(class):lower()
    local spec = Du.specName(class, tree)
    return spec and spec .. " " .. cls or cls
end

-- Adds to `match` ({ [plan name] = raider's name }) a raider for each
-- made-up player of `plan` who has none yet, from `members` (the roster).
-- Returns `match`.
local function matchUp(plan, members, match)
    local named, used, here = {}, {}, {}
    for _, p in ipairs(plan.members or {}) do named[p.name] = true end
    for _, real in pairs(match) do used[real] = true end
    local free = {}
    for _, m in ipairs(members) do
        here[m.name] = true
        if not m.me and not named[m.name] and not used[m.name] then free[#free + 1] = m end
    end
    table.sort(free, function(a, b) return a.name < b.name end)
    local open = {}
    for _, p in ipairs(plan.members or {}) do
        if not p.real and not match[p.name] and not here[p.name] then open[#open + 1] = p end
    end
    table.sort(open, function(a, b) return a.name < b.name end)
    local specs = plan.specs or {}
    local fits = {
        function(p, m) return specs[p.name] ~= nil and m.spec == specs[p.name] end,
        function(p, m)
            local role = planRole(p, specs[p.name])
            return role ~= nil and m.role == role
        end,
        function() return true end,
    }
    for _, fit in ipairs(fits) do
        for _, p in ipairs(open) do
            if not match[p.name] then
                for _, m in ipairs(free) do
                    if not used[m.name] and m.class == p.class and fit(p, m) then
                        match[p.name], used[m.name] = m.name, true
                        break
                    end
                end
            end
        end
    end
    return match
end

-- How plan `plan` meets the raid in `members`. `map` takes each name the
-- plan uses to the raider in that place: a made-up player to their match,
-- and anyone here to themselves, us too. `from` is the other way round, the
-- plan's name for each raider. `covered` is every name the plan speaks for,
-- here or not: its players, their matches and us. `match` is the matches,
-- the ones in `keep` first when they're still here.
local function meet(plan, members, keep)
    local here, map, from, covered = {}, {}, {}, {}
    for _, m in ipairs(members) do
        here[m.name] = true
        map[m.name], from[m.name] = m.name, m.name
    end
    -- A raider who left frees their place for the next one to join.
    local match = {}
    for who, real in pairs(keep or {}) do
        if here[real] then match[who] = real end
    end
    match = matchUp(plan, members, match)
    for _, p in ipairs(plan.members or {}) do
        covered[p.name] = true
        local real = here[p.name] and p.name or match[p.name]
        if real then
            map[p.name], from[real], covered[real] = real, p.name, true
        end
    end
    local me = R.real.me()
    if me then covered[me.name] = true end
    return map, covered, match, from
end

-- =============================================================
-- A plan's assignments in the raid
-- =============================================================
-- The parts of a job's entry that name players, as { key, prefix }. A key
-- of `picks`, `never`, `order` or `want` names a player when it starts
-- with "name:". The others are a class or a spec, which every raid has.
local NAMED = { { "picks", "name:" }, { "never", "name:" }, { "order", "name:" }, { "want", "name:" },
                { "choice", "" }, { "matrix", "" }, { "assign", "" } }

-- The name in `key`, or nil when it doesn't name a player. A choice, a
-- totem or a paladin override for a whole spec is kept under the spec's
-- pick, which every raid has.
local function nameIn(key, prefix)
    if type(key) ~= "string" then return nil end
    if prefix == "" then return not Du.isSpecKey(key) and key or nil end
    return key:match("^" .. prefix .. "(.+)$")
end

local function tidy(e)
    for _, f in ipairs(NAMED) do
        if type(e[f[1]]) == "table" and next(e[f[1]]) == nil then e[f[1]] = nil end
    end
    for name, f in pairs(type(e.fights) == "table" and e.fights or {}) do
        if next(f) == nil then e.fights[name] = nil end
    end
    if type(e.fights) == "table" and next(e.fights) == nil then e.fights = nil end
    return next(e) ~= nil and e or nil
end

-- The plan's assignments `duty` for the raid: each name in them goes
-- through `map` ({ [plan name] = raider's name }). A name `map` doesn't have
-- stays as it is, for a player who isn't here. Auto works around them, and
-- the pages show them dimmed.
local function mapDuty(duty, map)
    local out = {}
    for id, e in pairs(type(duty) == "table" and duty or {}) do
        if type(e) == "table" and D.JOB[id] then
            local x = copy(e)
            for _, f in ipairs(NAMED) do
                local k, prefix = f[1], f[2]
                if type(e[k]) == "table" then
                    x[k] = {}
                    for key, v in pairs(e[k]) do
                        local name = nameIn(key, prefix)
                        if not name then
                            x[k][key] = copy(v)
                        else
                            x[k][prefix .. (map[name] or name)] = copy(v)
                        end
                    end
                end
            end
            for _, f in pairs(type(x.fights) == "table" and x.fights or {}) do
                for _, v in pairs(f) do
                    if type(v) == "table" and map[v.giver] then v.giver = map[v.giver] end
                end
            end
            -- A paladin override for a player names them too.
            for name, row in pairs(type(x.assign) == "table" and x.assign or {}) do
                if type(row) == "table" then
                    local t = {}
                    for target, v in pairs(row) do
                        local who = nameIn(target, "name:")
                        t[who and "name:" .. (map[who] or who) or target] = v
                    end
                    x.assign[name] = next(t) and t or nil
                end
            end
            out[id] = tidy(x)
        end
    end
    return out
end

-- Puts back into `out` (mapDuty's) what the board's assignments `board` set
-- for players the plan doesn't speak for (not in `covered`). Applying a
-- plan never wipes what the leader set by hand for a raider the plan
-- doesn't have, unless the plan sets the same thing: a job's picks, when
-- the plan has picks for it, or a fight's school, when the plan names who
-- gives it.
local function keepOthers(out, board, covered)
    for id, b in pairs(type(board) == "table" and board or {}) do
        if type(b) == "table" and D.JOB[id] then
            local e = out[id] or {}
            for _, f in ipairs(NAMED) do
                local k, prefix = f[1], f[2]
                local mine = type(b[k]) == "table" and b[k] or {}
                local replaced = k == "picks" and e.picks ~= nil
                for key, v in pairs(mine) do
                    local name = nameIn(key, prefix)
                    if name and not covered[name] and not replaced then
                        e[k] = e[k] or {}
                        if e[k][key] == nil then e[k][key] = copy(v) end
                    end
                end
            end
            for fight, f in pairs(type(b.fights) == "table" and b.fights or {}) do
                for school, v in pairs(f) do
                    if type(v) == "table" and not covered[v.giver] then
                        e.fights = e.fights or {}
                        e.fights[fight] = e.fights[fight] or {}
                        if type(e.fights[fight][school]) ~= "table" then e.fights[fight][school] = copy(v) end
                    end
                end
            end
            out[id] = tidy(e)
        end
    end
    return out
end

-- What the assignments would be with plan `plan` applied.
--
-- A raider who takes a made-up player's place (in `match`) gets their
-- party, but not their overrides. Overrides are only ever set by hand for a
-- real player. Giving them out on their own put a made-up paladin's forced
-- Might on every paladin we grouped with. So the made-up player's settings
-- stay under their own name, like a player of the plan who isn't here, and
-- what the board set for the raider stays too.
local function forRaid(plan, map, covered, match)
    local m, c = copy(map), copy(covered)
    for who, real in pairs(match or {}) do
        m[who], c[real] = nil, nil
    end
    local state = NS.edited()
    return keepOthers(mapDuty(plan.duty, m), state and state.duty, c)
end

-- `board` (assignments) with what plan assignments `duty` set for plan
-- player `from` given to raider `to`, who just joined: their picks, the jobs
-- they never do, their choice, their blessings or totems by hand, their own
-- blessing order and the schools they give in a fight. A made-up player's
-- place on the board, kept while nobody had it, goes to the raider. Everything
-- else on the board stays.
local function joinDuty(board, duty, from, to)
    local out = copy(board) or {}
    for id, e in pairs(type(duty) == "table" and duty or {}) do
        if type(e) == "table" and D.JOB[id] then
            local x = out[id] or {}
            for _, f in ipairs(NAMED) do
                local k, prefix = f[1], f[2]
                -- Not `and`/`or`: a missing table would give `false`, and
                -- we'd copy that in as their setting.
                local v = nil
                if type(e[k]) == "table" then v = e[k][prefix .. from] end
                if v ~= nil then
                    x[k] = x[k] or {}
                    x[k][prefix .. to] = copy(v)
                end
            end
            for fight, f in pairs(type(e.fights) == "table" and e.fights or {}) do
                for school, v in pairs(f) do
                    if type(v) == "table" and v.giver == from then
                        x.fights = x.fights or {}
                        x.fights[fight] = x.fights[fight] or {}
                        x.fights[fight][school] = { giver = to, buff = v.buff }
                    end
                end
            end
            out[id] = tidy(x)
        end
    end
    if from ~= to then
        for id, x in pairs(out) do
            if type(x) == "table" then
                for _, f in ipairs(NAMED) do
                    local t = x[f[1]]
                    if type(t) == "table" then t[f[2] .. from] = nil end
                end
                for _, row in pairs(type(x.assign) == "table" and x.assign or {}) do
                    if type(row) == "table" and row["name:" .. from] ~= nil then
                        row["name:" .. to], row["name:" .. from] = row["name:" .. from], nil
                    end
                end
                out[id] = tidy(x)
            end
        end
    end
    return out
end

-- The assignments `board` without what plan `plan` gave the raiders who took
-- a made-up player's place, in `gone` ({ [made-up name] = raider's name }).
--
-- We call it when such a raider leaves, or when we leave the group. Without
-- it, each group's stand-in kept the made-up player's settings for good. A
-- plan with a made-up paladin on Might for everyone, carried from group to
-- group, left that override on every paladin we ever grouped with.
--
-- Only what still equals the plan's setting goes. What the leader changed
-- by hand since stays.
local function takeBack(board, plan, gone)
    local out = copy(board) or {}
    if not next(gone) then return out end
    for id, e in pairs(type(plan.duty) == "table" and plan.duty or {}) do
        local x = out[id]
        if type(e) == "table" and type(x) == "table" and D.JOB[id] then
            for who, real in pairs(gone) do
                for _, f in ipairs(NAMED) do
                    local k, prefix = f[1], f[2]
                    local mine, theirs = x[k], e[k]
                    if type(mine) == "table" and type(theirs) == "table" and theirs[prefix .. who] ~= nil
                       and Du.same(mine[prefix .. real], theirs[prefix .. who]) then
                        mine[prefix .. real] = nil
                    end
                end
                for fight, f in pairs(type(x.fights) == "table" and x.fights or {}) do
                    local planned = type(e.fights) == "table" and e.fights[fight]
                    for school, v in pairs(type(f) == "table" and f or {}) do
                        local pv = type(planned) == "table" and planned[school]
                        if type(v) == "table" and v.giver == real and type(pv) == "table" and pv.giver == who
                           and pv.buff == v.buff then
                            f[school] = nil
                        end
                    end
                end
            end
            out[id] = tidy(x)
        end
    end
    return out
end

-- Puts `duty` in the state we edit, as one step that Undo takes back: into
-- the group's state when we may change it, or into our draft when we may
-- only suggest. Returns whether we may edit at all.
local function restore(duty, text)
    if not NS.writable() then return false end
    Du.restore({ duty = duty }, text)
    return true
end

-- Gives raider `m` plan player `who`'s spec, when it's their own place and
-- we haven't learned their spec. What their talents, addon or raid role say
-- is fresher than what the plan remembers, and a match has a spec of
-- their own.
local function giveSpec(plan, who, m)
    local tree = (plan.specs or {})[who]
    if who == m.name and tree and not m.me and not m.learned and R.spec(m.class, tree) and m.spec ~= tree then
        R.setSpec(m.name, tree)
    end
end

-- =============================================================
-- Applying a plan to the raid
-- =============================================================
-- The plan we applied last: { name, match, placed, restored, want, auto,
-- carried }. The players who join later get their place and their
-- assignments from it. `placed` and `restored` are the raiders we already
-- gave a party and assignments, by name, and `want` the layout we last
-- asked the move queue for. `auto` is set when it was applied as the plan
-- for the instance (Auto on the PLAN row).
--
-- `carried` is set when it wasn't applied in the group we're in: solo, or
-- in a group we left since. It goes on into the next group only when we
-- lead it, since someone else's raid has its own plan.

-- Whether the plan in use waits, since we're in someone else's group.
local function waiting()
    return active ~= nil and active.carried and R.real.grouped() and not G.isLeader()
end

function Pl.active()
    if not active or waiting() then return nil end
    return active.name
end

-- Player `name` of the plan in use, as { name, class, spec }, or nil.
function Pl.player(name)
    local plan = active and Pl.get(active.name)
    for _, p in ipairs(plan and plan.members or {}) do
        if p.name == name then
            return { name = name, class = p.class, spec = (plan.specs or {})[name] }
        end
    end
    return nil
end

-- Whether the active plan went in as the plan for the instance.
function Pl.activeAuto() return active ~= nil and active.auto == true end

-- Stops giving the players who join their place in the active plan.
function Pl.stop()
    setActive(nil)
    changed()
end

-- The plan's real players who aren't here, by name.
function Pl.missing(name)
    local plan, t = Pl.get(name), {}
    if not plan then return t end
    for _, p in ipairs(plan.members or {}) do
        if p.real and not R.real.byName(p.name) then t[#t + 1] = p.name end
    end
    table.sort(t)
    return t
end

-- The party plan `plan` wants each raider in, by name, through `map`.
local function wanted(plan, map)
    local want = {}
    for _, p in ipairs(plan.members or {}) do
        local real = map[p.name]
        if real then want[real] = p.group end
    end
    local me = R.real.me()
    if me and plan.self then want[me.name] = plan.self.group end
    return want
end

-- Whether we may apply a plan at all: change the assignments (or suggest
-- them), or move players.
function Pl.canApply()
    if NS.mock then return false end
    if not R.real.grouped() then return true end
    return NS.Suggest.canChange() or (R.real.raid() and G.mayArrange())
end

-- Whether applying a plan only puts it in our draft, since we may suggest
-- but not change the assignments.
function Pl.drafting()
    return not NS.mock and not R.canEdit() and NS.Suggest.canChange()
end

-- The matches the active plan made, to keep when it's applied again.
local function kept(name)
    return active and active.name == name and active.match or nil
end

-- What applying plan `name` would do, for the raid pane to show first:
--   { plan, want = { [name] = party } for everyone here, moved = { [name] =
--     party they leave }, n = how many move, changes = how many jobs'
--     assignments change, missing = how many of its real players aren't
--     here, matches = { { from, what, to } } for the raiders who take a
--     made-up player's place, matchOf = the same by raider's name,
--     unmatched = how many made-up players have no match }
-- `want` is where the move queue would put everyone, so a player the plan
-- doesn't name shows where a swap would leave them.
function Pl.preview(name)
    local plan = Pl.get(name)
    if not plan or not Pl.canApply() then return nil end
    local members = R.real.list()
    local map, covered, match = meet(plan, members, kept(name))
    local p = { plan = name, want = {}, moved = {}, n = 0, changes = 0, missing = #Pl.missing(name),
                matches = {}, matchOf = {}, unmatched = 0 }
    if R.real.raid() and G.mayArrange() then
        p.want = G.layout(wanted(plan, map), members)
    end
    for _, m in ipairs(members) do
        p.want[m.name] = p.want[m.name] or m.group
        if p.want[m.name] ~= m.group then
            p.moved[m.name] = m.group
            p.n = p.n + 1
        end
    end
    if NS.Suggest.canChange() then
        local duty, state = forRaid(plan, map, covered, match), NS.edited()
        for _, job in ipairs(D.JOBS) do
            local want = type(duty[job.id]) == "table" and duty[job.id] or nil
            if not Du.same(want, state and state.duty[job.id]) then p.changes = p.changes + 1 end
        end
    end
    for _, q in ipairs(plan.members or {}) do
        if not q.real and not R.real.byName(q.name) then
            if match[q.name] then
                local x = { from = q.name, what = describe(q.class, (plan.specs or {})[q.name]), to = match[q.name] }
                p.matches[#p.matches + 1] = x
                p.matchOf[x.to] = x
            else
                p.unmatched = p.unmatched + 1
            end
        end
    end
    table.sort(p.matches, function(a, b) return a.from < b.from end)
    return p
end

-- Applies plan `name` to the raid we're in, or to us alone: the specs and
-- assignments of the players here and the raiders who take a made-up
-- player's place, then their parties. Returns whether it changed anything,
-- and whether players are moving. The plan stays in use, so a player who
-- joins later gets their place too. `auto` says it's the plan for the
-- instance, picked by Auto.
function Pl.apply(name, auto)
    local plan = Pl.get(name)
    if not plan or NS.mock then return false end
    local members = R.real.list()
    local map, covered, match = meet(plan, members, kept(name))
    local edit = NS.Suggest.canChange()
    local edited = false
    if edit then
        for _, m in ipairs(members) do giveSpec(plan, m.name, m) end
        edited = restore(forRaid(plan, map, covered, match), "load " .. name)
    end
    local arrange = R.real.raid() and G.mayArrange()
    local want = wanted(plan, map)
    local moving = arrange and G.arrange(want) or false
    setActive({ name = name, match = match, placed = {}, restored = {}, want = moving and want or nil,
                auto = auto and true or nil, carried = not R.real.grouped() or nil })
    for _, m in ipairs(R.real.list()) do
        if arrange then active.placed[m.name] = true end
        if edited then active.restored[m.name] = true end
    end
    return edited or moving, moving
end

-- Gives the raiders who joined since the active plan was applied their
-- place and their assignments: a player of the plan their own, and someone
-- new the place of a made-up player they match (only the place, see
-- forRaid). In a party we only give assignments, and the places wait until
-- it's a raid.
local function follow()
    if not active or NS.mock or not R.real.grouped() or waiting() then return end
    local plan = Pl.get(active.name)
    if not plan then
        setActive(nil)
        return
    end
    local members = R.real.list()
    local here, gone = {}, {}
    for _, m in ipairs(members) do here[m.name] = true end
    for who, real in pairs(active.match or {}) do
        if not here[real] then gone[who] = real end
    end
    local map, _, match, from = meet(plan, members, active.match)
    active.match = match
    local planned = wanted(plan, map)
    local arrange = R.real.raid() and G.mayArrange()
    local edit = NS.Suggest.canChange()
    local joined, duty = {}, nil
    if edit and next(gone) then
        local state = NS.edited()
        duty = takeBack(state and state.duty, plan, gone)
    end
    for _, m in ipairs(members) do
        if arrange and not active.placed[m.name] then
            active.placed[m.name] = true
            if planned[m.name] then joined[m.name] = planned[m.name] end
        end
        if edit and not active.restored[m.name] then
            active.restored[m.name] = true
            local who = from[m.name]
            if who == m.name and not m.me then
                giveSpec(plan, who, m)
                local state = NS.edited()
                duty = joinDuty(duty or (state and state.duty), plan.duty, who, m.name)
            end
        end
    end
    if duty then restore(duty, "load " .. active.name) end
    if next(joined) then
        -- Everyone already in their planned party is in the layout too, so
        -- a joiner who swaps into a full party swaps with someone the plan
        -- doesn't put there. The moves still under way go on.
        local want = G.arranging() and copy(active.want) or {}
        for _, m in ipairs(members) do
            if planned[m.name] and planned[m.name] == m.group then want[m.name] = m.group end
        end
        for name, g in pairs(joined) do want[name] = g end
        active.want = want
        G.arrange(want)
    end
end

NS.listen("roster", function()
    if active then NS.soon("planFollow", 0.5, follow) end
end)

-- Invites plan `name`'s players who aren't here. Returns how many.
function Pl.invite(name)
    return G.invite(Pl.missing(name))
end

-- =============================================================
-- Plans for an instance
-- =============================================================
-- The instance we're in: its ID, name and how many it's for, or nil.
function Pl.instance()
    if not _G.GetInstanceInfo then return nil end
    local ok, iname, itype, _, _, maxPlayers, _, _, id = pcall(GetInstanceInfo)
    if not ok or not id or itype == nil or itype == "none" then return nil end
    return { id = tostring(id), name = iname, size = tonumber(maxPlayers) }
end

-- The plan for instance `id`, or nil.
function Pl.forInstance(id)
    local name = id and NS.db.planFor and NS.db.planFor[id]
    return plans()[name] and name or nil
end

-- The plan for the instance we're in.
function Pl.forHere()
    local inst = Pl.instance()
    return inst and Pl.forInstance(inst.id) or nil
end

-- Makes plan `name` the one for instance `id`, or none (nil).
function Pl.useFor(id, name)
    if not id then return false end
    if type(NS.db.planFor) ~= "table" then NS.db.planFor = {} end
    NS.db.planFor[tostring(id)] = name
    changed()
    return true
end

-- The instances we zoned into last, newest first, so a plan can be set for
-- one before we go there. The game only tells us about the instance we're
-- in, so these are what we know.
local RECENT = 10

local function remember(inst)
    local db = NS.db
    if type(db.instances) ~= "table" then db.instances = {} end
    local list = db.instances
    for i = #list, 1, -1 do
        if list[i].id == inst.id then table.remove(list, i) end
    end
    table.insert(list, 1, { id = inst.id, name = inst.name, size = inst.size })
    for i = #list, RECENT + 1, -1 do list[i] = nil end
end

-- The instances a plan can be set for: the one we're in first, then the
-- ones we zoned into last, as { id, name, size, here }.
function Pl.instances()
    local t, seen = {}, {}
    local inst = Pl.instance()
    if inst then
        t[1] = { id = inst.id, name = inst.name, size = inst.size, here = true }
        seen[inst.id] = true
    end
    for _, x in ipairs(type(NS.db.instances) == "table" and NS.db.instances or {}) do
        if not seen[x.id] then
            seen[x.id] = true
            t[#t + 1] = { id = x.id, name = x.name, size = x.size }
        end
    end
    return t
end

-- The raid size the leader picked for the raid we're in, or nil for none.
-- The pane's heading picks it. While a 25 forms in town, the head count
-- alone would say 15 when 12 are in.
function Pl.pickedSize() return picked end

function Pl.pickSize(n)
    picked = tonumber(n)
    changed()
end

-- How many the raid is for: the mock's size, else the size the leader
-- picked, else the instance's, else the size of plan `preview` (the one
-- the pane previews), the active plan's in a group or the plan for the
-- instance, else the size Forever has that fits who is here.
function Pl.raidSize(preview)
    if NS.mock then return M.raidSize() end
    if picked and R.raid() then return picked end
    local inst = Pl.instance()
    if inst and inst.size and inst.size > 5 then return inst.size end
    local inUse = R.real.grouped() and Pl.active() or nil
    local plan = Pl.get(preview) or Pl.get(inUse) or Pl.get(Pl.forHere())
    if plan and plan.size then return plan.size end
    if not R.raid() then return 5 end
    return sizeFor(#R.list())
end

-- On zoning into an instance that has a plan, as the leader, we say so
-- once.
local hinted

local function hint()
    local inst = Pl.instance()
    if not inst then
        hinted = nil
        return
    end
    remember(inst)
    local name = Pl.forHere()
    if not name or hinted == inst.id or NS.mock or not R.real.grouped() or not G.isLeader() then return end
    if not NS.Options.get("planHint") then return end
    hinted = inst.id
    NS.print("Plan %s is set for this instance. Pick Auto on the Assignments page's PLAN row to apply it.", name)
end

NS.on("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, hint) end)

-- The next group is another raid, with its own size and its own players.
-- The plan stays in use, and gives them their places when we lead it.
local function left()
    picked = nil
    if not active then return end
    local plan = Pl.get(active.name)
    if plan and not NS.mock and next(active.match or {}) then
        local state = NS.edited()
        local duty = takeBack(state and state.duty, plan, active.match)
        if not Du.same(duty, state and state.duty) then restore(duty, "plan " .. active.name .. " ends") end
    end
    active.match, active.placed, active.restored, active.want = {}, {}, {}, nil
    active.carried = true
end
NS.on("GROUP_LEFT", left)
NS.listen("groupLeft", left)

-- A login outside a group is after we left the last one.
NS.listen("login", function()
    if active and not R.real.grouped() then left() end
end)

NS.listen("loaded", function()
    local db = NS.db
    if type(db.plans) ~= "table" then db.plans = {} end
    if type(db.planFor) ~= "table" then db.planFor = {} end
    if type(db.instances) ~= "table" then db.instances = {} end
    for i = #db.instances, 1, -1 do
        local x = db.instances[i]
        if type(x) ~= "table" or type(x.id) ~= "string" then table.remove(db.instances, i) end
    end
    for name, p in pairs(db.plans) do
        if type(p) ~= "table" then db.plans[name] = nil else tidyPlan(p) end
    end
    if type(db.planFolders) ~= "table" then db.planFolders = {} end
    for i = #db.planFolders, 1, -1 do
        if type(db.planFolders[i]) ~= "string" then table.remove(db.planFolders, i) end
    end
    if type(db.planFolder) ~= "table" then db.planFolder = {} end
    for name in pairs(db.planFolder) do
        if not db.plans[name] then db.planFolder[name] = nil end
    end
    local use = db.planInUse
    if type(use) == "table" and type(use.name) == "string" and db.plans[use.name] then
        for _, k in ipairs({ "match", "placed", "restored" }) do
            if type(use[k]) ~= "table" then use[k] = {} end
        end
        if type(use.want) ~= "table" then use.want = nil end
        active = use
    else
        db.planInUse, active = nil, nil
    end
end)
