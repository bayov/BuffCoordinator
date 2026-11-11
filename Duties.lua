-- Who does each job: the board.
--
-- Every job is "auto" until the leader or an assistant changes it. Auto picks
-- who does a job by the rules in the job's kind (Data.lua): one giver buffs
-- the raid with a long buff, every paladin gives each person a different
-- blessing, and a single job goes to the spec it prefers.
--
-- An override is a list of picks: a player ("name:Grom"), a class
-- ("class:WARRIOR") or a class and spec ("spec:WARRIOR:3", by talent tree).
-- What the picks mean depends on how many givers the job has, and
-- Du.pickText says it in words:
--   one giver   a long buff or a single job takes the picks in order, the
--               first one here who can do it. A class or a spec picked
--               means one of them, the best fit. So "Grom, else a warrior,
--               else auto".
--   many        blessings, auras and judgements take everyone picked.
-- When nobody picked can do it, the job goes back to auto, and the plan says
-- why (`plan.picked`). A job can also name players it never goes to, even
-- in auto ("Never: Carl"). A choice job (auras, judgements) also takes which
-- option each giver puts up. Blessings take the order of blessings a class,
-- a spec or one player wants, and which blessing a paladin gives a whole
-- class.
--
-- A long buff or a blessing also has backups: the others who can give it.
-- A backup's HUD has the assignment too, and it lights up when someone has
-- been missing the buff for a while (the "Backups wait" setting), so a
-- priest who is late or lagging gets covered. Two players may click at once
-- now and then, which costs a little mana and nothing else.
--
-- A fight that needs resistances (Ragnaros wants fire) is set up once and
-- chosen before the pull. For each school it asks for, one player puts the
-- resistance up instead of something else of theirs (an aura, a totem, an
-- aspect). We pick whoever loses the least by it, and the Assignments page
-- says what the raid loses.
--
-- The board is worked out from the roster and the overrides only, never from
-- the buffs anyone has up right now. So everyone who runs the addon with the
-- same overrides works out the same board.
--
-- While a player drafts a suggestion (Suggest.lua), the getters and setters
-- here read and change the draft, because the window uses them. Working the
-- board out reads the group's state (NS.asGroup).
--
-- Every setter is one step we can undo (Du.undo), and Du.batch makes many
-- setters one step. The settings one at a time are "items" (below), which
-- an undo step, a suggestion and the overrides' statuses all go by.
--
-- `db.duty[job]` is
--   picks    { [pick] = place }, 1 first, or nil for auto. Saves from
--            before the order have `true` for every place.
--   never    { [pick] = true }: who never does the job
--   choice   { [giver name] = buff id } for a choice job
--   order    for blessings: { [CLASS, "CLASS:tree" or "name:X"] = { blessing ids } }
--   assign   for blessings: { [paladin name] = { ["all" or a pick] = blessing id } },
--   matrix   for blessings: { [paladin name] = { [CLASS] = blessing id or "none" } },
--            for totems: { [shaman name] = { [element] = totem id or "none" } }
--   on       true or false when the job was turned on or off by hand
--   fights   for resistances: { [fight name] = { [school] = true for auto, or
--            { giver = name, buff = id } } }
--   fight    for resistances: the fight on now, or nil

local _, NS = ...
local D, R = NS.Data, NS.Roster

local format = string.format

local Du = {}
NS.Duties = Du

local copy = NS.copy

local function same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
Du.same = same

local function sortedKeys(t)
    local list = {}
    if type(t) ~= "table" then return list end
    for k in pairs(t) do
        if type(k) == "string" then list[#list + 1] = k end
    end
    table.sort(list)
    return list
end

-- =============================================================
-- Words
-- =============================================================
local function bname(b)
    return NS.Tracking and NS.Tracking.title(b) or b.name
end

local className, classWord, upperFirst, andList = NS.className, NS.classWord, NS.upperFirst, NS.andList
local article = NS.article

local SPECIAL = { beastmastery = "Beast Mastery", feralcombat = "Feral" }

-- A spec's name as players say it: "Holy", "Beast Mastery". nil when we
-- don't know the spec.
function Du.specName(class, tree)
    local s = R.spec(class, tree)
    if not s then return nil end
    return SPECIAL[s.key] or upperFirst(s.key)
end

-- Whether job `job` has one giver, which makes its picks an ordered list.
local function oneGiver(job)
    return job.kind == "cover" or job.kind == "single"
end
Du.oneGiver = oneGiver

-- =============================================================
-- Overrides
-- =============================================================
-- A duty table the getters read instead of the state's, while Du.costs works
-- out a board with fewer overrides.
local reading

-- The override entry of job `jobId`, or nil.
local function entry(jobId)
    local duty = reading
    if not duty then
        local state = NS.edited()
        duty = state and state.duty
    end
    local e = duty and duty[jobId]
    return type(e) == "table" and e or nil
end

-- Field `k` of job `jobId`'s entry when it's a table, else nil. A board
-- sent over the network may hold anything where a table should be, and
-- every client works the board out from it, so the getters only read what
-- has the right shape.
local function part(jobId, k)
    local e = entry(jobId)
    local t = e and e[k]
    return type(t) == "table" and t or nil
end

-- What `t[k]` holds when it's a string, else nil.
local function str(t, k)
    local v = t and t[k]
    return type(v) == "string" and v or nil
end

-- Row `name` of job `jobId`'s matrix when it's a table, else nil.
local function row(jobId, name)
    local m = part(jobId, "matrix")
    local r = m and m[name]
    return type(r) == "table" and r or nil
end

-- Drops what holds nothing any more in `duty`'s entry for `jobId`, and the
-- entry itself when it's empty.
local function tidyIn(duty, jobId)
    local e = duty[jobId]
    if type(e) ~= "table" then return end
    for _, k in ipairs({ "matrix", "assign", "want" }) do
        if type(e[k]) == "table" then
            for name, row in pairs(e[k]) do
                if type(row) ~= "table" or next(row) == nil then e[k][name] = nil end
            end
        end
    end
    for _, k in ipairs({ "picks", "never", "choice", "matrix", "order", "assign", "want", "fights" }) do
        if type(e[k]) == "table" and next(e[k]) == nil then e[k] = nil end
    end
    if next(e) == nil then duty[jobId] = nil end
end

-- The undo steps, newest last: { text, where, items }. `items` is what the
-- step changed, one setting each (Du.diff), so undoing it puts back only
-- those settings and leaves what another officer changed in the same job
-- alone. `where` is the state the step changed: our draft, or the group's
-- (NS.state). A step is only undone in the state it changed, so a board
-- whoever runs it sent us since, a group we left or a draft we applied
-- leaves its steps behind.
local history = {}
local HISTORY = 50
-- The steps we undid, newest last, for Du.redo. A new step drops them, as
-- in any editor.
local future = {}
-- The step being made now: the entries it changes as they were before.
local step
-- True while we undo, so undoing isn't a step of its own.
local replaying = false

local function where()
    return NS.draft or NS.state()
end

-- Remembers job `jobId`'s entry in `state` before the step changes it.
local function begin(state, jobId)
    step = step or { before = {}, jobs = {} }
    if step.before[jobId] == nil then
        step.before[jobId] = copy(state.duty[jobId]) or false
        step.jobs[#step.jobs + 1] = jobId
    end
end

-- The entry an edit of job `jobId` goes into, made when it's missing. nil
-- when the assignments are locked for us.
--
-- With `own`, it's an edit of our own blessing order (Du.setOwnBlessOrder),
-- which anyone may make. It goes into the group's assignments even when we
-- may only suggest changes, never into our draft.
local function edit(jobId, own)
    local state
    if own then
        if NS.Sync and NS.Sync.early then NS.Sync.early() end
        state = NS.state()
    else
        state = NS.writable()
    end
    if not state then return nil end
    begin(state, jobId)
    local e = state.duty[jobId]
    if type(e) ~= "table" then
        e = {}
        state.duty[jobId] = e
    end
    return e
end

local changeText

-- Keeps step `s` for Du.undo, unless it changed nothing.
local function remember(s, text)
    if replaying then return end
    local state = NS.edited()
    local old, new = {}, {}
    for _, id in ipairs(s.jobs) do
        old[id] = s.before[id] or nil
        new[id] = state.duty[id]
    end
    local diff = Du.diff(old, new)
    local specs = s.specs
    if #diff == 0 and not specs then return end
    if not text and #diff == 0 then
        text = specs[1].text
        if #specs > 1 then text = format("%s and %d more", text, #specs - 1) end
    elseif not text then
        text = changeText(diff[1])
        local more = #diff - 1 + (specs and #specs or 0)
        if more > 0 then text = format("%s and %d more", text, more) end
    end
    -- In a draft we also keep what each setting was in the group's
    -- assignments then (`bw`), so an undo can tell when the leader changed it
    -- since.
    local d = NS.draft
    if d and d.base then
        for _, it in ipairs(diff) do it.bw = copy(Du.itemValue(d.base.duty, it)) end
    end
    Du.keep({ text = text, where = where(), items = diff, specs = specs })
end

-- Ends step `s`: tidies its jobs, keeps it for Du.undo, and tells the
-- window. An edit of a draft changes only what the window shows. Any other
-- edit changes the board, and Sync.lua sends each job it changed.
--
-- Our own blessing order (`what` is "own") went into the group's
-- assignments even with a draft, and isn't kept for Du.undo, since an undo
-- would go into the draft.
local function finish(s, what, text)
    local own = what == "own"
    local state = own and NS.state() or NS.edited()
    for _, id in ipairs(s.jobs) do tidyIn(state.duty, id) end
    if not own then remember(s, text) end
    if NS.draft and not own then
        NS.signal("draft")
        return
    end
    Du.update()
    -- Only "Everything to auto" (Du.resetAll) goes to the group as one
    -- reset. One job back to auto (Du.reset) is an edit of that job like
    -- any other, or everyone would clear every job.
    if what == "resetAll" then
        -- A fight's givers set by hand go first, as an edit of their own,
        -- while Sync.lua still knows what they were. A client from before a
        -- reset cleared the fights too leaves them alone on a reset, so it
        -- takes them from this edit.
        if s.before.resistances and not same(s.before.resistances, state.duty.resistances) then
            NS.signal("edit", "resistances", "reset")
        end
        NS.signal("edit", nil, "reset")
        return
    end
    -- Sync.lua tells what an edit changed from the assignments it had
    -- before, so the group hears one job at a time, each on top of the ones
    -- before it.
    local jobs, after = {}, {}
    for _, id in ipairs(s.jobs) do
        if not same(s.before[id] or nil, state.duty[id]) then
            jobs[#jobs + 1] = id
            after[id] = state.duty[id]
            state.duty[id] = s.before[id] or nil
        end
    end
    for _, id in ipairs(jobs) do
        state.duty[id] = after[id]
        NS.signal("edit", id, what)
    end
end

local function changed(jobId, what)
    if not step or step.batch then return end
    local s = step
    step = nil
    finish(s, what)
end

-- Runs `fn`, which may call any of the setters, as one step: one undo, one
-- new board. `text` says what it did for Du.undoText ("load Molten Core"),
-- and without it we say what changed.
function Du.batch(text, fn)
    if step and step.batch then return fn() end
    step = { batch = true, before = {}, jobs = {} }
    local ok, err = pcall(fn)
    local s = step
    step = nil
    if #s.jobs > 0 then
        finish(s, "batch", text)
    elseif s.specs then
        remember(s, text)
    end
    if not ok then error(err, 0) end
end

function Du.enabled(job)
    local e = entry(job.id)
    if e and type(e.on) == "boolean" then return e.on end
    return not job.optional
end

function Du.setEnabled(job, on)
    local e = edit(job.id)
    if not e then return end
    if on == not job.optional then on = nil end
    e.on = on
    changed(job.id, "enabled")
end

-- =============================================================
-- Picks
-- =============================================================
function Du.splitPick(pick)
    if type(pick) ~= "string" then return nil end
    return pick:match("^([^:]+):([^:]+):?(.*)$")
end

-- Whether `pick` is one: a player, a class or a spec.
local function isPick(pick)
    local kind = Du.splitPick(pick)
    return kind == "name" or kind == "class" or kind == "spec"
end

function Du.pickMatches(pick, m)
    local kind, a, b = Du.splitPick(pick)
    if kind == "name" then return m.name == a end
    if kind == "class" then return m.class == a end
    if kind == "spec" then return m.class == a and m.spec == tonumber(b) end
    return false
end

-- The picks of set `set` in order: by the place each was given, then a
-- player before a spec before a class, then by name. An older save gave
-- every pick `true`, which comes after the places.
local PICK_KIND = { name = 1, spec = 2, class = 3 }

local function ordered(set)
    if type(set) ~= "table" then return nil end
    local list = {}
    for pick, v in pairs(set) do
        if v and type(pick) == "string" and Du.splitPick(pick) then list[#list + 1] = pick end
    end
    if #list == 0 then return nil end
    local function place(p) return type(set[p]) == "number" and set[p] or math.huge end
    table.sort(list, function(a, b)
        if place(a) ~= place(b) then return place(a) < place(b) end
        local ka, kb = PICK_KIND[a:match("^(%a+)")] or 9, PICK_KIND[b:match("^(%a+)")] or 9
        if ka ~= kb then return ka < kb end
        return a < b
    end)
    return list
end

-- A list of picks as the set we keep, or nil when it's empty.
local function ranked(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local set = {}
    for i, pick in ipairs(list) do
        if set[pick] == nil then set[pick] = i end
    end
    return set
end

-- The picks of job `jobId` as a set, or nil for auto.
function Du.picks(jobId)
    local list = ordered(entry(jobId) and entry(jobId).picks)
    if not list then return nil end
    local set = {}
    for _, pick in ipairs(list) do set[pick] = true end
    return set
end

-- The picks of job `jobId` in order, or nil for auto.
function Du.pickList(jobId)
    local e = entry(jobId)
    return ordered(e and e.picks)
end

-- Who job `jobId` never goes to, as a set of picks, or nil.
function Du.never(jobId)
    local e = entry(jobId)
    local n = e and e.never
    if type(n) ~= "table" or next(n) == nil then return nil end
    return n
end

local function without(list, pick)
    local t = {}
    for _, p in ipairs(list or {}) do
        if p ~= pick then t[#t + 1] = p end
    end
    return t
end

-- Picks or unpicks `pick`. A new pick goes last, after the ones before it.
function Du.setPick(jobId, pick, on)
    local e = edit(jobId)
    if not e then return end
    local list = without(ordered(e.picks), pick)
    if on then
        list[#list + 1] = pick
        if type(e.never) == "table" then e.never[pick] = nil end
    end
    e.picks = ranked(list)
    changed(jobId, "picks")
end

-- Sets job `jobId`'s picks to `list`, in its order.
function Du.setPicks(jobId, list)
    local e = edit(jobId)
    if not e then return end
    e.picks = ranked(list)
    for _, pick in ipairs(list or {}) do
        if type(e.never) == "table" then e.never[pick] = nil end
    end
    changed(jobId, "picks")
end

-- Keeps `pick` off job `jobId`, even in auto, or lets them back on.
function Du.setNever(jobId, pick, on)
    local e = edit(jobId)
    if not e then return end
    e.never = type(e.never) == "table" and e.never or {}
    e.never[pick] = on and true or nil
    if on then e.picks = ranked(without(ordered(e.picks), pick)) end
    changed(jobId, "never")
end

function Du.clearPicks(jobId)
    local e = edit(jobId)
    if not e then return end
    e.picks = nil
    changed(jobId, "picks")
end

-- Whether player `m` matches one of `picks`, and whether by name. A board
-- from the network may hold anything, so what isn't a pick never matches.
local function picked(picks, m)
    if not picks then return true, false end
    if picks["name:" .. m.name] then return true, true end
    for pick in pairs(picks) do
        if type(pick) == "string" and Du.pickMatches(pick, m) then return true, false end
    end
    return false, false
end

-- Whether job `never` keeps player `m` off it.
local function barred(never, m)
    if type(never) ~= "table" then return false end
    for pick, on in pairs(never) do
        if on and type(pick) == "string" and Du.pickMatches(pick, m) then return true end
    end
    return false
end

-- A pick in words: "Bob", and for a job with one giver "a warlock" or "an
-- Affliction warlock", for one with many "all warlocks" or "Affliction
-- warlocks".
function Du.pickWords(pick, one)
    local kind, a, b = Du.splitPick(pick)
    if kind == "name" then return a end
    if kind == "class" then
        return one and article(className(a):lower()) or "all " .. classWord(a)
    end
    local spec = Du.specName(a, tonumber(b)) or "?"
    if one then return article(spec .. " " .. className(a):lower()) end
    return spec .. " " .. classWord(a)
end

-- What job `jobId`'s picks mean, as a sentence: "Bob, else a warlock, else
-- auto. Never Carl." `list` and `never` are the job's own unless given.
local function pickSentence(job, list, never)
    local one = oneGiver(job)
    local parts = {}
    if list then
        local words = {}
        for i, pick in ipairs(list) do words[i] = Du.pickWords(pick, one) end
        if one then
            parts[1] = table.concat(words, ", else ") .. ", else auto."
            if job.scope == "party" then parts[1] = parts[1] .. " In each party." end
        else
            parts[1] = andList(words) .. ", else auto."
        end
    else
        parts[1] = "Auto."
    end
    if never then
        local words = {}
        for _, pick in ipairs(ordered(never) or {}) do words[#words + 1] = Du.pickWords(pick, false) end
        if #words > 0 then parts[#parts + 1] = "Never " .. andList(words, "or") .. "." end
    end
    return upperFirst(table.concat(parts, " "))
end

function Du.pickText(jobId)
    local job = D.JOB[jobId]
    if not job then return "" end
    return pickSentence(job, Du.pickList(jobId), Du.never(jobId))
end

-- =============================================================
-- Choices, blessings and totems by hand
-- =============================================================
-- A paladin's blessing override, an aura or judgement, and a totem are kept
-- under the giver's name. One for a whole spec is kept under the spec's
-- pick instead, like "spec:PALADIN:1" for Holy paladins, and every player
-- of the spec does it unless they have their own.

-- The spec pick of player `m`, or nil while we don't know their spec.
local function specKey(m)
    return m and m.class and m.spec and format("spec:%s:%d", m.class, m.spec) or nil
end
Du.specKey = specKey

-- Whether `key` is a whole spec's rather than a player's name.
function Du.isSpecKey(key)
    return type(key) == "string" and key:find("^spec:%u+:%d$") ~= nil
end

-- Who a setting kept under `key` is about, in words, and whether that's
-- many: "Mira", or "Holy paladins".
function Du.holderWords(key)
    if Du.isSpecKey(key) then return upperFirst(Du.pickWords(key, false)), true end
    return key, false
end

function Du.choice(jobId, giver)
    return str(part(jobId, "choice"), giver)
end

-- What player `m` puts up for choice job `jobId` by hand: their own, else
-- their spec's. The key it's kept under comes second.
function Du.choiceFor(jobId, m)
    local v = Du.choice(jobId, m.name)
    if v then return v, m.name end
    local key = specKey(m)
    v = key and Du.choice(jobId, key)
    if v then return v, key end
    return nil
end

function Du.setChoice(jobId, giver, buffId)
    local e = edit(jobId)
    if not e then return end
    e.choice = type(e.choice) == "table" and e.choice or {}
    e.choice[giver] = buffId
    changed(jobId, "choice")
end

-- The blessing paladin `paladin` gives everyone of `class` by hand: a
-- blessing ID, "none", or nil for auto.
function Du.blessing(paladin, class)
    return str(row("blessings", paladin), class)
end

function Du.setBlessing(paladin, class, buffId)
    local e = edit("blessings")
    if not e then return end
    e.matrix = type(e.matrix) == "table" and e.matrix or {}
    local row = type(e.matrix[paladin]) == "table" and e.matrix[paladin] or {}
    row[class] = buffId
    e.matrix[paladin] = next(row) and row or nil
    changed("blessings", "matrix")
end

-- The totem shaman `shaman` puts down for `element` by hand: a totem ID,
-- "none", or nil for auto.
function Du.totem(shaman, element)
    return str(row("totems", shaman), element)
end

-- The totem shaman `m` puts down for `element` by hand: their own, else
-- their spec's. The key it's kept under comes second.
function Du.totemFor(m, element)
    local v = Du.totem(m.name, element)
    if v then return v, m.name end
    local key = specKey(m)
    v = key and Du.totem(key, element)
    if v then return v, key end
    return nil
end

function Du.setTotem(shaman, element, buffId)
    local e = edit("totems")
    if not e then return end
    e.matrix = type(e.matrix) == "table" and e.matrix or {}
    local row = type(e.matrix[shaman]) == "table" and e.matrix[shaman] or {}
    row[element] = buffId
    e.matrix[shaman] = next(row) and row or nil
    changed("totems", "matrix")
end

-- The blessings wanted by `key`, set by hand: a class ("WARRIOR"), a spec
-- ("WARRIOR:3") or a player ("name:Grom"). nil when it's the default.
function Du.blessOrderOf(key)
    local o = part("blessings", "order")
    local list = o and o[key]
    if type(list) ~= "table" then return nil end
    -- An order saved with a blessing the game no longer has, like
    -- Sanctuary, which isn't in WoW Forever, leaves it out.
    for _, id in ipairs(list) do
        if not D.BY_ID[id] then
            local t = {}
            for _, x in ipairs(list) do
                if D.BY_ID[x] then t[#t + 1] = x end
            end
            return t
        end
    end
    return list
end

-- Whether any class, spec or player has a blessing order set by hand.
function Du.anyBlessOrder()
    for key, list in pairs(part("blessings", "order") or {}) do
        if type(key) == "string" and type(list) == "table" then return true end
    end
    return false
end

-- The blessings `key` wants when nothing is set for it by hand: a player
-- wants what their spec does, a spec what its class does unless the data
-- says otherwise, and a class what the data says.
function Du.baseOrder(key)
    local class, rest = key:match("^(%u+):?(.*)$")
    if key:find("^name:") then
        local m = R.byName(key:sub(6))
        local p = NS.db and NS.db.people[key:sub(6)]
        local c, tree = m and m.class or p and p.class, m and m.spec or p and p.spec
        if not c then return { "kings" } end
        return Du.orderOfSpec(c, tree)
    end
    if rest ~= "" then return Du.orderOfSpec(class, tonumber(rest), true) end
    local own = Du.blessOrderOf(class)
    if own then return own end
    local d = D.BLESSING_ORDER[class]
    return d and d.class or { "kings" }
end

-- The order of a class's spec: set by hand for the spec, else the data's for
-- the spec when the class has none set by hand, else the class's.
function Du.orderOfSpec(class, tree, skipOwn)
    local own = not skipOwn and tree and Du.blessOrderOf(class .. ":" .. tree)
    if own then return own end
    local classOwn = Du.blessOrderOf(class)
    if classOwn then return classOwn end
    local d = D.BLESSING_ORDER[class]
    return d and (tree and d[tree] or d.class) or { "kings" }
end

-- The blessings player `m` wants, most wanted first, and where that comes
-- from: "player", "spec", "class" or "default".
function Du.blessOrder(m)
    local own = Du.blessOrderOf("name:" .. m.name)
    if own then return own, "player" end
    if m.spec and Du.blessOrderOf(m.class .. ":" .. m.spec) then
        return Du.blessOrderOf(m.class .. ":" .. m.spec), "spec"
    end
    if Du.blessOrderOf(m.class) then return Du.blessOrderOf(m.class), "class" end
    local d = D.BLESSING_ORDER[m.class]
    return d and (m.spec and d[m.spec] or d.class) or { "kings" }, "default"
end

-- Whether player `name`'s blessing order is one they set themselves on
-- their You page (Du.setOwnBlessOrder), not an override the leader set.
function Du.selfOrder(name)
    local o = part("blessings", "order")
    local list = o and o["name:" .. name]
    return type(list) == "table" and list.self == true
end

-- Sets our own blessing order from the You page, or puts it back to what
-- our spec wants (nil).
--
-- Only the leader and the assistants change assignments, but anyone may say
-- which blessings they want themselves. So this edit goes to the group even
-- from a raider who can't change anything else, and everyone takes it from
-- them (Sync.lua). It's kept with `self` set, so Needs can show it's the
-- player's own choice and not the leader's. The leader may still change it,
-- and then it's theirs.
function Du.setOwnBlessOrder(list)
    local me = R.me()
    if not me then return end
    local v = nil
    if list then
        v = copy(list)
        v.self = true
    end
    local e = edit("blessings", true)
    if not e then return end
    e.order = type(e.order) == "table" and e.order or {}
    e.order["name:" .. me.name] = v
    changed("blessings", "own")
end

function Du.setBlessOrder(key, list)
    local e = edit("blessings")
    if not e then return end
    e.order = type(e.order) == "table" and e.order or {}
    e.order[key] = list
    changed("blessings", "order")
end

-- Puts `buffId` at place `pos` of `key`'s order, starting from what `key`
-- wants now. A blessing it had elsewhere moves out of the way.
function Du.setBlessAt(key, pos, buffId)
    local cur = Du.blessOrderOf(key) or Du.baseOrder(key)
    local list = {}
    for _, id in ipairs(cur) do
        if id ~= buffId then list[#list + 1] = id end
    end
    table.insert(list, math.min(pos, #list + 1), buffId)
    Du.setBlessOrder(key, list)
end

-- Paladin overrides: which blessing a paladin covers, and for whom.
-- `target` is "all", a class, a spec or a player (a pick).
--
-- By default an override covers those of `target` who need the blessing:
-- the ones it's among the blessings they want, as many as there are
-- paladins (Blessing Priority). So Pal Foo on Wisdom for shamans gives
-- Wisdom to every shaman but an Enhancement one, who wants Kings and Might
-- with two paladins here. Auto chooses what else Foo gives. A forced
-- override gives it to everyone of `target`, wanted or not, so the
-- Enhancement shaman gets Wisdom too. An override for a player starts
-- forced, since they were chosen by name. Each override is its own, so one
-- paladin can cover Might for warriors and give Grom Wisdom.
--
-- They live in the blessings entry's `assign` as { [paladin] = { [target] =
-- value } }. The value is the blessing's ID, or { buff, force = true } when
-- it's forced. A save from before held { buff, to = { picks } } for a
-- paladin, which reads as a forced override per pick, or one for "all".
local TARGET_RANK = { all = 1, class = 2, spec = 3, name = 4 }

local function isTarget(t)
    return t == "all" or isPick(t)
end

-- The rank of target `t`: everyone first, then a class, a spec, a player.
function Du.targetRank(t)
    if t == "all" then return 1 end
    return TARGET_RANK[t:match("^(%a+)")] or 9
end

local function isBlessingId(id)
    local b = type(id) == "string" and D.BY_ID[id]
    return b and b.family == "blessing" or false
end

-- An override's value as { buff, force }, or nil when it isn't one.
local function readValue(v)
    if isBlessingId(v) then return { buff = v, force = false } end
    if type(v) == "table" and isBlessingId(v.buff) then return { buff = v.buff, force = v.force == true } end
    return nil
end

-- An override's value as we keep it.
local function value(buff, force)
    if not buff then return nil end
    return force and { buff = buff, force = true } or buff
end

-- `row` as { [target] = { buff, force } }, from either shape a save may have.
local function assignRow(row)
    if type(row) ~= "table" then return {} end
    local out = {}
    if type(row.buff) == "string" then
        if not isBlessingId(row.buff) then return out end
        local to = type(row.to) == "table" and row.to or {}
        if #to == 0 then out.all = { buff = row.buff, force = false } end
        for _, pick in ipairs(to) do
            if isPick(pick) then out[pick] = { buff = row.buff, force = true } end
        end
        return out
    end
    for t, v in pairs(row) do
        local x = isTarget(t) and readValue(v)
        if x then out[t] = x end
    end
    return out
end

local function byTarget(x, y)
    local a, b = Du.targetRank(x.target), Du.targetRank(y.target)
    if a ~= b then return a < b end
    return x.target < y.target
end

-- Paladin `paladin`'s overrides, as { target, buff, force }: everyone
-- first, then the classes, the specs and the players. `paladin` is a name,
-- or a spec's pick for the overrides of the whole spec.
function Du.assignsOf(paladin)
    local all = part("blessings", "assign")
    local list = {}
    for t, x in pairs(assignRow(all and all[paladin])) do
        list[#list + 1] = { target = t, buff = x.buff, force = x.force }
    end
    table.sort(list, byTarget)
    return list
end

-- The overrides paladin `m` goes by: their own, and their spec's for whom
-- they have none of their own. One of the spec's has `holder`, its key.
function Du.assignsFor(m)
    local list = Du.assignsOf(m.name)
    local key = specKey(m)
    if not key then return list end
    local own = {}
    for _, x in ipairs(list) do own[x.target] = true end
    for _, x in ipairs(Du.assignsOf(key)) do
        if not own[x.target] then
            x.holder = key
            list[#list + 1] = x
        end
    end
    table.sort(list, byTarget)
    return list
end

-- The blessing `paladin` covers for `target` by override, or nil, and
-- whether it's forced.
function Du.assignOf(paladin, target)
    local all = part("blessings", "assign")
    local x = assignRow(all and all[paladin])[target]
    if not x then return nil, false end
    return x.buff, x.force
end

-- Every override, as { paladin, target, buff, force }, by paladin.
function Du.assigns()
    local names = {}
    for name in pairs(part("blessings", "assign") or {}) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    table.sort(names)
    local t = {}
    for _, name in ipairs(names) do
        for _, x in ipairs(Du.assignsOf(name)) do
            t[#t + 1] = { paladin = name, target = x.target, buff = x.buff, force = x.force }
        end
    end
    return t
end

-- The paladins with an override, by name.
function Du.assigned()
    local t, seen = {}, {}
    for _, x in ipairs(Du.assigns()) do
        if not seen[x.paladin] then
            seen[x.paladin] = true
            t[#t + 1] = x.paladin
        end
    end
    return t
end

-- `e.assign[paladin]` in today's shape, so a save from before changes into
-- it on its first edit.
local function editRow(e, paladin)
    e.assign = type(e.assign) == "table" and e.assign or {}
    local row = e.assign[paladin]
    if type(row) == "table" and row.buff ~= nil then
        local t = {}
        for target, x in pairs(assignRow(row)) do t[target] = value(x.buff, x.force) end
        row = t
    end
    e.assign[paladin] = type(row) == "table" and row or {}
    return e.assign[paladin]
end

-- Whether a new override for `target` starts forced: one for a player does.
local function forcedFirst(target)
    return target:find("^name:") ~= nil
end

local function put(paladin, target, buff, force)
    local e = edit("blessings")
    if not e then return end
    local row = editRow(e, paladin)
    row[target] = value(buff, force)
    if next(row) == nil then e.assign[paladin] = nil end
    changed("blessings", "assign")
end

-- Sets paladin `paladin` to cover blessing `buffId` for `target`, or takes
-- the override away when it's nil. It stays forced or not as it was.
function Du.setAssign(paladin, target, buffId)
    local had, force = Du.assignOf(paladin, target)
    if not had then force = forcedFirst(target) end
    put(paladin, target, buffId, force)
end

-- Forces an override on everyone it's for, or back to only those who need
-- it.
function Du.setAssignForce(paladin, target, on)
    local buff = Du.assignOf(paladin, target)
    if buff then put(paladin, target, buff, on) end
end

-- Moves an override to another paladin or target, as one step. One that's
-- there already gives way to it. Moved between a player and a group, it
-- starts as a new one for that kind of target would.
function Du.moveAssign(paladin, target, toPaladin, toTarget)
    local buff, force = Du.assignOf(paladin, target)
    if not buff or (paladin == toPaladin and target == toTarget) then return end
    if forcedFirst(target) ~= forcedFirst(toTarget) then force = forcedFirst(toTarget) end
    Du.batch(nil, function()
        put(paladin, target, nil)
        put(toPaladin, toTarget, buff, force)
    end)
end

-- =============================================================
-- Givers: every override as one giver doing one thing
-- =============================================================
-- The Assignments page's Overrides (Overrides.lua) shows every override as
-- a card: a giver and what they do. The paladin overrides are Du.assigns. The rest
-- live where auto reads them, and these are their cards:
--   pick    a giver of a one-giver job (Fortitude, a curse). Several picks
--           on a job go in order, so the second takes over when the first
--           can't (`place`).
--   never   the giver never does the job, even in auto
--   choice  the giver puts up `buff` for a choice job (an aura, a
--           judgement), or nothing when `never`
--   totem   the shaman puts down `buff` for `element`, or nothing
--   bless   an older paladin override: a blessing for a whole class
-- A card is { kind, job, giver (a pick), buff (an id or nil), never,
-- place, element, class, key (its item's key, for its status) }.
local function card(kind, jobId, giver, t)
    t = t or {}
    t.kind, t.job, t.giver = kind, jobId, giver
    return t
end

-- The key a choice, a totem or a paladin override of giver `pick` is kept
-- under: a player's name, or a spec's pick itself. Nil for a class.
local function holderOf(pick)
    local name = type(pick) == "string" and pick:match("^name:(.+)$")
    if name then return name end
    return Du.isSpecKey(pick) and pick or nil
end
Du.holderOf = holderOf

-- The giver pick of key `key`, the other way round.
local function pickOf(key)
    return Du.isSpecKey(key) and key or "name:" .. key
end
Du.pickOf = pickOf

-- The buff a pick of job `job` gives: the first option of the pick's class.
local function pickBuff(job, pick)
    local _, a = Du.splitPick(pick)
    local class = pick:find("^name:") and R.byName(a) and R.byName(a).class
                  or pick:find("^name:") and type(NS.db.people[a]) == "table" and NS.db.people[a].class or a
    for _, id in ipairs(job.options) do
        if D.BY_ID[id].class == class then return id end
    end
    return job.options[1]
end

function Du.giverCards()
    local t = {}
    for _, job in ipairs(D.JOBS) do
        local id = job.id
        if job.kind ~= "blessing" and job.kind ~= "resist" and job.kind ~= "totem" then
            for i, pick in ipairs(Du.pickList(id) or {}) do
                t[#t + 1] = card("pick", id, pick, { buff = pickBuff(job, pick), place = i,
                                                     key = Du.itemKey("picks", id) })
            end
            for _, pick in ipairs(sortedKeys(Du.never(id))) do
                t[#t + 1] = card("never", id, pick, { buff = pickBuff(job, pick), never = true,
                                                      key = Du.itemKey("never", id, pick) })
            end
            for _, name in ipairs(sortedKeys(part(id, "choice"))) do
                local v = Du.choice(id, name)
                if v then
                    t[#t + 1] = card("choice", id, pickOf(name),
                                     { buff = v ~= "none" and v or pickBuff(job, pickOf(name)), never = v == "none",
                                       key = Du.itemKey("choice", id, name) })
                end
            end
        elseif job.kind == "totem" then
            for _, name in ipairs(sortedKeys(part(id, "matrix"))) do
                for _, element in ipairs(D.ELEMENTS) do
                    local v = Du.totem(name, element)
                    if v then
                        local b = D.BY_ID[v]
                        local first
                        for _, x in ipairs(D.TOTEM_ORDER) do
                            if not first and D.BY_ID[x].element == element then first = x end
                        end
                        t[#t + 1] = card("totem", id, pickOf(name),
                                         { buff = b and v or first, never = v == "none", element = element,
                                           key = Du.itemKey("totem", name, element) })
                    end
                end
            end
        elseif job.kind == "blessing" then
            for _, pick in ipairs(sortedKeys(Du.never(id))) do
                t[#t + 1] = card("never", id, pick, { never = true, key = Du.itemKey("never", id, pick) })
            end
            for _, pick in ipairs(Du.pickList(id) or {}) do
                t[#t + 1] = card("pick", id, pick, { key = Du.itemKey("picks", id) })
            end
            for _, name in ipairs(sortedKeys(part(id, "matrix"))) do
                for _, class in ipairs(sortedKeys(row(id, name))) do
                    local v = Du.blessing(name, class)
                    if v then
                        t[#t + 1] = card("bless", id, "name:" .. name,
                                         { buff = v ~= "none" and v or nil, never = v == "none", class = class,
                                           key = Du.itemKey("bless", name, class) })
                    end
                end
            end
        end
    end
    return t
end

-- What a player of class `class` can be set to do, in the job order:
-- { job, buff }, a job with options once per option of the class.
function Du.giverOptions(class)
    local t = {}
    for _, job in ipairs(D.JOBS) do
        if job.kind ~= "resist" then
            for _, id in ipairs(job.options) do
                local b = D.BY_ID[id]
                if b.class == class then t[#t + 1] = { job = job.id, buff = id } end
            end
        end
    end
    return t
end

-- Takes card `x` away, back to auto.
local function dropCard(x)
    local name = holderOf(x.giver)
    if x.kind == "pick" then
        Du.setPick(x.job, x.giver, false)
    elseif x.kind == "never" then
        Du.setNever(x.job, x.giver, false)
    elseif x.kind == "choice" then
        Du.setChoice(x.job, name, nil)
    elseif x.kind == "totem" then
        Du.setTotem(name, x.element, nil)
    elseif x.kind == "bless" then
        Du.setBlessing(name, x.class, nil)
    end
end

function Du.removeGiver(x)
    Du.batch(nil, function() dropCard(x) end)
end

-- Sets player `name` to give `buffId` of job `jobId`: a pick after the
-- others on a one-giver job, their choice on a choice job, their totem of
-- its element. A blessing is an override for whoever needs it, or for the
-- first class here they have none for. `pick` stands in for the player
-- when it's a class or a spec.
local function giveIt(pick, jobId, buffId, place)
    local job = D.JOB[jobId]
    local name = holderOf(pick)
    if job.kind == "blessing" then
        if not name then return end
        local target = not Du.assignOf(name, "all") and "all" or nil
        if not target then
            for _, m in ipairs(R.list()) do
                if not target and not Du.assignOf(name, "class:" .. m.class) then target = "class:" .. m.class end
            end
        end
        if target then Du.setAssign(name, target, buffId) end
    elseif job.kind == "totem" then
        if name then Du.setTotem(name, D.BY_ID[buffId].element, buffId) end
    elseif job.kind == "choice" then
        if name then Du.setChoice(jobId, name, buffId) end
    else
        local list = without(Du.pickList(jobId), pick)
        table.insert(list, math.min(place or #list + 1, #list + 1), pick)
        Du.setPicks(jobId, list)
    end
end

-- `who` is a player's name, or a spec's pick for the whole spec.
function Du.addGiver(who, jobId, buffId)
    Du.batch(nil, function() giveIt(pickOf(who), jobId, buffId) end)
end

-- Changes card `x` to `pick` giving `buffId` of job `jobId`, as one step.
-- A pick that stays on its job keeps its place, and a card for never doing
-- it stays one.
function Du.moveGiver(x, pick, jobId, buffId)
    local name = holderOf(pick)
    local job = D.JOB[jobId]
    Du.batch(nil, function()
        local place = x.kind == "pick" and x.job == jobId and x.place or nil
        dropCard(x)
        if not x.never then
            giveIt(pick, jobId, buffId, place)
        elseif job.kind == "totem" then
            if name then Du.setTotem(name, D.BY_ID[buffId].element, "none") end
        elseif x.kind == "choice" and job.kind == "choice" then
            if name then Du.setChoice(jobId, name, "none") end
        else
            Du.setNever(jobId, pick, true)
        end
    end)
end

-- Turns card `x` into never doing it, or back: a pick into Never, a choice
-- or a totem into nothing, and the other way.
function Du.setGiverNever(x, on)
    local name = holderOf(x.giver)
    Du.batch(nil, function()
        if x.kind == "pick" or x.kind == "never" then
            if on then Du.setNever(x.job, x.giver, true) else Du.setPick(x.job, x.giver, true) end
        elseif x.kind == "choice" then
            Du.setChoice(x.job, name, on and "none" or x.buff)
        elseif x.kind == "totem" then
            Du.setTotem(name, x.element, on and "none" or x.buff)
        end
    end)
end

-- =============================================================
-- Fights
-- =============================================================
-- The fights set up for resistances, by name.
function Du.fights()
    local t = {}
    for name, f in pairs(part("resistances", "fights") or {}) do
        if type(name) == "string" and type(f) == "table" then t[#t + 1] = name end
    end
    table.sort(t)
    return t
end

-- The fight on now, or nil.
function Du.fight()
    local e = entry("resistances")
    local f, fights = str(e, "fight"), part("resistances", "fights")
    if f and fights and type(fights[f]) == "table" then return f end
    return nil
end

function Du.setFight(name)
    local e = edit("resistances")
    if not e then return end
    e.fight = name
    changed("resistances", "fight")
end

-- Sets up a new fight with nothing in it yet. It's on only once someone
-- turns it on.
function Du.addFight(name)
    if type(name) ~= "string" or name == "" then return end
    local e = edit("resistances")
    if not e then return end
    e.fights = type(e.fights) == "table" and e.fights or {}
    e.fights[name] = type(e.fights[name]) == "table" and e.fights[name] or {}
    changed("resistances", "fights")
end

function Du.removeFight(name)
    local e = edit("resistances")
    if not e then return end
    if type(e.fights) == "table" then e.fights[name] = nil end
    if e.fight == name then e.fight = nil end
    changed("resistances", "fights")
end

-- Renames fight `old` to `new`, and keeps it on when it was. Answers
-- whether it did: a name that's empty or another fight's doesn't.
function Du.renameFight(old, new)
    new = type(new) == "string" and new:match("^%s*(.-)%s*$") or ""
    local fights = part("resistances", "fights")
    if new == "" or new == old or not (fights and type(fights[old]) == "table") or fights[new] ~= nil then
        return false
    end
    Du.batch(format("rename %s to %s", old, new), function()
        local e = edit("resistances")
        if not e then return end
        e.fights[new], e.fights[old] = e.fights[old], nil
        if e.fight == old then e.fight = new end
        changed("resistances", "fights")
    end)
    return true
end

-- What fight `fight` asks for school `school`: nil when it doesn't, true for
-- auto, or { giver, buff } set by hand.
function Du.resist(fight, school)
    local fights = part("resistances", "fights")
    local f = fights and fights[fight]
    local v = type(f) == "table" and f[school]
    if v == true or type(v) == "table" then return v end
    return nil
end

function Du.setResist(fight, school, value)
    local e = edit("resistances")
    if not e then return end
    e.fights = type(e.fights) == "table" and e.fights or {}
    e.fights[fight] = type(e.fights[fight]) == "table" and e.fights[fight] or {}
    e.fights[fight][school] = value
    changed("resistances", "fights")
end

-- Back to auto: no picks, no choices, no blessings by hand. Turning a job on
-- or off stays, and so do the fights. What each spec wants (the priority)
-- stays too, since a job's "Back to auto" is about who gives it, not who
-- wants it.
local function clearHand(e)
    e.picks, e.never, e.choice, e.matrix, e.assign = nil, nil, nil, nil, nil
end

function Du.reset(jobId)
    local e = edit(jobId)
    if not e then return end
    clearHand(e)
    changed(jobId, "reset")
end

-- Every job back to auto, as one step, priorities included. The fights
-- stay, with auto's givers. The group hears it as one message.
local function toAuto(e)
    clearHand(e)
    e.order, e.want = nil, nil
    for _, f in pairs(type(e.fights) == "table" and e.fights or {}) do
        for school, v in pairs(type(f) == "table" and f or {}) do
            if type(v) == "table" then f[school] = true end
        end
    end
end

function Du.resetAll()
    local state = NS.writable()
    if not state then return end
    local s = { before = {}, jobs = {} }
    for _, job in ipairs(D.JOBS) do
        local e = state.duty[job.id]
        if type(e) == "table" then
            s.before[job.id] = copy(e)
            s.jobs[#s.jobs + 1] = job.id
            toAuto(e)
        end
    end
    finish(s, "resetAll", "everything to auto")
end

-- Every job of duty table `duty` back to auto, like Du.resetAll, outside
-- the edit path. It's how a reset from the leader or an assistant reaches
-- us (Sync.lua).
function Du.allToAuto(duty)
    for id, e in pairs(duty) do
        if type(e) == "table" then toAuto(e) end
        tidyIn(duty, id)
        if type(duty[id]) ~= "table" then duty[id] = nil end
    end
end

-- Whether job `jobId` has an override, something set by hand about who
-- gives it. What specs want (order, want) is priority, not an override.
function Du.custom(jobId)
    local e = entry(jobId)
    return e ~= nil and (e.picks ~= nil or e.never ~= nil or e.choice ~= nil or e.matrix ~= nil
                         or e.assign ~= nil)
end

-- =============================================================
-- Items: the settings one at a time
-- =============================================================
-- An undo step, a suggestion and the overrides' statuses need the settings
-- one at a time, not as whole job entries, because the blessings entry
-- holds every blessing order and every paladin's cells. A raider who suggests
-- their own Wisdom changes one item, and applying it leaves the leader's
-- newer cells alone.
--
-- An item is { key, kind, job, a, b, value }. Its kind says where it lives:
--   on       a = job              turned on or off by hand
--   picks    a = job              the picks in order, as a list
--   never    a = job, b = pick
--   choice   a = job, b = giver
--   totem    a = shaman, b = element
--   bless    a = paladin, b = CLASS
--   assign   a = paladin, b = "all" or a pick
--   order    a = key ("WARRIOR", "WARRIOR:3", "name:Bob")
--   fight    a = fight name       true while the fight is set up
--   resist   a = fight, b = school
--   fighton                       the fight on now
-- A "hand" item is a constraint: something set by hand that auto works
-- around (Du.constraints). The rest are settings of the board.
local function sub(e, k)
    local t = e and e[k]
    return type(t) == "table" and t or nil
end

local function cell(e, k, a, b)
    local row = sub(e, k)
    row = row and row[a]
    if type(row) ~= "table" then return nil end
    return row[b]
end

local function setCell(e, k, a, b, v)
    e[k] = sub(e, k) or {}
    local row = type(e[k][a]) == "table" and e[k][a] or {}
    row[b] = v
    e[k][a] = next(row) and row or nil
end

local function isBuff(v, ok)
    return type(v) == "string" and (v == "none" or (D.BY_ID[v] ~= nil and (not ok or ok(D.BY_ID[v]))))
end

local KINDS = {
    on = {
        get = function(e) return e.on end,
        set = function(e, _, _, v) e.on = v end,
        check = function(v) return type(v) == "boolean" end,
    },
    picks = {
        hand = true,
        get = function(e) return ordered(e.picks) end,
        set = function(e, _, _, v) e.picks = ranked(v) end,
        check = function(v)
            if type(v) ~= "table" or #v == 0 then return false end
            for _, p in ipairs(v) do
                if not isPick(p) then return false end
            end
            return true
        end,
    },
    never = {
        hand = true,
        get = function(e, _, b) local n = sub(e, "never") return n and n[b] and true or nil end,
        set = function(e, _, b, v)
            e.never = sub(e, "never") or {}
            e.never[b] = v
        end,
        check = function(v) return v == true end,
        b = isPick,
    },
    choice = {
        hand = true,
        get = function(e, _, b) local c = sub(e, "choice") return c and c[b] end,
        set = function(e, _, b, v)
            e.choice = sub(e, "choice") or {}
            e.choice[b] = v
        end,
        check = function(v) return isBuff(v) end,
        b = function(b) return type(b) == "string" end,
    },
    totem = {
        hand = true, job = "totems",
        get = function(e, a, b) return cell(e, "matrix", a, b) end,
        set = function(e, a, b, v) setCell(e, "matrix", a, b, v) end,
        check = function(v) return isBuff(v, function(x) return x.element ~= nil end) end,
        b = function(b) return b == "earth" or b == "fire" or b == "water" or b == "air" end,
    },
    bless = {
        hand = true, job = "blessings",
        get = function(e, a, b) return cell(e, "matrix", a, b) end,
        set = function(e, a, b, v) setCell(e, "matrix", a, b, v) end,
        check = function(v) return isBuff(v, function(x) return x.family == "blessing" end) end,
        b = function(b) return type(b) == "string" and b:find("^%u+$") ~= nil end,
    },
    assign = {
        hand = true, job = "blessings",
        get = function(e, a, b)
            local rows = sub(e, "assign")
            local x = rows and assignRow(rows[a])[b]
            return x and value(x.buff, x.force)
        end,
        set = function(e, a, b, v)
            local row = editRow(e, a)
            row[b] = v
            if next(row) == nil then e.assign[a] = nil end
        end,
        check = function(v) return readValue(v) ~= nil end,
        b = isTarget,
    },
    order = {
        hand = true, job = "blessings",
        get = function(e, a) local o = sub(e, "order") return o and o[a] end,
        set = function(e, a, _, v)
            e.order = sub(e, "order") or {}
            e.order[a] = v
        end,
        -- An empty order is a class or player who wants no blessing.
        check = function(v)
            if type(v) ~= "table" then return false end
            for _, id in ipairs(v) do
                if not (D.BY_ID[id] and D.BY_ID[id].family == "blessing") then return false end
            end
            return true
        end,
    },
    want = {
        hand = true,
        job = function(_, b) local x = D.BY_ID[b] return x and x.job end,
        get = function(e, a, b) return cell(e, "want", a, b) end,
        set = function(e, a, b, v) setCell(e, "want", a, b, v) end,
        check = function(v) return type(v) == "boolean" end,
        b = function(b)
            local x = type(b) == "string" and D.BY_ID[b]
            return x and x.job ~= nil and x.family ~= "blessing" and not x.school or false
        end,
    },
    fight = {
        job = "resistances",
        get = function(e, a) local f = sub(e, "fights") return f and type(f[a]) == "table" or nil end,
        set = function(e, a, _, v)
            e.fights = sub(e, "fights") or {}
            if v then
                e.fights[a] = type(e.fights[a]) == "table" and e.fights[a] or {}
            else
                e.fights[a] = nil
            end
        end,
        check = function(v) return v == true end,
    },
    resist = {
        hand = function(v) return type(v) == "table" end,
        job = "resistances",
        get = function(e, a, b) return cell(e, "fights", a, b) end,
        set = function(e, a, b, v)
            e.fights = sub(e, "fights") or {}
            if type(e.fights[a]) ~= "table" then
                -- A fight removed since: setting a school sets it up again,
                -- and clearing one leaves it gone.
                if v == nil then return end
                e.fights[a] = {}
            end
            e.fights[a][b] = v
        end,
        check = function(v)
            if v == true then return true end
            return type(v) == "table" and type(v.giver) == "string" and isBuff(v.buff)
        end,
        b = function(b) return D.SCHOOL[b] ~= nil end,
    },
    fighton = {
        job = "resistances",
        get = function(e) return type(e.fight) == "string" and e.fight or nil end,
        set = function(e, _, _, v) e.fight = v end,
        check = function(v) return type(v) == "string" end,
        noA = true,
    },
}
local KIND_ORDER = { "on", "picks", "never", "choice", "totem", "assign", "bless", "order", "want", "fight", "resist",
                     "fighton" }
local KIND_PLACE = {}
for i, k in ipairs(KIND_ORDER) do KIND_PLACE[k] = i end
local JOB_PLACE = {}
for i, job in ipairs(D.JOBS) do JOB_PLACE[job.id] = i end

function Du.itemKey(kind, a, b)
    return kind .. "\1" .. (a or "") .. "\1" .. (b or "")
end

local function jobOf(kind, a, b)
    local job = KINDS[kind].job
    if type(job) == "function" then return job(a, b) end
    return job or a
end

local function isHand(it, v)
    local h = KINDS[it.kind].hand
    if type(h) == "function" then return h(v) end
    return h == true
end

-- Every item of duty table `duty`, in order: by job, then kind. Only what
-- has the right shape, like an item from the wire (Du.cleanItem), since a
-- board from the network may hold anything.
local function itemsOf(duty, onlyJob)
    local t = {}
    local function add(kind, a, b, v)
        if v == nil or not Du.cleanItem({ k = kind, a = a, b = b, v = v }) then return end
        local job = jobOf(kind, a, b)
        if onlyJob and job ~= onlyJob then return end
        t[#t + 1] = { key = Du.itemKey(kind, a, b), kind = kind, job = job, a = a, b = b, value = v }
    end
    for _, job in ipairs(D.JOBS) do
        local e = type(duty) == "table" and (not onlyJob or onlyJob == job.id) and duty[job.id]
        if type(e) == "table" then
            local id = job.id
            if type(e.on) == "boolean" then add("on", id, nil, e.on) end
            add("picks", id, nil, ordered(e.picks))
            for _, pick in ipairs(sortedKeys(e.never)) do add("never", id, pick, e.never[pick] and true or nil) end
            for _, giver in ipairs(sortedKeys(e.choice)) do add("choice", id, giver, e.choice[giver]) end
            for _, key in ipairs(sortedKeys(e.want)) do
                for _, buff in ipairs(sortedKeys(e.want[key])) do add("want", key, buff, e.want[key][buff]) end
            end
            if id == "totems" or id == "blessings" then
                local kind = id == "totems" and "totem" or "bless"
                for _, name in ipairs(sortedKeys(e.matrix)) do
                    for _, x in ipairs(sortedKeys(e.matrix[name])) do add(kind, name, x, e.matrix[name][x]) end
                end
            end
            if id == "blessings" then
                for _, name in ipairs(sortedKeys(e.assign)) do
                    local row = assignRow(e.assign[name])
                    for _, t in ipairs(sortedKeys(row)) do
                        add("assign", name, t, value(row[t].buff, row[t].force))
                    end
                end
                for _, key in ipairs(sortedKeys(e.order)) do add("order", key, nil, e.order[key]) end
            end
            if id == "resistances" then
                for _, name in ipairs(sortedKeys(e.fights)) do
                    local f = e.fights[name]
                    if type(f) == "table" then
                        add("fight", name, nil, true)
                        for _, school in ipairs(D.SCHOOLS) do add("resist", name, school.id, f[school.id]) end
                    end
                end
                if type(e.fight) == "string" then add("fighton", nil, nil, e.fight) end
            end
        end
    end
    return t
end

local function before(x, y)
    if x.job ~= y.job then return (JOB_PLACE[x.job] or 99) < (JOB_PLACE[y.job] or 99) end
    if x.kind ~= y.kind then return KIND_PLACE[x.kind] < KIND_PLACE[y.kind] end
    if (x.a or "") ~= (y.a or "") then return (x.a or "") < (y.a or "") end
    return (x.b or "") < (y.b or "")
end

-- What changed from duty table `old` to `new`, item by item, as
-- { key, kind, job, a, b, v (the new value, nil for auto), w (the old) }.
-- `onlyJob` keeps to one job.
function Du.diff(old, new, onlyJob)
    local was, now, all = {}, {}, {}
    for _, it in ipairs(itemsOf(old, onlyJob)) do
        was[it.key] = it
        all[#all + 1] = it
    end
    for _, it in ipairs(itemsOf(new, onlyJob)) do
        now[it.key] = it
        if not was[it.key] then all[#all + 1] = it end
    end
    table.sort(all, before)
    local out = {}
    for _, it in ipairs(all) do
        local w, v = was[it.key] and was[it.key].value, now[it.key] and now[it.key].value
        if not same(w, v) then
            out[#out + 1] = { key = it.key, kind = it.kind, job = it.job, a = it.a, b = it.b,
                              v = copy(v), w = copy(w) }
        end
    end
    return out
end

-- An item from the wire, or nil when it isn't one we know with values of
-- the right kind. Its `v` and `w` are kept only when they make sense.
function Du.cleanItem(t)
    if type(t) ~= "table" then return nil end
    local kind = t.k or t.kind
    local k = type(kind) == "string" and KINDS[kind]
    if not k then return nil end
    local a, b = t.a, t.b
    if k.noA then
        a = nil
    elseif type(a) ~= "string" or a == "" then
        return nil
    end
    if k.b then
        if not k.b(b) then return nil end
    else
        b = nil
    end
    local job = jobOf(kind, a, b)
    if not job or not D.JOB[job] then return nil end
    if (kind == "choice") and t.v ~= nil and t.v ~= "none" then
        local ok = false
        for _, id in ipairs(D.JOB[job].options) do ok = ok or id == t.v end
        if not ok then return nil end
    end
    local v = t.v
    if v ~= nil and not k.check(v) then return nil end
    local w = t.w
    if w ~= nil and not k.check(w) then w = nil end
    return { key = Du.itemKey(kind, a, b), kind = kind, job = job, a = a, b = b, v = v, w = w }
end

-- The value of item `it` in duty table `duty`, or nil for auto.
function Du.itemValue(duty, it)
    local e = type(duty) == "table" and duty[it.job]
    if type(e) ~= "table" then return nil end
    return KINDS[it.kind].get(e, it.a, it.b)
end

-- Puts item `it` with value `v` straight into duty table `duty`, outside the
-- edit path, for a draft.
function Du.putItem(duty, it, v)
    duty[it.job] = type(duty[it.job]) == "table" and duty[it.job] or {}
    KINDS[it.kind].set(duty[it.job], it.a, it.b, copy(v))
    tidyIn(duty, it.job)
end

-- Applies items `list` ({ kind, a, b, v }, v nil for auto) through the edit
-- path, as one step that `text` names.
function Du.applyItems(list, text)
    Du.batch(text, function()
        for _, it in ipairs(list) do
            local e = edit(it.job)
            if e then
                KINDS[it.kind].set(e, it.a, it.b, copy(it.v))
                changed(it.job, "items")
            end
        end
    end)
end

local function blessWord(id)
    if id == "none" then return "nothing" end
    local b = D.BY_ID[id]
    return b and (bname(b):gsub("^Blessing of ", "")) or tostring(id)
end

local function buffWord(id)
    if id == "none" then return "nothing" end
    local b = D.BY_ID[id]
    return b and bname(b) or tostring(id)
end

local function orderKeyWord(key)
    local name = key:match("^name:(.+)$")
    if name then return name end
    local class, tree = key:match("^(%u+):?(%d*)$")
    if not class then return key end
    if tree ~= "" then return (Du.specName(class, tonumber(tree)) or "?") .. " " .. classWord(class) end
    return upperFirst(classWord(class))
end

-- Who override target `t` is, in words: "whoever needs it" (or
-- "everyone" when it's forced), "warriors" (or "all warriors"), "Fury
-- warriors" or "Grom".
function Du.targetWords(t, force)
    if t == "all" then return force and "everyone" or "whoever needs it" end
    local kind, a = Du.splitPick(t)
    if kind == "class" then return (force and "all " or "") .. classWord(a) end
    return Du.pickWords(t, false)
end

-- A paladin override after the paladin's name: "covers Kings for whoever
-- needs it", "covers Wisdom for shamans who need it", "gives all shamans
-- Wisdom" or "gives Grom Wisdom". With `now`, as something to do: "cover",
-- "give".
function Du.assignWords(buff, target, force, now)
    local word = blessWord(buff)
    if force then return format("%s %s %s", now and "give" or "gives", Du.targetWords(target, true), word) end
    local verb = now and "cover" or "covers"
    if target == "all" then return format("%s %s for whoever needs it", verb, word) end
    if target:find("^name:") then
        return format("%s %s for %s if they need it", verb, word, Du.targetWords(target))
    end
    return format("%s %s for %s who need it", verb, word, Du.targetWords(target))
end

-- What item `it` with value `v` is, as a short sentence: "Bob gives
-- Fortitude, else a priest", "Pal gives warriors Might", "Thrall puts down
-- Windfury Totem", "Thrall gives fire resistance on Ragnaros", "Warriors
-- want Kings, then Might", "Thorns is turned off".
function Du.itemText(it, v)
    local job = D.JOB[it.job]
    local title = job and Du.title(job) or it.job
    local kind = it.kind
    if kind == "on" then return format("%s is turned %s", title, v and "on" or "off") end
    if kind == "picks" then
        local one = job and oneGiver(job)
        local words, plural = {}, false
        for i, pick in ipairs(v or {}) do
            words[i] = Du.pickWords(pick, one)
            if not one and not pick:find("^name:") then plural = true end
        end
        if #words == 0 then return title .. " is auto" end
        plural = plural or (not one and #words > 1)
        -- A debuff goes on the target, so nobody "gives" it.
        local verb
        if job and job.scope == "target" then
            verb = plural and "are on" or "is on"
        else
            verb = plural and "give" or "gives"
        end
        if one then
            local rest = {}
            for i = 2, #words do rest[#rest + 1] = words[i] end
            local text = format("%s %s %s", upperFirst(words[1]), verb, title)
            if #rest > 0 then text = text .. ", else " .. table.concat(rest, ", else ") end
            return text
        end
        return format("%s %s %s", upperFirst(andList(words)), verb, title)
    end
    if kind == "never" then
        local who = Du.pickWords(it.b, false)
        local plural = not it.b:find("^name:")
        return format("%s %s set to never give %s", upperFirst(who), plural and "are" or "is", title)
    end
    if kind == "choice" then
        local who, many = Du.holderWords(it.b)
        local verb = many and "put up" or "puts up"
        if v == "none" then return format("%s %s nothing for %s", who, verb, title) end
        return format("%s %s %s", who, verb, buffWord(v))
    end
    if kind == "totem" then
        local who, many = Du.holderWords(it.a)
        local verb = many and "put down" or "puts down"
        if v == "none" then return format("%s %s no %s totem", who, verb, it.b) end
        return format("%s %s %s", who, verb, buffWord(v))
    end
    if kind == "bless" then return format("%s gives %s %s", it.a, classWord(it.b), blessWord(v)) end
    if kind == "assign" then
        local x = readValue(v)
        local who, many = Du.holderWords(it.a)
        return x and format("%s %s", who, Du.assignWords(x.buff, it.b, x.force, many)) or it.key
    end
    if kind == "order" then
        local words = {}
        for i, id in ipairs(v or {}) do words[i] = blessWord(id) end
        local who = orderKeyWord(it.a)
        local verb = it.a:find("^name:") and "wants" or "want"
        if #words == 0 then return format("%s %s no blessing", who, verb) end
        return format("%s %s %s", who, verb, table.concat(words, ", then "))
    end
    if kind == "want" then
        local one = it.a:find("^name:") ~= nil
        local verb = v and (one and "wants" or "want") or (one and "doesn't want" or "don't want")
        return format("%s %s %s", orderKeyWord(it.a), verb, buffWord(it.b))
    end
    if kind == "fight" then return it.a .. " is a fight" end
    if kind == "resist" then
        local school = D.SCHOOL[it.b] and D.SCHOOL[it.b].title:lower() or tostring(it.b)
        if type(v) == "table" then return format("%s gives %s resistance on %s", v.giver, school, it.a) end
        return format("Auto gives %s resistance on %s", school, it.a)
    end
    if kind == "fighton" then return format("The fight on now is %s", tostring(v)) end
    return it.key
end

-- A change of a setting by hand on one player, or a blessing order, as
-- something to do: "set Thrall to put down Windfury Totem", "let auto choose
-- what Pal gives warriors". With `past`, as something someone did, for the
-- line we print. Du.itemText says what the setting is, and this says it as a
-- change. The other kinds are changeText's.
function Du.itemChange(it, past)
    local function verb(now, did) return past and did or now end
    local v, w = it.v, it.w
    local kind = it.kind
    local school = kind == "resist" and (D.SCHOOL[it.b] and D.SCHOOL[it.b].title:lower() or tostring(it.b))
    local who = (kind == "order" or kind == "want") and orderKeyWord(it.a)
    if who and it.a:find("^%u+$") then who = who:lower() end
    -- A setting for a whole spec is about "Holy paladins".
    local holder = (kind == "choice" and it.b) or ((kind == "totem" or kind == "assign") and it.a) or nil
    local whom, many = Du.holderWords(holder)
    if many then whom = whom:lower() end
    if v == nil then
        if kind == "choice" then return format("let auto choose what %s %s up", whom, many and "put" or "puts") end
        if kind == "totem" then return format("let auto choose %s%s %s totem", whom, many and "'" or "'s", it.b) end
        if kind == "bless" then return format("let auto choose what %s gives %s", it.a, classWord(it.b)) end
        if kind == "assign" then
            local verb = many and "give" or "gives"
            if it.b == "all" then return format("let auto choose what %s %s", whom, verb) end
            return format("let auto choose what %s %s %s", whom, verb, Du.targetWords(it.b, true))
        end
        if kind == "order" then
            return format("let auto choose what %s %s", who, it.a:find("^name:") and "wants" or "want")
        end
        if kind == "want" then
            return format("let auto choose whether %s %s %s", who, it.a:find("^name:") and "wants" or "want",
                          buffWord(it.b))
        end
        if kind == "resist" then
            return format("%s %s resistance on %s", verb("stop asking for", "stopped asking for"), school, it.a)
        end
        return verb("clear ", "cleared ") .. Du.itemText(it, w)
    end
    if kind == "choice" then
        if v == "none" then
            local job = D.JOB[it.job]
            return format("set %s to put up nothing for %s", whom, job and Du.title(job) or it.job)
        end
        return format("set %s to put up %s", whom, buffWord(v))
    end
    if kind == "totem" then
        if v == "none" then return format("set %s to put down no %s totem", whom, it.b) end
        return format("set %s to put down %s", whom, buffWord(v))
    end
    if kind == "bless" then return format("set %s to give %s %s", it.a, classWord(it.b), blessWord(v)) end
    if kind == "assign" then
        local x = readValue(v)
        return x and format("set %s to %s", whom, Du.assignWords(x.buff, it.b, x.force, true)) or it.key
    end
    if kind == "order" then
        local words = {}
        for i, id in ipairs(v or {}) do words[i] = blessWord(id) end
        if #words == 0 then return format("set %s to want no blessing", who) end
        return format("set %s to want %s", who, table.concat(words, ", then "))
    end
    if kind == "want" then
        return format("set %s to %s %s", who, v and "want" or "not want", buffWord(it.b))
    end
    if kind == "resist" then
        if type(v) == "table" then return format("set %s to give %s resistance on %s", v.giver, school, it.a) end
        return format("let auto give %s resistance on %s", school, it.a)
    end
    return (past and "set " or "") .. Du.itemText(it, v)
end

-- A change of an item as something to do: "put Bob on Fortitude", "set Pal
-- to give warriors Might", "let auto choose Thrall's air totem". With `past`,
-- as something someone did, for the line we print.
function changeText(it, past)
    local job = D.JOB[it.job]
    local title = job and Du.title(job) or it.job
    local function verb(now, did) return past and did or now end
    if it.kind == "picks" then
        if it.v == nil then return format("set %s back to auto", title) end
        local one = job and oneGiver(job)
        local words = {}
        for i, pick in ipairs(it.v) do words[i] = Du.pickWords(pick, one) end
        return format("put %s on %s", one and table.concat(words, ", else ") or andList(words), title)
    end
    if it.kind == "on" then
        local on = it.v
        if on == nil then on = job and not job.optional end
        return (on and verb("turn on ", "turned on ") or verb("turn off ", "turned off ")) .. title
    end
    if it.kind == "never" then
        local who = Du.pickWords(it.b, false)
        if it.v then return format("%s %s off %s", verb("keep", "kept"), who, title) end
        return format("let %s back on %s", who, title)
    end
    if it.kind == "fight" then
        return (it.v and verb("add the fight ", "added the fight ") or verb("delete the fight ", "deleted the fight ")) .. it.a
    end
    if it.kind == "fighton" then
        return it.v and format(verb("turn on the fight %s", "turned on the fight %s"), it.v) or verb("turn the fight off", "turned the fight off")
    end
    return Du.itemChange(it, past)
end
Du.changeText = changeText

-- A spec set by hand, as something done: "set Bob's spec to Beast Mastery",
-- or "set Bob's spec back to auto" when `tree` is nil.
function Du.specText(name, tree)
    local m = R.byName(name)
    local p = NS.db and NS.db.people[name]
    local class = m and m.class or p and p.class
    local spec = tree and class and Du.specName(class, tree)
    if spec then return format("set %s's spec to %s", name, spec) end
    if tree then return format("set %s's spec", name) end
    return format("set %s's spec back to auto", name)
end

-- =============================================================
-- Undo, snapshots
-- =============================================================
-- Who last changed each setting, by item key, for an undo that has nothing
-- left to undo. Only the edits of the others that reach us (Sync.lua).
local lastBy = {}

-- Notes that player `name` changed the group's assignments from duty table
-- `old` to `new`.
function Du.changedBy(name, old, new)
    for _, it in ipairs(Du.diff(old, new)) do lastBy[it.key] = name end
end

-- Keeps step `s` ({ text, where, items, specs, mock }) for Du.undo, and
-- drops the steps we could redo.
function Du.keep(s)
    history[#history + 1] = s
    if #history > HISTORY then table.remove(history, 1) end
    for i = #future, 1, -1 do future[i] = nil end
end

-- Whether we're undoing or redoing now, when nothing we change is a step
-- of its own.
function Du.replaying() return replaying end

-- Runs `fn` without keeping what it changes as steps. A change to the mock
-- raid (Mock.lua) is one step of its own, a copy of the raid before and
-- after, so the edits it makes on the way aren't steps too.
function Du.untracked(fn, ...)
    if replaying then return fn(...) end
    replaying = true
    local ok, a, b = pcall(fn, ...)
    replaying = false
    if not ok then error(a, 0) end
    return a, b
end

-- Keeps a change to the mock raid as a step: `before` and `after` are
-- copies of it (Mock.snapshot). Undoing it puts `before` back.
function Du.keepMock(text, before, after)
    if replaying or same(before, after) then return end
    Du.keep({ text = text, where = NS.state(), mock = { before = before, after = after } })
end

-- Keeps a spec set by hand as a step: player `name`'s from `old` to `new`.
-- Inside Du.batch it's part of the batch's step.
function Du.keepSpec(name, old, new)
    if replaying or old == new then return end
    local text = new and format("set %s's spec", name) or format("set %s's spec back to auto", name)
    local sp = { name = name, w = old, v = new, text = text }
    if step and step.batch then
        step.specs = step.specs or {}
        step.specs[#step.specs + 1] = sp
        return
    end
    Du.keep({ text = text, where = where(), items = {}, specs = { sp } })
end

-- Forgets every step, as when another plan is loaded into the mock raid
-- and the steps before it would change a raid that isn't there anymore.
function Du.forgetSteps()
    for i = #history, 1, -1 do history[i] = nil end
    for i = #future, 1, -1 do future[i] = nil end
end

-- Drops the steps of a draft that's gone, applied or discarded.
local function prune(list)
    while #list > 0 do
        local top = list[#list]
        if top.where.base and top.where ~= NS.draft then
            table.remove(list)
        else
            break
        end
    end
end

local function mayStep(list)
    prune(list)
    local top = list[#list]
    if not top or top.where ~= where() then return false end
    if NS.draft then return NS.Suggest == nil or NS.Suggest.canChange() end
    return R.canEdit()
end

function Du.canUndo() return mayStep(history) end
function Du.canRedo() return mayStep(future) end

-- "Undo: put Bob on Fortitude", or nil when there's nothing to undo.
function Du.undoText()
    if not Du.canUndo() then return nil end
    return "Undo: " .. history[#history].text
end

-- "Redo: put Bob on Fortitude", or nil when there's nothing to redo.
function Du.redoText()
    if not Du.canRedo() then return nil end
    return "Redo: " .. future[#future].text
end

-- Puts the mock raid back as copy `snap`, for undoing or redoing step
-- `top` of it.
local function replayMock(snap)
    replaying = true
    local ok, err = pcall(NS.Mock.restore, snap)
    replaying = false
    if not ok then error(err, 0) end
end

-- Puts the settings the last step changed back as they were, through the
-- edit path, so the group hears it like any edit.
--
-- A setting someone changed again since (another officer, or the leader
-- under our draft) is no longer what we set, and undoing our step leaves it
-- alone. In a draft, a setting our step changed from the group's value goes
-- back to the group's value now, which may be newer than the one we saw.
--
-- When someone changed every setting of the step since, there's nothing left
-- to undo, and we say so rather than do nothing.
function Du.undo()
    if not Du.canUndo() then return false end
    local top = table.remove(history)
    if top.mock then
        replayMock(top.mock.before)
        future[#future + 1] = top
        return true
    end
    local state = NS.edited()
    local d = NS.draft
    local list = {}
    for _, it in ipairs(top.items or {}) do
        if same(Du.itemValue(state.duty, it), it.v) then
            local back = it.w
            if d and d.base and same(it.w, it.bw) then back = Du.itemValue(d.base.duty, it) end
            list[#list + 1] = { key = it.key, kind = it.kind, job = it.job, a = it.a, b = it.b, v = copy(back) }
        end
    end
    -- Only a step from Du.keepStep has specs, and only the specs still as
    -- it left them go back.
    local specs = {}
    for _, sp in ipairs(top.specs or {}) do
        if state.specs[sp.name] == sp.v then specs[#specs + 1] = sp end
    end
    if #list == 0 and #specs == 0 and #(top.items or {}) + #(top.specs or {}) > 0 then
        local who
        for _, it in ipairs(top.items) do
            local by = lastBy[it.key]
            if who == nil then who = by or false end
            if by ~= who then who = false end
        end
        if who then
            NS.print("%s changed that since, so there's nothing to undo.", who)
        else
            NS.print("That was changed since, so there's nothing to undo.")
        end
        return false
    end
    replaying = true
    local ok, err = pcall(function()
        if #list > 0 then Du.applyItems(list) end
        for _, sp in ipairs(specs) do R.setSpec(sp.name, sp.w) end
    end)
    replaying = false
    if not ok then error(err, 0) end
    future[#future + 1] = top
    return true
end

-- Makes the last step we undid again. As with undo, a setting someone
-- changed since stays as they left it.
function Du.redo()
    if not Du.canRedo() then return false end
    local top = table.remove(future)
    if top.mock then
        replayMock(top.mock.after)
        history[#history + 1] = top
        return true
    end
    local state = NS.edited()
    local list, specs = {}, {}
    for _, it in ipairs(top.items or {}) do
        if same(Du.itemValue(state.duty, it), it.w) then
            list[#list + 1] = { key = it.key, kind = it.kind, job = it.job, a = it.a, b = it.b, v = copy(it.v) }
        end
    end
    for _, sp in ipairs(top.specs or {}) do
        if state.specs[sp.name] == sp.w then specs[#specs + 1] = sp end
    end
    if #list == 0 and #specs == 0 then
        NS.print("That was changed since, so there's nothing to redo.")
        return false
    end
    replaying = true
    local ok, err = pcall(function()
        if #list > 0 then Du.applyItems(list) end
        for _, sp in ipairs(specs) do R.setSpec(sp.name, sp.v) end
    end)
    replaying = false
    if not ok then error(err, 0) end
    history[#history + 1] = top
    return true
end

-- Keeps a change that didn't come through the edit path as a step to undo:
-- the group's assignments from duty table `old` to `new`, and the specs set
-- by hand from `oldSpecs` to `newSpecs`. Sync.lua keeps a board handed over
-- to us this way, so a leader who comes back can undo it and have their own
-- again. Answers whether there was anything to keep.
function Du.keepStep(text, old, new, oldSpecs, newSpecs)
    local items = Du.diff(old, new)
    oldSpecs, newSpecs = oldSpecs or {}, newSpecs or {}
    local specs, seen = {}, {}
    for _, t in ipairs({ oldSpecs, newSpecs }) do
        for name in pairs(t) do
            if not seen[name] and oldSpecs[name] ~= newSpecs[name] then
                specs[#specs + 1] = { name = name, w = oldSpecs[name], v = newSpecs[name] }
            end
            seen[name] = true
        end
    end
    if #items == 0 and #specs == 0 then return false end
    Du.keep({ text = text, where = NS.state(), items = items, specs = specs })
    return true
end

-- A copy of the assignments the window edits: the draft's while we draft.
-- Du.restore takes it back.
function Du.snapshot()
    local state = NS.edited()
    return { duty = copy(state and state.duty or {}) }
end

-- Sets the assignments to snapshot `snap` through the edit path, as one step
-- that `text` names ("load Molten Core").
function Du.restore(snap, text)
    local duty = type(snap) == "table" and (type(snap.duty) == "table" and snap.duty or snap) or {}
    local state = NS.edited()
    if not state then return end
    Du.batch(text or "restore", function()
        for _, job in ipairs(D.JOBS) do
            local want = type(duty[job.id]) == "table" and duty[job.id] or nil
            if not same(want, state.duty[job.id]) then
                local e = edit(job.id)
                if e then
                    for k in pairs(e) do e[k] = nil end
                    for k, v in pairs(want or {}) do e[k] = copy(v) end
                    changed(job.id, "restore")
                end
            end
        end
    end)
end

NS.listen("groupLeft", function()
    Du.forgetSteps()
    for k in pairs(lastBy) do lastBy[k] = nil end
    for k in pairs(Du.told) do Du.told[k] = nil end
end)

-- =============================================================
-- Who can give what, and who wants it
-- =============================================================
local function knowsSpell(b)
    local known = (C_SpellBook and C_SpellBook.IsSpellKnown) or _G.IsPlayerSpell or _G.IsSpellKnown
    if not known then return false end
    for _, id in ipairs(b.spells) do
        local ok, yes = pcall(known, id)
        if ok and yes == true then return true end
    end
    return false
end

-- The talent buffs and debuffs players with the addon told us they know, by
-- name: { [id] = true }. Sync.lua fills it from their hellos.
Du.told = {}

-- The talent buffs and debuffs we know ourselves: { [id] = true }. Our hello
-- tells the others, so every client goes by the same.
local ownKnown

function Du.ownTalents()
    if not ownKnown then
        ownKnown = {}
        for _, list in ipairs({ D.BUFFS, D.DEBUFFS }) do
            for _, b in ipairs(list) do
                if b.talent and knowsSpell(b) then ownKnown[b.id] = true end
            end
        end
    end
    return ownKnown
end

-- Our talents changed, so what we can give may have too. A roster scan only
-- signals when the members changed, and talents aren't part of that, so we
-- force one.
local function talentsChanged()
    ownKnown = nil
    NS.soon("talents", 0.3, function() NS.Roster.scan(true) end)
end
NS.on("PLAYER_TALENT_UPDATE", talentsChanged)
NS.on("TRAIT_CONFIG_UPDATED", talentsChanged)
NS.on("SPELLS_CHANGED", talentsChanged)
NS.listen("login", talentsChanged)

-- =============================================================
-- Levels and ranks
-- =============================================================
-- A buff's ranks are { spell, level, ... }, rank 1 first (b.ranks, from
-- RanksData.lua). Nobody below the first rank's level can give it, and a
-- higher level gives a better rank: a level 20 priest's Fortitude is rank 2,
-- a level 30's rank 3. A rank a talent teaches has level 0, and Du.canGive
-- asks for the talent instead. A player whose level we don't know, like one
-- of a mock raid, has every rank.
--
-- The game won't put a rank on a player more than RANK_REACH levels below
-- it. Fortitude rank 4 is level 36, so a level 20 player takes rank 3 at
-- most.
local RANK_REACH = 10
Du.RANK_REACH = RANK_REACH

-- The level `b` is first learned at, or nil when there's none to wait for.
function Du.needsLevel(b)
    local lv = b.ranks and b.ranks[2]
    if lv and lv > 1 then return lv end
    return nil
end

-- The best rank of `b` a giver of level `level` has, that a player of level
-- `target` can take, as (rank, its spell, its level). `known(spell)`, when
-- given, says which ranks the giver learned, and with none of them known we
-- go by the level alone. 0 when there's no such rank, and nil for a buff
-- without ranks.
function Du.rankFor(b, level, target, known)
    local r = b.ranks
    if not r then return nil end
    local best, spell, at = 0, nil, nil
    local function pick(check)
        for i = 1, #r / 2 do
            local s, lv = r[2 * i - 1], r[2 * i]
            if (not level or lv <= level) and (not target or lv <= target + RANK_REACH)
               and (not check or known(s)) then
                best, spell, at = i, s, lv
            end
        end
    end
    if known then pick(true) end
    if best == 0 then pick(false) end
    return best, spell, at
end

-- The rank of `b` that aura spell `id` is and the level it's learned at, or
-- nil. A group version counts as the best rank of its level: Prayer of
-- Fortitude at level 48 is as good as Fortitude rank 5.
function Du.rankOfSpell(b, id)
    local r = b.ranks
    for i = 1, r and #r / 2 or 0 do
        if r[2 * i - 1] == id then return i, r[2 * i] end
    end
    local g = b.groupRanks
    for i = 1, g and r and #g / 2 or 0 do
        if g[2 * i - 1] == id then return Du.rankAtLevel(b, g[2 * i]), g[2 * i] end
    end
    return nil
end

-- The best rank of `b` learned by `level`, or nil when there's none.
function Du.rankAtLevel(b, level)
    local r, best = b.ranks, nil
    for i = 1, r and #r / 2 or 0 do
        if r[2 * i] <= level then best = i end
    end
    return best
end

-- The level of the best rank of `b` player `m` gives, to put the player
-- with the better rank first. 0 for a buff without ranks, so everyone ties.
function Du.rankLevel(m, b)
    local _, _, at = Du.rankFor(b, m.level)
    return at or 0
end

-- Whether player `m` is high enough to take `b` from someone at all: a buff
-- we cast on one player, of a rank no more than RANK_REACH above them.
-- Blessing of Kings is level 20, so a level 8 player can't have it yet.
-- Totems, auras and shouts reach everyone in range, whatever their level.
function Du.canTake(m, b)
    local lv = b.kind == "long" and b.ranks and b.ranks[2]
    return not (lv and m.level and lv > m.level + RANK_REACH)
end

-- Why player `m` is too low for `b`, in words, or nil.
function Du.levelWhy(m, b)
    local need = Du.needsLevel(b)
    if need and m.level and m.level < need then
        return format("%s is level %d, and %s needs %d.", m.name, m.level, bname(b), need)
    end
    return nil
end

-- Whether we know player `m` is another spec than talent buff `b` needs,
-- for a talent at the bottom of its tree (`deep`), which only that spec
-- reaches. A spec we only guessed from the raid role doesn't count.
local function wrongSpec(m, b)
    return b.talent ~= nil and b.deep == true and m.spec ~= nil and m.spec ~= b.talent and m.specFrom ~= "role"
end

-- Why player `m` can't give `b`, when it's their level or their spec.
function Du.cantWhy(m, b)
    local why = Du.levelWhy(m, b)
    if why then return why end
    if wrongSpec(m, b) then
        local spec = Du.specName(b.class, b.talent) or "?"
        return format("%s isn't %s, and %s needs it.", m.name, spec, bname(b))
    end
    return nil
end

-- Whether player `m` can give buff or debuff `b`. They need the level of its
-- first rank. A talent buff needs the talent's tree as their spec, or that
-- they told us they know it. `byName` is a leader's pick by name, who knows
-- better than we do about the talent, but not about the level, and not when
-- we know they're another spec than a deep talent needs.
--
-- Every client must work out the same board, so we only go by what every
-- client with the addon has: the specs, and the talents players told the
-- group in their hello. Never by what only our client saw, like a buff we
-- saw someone give.
function Du.canGive(m, b, byName)
    if m.class ~= b.class or not m.online then return false end
    local need = Du.needsLevel(b)
    if need and m.level and m.level < need then return false end
    if not b.talent then return true end
    if m.spec == b.talent then return true end
    local known = m.me and Du.ownTalents() or Du.told[m.name]
    if known ~= nil then return known[b.id] == true end
    return byName and not wrongSpec(m, b) or false
end

-- Stands in for a list the data leaves out. The HUD asks who wants what for
-- every player twice a second, and a new empty table each time added up.
-- Nothing writes to it.
local NONE = {}

-- Whether a player with tags `tags` (a set) wants `b` by the data alone.
local function tagged(tags, b)
    if b.debuff then
        for _, tag in ipairs(b.benefits or NONE) do
            if tags[tag] then return true end
        end
        return false
    end
    for _, tag in ipairs(b.unwanted or NONE) do
        if tags[tag] then return false end
    end
    for _, tag in ipairs(b.wants or NONE) do
        if tag == "all" or tags[tag] then return true end
    end
    return false
end

-- Buffs by Spec: which buffs and debuffs other than the blessings a spec
-- or a player wants. Blessing Priority has the blessings, in order. By
-- default it's the data's (a spec's tags against what each buff wants),
-- and the leader can turn one on or off for a spec ("WARRIOR:3") or a
-- player ("name:Grom"). Auto aims for it like for the blessings: a buff
-- nobody here wants has no giver, and a party aura goes where it's wanted.
-- It lives in the entry of the buff's job as want = { [key] = { [buff id]
-- = true or false } }.

-- What `key` wants of `b` by override, or nil.
local function ownWant(key, b)
    if not b.job then return nil end
    local w = part(b.job, "want")
    local row = w and w[key]
    if type(row) ~= "table" then return nil end
    local v = row[b.id]
    if type(v) == "boolean" then return v end
    return nil
end
Du.wantOf = function(key, b) return ownWant(key, b) end

-- Whether a spec wants `b`, by override or else by its tags.
function Du.specWants(class, tree, b)
    local own = ownWant(class .. ":" .. tree, b)
    if own ~= nil then return own end
    local s = D.SPECS[class] and D.SPECS[class][tree]
    if not s then return false end
    local tags = {}
    for _, tag in ipairs(s.tags) do tags[tag] = true end
    return tagged(tags, b)
end

-- Whether player `m` wants `b` going by their spec: its override, else the
-- data's. With their spec unknown and a spec of their class overridden,
-- they want it when all three specs do.
local function specWant(m, b)
    if m.spec then
        local own = ownWant(m.class .. ":" .. m.spec, b)
        if own ~= nil then return own end
    elseif m.class and b.job then
        local any = false
        for tree = 1, 3 do any = any or ownWant(m.class .. ":" .. tree, b) ~= nil end
        if any then
            for tree = 1, 3 do
                if not Du.specWants(m.class, tree, b) then return false end
            end
            return true
        end
    end
    return tagged(m.tags or NONE, b)
end

-- Whether player `m` wants buff or debuff `b`: their own override, else
-- their spec's. Nobody wants what they're too low to take (Du.canTake),
-- unless `anyLevel` asks what they'd want at any level.
function Du.wants(m, b, anyLevel)
    if not anyLevel and not Du.canTake(m, b) then return false end
    if m.name then
        local own = ownWant("name:" .. m.name, b)
        if own ~= nil then return own end
    end
    return specWant(m, b)
end

-- Turns `b` on or off for `key`, or back to what it'd be without an
-- override (nil). One that's what it'd be anyway is no override.
function Du.setWant(key, buffId, on)
    local b = D.BY_ID[buffId]
    if not (b and b.job) then return end
    if on ~= nil then
        local class, tree = key:match("^(%u+):(%d)$")
        local base
        if class then
            local s = D.SPECS[class] and D.SPECS[class][tonumber(tree)]
            local tags = {}
            for _, tag in ipairs(s and s.tags or {}) do tags[tag] = true end
            base = tagged(tags, b)
        else
            local m = R.byName(key:match("^name:(.+)$") or "")
            if m then base = specWant(m, b) end
        end
        if base == on then on = nil end
    end
    local e = edit(b.job)
    if not e then return end
    e.want = type(e.want) == "table" and e.want or {}
    local row = type(e.want[key]) == "table" and e.want[key] or {}
    row[buffId] = on
    e.want[key] = next(row) and row or nil
    changed(b.job, "want")
end

-- Every key with a want of its own: specs ("WARRIOR:3") and players
-- ("name:Grom"), as a set.
function Du.wantKeys()
    local t = {}
    for _, job in ipairs(D.JOBS) do
        for key, row in pairs(part(job.id, "want") or {}) do
            if type(row) == "table" and next(row) then t[key] = true end
        end
    end
    return t
end

-- Whether anyone online among `members` wants `b`.
local function wanted(b, members)
    for _, m in ipairs(members) do
        if m.online and Du.wants(m, b) then return true end
    end
    return false
end

-- How well player `m` fits job `job`'s `prefer` list: 1 is the best, and a
-- player who fits none of it comes after everyone who does.
local function fit(job, m)
    for i, p in ipairs(job.prefer or {}) do
        if p == m.specKey or p == m.role then return i end
    end
    return 99
end

-- The highest level in the group the board is worked out for (compute sets
-- it), or nil when we know nobody's.
local topLevel

-- How many ranks player `m` is short of what the highest level in the group
-- has, for the best of job `job`'s buffs of their class. Two classes' buffs
-- have ranks at different levels (Demoralizing Shout's are at 14, 24, 34,
-- Demoralizing Roar's at 10, 20, 32), so we count ranks. Everyone at the
-- group's top level is 0, and then the job's fit decides.
local function jobRank(job, m)
    local short = math.huge
    for _, id in ipairs(job.options) do
        local b = D.BY_ID[id]
        if b.class == m.class then
            local have, top = Du.rankFor(b, m.level), Du.rankFor(b, topLevel)
            short = math.min(short, have and top - have or 0)
        end
    end
    return short
end

-- How well the best spec of player `m`'s class fits job `job`, so two of
-- one class tie on it.
local function classFit(job, m)
    local best = fit(job, m)
    for _, s in pairs(D.SPECS[m.class] or {}) do
        best = math.min(best, fit(job, { specKey = s.key, role = s.role }))
    end
    return best
end

-- By how well their class fits the job, then the better rank, then how well
-- their spec fits. So a level 30 Arms warrior shouts before a level 12 Fury
-- one, and at the same level Fury goes first. Each is a key of the player
-- alone, which keeps the order whole for table.sort.
local function byFit(job)
    return function(a, b)
        local ca, cb = classFit(job, a), classFit(job, b)
        if ca ~= cb then return ca < cb end
        local ra, rb = jobRank(job, a), jobRank(job, b)
        if ra ~= rb then return ra < rb end
        local fa, fb = fit(job, a), fit(job, b)
        if fa ~= fb then return fa < fb end
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end
end

local function byGroup(a, b)
    if a.group ~= b.group then return a.group < b.group end
    return a.name < b.name
end

-- =============================================================
-- Working out the board
-- =============================================================
-- The board is { [job id] = plan }, and a plan is
--   { job, active, code, why, fallback, picked, list, backups }
-- `backups` is, for a long buff, the others who can give it, in the order
-- they'd take over. `active` is false when the job has nobody on it, and
-- `code` says why, with `why` the words for it:
--   unwanted   nobody here wants it
--   nobody     nobody here can give it, or everyone who can is busy
--   off        it's turned off
--   absent     the players picked are gone, and nobody else can give it
--   nofight    (resistances) no fight is on
--   noschools  (resistances) the fight asks for nothing
-- `fallback` is true when the job has picks and none of them could take
-- it, so it went back to auto. `picked` says how the picks went:
--   { status ("applied", "absent" or "blocked"), reason, fixes }
-- where `fixes` is a list of { text, fn } the window may offer, like "Move
-- Bob here". `list` is the assignments, each
--   { job, giver (a member), buff, party (party scope),
--     bless ({ [name] = blessing id }, for blessings), why, hand }
-- `why` says in a few words why the giver has it, for tooltips, and `hand`
-- is true when it was set by hand (so Du.pin has nothing to do).
local HAND = "Override."

local CODES = {
    unwanted = "Nobody here wants it.",
    nobody = "Nobody here can give it.",
    off = "Turned off.",
    absent = "Nobody chosen is here, and nobody else can give it.",
    nofight = "No fight turned on.",
    noschools = "This fight needs no resistances.",
}

local function inactive(plan, code)
    plan.active, plan.code, plan.why = false, code, CODES[code]
    return false
end

-- What family holds player `m` already, for buff `b`: { job, buff }, or nil.
local function busy(holding, m, b)
    local fam = b.family
    return fam and holding[m.name] and holding[m.name][fam] or nil
end

local function hold(holding, m, b, job)
    if not b.family then return end
    holding[m.name] = holding[m.name] or {}
    holding[m.name][b.family] = { job = job, buff = b }
end

local function busyWhy(m, h)
    return { text = format("%s already does %s.", m.name, bname(h.buff)), who = m.name, holder = h.job.id }
end

-- Why nobody for pick `pick` is among `members`: "Bob isn't here.", "Bob is
-- offline." or "No warlocks here."
local function awayWhy(pick, members)
    local kind, a = Du.splitPick(pick)
    for _, m in ipairs(members) do
        if Du.pickMatches(pick, m) and not m.online and kind == "name" then
            return format("%s is offline.", m.name)
        end
    end
    if kind == "name" then return format("%s isn't here.", a) end
    return format("No %s here.", (Du.pickWords(pick, false):gsub("^all ", "")))
end

-- The first of picks `list` with someone among `members` who can take the
-- job. `can(m, byName)` returns what they'd put up, or nil and why not
-- ({ text, who, holder }). `better` sorts the players a class or spec pick
-- matches. Returns the player, what `can` gave, and how the picks went.
local function fromPicks(list, members, never, can, better)
    local blocked, skipped = nil, {}
    for _, pick in ipairs(list) do
        local here = {}
        for _, m in ipairs(members) do
            if m.online and Du.pickMatches(pick, m) and not barred(never, m) then here[#here + 1] = m end
        end
        table.sort(here, better)
        local first
        for _, m in ipairs(here) do
            local what, why = can(m, pick:find("^name:") ~= nil)
            if what then
                return m, what, { status = "applied", pick = pick,
                                  note = #skipped > 0 and table.concat(skipped, " ") or nil }
            end
            first = first or why
        end
        if first then
            blocked = blocked or { why = first, pick = pick }
            skipped[#skipped + 1] = first.text
        else
            skipped[#skipped + 1] = awayWhy(pick, members)
        end
    end
    if blocked then return nil, nil, { status = "blocked", why = blocked.why, pick = blocked.pick } end
    return nil, nil, { status = "absent" }
end

-- How the picks of a job went, from each try (one per party for a party
-- job): applied when any took it, else blocked when someone picked was here
-- and couldn't, else absent. Adds the words and the fixes.
local function settle(job, plan, tries, members)
    if not tries or #tries == 0 then return end
    local out
    for _, t in ipairs(tries) do
        if t.status == "applied" then out = out or t end
    end
    if not out then
        for _, t in ipairs(tries) do
            if t.status == "blocked" then out = out or t end
        end
    end
    out = out or { status = "absent" }
    local fixes = {}
    if out.status == "blocked" then
        out.reason = out.why.text
        local holder = out.why.holder and D.JOB[out.why.holder]
        if holder and holder.kind ~= "resist" and holder.kind ~= "totem" and holder.id ~= job.id then
            local name = out.why.who
            fixes[#fixes + 1] = { text = format("Move %s here", name), fn = function()
                Du.batch(format("move %s to %s", name, Du.title(job)), function()
                    Du.release(holder.id, name)
                end)
            end }
        end
    elseif out.status == "absent" then
        local list = Du.pickList(job.id) or {}
        out.reason = #list == 1 and awayWhy(list[1], members) or "Nobody chosen is here."
    end
    if out.status ~= "applied" then
        fixes[#fixes + 1] = { text = "Back to auto", fn = function() Du.clearPicks(job.id) end }
    end
    out.fixes = fixes
    plan.picked = out
    plan.fallback = out.status ~= "applied"
end

-- Takes player `name` off job `jobId`, for a fix that moves them: their
-- pick or their choice by hand when they have one, else "Never" them there.
function Du.release(jobId, name)
    local list = Du.pickList(jobId)
    local pick = "name:" .. name
    for _, p in ipairs(list or {}) do
        if p == pick then
            Du.setPick(jobId, pick, false)
            return
        end
    end
    if Du.choice(jobId, name) then
        Du.setChoice(jobId, name, nil)
        if not list then return end
    end
    Du.setNever(jobId, pick, true)
end

-- A long buff: one giver for the whole raid. On Forever each group version
-- (Prayer of Fortitude, Arcane Brilliance, Gift of the Wild) reaches every
-- raid member within 100 yards of the caster, so a second giver would only
-- spend reagents. The others who can give it are backups.
--
-- The giver with the better rank comes first. Then we spread the long
-- buffs: a priest already on Fortitude comes after one who isn't on
-- anything yet for Divine Spirit. `load` counts each player's
-- long buffs so far.
local function cover(job, members, plan, load)
    local b = D.BY_ID[job.buff]
    if not wanted(b, members) then return inactive(plan, "unwanted") end
    local never, list = Du.never(job.id), Du.pickList(job.id)
    local function lighter(x, y)
        local rx, ry = Du.rankLevel(x, b), Du.rankLevel(y, b)
        if rx ~= ry then return rx > ry end
        local lx, ly = load[x.name] or 0, load[y.name] or 0
        if lx ~= ly then return lx < ly end
        return byGroup(x, y)
    end
    local g, alts, hand = nil, {}, false
    if list then
        local _, try
        g, _, try = fromPicks(list, members, never, function(m, byName)
            if Du.canGive(m, b, byName) then return b end
            return nil, { text = Du.cantWhy(m, b) or format("%s can't give %s.", m.name, bname(b)), who = m.name }
        end, lighter)
        settle(job, plan, { try }, members)
        hand = g ~= nil
    end
    if not g then
        local all = {}
        for _, m in ipairs(members) do
            if not barred(never, m) and Du.canGive(m, b) then all[#all + 1] = m end
        end
        if #all == 0 then
            return inactive(plan, plan.picked and plan.picked.status == "absent" and "absent" or "nobody")
        end
        table.sort(all, lighter)
        g = all[1]
        for i = 2, #all do alts[#alts + 1] = all[i] end
    end
    local first = (load[g.name] or 0) == 0
    load[g.name] = (load[g.name] or 0) + 1
    plan.list[1] = { job = job, giver = g, buff = b, why = hand and HAND or nil, hand = hand or nil,
                     auto = not hand and { kind = "cover", first = first } or nil, alts = alts }
    -- Everyone else who can give it is a backup, picked or not, in the
    -- order they'd take over. Not in the roster's order, which differs from
    -- client to client.
    plan.backups, plan.reserve = {}, {}
    for _, m in ipairs(members) do
        if m ~= g and not barred(never, m) and Du.canGive(m, b) then plan.backups[#plan.backups + 1] = m end
    end
    table.sort(plan.backups, lighter)
    for i, m in ipairs(plan.backups) do
        plan.reserve[i] = { job = job, giver = m, buff = b, backup = true }
    end
end

-- Blessings. Each player gets as many of the blessings they want (their
-- order, Du.blessOrder) as there are paladins, one from each. With two
-- paladins a mage gets Kings and Wisdom, with one only Kings.
--
-- Forever has no Greater Blessings, so every blessing is a cast on one
-- player. Still, each paladin gives one blessing to each whole class where
-- it can (the blessings most of the class wants), so their clicking stays
-- simple and the whispers short. A player of the class who wants another
-- one gets it from a paladin as well. So if every shaman but one wants
-- Wisdom, one paladin gives the shamans Wisdom and the Enhancement shaman
-- Might.
--
-- Each paladin also keeps to one blessing across classes where it can (the
-- one the raid wants most from it), so the first paladin is Kings for
-- everyone. A blessing a leader set for a paladin and a class comes first.
--
-- A paladin with no blessing for a class, because the class wants fewer
-- blessings than there are paladins, is its backup. With three paladins the
-- third backs up a class that wants only two, like warriors (Kings and
-- Might). A backup puts on whichever blessing someone of the class
-- is missing from the others.
--
-- A paladin override (Du.assignsOf) has the paladin cover a blessing for
-- whoever of its target needs it, or for all of them when it's forced. One
-- for everyone makes the blessing the paladin's own before auto picks the
-- others'. Auto works out the rest around them.
--
-- For the constraints, the plan also keeps `pool` (the paladins on it, by
-- name), `byClass` (each paladin's blessing by class), `cellWhy` (why a
-- blessing set by hand isn't given) and `assignWhy` (what's wrong with a
-- paladin override on its own, assignCheck).
local BLESS_ORDER = { kings = 1, might = 2, wisdom = 3 }

-- Whether `id` is a blessing. A blessing set by hand may come from a board
-- sent over the network, which could hold any buff or anything at all.
local function isBlessing(id)
    local b = type(id) == "string" and D.BY_ID[id]
    return b and b.family == "blessing" and BLESS_ORDER[id] ~= nil or false
end

-- Whether blessing list `list` holds `id`.
local function holds(list, id)
    for _, x in ipairs(list or {}) do
        if x == id then return true end
    end
    return false
end

-- Who of pick `pick` doesn't want blessing `id` in Blessing Priority, in
-- words, or nil when they all do: "Grom", "Fury warriors", "warriors", or
-- "Arms and Fury warriors" when only some of a class's specs don't. The
-- second value is whether none of them want it.
local function unwanted(pick, id)
    local kind, a, b = Du.splitPick(pick)
    if kind == "name" then
        if holds(Du.blessOrderOf(pick) or Du.baseOrder(pick), id) then return nil, false end
        return a, true
    end
    if kind == "spec" then
        if holds(Du.orderOfSpec(a, tonumber(b)), id) then return nil, false end
        return Du.pickWords(pick, false), true
    end
    local specs = {}
    for tree = 1, 3 do
        if not holds(Du.orderOfSpec(a, tree), id) then specs[#specs + 1] = Du.specName(a, tree) or "?" end
    end
    if #specs == 0 then return nil, false end
    if #specs == 3 then return classWord(a), true end
    return andList(specs) .. " " .. classWord(a), false
end

-- What's wrong with the paladin overrides on their own, as plan.assignWhy:
-- { [paladin] = { [target] = { level = "bad" or "idle", lines } } }.
--   bad   the paladin can't give it.
--   idle  it covers players who never want it in Blessing Priority, so it
--         does nothing.
-- What an override costs the others is Du.costs's, which compares the
-- board with the board auto would make without it.
local function assignCheck(plan, paladins)
    plan.assignWhy = {}
    for _, p in ipairs(paladins) do
        for _, x in ipairs(Du.assignsFor(p)) do
            local b, why = D.BY_ID[x.buff], nil
            local word = (bname(b):gsub("^Blessing of ", ""))
            if not Du.canGive(p, b, true) then
                why = { level = "bad", lines = { format("%s can't give %s.", p.name, bname(b)) } }
            elseif not x.force and x.target ~= "all" then
                local who, all = unwanted(x.target, x.buff)
                if who and all then
                    local one = x.target:find("^name:") ~= nil
                    why = { level = "idle", lines = { format("%s %s want %s, so it does nothing.", upperFirst(who),
                                                             one and "doesn't" or "don't", word) } }
                end
            end
            if why then
                plan.assignWhy[p.name] = plan.assignWhy[p.name] or {}
                plan.assignWhy[p.name][x.target] = why
            end
        end
    end
end

local function blessings(job, members, plan)
    local paladins = {}
    local picks, never = Du.picks(job.id), Du.never(job.id)
    local all, chosen = {}, {}
    plan.poolWhy, plan.cellWhy = {}, {}
    for _, m in ipairs(members) do
        if m.class == "PALADIN" and m.online then
            if barred(never, m) then
                plan.poolWhy[m.name] = format("%s is set to never bless.", m.name)
            else
                all[#all + 1] = m
                if picks and picked(picks, m) then chosen[#chosen + 1] = m end
            end
        end
    end
    if picks then
        settle(job, plan, { { status = #chosen > 0 and "applied" or "absent" } }, members)
    end
    if picks and #chosen > 0 then
        paladins = chosen
        for _, m in ipairs(all) do
            if not picked(picks, m) then
                plan.poolWhy[m.name] = format("%s isn't one of the chosen paladins.", m.name)
            end
        end
    else
        paladins = all
    end
    if #paladins == 0 then
        return inactive(plan, picks and #all == 0 and "absent" or "nobody")
    end
    table.sort(paladins, function(a, b) return a.name < b.name end)
    plan.pool = {}
    for _, p in ipairs(paladins) do plan.pool[p.name] = true end
    local n = #paladins
    local enabled = {}
    for _, id in ipairs(job.options) do enabled[id] = not D.BY_ID[id].optional end

    -- What each player wants: the first `n` of their order that a paladin
    -- here can give. Those their camp buffs stand in for come last, so a
    -- paladin gives one only with nothing better to give them (Tracking.lua).
    local function givable(id)
        if not enabled[id] then return false end
        for _, p in ipairs(paladins) do
            if Du.canGive(p, D.BY_ID[id]) then return true end
        end
        return false
    end
    local wants, byClass, classes = {}, {}, {}
    for _, m in ipairs(members) do
        if m.online then
            local set, list = {}, {}
            local camp = NS.Tracking.campOf(m.name) or {}
            for _, late in ipairs({ false, true }) do
                for _, id in ipairs(Du.blessOrder(m)) do
                    if #list < n and not set[id] and (camp[id] == true) == late and givable(id)
                       and Du.canTake(m, D.BY_ID[id]) then
                        set[id] = #list + 1
                        list[#list + 1] = id
                    end
                end
            end
            wants[m.name] = set
            if not byClass[m.class] then
                byClass[m.class] = {}
                classes[#classes + 1] = m.class
            end
            table.insert(byClass[m.class], m)
        end
    end
    table.sort(classes)

    -- How many players want each blessing, and how highly: a blessing more
    -- want, or want sooner, comes first. Only those online want anything.
    local function ranked(people)
        local count, place = {}, {}
        for _, m in ipairs(people) do
            for id, pos in pairs(wants[m.name] or {}) do
                count[id] = (count[id] or 0) + 1
                place[id] = (place[id] or 0) + pos
            end
        end
        local list = {}
        for id in pairs(count) do list[#list + 1] = id end
        table.sort(list, function(a, b)
            if count[a] ~= count[b] then return count[a] > count[b] end
            if place[a] ~= place[b] then return place[a] < place[b] end
            return BLESS_ORDER[a] < BLESS_ORDER[b]
        end)
        return list
    end

    -- Each paladin's own blessing: the raid's most wanted to the first
    -- paladin, the next to the second, of those they can give. A paladin
    -- set by hand to a blessing for some class keeps to that one, so the
    -- others are worked out around it.
    local main, taken = {}, {}
    -- The paladin overrides (Du.assignsOf), by paladin. One for everyone
    -- makes the blessing the paladin's own, and `prefer` is who covers each
    -- blessing for whoever needs it.
    local prefer, rules = {}, {}
    for _, p in ipairs(paladins) do
        for _, x in ipairs(Du.assignsFor(p)) do
            if Du.canGive(p, D.BY_ID[x.buff], true) then
                rules[p.name] = rules[p.name] or {}
                table.insert(rules[p.name], x)
                if x.target == "all" then
                    main[p.name], taken[x.buff] = x.buff, true
                    if not x.force then prefer[x.buff] = prefer[x.buff] or p end
                end
            end
        end
    end
    -- The override of paladin `p` that puts a blessing on player `m`, who
    -- wants `want` (wants[m.name]): the most specific that's for them, a
    -- player before a spec before a class before everyone. One that isn't
    -- forced is for them only when they need its blessing.
    local function ruleFor(p, m, want)
        local list = rules[p.name] or {}
        for i = #list, 1, -1 do
            local x = list[i]
            if (x.target == "all" or Du.pickMatches(x.target, m)) and (x.force or want and want[x.buff]) then
                return x
            end
        end
        return nil
    end
    for _, p in ipairs(paladins) do
        local n, best = {}, nil
        for _, class in ipairs(classes) do
            local id = Du.blessing(p.name, class)
            if isBlessing(id) then
                n[id] = (n[id] or 0) + 1
                if not best or n[id] > n[best] or (n[id] == n[best] and BLESS_ORDER[id] < BLESS_ORDER[best]) then
                    best = id
                end
            end
        end
        if best and not taken[best] and not main[p.name] then main[p.name], taken[best] = best, true end
    end
    -- Kings goes to a Protection paladin when there is one and nobody was
    -- set to it by hand, so the Holy and Retribution paladins are free for
    -- Might and Wisdom.
    local ranks = ranked(members)
    local wantKings = false
    for _, id in ipairs(ranks) do wantKings = wantKings or id == "kings" end
    if wantKings and not taken.kings then
        for _, p in ipairs(paladins) do
            if not main[p.name] and p.spec == 2 and Du.canGive(p, D.BY_ID.kings) then
                main[p.name], taken.kings = "kings", true
                break
            end
        end
    end
    for _, id in ipairs(ranks) do
        for _, p in ipairs(paladins) do
            if not main[p.name] and not taken[id] and Du.canGive(p, D.BY_ID[id]) then
                main[p.name], taken[id] = id, true
                break
            end
        end
    end

    -- The classes where someone gets fewer blessings than they should, as
    -- { [class] = { class, missing = { [blessing] = { members } },
    --               twice = { [blessing] = { paladin names } },
    --               none = { paladin names set to give the class nothing },
    --               unknown = { [blessing] = true when no paladin here knows it } } }
    local warnings = {}
    local function warn(class)
        warnings[class] = warnings[class] or { class = class, missing = {}, twice = {}, none = {}, unknown = {} }
        return warnings[class]
    end

    local byPaladin = {}
    for _, p in ipairs(paladins) do
        byPaladin[p.name] = { job = job, giver = p, bless = {}, byClass = {}, backupFor = {} }
    end
    for _, class in ipairs(classes) do
        local people = byClass[class]
        local wanted = ranked(people)
        local isWanted, used, skip, byHand = {}, {}, {}, {}
        for _, id in ipairs(wanted) do isWanted[id] = true end
        local g = {}
        -- Set by hand first.
        for _, p in ipairs(paladins) do
            local set = Du.blessing(p.name, class)
            if set == "none" then
                skip[p.name] = true
            elseif isBlessing(set) and Du.canGive(p, D.BY_ID[set], true) then
                -- Two paladins set to the same blessing both give it. When
                -- that leaves someone short, the plan warns (below). A
                -- blessing set by hand is the leader's choice, who knows
                -- better than we do, like a pick by name.
                g[p.name], used[set], byHand[p.name] = set, true, true
            elseif isBlessing(set) then
                plan.cellWhy[p.name .. "\1" .. class] = format("%s can't give %s.", p.name, bname(D.BY_ID[set]))
            end
        end
        -- A paladin's override for this class, or for everyone, makes its
        -- blessing theirs for the class, when it's forced or someone in the
        -- class needs it. The newest one wins, as in ruleFor. Who gets it is
        -- the override's (ruleFor, below). Without this, an override for
        -- everyone left the class to auto's blessing and then put the
        -- override's on each player one at a time.
        for _, p in ipairs(paladins) do
            local list = rules[p.name] or {}
            for i = #list, 1, -1 do
                local x = list[i]
                if (x.target == "class:" .. class or x.target == "all") and not g[p.name] and not skip[p.name]
                   and (x.force or isWanted[x.buff]) then
                    g[p.name], used[x.buff] = x.buff, true
                end
            end
        end
        -- Then each paladin's own blessing when the class wants it.
        for _, p in ipairs(paladins) do
            local id = main[p.name]
            if not g[p.name] and not skip[p.name] and id and isWanted[id] and not used[id] then
                g[p.name], used[id] = id, true
            end
        end
        -- Then the class's most wanted left.
        for _, p in ipairs(paladins) do
            if not g[p.name] and not skip[p.name] then
                for _, id in ipairs(wanted) do
                    if not used[id] and Du.canGive(p, D.BY_ID[id]) then
                        g[p.name], used[id] = id, true
                        break
                    end
                end
            end
        end
        -- A paladin left over is the class's backup.
        for _, p in ipairs(paladins) do
            if not g[p.name] and not skip[p.name] then byPaladin[p.name].backupFor[class] = true end
        end
        for _, p in ipairs(paladins) do byPaladin[p.name].byClass[class] = g[p.name] end

        -- Each player: the class's blessing from each paladin when they want
        -- it, and what they want that's left as single blessings from the
        -- paladins whose class blessing they don't want. A blessing set by
        -- hand for the class that nobody in it wants goes to the whole class
        -- anyway, since the leader asked for it (Wisdom on the rogues). When
        -- some of the class want it, the ones who don't keep to their own.
        for _, m in ipairs(people) do
            local want, got, done, forced = wants[m.name], {}, {}, {}
            -- First what a paladin's override puts on this player. The
            -- others give them something else instead.
            for _, p in ipairs(paladins) do
                local x = not skip[p.name] and ruleFor(p, m, want)
                if x and not got[x.buff] then
                    byPaladin[p.name].bless[m.name] = x.buff
                    got[x.buff], done[p.name], forced[x.buff] = true, true, true
                end
            end
            for _, p in ipairs(paladins) do
                local id = g[p.name]
                if id and not done[p.name] and not forced[id]
                   and (want[id] or (byHand[p.name] and not isWanted[id])) then
                    byPaladin[p.name].bless[m.name] = id
                    got[id], done[p.name] = true, true
                end
            end
            local left = {}
            for id, pos in pairs(want) do
                if not got[id] then left[#left + 1] = { id = id, pos = pos } end
            end
            table.sort(left, function(a, b) return a.pos < b.pos end)
            for _, l in ipairs(left) do
                -- The paladin assigned to the blessing gives it when free.
                local first = prefer[l.id]
                local order = paladins
                if first then
                    order = { first }
                    for _, p in ipairs(paladins) do
                        if p ~= first then order[#order + 1] = p end
                    end
                end
                for _, p in ipairs(order) do
                    if not done[p.name] and not skip[p.name] and Du.canGive(p, D.BY_ID[l.id]) then
                        byPaladin[p.name].bless[m.name] = l.id
                        got[l.id], done[p.name] = true, true
                        break
                    end
                end
            end
            -- What they should get and don't: two paladins on one blessing,
            -- or a paladin set to give the class nothing.
            for _, l in ipairs(left) do
                if not got[l.id] then
                    local w = warn(class)
                    w.missing[l.id] = w.missing[l.id] or {}
                    table.insert(w.missing[l.id], m)
                    local known = false
                    for _, p in ipairs(paladins) do known = known or Du.canGive(p, D.BY_ID[l.id]) end
                    if not known then w.unknown[l.id] = true end
                end
            end
        end
        -- The blessings two paladins give this class.
        local w = warnings[class]
        if w then
            local givers = {}
            for _, p in ipairs(paladins) do
                local id = g[p.name]
                if id then
                    givers[id] = givers[id] or {}
                    table.insert(givers[id], p.name)
                end
            end
            for id, names in pairs(givers) do
                if #names > 1 then w.twice[id] = names end
            end
            for _, p in ipairs(paladins) do
                if skip[p.name] then w.none[#w.none + 1] = p.name end
            end
        end
    end
    plan.warnings = warnings
    assignCheck(plan, paladins)
    plan.byClass = {}
    for _, p in ipairs(paladins) do
        plan.byClass[p.name] = byPaladin[p.name].byClass
        if next(byPaladin[p.name].bless) then plan.list[#plan.list + 1] = byPaladin[p.name] end
    end
    -- The backups: for each class a paladin backs up, every blessing its
    -- players get from the others, unless the backup blesses them already.
    plan.reserve = {}
    for _, p in ipairs(paladins) do
        local mine = byPaladin[p.name]
        if next(mine.backupFor) then
            local spare = {}
            for _, m in ipairs(members) do
                if m.online and mine.backupFor[m.class] and not mine.bless[m.name] then
                    for _, q in ipairs(paladins) do
                        local id = q ~= p and byPaladin[q.name].bless[m.name]
                        if id then spare[#spare + 1] = { m = m, b = D.BY_ID[id] } end
                    end
                end
            end
            if #spare > 0 then
                plan.reserve[#plan.reserve + 1] = { job = job, giver = p, backup = true,
                                                    classes = mine.backupFor, spare = spare }
            end
        end
    end
end

-- Each giver puts up one of the job's options, a different one each. A
-- giver's option set by hand goes first. Everyone picked is a giver, and
-- without picks everyone who can. `plan.choiceWhy` says why a giver's
-- option set by hand isn't what they put up.
local function choiceIn(job, members, plan, holding, party)
    -- The options anyone in reach wants, the most wanted first, else in the
    -- data's order. Each player who wants one gives it a point, or with a
    -- family order for their role (the paladin auras) a point for each place
    -- it's ahead of the end of their list. So a party of healers, whose
    -- first is Concentration and second Devotion, gets Concentration, though
    -- everyone wants Devotion.
    local options, count, place = {}, {}, {}
    local fam = D.FAMILIES[D.BY_ID[job.options[1]].family or ""]
    local function points(m, b)
        if not (m.online and Du.wants(m, b)) then return 0 end
        local order = fam and fam.order and (fam.order[m.role] or fam.order.unknown)
        for i, id in ipairs(order or {}) do
            if id == b.id then return #order - i + 2 end
        end
        return 1
    end
    for i, id in ipairs(job.options) do
        local b = D.BY_ID[id]
        if wanted(b, members) then
            options[#options + 1] = b
            place[id], count[id] = i, 0
            for _, m in ipairs(members) do count[id] = count[id] + points(m, b) end
        end
    end
    table.sort(options, function(x, y)
        if count[x.id] ~= count[y.id] then return count[x.id] > count[y.id] end
        return place[x.id] < place[y.id]
    end)
    plan.choiceWhy = plan.choiceWhy or {}
    if #options == 0 then
        plan.code = plan.code or "unwanted"
        return false
    end
    local picks, never = Du.picks(job.id), Du.never(job.id)
    -- Everyone who can give at least one option they aren't busy with, and
    -- of them who's picked.
    local all, chosen, whyNot, blocked = {}, {}, {}, nil
    for _, m in ipairs(members) do
        if m.online and barred(never, m) then
            whyNot[m.name] = format("%s is set to never do it.", m.name)
        elseif m.online then
            local isPicked, byName = picked(picks, m)
            local can, why = false, nil
            for _, b in ipairs(options) do
                if Du.canGive(m, b, isPicked and byName) then
                    local h = busy(holding, m, b)
                    if h then
                        why = why or busyWhy(m, h)
                    else
                        can = true
                        break
                    end
                end
            end
            if can then
                all[#all + 1] = m
                if picks and isPicked then chosen[#chosen + 1] = m end
            elseif why then
                whyNot[m.name] = why.text
                if picks and isPicked then blocked = blocked or why end
            end
        end
    end
    local givers = all
    if picks then
        local try = { status = "absent" }
        if #chosen > 0 then
            try = { status = "applied" }
            givers = chosen
        elseif blocked then
            try = { status = "blocked", why = blocked }
        end
        plan.tries = plan.tries or {}
        plan.tries[#plan.tries + 1] = try
    end
    local isGiver = {}
    for _, m in ipairs(givers) do isGiver[m.name] = true end
    -- Why a giver's option set by hand won't be what they put up.
    for _, m in ipairs(members) do
        local id = Du.choiceFor(job.id, m)
        if id and not isGiver[m.name] and m.online then
            plan.choiceWhy[m.name] = whyNot[m.name]
                                     or format("%s isn't giving it.", m.name)
        end
    end
    if #givers == 0 then
        plan.code = plan.code or "nobody"
        return false
    end
    table.sort(givers, function(a, b) return a.name < b.name end)
    local hand = picks ~= nil and #chosen > 0
    local taken, has = {}, {}
    local function assign(m, b, why)
        local byHand = why == HAND or hand
        plan.list[#plan.list + 1] = { job = job, giver = m, buff = b, party = party, hand = byHand or nil,
                                      why = why or (hand and HAND or "Auto: each giver takes a different one.") }
        taken[b.id], has[m.name] = true, true
        hold(holding, m, b, job)
    end
    for _, m in ipairs(givers) do
        local id = Du.choiceFor(job.id, m)
        local b = id and D.BY_ID[id]
        if id == "none" then
            has[m.name] = true
        elseif b and Du.canGive(m, b, true) then
            assign(m, b, HAND)
        elseif b then
            plan.choiceWhy[m.name] = Du.cantWhy(m, b) or format("%s can't put up %s.", m.name, bname(b))
        end
    end
    for _, m in ipairs(givers) do
        if not has[m.name] then
            for _, b in ipairs(options) do
                if not taken[b.id] and not b.optional and Du.canGive(m, b) and not busy(holding, m, b) then
                    assign(m, b)
                    break
                end
            end
        end
    end
    return true
end

-- One giver for the raid (or the party): the first pick here who can do it
-- (fromPicks), else auto's best fit for the first option someone free can
-- give. A player picked puts up the first option they can give, so warlocks
-- picked for the minor armor put up Curse of Recklessness even though
-- Faerie Fire comes first.
local function singleIn(job, members, plan, holding, party)
    local list, never = Du.pickList(job.id), Du.never(job.id)
    local opts = {}
    for _, id in ipairs(job.options) do
        local b = D.BY_ID[id]
        -- An optional buff counts once its job is turned on (Blood Pact), or
        -- when someone is picked for the job (Scorpid Sting).
        if (not b.optional or list or job.optional) and wanted(b, members) then opts[#opts + 1] = b end
    end
    if #opts == 0 then
        plan.code = plan.code or "unwanted"
        return false
    end
    -- What `m` can put up for the job, or why not.
    local function option(m, byName)
        local why
        for _, b in ipairs(opts) do
            if Du.canGive(m, b, byName) then
                local h = busy(holding, m, b)
                if not h then return b end
                why = why or busyWhy(m, h)
            end
        end
        if not why then
            for _, b in ipairs(opts) do
                local text = b.class == m.class and Du.cantWhy(m, b)
                if text then why = { text = text, who = m.name } end
            end
        end
        return nil, why or { text = format("%s can't give %s.", m.name, Du.title(job)), who = m.name }
    end
    local g, b, hand, alts = nil, nil, false, {}
    if list then
        local try
        g, b, try = fromPicks(list, members, never, option, byFit(job))
        plan.tries = plan.tries or {}
        plan.tries[#plan.tries + 1] = try
        hand = g ~= nil
    end
    -- An optional buff counted only for the picks. Auto leaves it out, so
    -- when the druid picked for the hit debuff is gone, no hunter gets asked
    -- for Scorpid Sting.
    local function auto(o) return not o.optional or job.optional end
    if not g then
        for _, o in ipairs(opts) do
            local all = {}
            for _, m in ipairs(auto(o) and members or {}) do
                if m.online and not barred(never, m) and Du.canGive(m, o) and not busy(holding, m, o) then
                    all[#all + 1] = m
                end
            end
            if #all > 0 then
                table.sort(all, byFit(job))
                g, b = all[1], o
                for i = 2, #all do alts[#alts + 1] = all[i] end
                break
            end
        end
    end
    if not g then
        plan.code = "nobody"
        return false
    end
    plan.list[#plan.list + 1] = { job = job, giver = g, buff = b, party = party, why = hand and HAND or nil,
                                  hand = hand or nil, alts = alts,
                                  auto = not hand and { kind = "single", fit = fit(job, g) } or nil }
    hold(holding, g, b, job)
    return true
end

-- Runs `fn` for the raid, or for each party with a party job.
local function scoped(job, members, plan, holding, fn)
    if job.scope ~= "party" then
        return fn(job, members, plan, holding, nil)
    end
    local parties, list = {}, {}
    for _, m in ipairs(members) do
        if not parties[m.group] then
            parties[m.group] = {}
            list[#list + 1] = m.group
        end
        table.insert(parties[m.group], m)
    end
    table.sort(list)
    local any = false
    for _, g in ipairs(list) do
        if fn(job, parties[g], plan, holding, g) then any = true end
    end
    return any
end

local board, mine = {}, {}

-- Totems. Each shaman puts down one totem of each element, so shamans share
-- them out like paladins do blessings. The rules by element, most important
-- first:
--
--   air     Windfury from the shaman nearest the melee: an Enhancement
--           shaman, else the one with the most melee in their party. It's the
--           totem that matters most, and the melee must stay in its range.
--           Then Grace of Air from a second Enhancement shaman, else a
--           Restoration shaman, then Elemental. Windwall for the party of
--           anyone left.
--   earth   Strength of Earth from the shaman nearest the melee, then
--           Stoneskin for the party of anyone left.
--   water   Mana Spring once in each party with a shaman, since two don't
--           stack. A shaman who isn't Restoration puts it down when the party
--           has one, so the Restoration shaman's water stays Healing Stream,
--           which they swap for Mana Tide when it's ready. Every other shaman
--           in the party puts Healing Stream down, since those stack.
--   fire    Flametongue from a Restoration shaman, whose fire totem would do
--           little otherwise. With Windfury down it only helps the
--           Enhancement shamans (the two never both apply), so it's only
--           wanted when there's one. Without Windfury anyone may put it down.
--           An Elemental or Enhancement shaman keeps fire for their damage.
--
-- A totem set by hand for a shaman and an element comes first, and "none"
-- leaves the element free. A fight's resistance totem takes its element
-- (`reserved`), and `plan.cellWhy` says so for a totem set by hand there.
D.TOTEM_ORDER = { "windfury", "strengthofearth", "manaspring", "graceofair", "flametongue",
                  "healingstream", "stoneskin", "windwall" }

local SUPPORT = { restoration = 1, elemental = 2, enhancement = 3 }
-- Who puts Grace of Air down first. The Enhancement shaman nearest the melee
-- already has Windfury in the air slot, so this is the second one.
local GRACE = { enhancement = 1, restoration = 2, elemental = 3 }

local function totems(job, members, plan, reserved, fight)
    local shamans = {}
    plan.cellWhy = {}
    for _, m in ipairs(members) do
        if m.class == "SHAMAN" and m.online then shamans[#shamans + 1] = m end
    end
    if #shamans == 0 then return inactive(plan, "nobody") end
    table.sort(shamans, function(a, b) return a.name < b.name end)

    -- How near the melee each shaman is: Enhancement shamans are in melee,
    -- and anyone else as near as their party's melee.
    local melee = {}
    for _, m in ipairs(members) do
        if m.online and m.tags.melee then melee[m.group] = (melee[m.group] or 0) + 1 end
    end
    local function near(m)
        return (m.specKey == "enhancement" and 100 or 0) + (melee[m.group] or 0)
    end
    local function nearest(a, b)
        if near(a) ~= near(b) then return near(a) > near(b) end
        return a.name < b.name
    end
    local function support(a, b)
        local sa, sb = SUPPORT[a.specKey] or 2, SUPPORT[b.specKey] or 2
        if sa ~= sb then return sa < sb end
        return a.name < b.name
    end

    local used, placed, inParty = {}, {}, {}
    local function take(m, element)
        used[m.name] = used[m.name] or {}
        used[m.name][element] = true
    end
    local function free(m, element)
        return not (used[m.name] and used[m.name][element])
    end
    local function put(m, b, why)
        take(m, b.element)
        local a = { job = job, giver = m, buff = b, party = b.party and m.group or nil, why = why,
                    hand = why == HAND or nil }
        plan.list[#plan.list + 1] = a
        if b.party then
            inParty[m.group] = inParty[m.group] or {}
            inParty[m.group][b.id] = true
        else
            placed[b.id] = true
        end
        return a
    end
    local function partyOf(m)
        local t = {}
        for _, x in ipairs(members) do
            if x.group == m.group then t[#t + 1] = x end
        end
        return t
    end
    -- The first of `list`, sorted by `order`, who can put `b` down, and the
    -- others who could.
    local function first(b, order, only)
        local list = {}
        for _, m in ipairs(shamans) do
            if free(m, b.element) and Du.canGive(m, b) and (not only or only(m)) then list[#list + 1] = m end
        end
        table.sort(list, function(x, y)
            local rx, ry = Du.rankLevel(x, b), Du.rankLevel(y, b)
            if rx ~= ry then return rx > ry end
            return order(x, y)
        end)
        local alts = {}
        for i = 2, #list do alts[#alts + 1] = list[i] end
        return list[1], alts
    end

    for _, m in ipairs(shamans) do
        local held = reserved[m.name] and reserved[m.name].element or {}
        for element, b in pairs(held) do
            take(m, element)
            local set = Du.totemFor(m, element)
            if set and set ~= "none" then
                plan.cellWhy[m.name .. "\1" .. element] = format("%s's %s totem goes to %s for %s.", m.name,
                                                                element, bname(b), fight or "the fight")
            end
        end
        for _, element in ipairs(D.ELEMENTS) do
            local id = free(m, element) and Du.totemFor(m, element)
            if id then
                take(m, element)
                local b = id ~= "none" and D.BY_ID[id]
                if b and b.element == element then put(m, b, HAND) end
            end
        end
    end

    local wf, soe, goa, ft = D.BY_ID.windfury, D.BY_ID.strengthofearth, D.BY_ID.graceofair,
                             D.BY_ID.flametongue
    -- The raid-wide ones.
    local function raidWide(b, order, why)
        if placed[b.id] or not wanted(b, members) then return end
        local m, alts = first(b, order)
        if m then put(m, b, why).alts = alts end
    end
    raidWide(wf, nearest, "Auto: the shaman nearest the melee.")
    raidWide(soe, nearest, "Auto: the shaman nearest the melee.")
    raidWide(goa, function(a, b)
        local ga, gb = GRACE[a.specKey] or 2, GRACE[b.specKey] or 2
        if ga ~= gb then return ga < gb end
        return a.name < b.name
    end, "Auto: Enhancement first, then Restoration, then Elemental.")
    -- Flametongue: for those who don't take Windfury, while it's down.
    if not placed.flametongue then
        local forWho = {}
        for _, m in ipairs(members) do
            if not placed.windfury or not Du.wants(m, wf) then forWho[#forWho + 1] = m end
        end
        if wanted(ft, forWho) then
            local m = first(ft, support, function(x) return x.specKey == "restoration" end)
                      or (not placed.windfury and first(ft, nearest))
            if m then
                put(m, ft, m.specKey == "restoration" and "Auto: a healer's fire totem is free."
                           or "Auto: no Windfury, so Flametongue.")
            end
        end
    end
    -- Mark who Flametongue is for, whoever put it down.
    for _, a in ipairs(plan.list) do
        if a.buff == ft and placed.windfury then a.except = wf end
    end

    -- Each party's own: Mana Spring from one shaman, a Restoration shaman
    -- last, then Healing Stream from the rest, then Stoneskin and Windwall.
    local ms, hs, ss, ww = D.BY_ID.manaspring, D.BY_ID.healingstream, D.BY_ID.stoneskin,
                           D.BY_ID.windwall
    local groups, byGroup = {}, {}
    for _, m in ipairs(shamans) do
        if not byGroup[m.group] then
            byGroup[m.group] = {}
            groups[#groups + 1] = m.group
        end
        table.insert(byGroup[m.group], m)
    end
    table.sort(groups)
    for _, g in ipairs(groups) do
        local here = byGroup[g]
        local party = partyOf(here[1])
        local function has(b) return inParty[g] and inParty[g][b.id] end
        if not has(ms) and wanted(ms, party) then
            local m = first(ms, function(a, b)
                local ra, rb = a.specKey == "restoration", b.specKey == "restoration"
                if ra ~= rb then return rb end
                return a.name < b.name
            end, function(x) return x.group == g end)
            if m then put(m, ms, "Auto: one per group. Two don't stack.") end
        end
        if wanted(hs, party) then
            for _, m in ipairs(here) do
                if free(m, "water") and Du.canGive(m, hs) then
                    local a = put(m, hs, "Auto: it stacks, so each shaman with a free water totem puts one down.")
                    if m.specKey == "restoration" then a.note = "Mana Tide Totem instead when it's ready." end
                end
            end
        end
        for _, b in ipairs({ ss, ww }) do
            if not has(b) and wanted(b, party) then
                local m = first(b, function(x, y) return x.name < y.name end,
                                function(x) return x.group == g end)
                if m then put(m, b, "Auto: no other totem of this element.") end
            end
        end
    end
end

-- =============================================================
-- Fights: resistances
-- =============================================================
-- What putting up resistance buff `b` costs player `m`: how much the slot it
-- takes is worth on the board without the fight (`base`). An empty slot
-- costs nothing, but a hunter's aspect and a damage shaman's fire totem are
-- their own damage, which costs a little.
local TOTEM_COST = { windfury = 40, strengthofearth = 38, graceofair = 34, flametongue = 30,
                     manaspring = 20, healingstream = 14, stoneskin = 12, windwall = 10 }
local AURA_COST = { devotion = 20, concentration = 18, retribution = 16 }

local function slotOf(base, m, b)
    local plan
    if b.class == "PALADIN" then plan = base.paladinAura
    elseif b.element then plan = base.totems end
    for _, a in ipairs(plan and plan.list or {}) do
        if a.giver.name == m.name and (not b.element or a.buff.element == b.element) then return a end
    end
end

local function costOf(base, m, b)
    local a = slotOf(base, m, b)
    if a then return AURA_COST[a.buff.id] or TOTEM_COST[a.buff.id] or 10 end
    if b.class == "HUNTER" then return 2 end
    if b.element == "fire" and m.specKey ~= "restoration" then return 2 end
    return 0
end

-- The givers of school `school`'s resistance in the order we try them. A
-- paladin's aura comes before a shaman's totem for fire and frost, since a
-- raid loses less with one aura gone than with one totem gone. Nature goes
-- to a hunter, unless there are three shamans: two do Windfury and Grace of
-- Air, and the third's air totem is free for Nature Resistance.
local function sourcesFor(school, members)
    if school.id ~= "nature" then return school.sources end
    local shamans = 0
    for _, m in ipairs(members) do
        if m.online and m.class == "SHAMAN" then shamans = shamans + 1 end
    end
    if shamans >= 3 then return { "natureres", "aspectofthewild" } end
    return school.sources
end

-- Who puts up each school the fight asks for. Each source in turn
-- (sourcesFor), and the giver it costs least of the first source anyone
-- can give. Returns the reserved slots by
-- player ({ aura = buff, element = { [element] = buff } }), the jobs the
-- fight turns on (Shadow Protection), what each school gets, and why a
-- giver set by hand doesn't put it up, by school.
local function chooseResists(fight, base, members)
    local reserved, force, schools, handWhy = {}, {}, {}, {}
    local function reserve(m, b)
        local r = reserved[m.name] or { element = {} }
        reserved[m.name] = r
        if b.class == "PALADIN" then r.aura = b end
        if b.element then r.element[b.element] = b end
        if b.class == "HUNTER" then r.aspect = b end
    end
    -- A slot set by hand is the leader's decision, so auto leaves it be.
    local function setByHand(m, b)
        if b.class == "PALADIN" then return Du.choiceFor("paladinAura", m) ~= nil end
        if b.element then return Du.totemFor(m, b.element) ~= nil end
        return false
    end
    local function taken(m, b)
        local r = reserved[m.name]
        if not r then return nil end
        if b.class == "PALADIN" then return r.aura end
        if b.element then return r.element[b.element] end
        return r.aspect
    end
    for _, school in ipairs(D.SCHOOLS) do
        local want = Du.resist(fight, school.id)
        if want then
            local best
            if type(want) == "table" then
                -- Set by hand.
                local m, b = nil, D.BY_ID[want.buff or ""]
                for _, x in ipairs(members) do
                    if x.name == want.giver then m = x end
                end
                if not m then
                    handWhy[school.id] = format("%s isn't here.", tostring(want.giver))
                elseif not m.online then
                    handWhy[school.id] = format("%s is offline.", m.name)
                elseif not (b and b.school == school.id and Du.canGive(m, b, true)) then
                    handWhy[school.id] = format("%s can't put up %s resistance.", m.name, school.title:lower())
                elseif taken(m, b) then
                    handWhy[school.id] = format("%s already puts up %s.", m.name, bname(taken(m, b)))
                else
                    best = { m = m, b = b, cost = costOf(base, m, b), set = true }
                end
            end
            for i, id in ipairs(best and {} or sourcesFor(school, members)) do
                if best then break end
                local b = D.BY_ID[id]
                if b.kind == "long" then
                    -- Shadow Protection takes no one's slot.
                    for _, m in ipairs(members) do
                        if Du.canGive(m, b) and not best then best = { b = b, cost = 0, via = b.job } end
                    end
                else
                    for _, m in ipairs(members) do
                        if Du.canGive(m, b) and not taken(m, b) and not setByHand(m, b) then
                            local cost = costOf(base, m, b)
                            if not best or cost < best.cost or (cost == best.cost and i == best.i
                                                                 and m.name < best.m.name) then
                                best = { m = m, b = b, cost = cost, i = i }
                            end
                        end
                    end
                end
            end
            if best and best.via then
                force[best.via] = true
            elseif best then
                reserve(best.m, best.b)
                -- What it takes the place of, for the Assignments page.
                best.instead = slotOf(base, best.m, best.b)
            end
            schools[school.id] = best or false
        end
    end
    return reserved, force, schools, handWhy
end

-- What a board's buffs reach, as { ["buff@party"] = { b, party } }, party 0
-- for the raid. Blessings and debuffs don't count, since a fight never takes
-- them.
local function reachOf(b0)
    local t = {}
    for id, plan in pairs(b0) do
        local job = D.JOB[id]
        if plan.active and job.kind ~= "blessing" and job.kind ~= "resist" and job.scope ~= "target" then
            for _, a in ipairs(plan.list) do
                if a.buff then t[a.buff.id .. "@" .. (a.party or 0)] = { b = a.buff, party = a.party } end
            end
        end
    end
    return t
end

-- Why auto put each giver on: "Auto: Holy, no other long buff. Also could:
-- Pell (on Divine Spirit)." We say it once the whole board is worked out,
-- so "on" names what the others ended up doing.
local function explain(new)
    local doing = {}
    for _, job in ipairs(D.JOBS) do
        for _, a in ipairs(new[job.id].list) do
            local n = a.giver.name
            doing[n] = doing[n] or {}
            table.insert(doing[n], { job = job.id, what = a.buff and bname(a.buff) or Du.title(job) })
        end
    end
    local function others(a)
        local t = {}
        for i = 1, math.min(2, #a.alts) do
            local m, on = a.alts[i], nil
            for _, d in ipairs(doing[m.name] or {}) do
                if d.job ~= a.job.id then
                    on = d.what
                    break
                end
            end
            t[#t + 1] = on and format("%s (on %s)", m.name, on) or m.name
        end
        if #a.alts > 2 then t[#t + 1] = format("%d more", #a.alts - 2) end
        return t
    end
    for _, job in ipairs(D.JOBS) do
        for _, a in ipairs(new[job.id].list) do
            local x = a.auto
            if x or (a.alts and not a.hand and a.why) then
                local spec = a.giver.spec and Du.specName(a.giver.class, a.giver.spec)
                local text
                if x and x.kind == "cover" then
                    text = #a.alts == 0 and "the only one who can"
                           or x.first and "no other long buff" or "the fewest long buffs"
                    if spec then text = spec .. ", " .. text end
                    text = "Auto: " .. text .. "."
                elseif x and x.kind == "single" then
                    if #a.alts == 0 then
                        text = "the only one who can"
                    elseif x.fit < 99 then
                        text = (spec or className(a.giver.class)) .. ", the best fit"
                    else
                        text = "first in group order"
                    end
                    text = "Auto: " .. text .. "."
                else
                    text = a.why
                end
                local also = others(a)
                if #also > 0 then text = text .. " Others who could: " .. table.concat(also, ", ") .. "." end
                a.why = text
            end
        end
    end
end

-- Whether job `job` has an override that names someone online among
-- `members`: a pick that matches them, or their choice, totems or blessings
-- set by hand. A pick of a player who is offline, or a Never, binds nobody,
-- so the job keeps its place in auto's order.
local function binds(job, members)
    local e = entry(job.id)
    if not e then return false end
    local here = {}
    for _, m in ipairs(members) do
        if m.online then here[m.name] = true end
    end
    for _, pick in ipairs(Du.pickList(job.id) or {}) do
        for _, m in ipairs(members) do
            if m.online and Du.pickMatches(pick, m) then return true end
        end
    end
    for _, field in ipairs({ "choice", "matrix", "assign" }) do
        for name in pairs(type(e[field]) == "table" and e[field] or {}) do
            if here[name] then return true end
        end
    end
    return false
end

-- `noFight` works the board out as if no fight were on, and `as` as if
-- fight `as` were.
local function compute(members, noFight, as)
    topLevel = nil
    for _, m in ipairs(members) do
        if m.online and m.level and m.level > (topLevel or 0) then topLevel = m.level end
    end
    local holding, load = {}, {}
    local new, my = {}, {}
    local fight = not noFight and (as or Du.fight()) or nil
    local base, reserved, force, schools, handWhy = nil, {}, {}, nil, {}
    if fight then
        base = compute(members, true)
        reserved, force, schools, handWhy = chooseResists(fight, base, members)
        for name, r in pairs(reserved) do
            if r.aura then holding[name] = { paladinAura = { job = D.JOB.resistances, buff = r.aura } } end
        end
    end
    -- What was set by hand is a constraint, and auto works around it. So the
    -- jobs with something set by hand go first: a warlock picked for Curse
    -- of Weakness is busy before auto picks a warlock for Curse of the
    -- Elements, and a priest picked for Divine Spirit counts as busy when
    -- auto picks who gives Fortitude. The fight's resistances go before
    -- everything.
    local order = {}
    for _, pass in ipairs({ true, false }) do
        for _, job in ipairs(D.JOBS) do
            if (job.kind == "resist" or binds(job, members)) == pass then order[#order + 1] = job end
        end
    end
    for _, job in ipairs(order) do
        local plan = { job = job, active = true, fallback = false, list = {} }
        new[job.id] = plan
        if job.kind == "resist" then
            plan.fight = fight
            plan.schools = schools or {}
            plan.handWhy = handWhy
            if not fight then inactive(plan, "nofight") end
            for _, school in ipairs(D.SCHOOLS) do
                local s = schools and schools[school.id]
                if s and s.m then
                    -- The note names what the giver puts up without the
                    -- fight, so the page can show the swap.
                    local instead = s.instead and s.instead.buff
                    plan.list[#plan.list + 1] = { job = job, giver = s.m, buff = s.b, school = school.id,
                                                  hand = s.set or nil, why = format("For %s.", fight),
                                                  note = instead and format("In place of %s.", bname(instead)) or nil }
                end
            end
            if fight and #plan.list == 0 and not next(schools) then inactive(plan, "noschools") end
        elseif not Du.enabled(job) and not force[job.id] then
            inactive(plan, "off")
        elseif job.kind == "cover" then
            cover(job, members, plan, load)
        elseif job.kind == "blessing" then
            blessings(job, members, plan)
        elseif job.kind == "totem" then
            totems(job, members, plan, reserved, fight)
        else
            local fn = job.kind == "choice" and choiceIn or singleIn
            local any = scoped(job, members, plan, holding, fn)
            settle(job, plan, plan.tries, members)
            plan.tries = nil
            if any then
                plan.code = nil
            else
                local code = plan.code or "nobody"
                if code == "nobody" and plan.picked and plan.picked.status == "absent" then code = "absent" end
                inactive(plan, code)
            end
        end
        if plan.active and #plan.list == 0 and job.kind ~= "resist" then inactive(plan, "nobody") end
    end
    explain(new)
    for _, job in ipairs(D.JOBS) do
        for _, a in ipairs(new[job.id].list) do
            if a.giver.me then my[#my + 1] = a end
        end
    end
    -- Our backup assignments come after our own.
    if not NS.Options or NS.Options.get("backups") then
        for _, job in ipairs(D.JOBS) do
            local plan = new[job.id]
            for _, a in ipairs(plan.active and plan.reserve or {}) do
                if a.giver.me then my[#my + 1] = a end
            end
        end
    end
    if fight then
        -- Who gives Shadow Protection, and what the raid loses for the fight.
        local plan = new.resistances
        for _, s in pairs(schools) do
            if s and s.via then
                local a = new[s.via].list[1]
                s.m = a and a.giver
            end
        end
        local was, now = reachOf(base), reachOf(new)
        plan.lost = {}
        for key, r in pairs(was) do
            if not now[key] then plan.lost[#plan.lost + 1] = r end
        end
        table.sort(plan.lost, function(a, b)
            if (a.party or 0) ~= (b.party or 0) then return (a.party or 0) < (b.party or 0) end
            return a.b.id < b.b.id
        end)
        -- A hunter's aspect and a damage shaman's fire totem are their own.
        plan.own = {}
        for _, a in ipairs(plan.list) do
            if not slotOf(base, a.giver, a.buff) and costOf(base, a.giver, a.buff) > 0 then
                plan.own[#plan.own + 1] = a
            end
        end
    end
    return new, my
end

-- Works the board out again from the roster and the group's overrides.
function Du.update()
    board, mine = NS.asGroup(compute, R.list())
    NS.signal("board")
    return board
end

function Du.board() return board end
function Du.plan(jobId) return board[jobId] end

-- The board the window shows: the group's, or while we draft a suggestion
-- the one the draft would make. A draft may set specs by hand, so it gets
-- its own copy of the roster with the specs it would give.
local drafted

local function draftBoard()
    if not drafted then
        local members = {}
        for i, m in ipairs(R.list()) do
            local c = {}
            for k, v in pairs(m) do c[k] = v end
            R.describe(c)
            members[i] = c
        end
        drafted = { board = compute(members), members = members }
    end
    return drafted
end

function Du.shown(jobId)
    if NS.draft then return draftBoard().board[jobId] end
    return board[jobId]
end

-- The roster the window shows, with the draft's specs while we draft.
function Du.shownMembers()
    if NS.draft then return draftBoard().members end
    return R.list()
end

-- The resistances plan fight `name` would have if it were on, for the
-- Assignments page to show every fight's givers and cost. Kept until the
-- board changes.
local previews = {}

function Du.preview(name)
    if name == Du.fight() then return Du.shown("resistances") end
    if previews[name] == nil then
        local b
        if NS.draft then
            b = compute(draftBoard().members, false, name)
        else
            b = NS.asGroup(compute, R.list(), false, name)
        end
        previews[name] = b.resistances
    end
    return previews[name]
end

NS.listen("draft", function()
    drafted = nil
    previews = {}
end)
NS.listen("board", function() previews = {} end)

-- Our own assignments, in the job order.
function Du.mine() return mine end

-- =============================================================
-- Pinning what auto chose
-- =============================================================
-- Turns what auto chose for assignment `a` of job `jobId` into a setting by
-- hand, so it stays put when people join or leave. A paladin is assigned
-- the blessing they give the most classes. It's one step, through the edit
-- path like any edit.
function Du.pin(jobId, a)
    local job = D.JOB[jobId]
    if not job or type(a) ~= "table" or not a.giver then return end
    local name = a.giver.name
    Du.batch(nil, function()
        if oneGiver(job) then
            local pick = "name:" .. name
            local list = without(Du.pickList(jobId), pick)
            if job.scope == "party" then
                list[#list + 1] = pick
            else
                table.insert(list, 1, pick)
            end
            Du.setPicks(jobId, list)
        elseif job.kind == "choice" then
            local picks = Du.picks(jobId)
            if picks and not picks["name:" .. name] then Du.setPick(jobId, "name:" .. name, true) end
            if a.buff then Du.setChoice(jobId, name, a.buff.id) end
        elseif job.kind == "totem" then
            if a.buff then Du.setTotem(name, a.buff.element, a.buff.id) end
        elseif job.kind == "blessing" then
            local n, best = {}, nil
            for _, id in pairs(a.byClass or {}) do
                n[id] = (n[id] or 0) + 1
                if not best or n[id] > n[best] or (n[id] == n[best] and id < best) then best = id end
            end
            if best then Du.setAssign(name, "all", best) end
        elseif job.kind == "resist" then
            local fight = Du.fight()
            if fight and a.school and a.buff then
                Du.setResist(fight, a.school, { giver = name, buff = a.buff.id })
            end
        end
    end)
end

-- =============================================================
-- What Costs.lua needs of ours
-- =============================================================
-- Costs.lua works out what the overrides cost, the constraints and the
-- gaps from the board. These are the pieces of this file it needs.

-- Runs `compute` reading duty table `duty` in place of the state's.
local function computeWith(duty, members)
    local was = reading
    reading = duty
    local ok, b = pcall(compute, members)
    reading = was
    if not ok then error(b, 0) end
    return b
end

Du.inner = {
    CODES = CODES,
    barred = barred,
    bname = bname,
    buffWord = buffWord,
    byGroup = byGroup,
    isHand = isHand,
    itemsOf = itemsOf,
    orderKeyWord = orderKeyWord,
    wanted = wanted,
    computeWith = computeWith,
}

-- What a job's buffs are called: "Fortitude", or "Sunder Armor or Expose
-- Armor" for a job with options.
function Du.title(job)
    if job.title then return job.title end
    return NS.Tracking and NS.Tracking.title(D.BY_ID[job.options[1]]) or D.BY_ID[job.options[1]].name
end

-- =============================================================
-- Public API
-- =============================================================
-- The names of the players on duty for a job, or for the job a buff or
-- debuff belongs to.
function NS.API.onDuty(id)
    local b = D.BY_ID[id]
    local jobId = b and b.job or id
    local plan = board[jobId]
    local t = {}
    if not plan then return t end
    for _, a in ipairs(plan.list) do
        if not b or a.buff == b or (a.bless and next(a.bless)) then t[#t + 1] = a.giver.name end
    end
    return t
end

-- Picks saved before they had an order are `true` each. We number them in
-- the order they're read in now, so they read the same way from here on.
-- The copy of whoever runs the board (db.remote) is left as it came, since
-- our checksum must match theirs.
--
-- A plan in use used to give everyone who joined a `false` setting for
-- each part of the blessings that names a player: a choice, a blessing
-- order and a "never". That was one of each for every player we ever
-- grouped with, and they showed up as player overrides on Needs. So we drop
-- every setting that isn't a value its part can hold: a choice that isn't
-- an ID, an order that isn't a list, a "never" that isn't true, and a row
-- of wants, totems or paladin overrides that isn't a table.
local KEEP = {
    choice = function(v) return type(v) == "string" end,
    order = function(v) return type(v) == "table" end,
    never = function(v) return v == true end,
    want = function(v) return type(v) == "table" end,
    matrix = function(v) return type(v) == "table" end,
    assign = function(v) return type(v) == "table" end,
}

local function migrate(duty)
    if type(duty) ~= "table" then return end
    for _, e in pairs(duty) do
        if type(e) == "table" and type(e.picks) == "table" then e.picks = ranked(ordered(e.picks)) end
        for k, ok in pairs(KEEP) do
            if type(e) == "table" and type(e[k]) == "table" then
                for key, v in pairs(e[k]) do
                    if not ok(v) then e[k][key] = nil end
                end
                if next(e[k]) == nil then e[k] = nil end
            end
        end
    end
end

NS.listen("roster", function() NS.soon("board", 0.1, Du.update) end)
-- Someone's camp buffs changed which blessings they want (Tracking.lua).
NS.listen("camp", function() NS.soon("board", 0.1, Du.update) end)
NS.listen("option", function(key)
    if key == nil or key == "backups" then Du.update() end
end)
NS.listen("loaded", function()
    migrate(NS.db.duty)
    if type(NS.db.mock) == "table" then migrate(NS.db.mock.duty) end
    for _, plan in pairs(type(NS.db.plans) == "table" and NS.db.plans or {}) do
        if type(plan) == "table" then migrate(plan.duty) end
    end
    Du.update()
end)
