-- Suggestions: changes from players who may not make them.
--
-- Only the leader and the assistants change assignments. When whoever runs
-- the board lets them (its "Let players suggest changes" setting), everyone
-- else may still use the window as if they could. Their changes go into a
-- draft that only their window shows. Their HUD and whispers, and everyone
-- else, keep going by the group's assignments. They send the draft to the
-- leader and the assistants as a suggestion, and one of them applies it or
-- turns it down. With the setting off, the window is view only for them,
-- even with a draft, so nobody makes changes just to find out they can't
-- send them. They may still discard the draft.
--
-- The leader or an assistant reviews a suggestion the same way. Review puts
-- it in a draft of their own, on top of the group's assignments, so their
-- window shows what it would change. They may change it further, then apply
-- it. Or they go through it change by change (Su.lines, in the constraints
-- panel), tick the ones they want and apply those (Su.applyChecked).
-- Applying sends each changed assignment as an edit of theirs, like any
-- other, and is one step they can undo.
--
-- A draft is a whole copy of the group's assignments and specs, because the
-- window's edits change entries in place. We keep the copy it started from
-- too, to tell what the draft changed. What it changed is a list of items
-- (Duties.lua), one setting each, never whole job entries: the blessings
-- entry holds every order and every paladin's cells, so a raider suggesting
-- their own Wisdom would otherwise send back every blessing as it was, and
-- applying it would quietly undo the leader's newer blessings. When the
-- group's assignments change under a draft, we copy them again and put the
-- draft's items back on top.
--
-- The messages (sent by Sync.lua to the whole group, and only the leader and
-- the assistants act on a suggestion):
--   S  a suggestion: { id, items = { { k, a, b, v, w } }, specs = { [name] =
--      tree or false }, note, duty = { [job] = entry or false } }. Each item
--      is a kind, where it lives, the value it suggests (`v`, none for auto)
--      and the value it was when the suggestion was made (`w`), which tells
--      the leader what they changed since. `note` is a line from the
--      suggester. `duty` is the whole entries of the jobs it changes, for a
--      leader on a version from before the items, who reads only that.
--   A  an answer to one: { to, id, applied, part }. `part` is true when the
--      leader applied some of it.

local _, NS = ...
local D, R, Du, S, O = NS.Data, NS.Roster, NS.Duties, NS.Sync, NS.Options

local format = string.format
local copy, ser = NS.copy, S.ser

local Su = {}
NS.Suggest = Su

-- Suggestions sent to us, by the name of who sent them:
-- { from, class, id, changes, n, at }
local pending = {}
local nextId = 0

-- =============================================================
-- The draft
-- =============================================================
-- Whether whoever runs the board lets players who can't change the
-- assignments suggest changes. When nobody who may change them runs the
-- addon, nobody could take a suggestion either.
function Su.open()
    if not R.grouped() then return false end
    local host = S.host()
    return host ~= nil and S.officer(host) and S.hasAddon(host.name) and not S.closed()
end

local function start(from)
    local state = NS.groupState()
    local base = { duty = copy(state.duty), specs = copy(state.specs) }
    NS.draft = { duty = copy(base.duty), specs = copy(base.specs), base = base, from = from }
    return NS.draft
end

-- The state an edit goes into (NS.writable): our draft while we have one
-- and may change it, the group's when we may change it, a new draft when we
-- may suggest, or nil when the assignments are locked for us.
function Su.target()
    if NS.draft then return Su.canChange() and NS.draft or nil end
    if R.canEdit() then
        -- Before we know who runs the board, our edits stay out of our own
        -- saved board (Sync.lua).
        S.early()
        return NS.state()
    end
    if not Su.open() then return nil end
    return start()
end

-- Whether the window lets us change anything. Not when suggestions are
-- closed for us, even with a draft: we may only discard it then.
function Su.canChange()
    return R.canEdit() or Su.open()
end

local function keys(a, b)
    local t, seen = {}, {}
    for _, x in ipairs({ a or {}, b or {} }) do
        for k in pairs(x) do
            if not seen[k] then
                seen[k] = true
                t[#t + 1] = k
            end
        end
    end
    table.sort(t)
    return t
end

-- What draft `d` changes: { items = { Duties.lua's diff }, specs = { [name]
-- = tree or false }, duty = { [job] = entry or false } }, and how many
-- changes that is.
function Su.changes(d)
    d = d or NS.draft
    local out, n = { duty = {}, specs = {}, items = {} }, 0
    if not d then return out, 0 end
    out.items = Du.diff(d.base.duty, d.duty)
    n = #out.items
    for _, id in ipairs(keys(d.duty, d.base.duty)) do
        if ser(d.duty[id]) ~= ser(d.base.duty[id]) then out.duty[id] = copy(d.duty[id]) or false end
    end
    for _, name in ipairs(keys(d.specs, d.base.specs)) do
        if d.specs[name] ~= d.base.specs[name] then
            out.specs[name] = d.specs[name] or false
            n = n + 1
        end
    end
    return out, n
end

-- Puts `changes` on top of draft `d`, item by item.
local function lay(d, changes)
    for _, it in ipairs(changes.items or {}) do Du.putItem(d.duty, it, it.v) end
    for name, tree in pairs(changes.specs) do d.specs[name] = tree or nil end
end

-- Whether the draft changes job `jobId`, or player `name`'s spec.
function Su.jobChanged(jobId)
    local d = NS.draft
    return d ~= nil and #Du.diff(d.base.duty, d.duty, jobId) > 0
end

function Su.specChanged(name)
    local d = NS.draft
    return d ~= nil and d.specs[name] ~= d.base.specs[name]
end

local function changedDraft()
    NS.signal("draft")
end

-- The group's assignments changed under the draft: copy them again and
-- keep the draft's changes on top.
local function rebase()
    local d = NS.draft
    if not d then return end
    local changes = Su.changes(d)
    local state = NS.groupState()
    d.base = { duty = copy(state.duty), specs = copy(state.specs) }
    d.duty, d.specs = copy(d.base.duty), copy(d.base.specs)
    lay(d, changes)
    changedDraft()
end

-- Drops our draft. A suggestion we sent is taken back, by sending it again
-- with no changes.
function Su.discard()
    local d = NS.draft
    if not d then return end
    if d.sent and not d.from and R.grouped() then S.send("S", { id = d.sent, duty = {}, specs = {}, items = {} }) end
    NS.draft = nil
    changedDraft()
end

-- What `changes` would do, as phrases: "put Bob on Fortitude".
function Su.describe(changes)
    local t = {}
    for _, it in ipairs(changes.items or {}) do t[#t + 1] = Du.changeText(it) end
    for _, name in ipairs(keys(changes.specs)) do t[#t + 1] = Du.specText(name, changes.specs[name] or nil) end
    return t
end

-- =============================================================
-- Sending a suggestion
-- =============================================================
-- What a suggestion asks for, to tell whether the draft changed since we
-- sent it: each item's value and the specs. Not the values the items had
-- then, nor the whole entries, which change when an officer changes
-- anything else in the same job.
local function asked(changes)
    local items = {}
    for i, it in ipairs(changes.items or {}) do items[i] = { key = it.key, v = it.v } end
    return ser({ items = items, specs = changes.specs or {} })
end

-- Whether the draft is the one we sent, unchanged since.
function Su.sent()
    local d = NS.draft
    return d ~= nil and d.sent ~= nil and d.sentText == asked(Su.changes(d))
end

-- A suggestion's items as they go on the wire, with the value each had.
local function wire(items)
    local t = S.wireItems(items)
    for i, it in ipairs(items) do t[i].w = it.w end
    return t
end

-- A note as we send and show it: one line, no escape codes, and short.
local NOTE_MAX = 120

local function cleanNote(note)
    if type(note) ~= "string" then return nil end
    note = note:gsub("[%c|]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if note == "" then return nil end
    return note:sub(1, NOTE_MAX)
end

-- Sends the draft as a suggestion, with `note` (a line for the leader)
-- when there is one.
function Su.submit(note)
    local d = NS.draft
    if not d or d.from or not Su.open() then return false end
    local changes, n = Su.changes(d)
    if n == 0 then return false end
    nextId = nextId + 1
    local id = (time() % 100000) * 100 + nextId % 100
    note = cleanNote(note)
    d.note = note
    S.send("S", { id = id, duty = changes.duty, specs = changes.specs, items = wire(changes.items), note = note })
    d.sent, d.sentText, d.answer = id, asked(changes), nil
    NS.print(n == 1 and "Sent your suggestion (1 change) to the leader and assistants."
             or "Sent your suggestion (%d changes) to the leader and assistants.", n)
    changedDraft()
    return true
end

-- =============================================================
-- Taking a suggestion
-- =============================================================
-- The suggestions waiting for us, oldest first.
function Su.pending()
    local t = {}
    for _, p in pairs(pending) do t[#t + 1] = p end
    table.sort(t, function(a, b) return a.at < b.at end)
    return t
end

local function answer(name, id, applied, part)
    pending[name] = nil
    S.send("A", { to = name, id = id, applied = applied, part = part or nil })
end

-- In a mock raid every edit goes into the mock's own assignments, so a
-- suggestion for the real group waits until it's closed.
local function mockOpen()
    if not NS.mock then return false end
    NS.print("End the mock raid to apply a suggestion.")
    return true
end

-- Applies `changes` to the group's assignments, as our own edits, so each
-- goes to the group and prints like any other, and the whole of it is one
-- step to undo. Only the items and specs `keep` names when it's given.
--
-- While we review another suggestion, its draft is where our edits go. So
-- applying Bob's suggestion as it came, while Carl's is open, would put
-- Bob's changes into Carl's draft and send nothing. We put the draft aside
-- while we apply, and then lay it on the group's new assignments.
local function applyChanges(changes, text, keep)
    local d = NS.draft
    NS.draft = nil
    local ok, err = pcall(function()
        local list = {}
        for _, it in ipairs(changes.items or {}) do
            if not keep or keep[it.key] then list[#list + 1] = it end
        end
        if #list > 0 then Du.applyItems(list, text) end
        for _, name in ipairs(keys(changes.specs)) do
            if not keep or keep["spec:" .. name] then R.setSpec(name, changes.specs[name] or nil) end
        end
    end)
    NS.draft = d
    if d then rebase() end
    if not ok then error(err, 0) end
end

-- Applies the draft we have: our own, or the suggestion we're reviewing,
-- with whatever we changed in it since.
function Su.apply()
    local d = NS.draft
    if not d or not R.canEdit() or mockOpen() then return false end
    local changes = Su.changes(d)
    NS.draft = nil
    applyChanges(changes, d.from and format("apply %s's suggestion", d.from) or "apply the draft")
    if d.from then
        local p = pending[d.from]
        answer(d.from, p and p.id or d.id, true)
    end
    changedDraft()
    return true
end

-- Reviews `name`'s suggestion: a draft of the group's assignments with it on
-- top.
function Su.review(name)
    local p = pending[name]
    if not p or not R.canEdit() then return end
    local d = start(name)
    d.id = p.id
    lay(d, p.changes)
    changedDraft()
end

-- Turns `name`'s suggestion down.
function Su.decline(name)
    local p = pending[name]
    if NS.draft and NS.draft.from == name then NS.draft = nil end
    answer(name, p and p.id or 0, false)
    changedDraft()
end

-- Applies `name`'s suggestion as it came, item by item, so what we changed
-- since in the same jobs stays.
function Su.accept(name)
    local p = pending[name]
    if not p or not R.canEdit() or mockOpen() then return end
    if NS.draft and NS.draft.from == name then NS.draft = nil end
    applyChanges(p.changes, format("apply %s's suggestion", name))
    answer(name, p.id, true)
    changedDraft()
end

-- `name`'s suggestion change by change, for review:
--   { key, text, since, spec }
-- `text` is what it does ("put Bob on Fortitude"), and `since` is true when
-- we changed that setting after the suggestion was made, so applying it
-- would undo our change. `spec` is the player's name for a spec change.
function Su.lines(name)
    local p = pending[name]
    local t = {}
    if not p then return t end
    local duty = NS.groupState().duty
    for _, it in ipairs(p.changes.items or {}) do
        t[#t + 1] = { key = it.key, text = Du.changeText(it),
                      since = it.known and not Du.same(Du.itemValue(duty, it), it.w) or false }
    end
    for _, who in ipairs(keys(p.changes.specs)) do
        t[#t + 1] = { key = "spec:" .. who, spec = who, text = Du.specText(who, p.changes.specs[who] or nil) }
    end
    return t
end

-- The note that came with `name`'s suggestion, or nil.
function Su.note(name)
    local p = pending[name]
    return p and p.note
end

-- Applies the changes of `name`'s suggestion whose keys (Su.lines) are in
-- set `checked`, and answers them. With none checked it's turned down.
function Su.applyChecked(name, checked)
    local p = pending[name]
    if not p or not R.canEdit() or mockOpen() then return false end
    local all, some = 0, 0
    for _, l in ipairs(Su.lines(name)) do
        all = all + 1
        if checked[l.key] then some = some + 1 end
    end
    if some == 0 then
        Su.decline(name)
        return false
    end
    if NS.draft and NS.draft.from == name then NS.draft = nil end
    applyChanges(p.changes, format("apply %s's suggestion", name), checked)
    answer(name, p.id, true, some < all)
    changedDraft()
    return true
end

-- A suggestion's changes as they came, kept to settings we know and values
-- of the right kind. A suggestion from a version before the items has only
-- whole job entries, and we take its items from how they differ from ours
-- now. We can't tell then what we changed since.
local function clean(data)
    local out, n = { duty = {}, specs = {}, items = {} }, 0
    if type(data.items) == "table" then
        for _, t in ipairs(data.items) do
            local it = Du.cleanItem(t)
            if it then
                it.known = true
                out.items[#out.items + 1] = it
            end
        end
    else
        local old, new = {}, {}
        local duty = NS.groupState().duty
        for id, e in pairs(type(data.duty) == "table" and data.duty or {}) do
            if D.JOB[id] and (type(e) == "table" or e == false) then
                old[id] = copy(duty[id])
                new[id] = e or nil
                out.duty[id] = e
            end
        end
        out.items = Du.diff(old, new)
    end
    n = #out.items
    for name, tree in pairs(type(data.specs) == "table" and data.specs or {}) do
        if type(name) == "string" and (type(tree) == "number" or tree == false) then
            out.specs[name] = tree
            n = n + 1
        end
    end
    return out, n
end

S.handle("S", function(m, data)
    if not R.real.canEdit() or not Su.open() or type(data.id) ~= "number" then return end
    local changes, n = clean(data)
    if n == 0 then
        -- They took it back.
        pending[m.name] = nil
        changedDraft()
        return
    end
    local note = cleanNote(data.note)
    pending[m.name] = { from = m.name, class = m.class, id = data.id, changes = changes, n = n, at = GetTime(),
                        note = note }
    local phrases = Su.describe(changes)
    NS.print("%s suggests: %s.%s Open %s to review it.", NS.classColored(m.name, m.class),
             #phrases > 0 and table.concat(phrases, ", ") or "nothing new",
             note and format(" \"%s\"", note) or "", NS.SLASH)
    changedDraft()
end)

S.handle("A", function(m, data)
    if not S.officer(m) or type(data.to) ~= "string" then return end
    local p = pending[data.to]
    if p and p.id == data.id then pending[data.to] = nil end
    if NS.draft and NS.draft.from == data.to and NS.draft.id == data.id then NS.draft = nil end
    local me = R.real.me()
    local who = NS.classColored(m.name, m.class)
    local d = NS.draft
    if me and data.to == me.name and d and not d.from and d.sent == data.id then
        if data.applied and data.part then
            -- They took some of it. Their edits reached us before this, so
            -- the group's assignments have what they took. Laid on top of
            -- them, our draft keeps only the changes they didn't take, which
            -- we may send again.
            d.sent, d.sentText, d.answer = nil, nil, nil
            rebase()
            local _, n = Su.changes(d)
            if n == 0 then
                NS.draft = nil
                NS.print("%s applied your suggestion.", who)
            else
                NS.print("%s applied part of your suggestion. The rest is still in your draft.", who)
            end
        elseif data.applied then
            NS.draft = nil
            NS.print("%s applied your suggestion.", who)
        else
            d.sent, d.sentText, d.answer = nil, nil, m.name
            NS.print("%s turned down your suggestion.", who)
        end
    elseif O.get("logEdits") and R.real.canEdit() and data.to ~= (me and me.name) then
        NS.print("%s %s %s's suggestion.", who, data.applied and "applied" or "turned down", data.to)
    end
    changedDraft()
end)

-- =============================================================
-- Keeping up
-- =============================================================
NS.listen("board", rebase)
NS.listen("groupLeft", function()
    for k in pairs(pending) do pending[k] = nil end
    if NS.draft then
        NS.draft = nil
        changedDraft()
    end
end)
NS.listen("roster", function()
    -- A suggestion from someone who left goes with them.
    for name in pairs(pending) do
        if not R.real.byName(name) then pending[name] = nil end
    end
end)
