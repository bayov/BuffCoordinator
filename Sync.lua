-- Keeping everyone in the group on the same assignments.
--
-- WHO RUNS THE BOARD (the "host" in the code). One player's client holds the
-- assignments the group goes by: the leader's when they run the addon, else
-- the first assistant's who does, else (in a party, or a raid whose leader
-- and assistants don't run it) the first player's by name who does. Everyone
-- works the host out the same way from the roster and who said hello, so
-- nobody has to agree on it.
--
-- WHAT WE SEND. The assignments are worked out from the roster, the specs
-- and what's set by hand only (Duties.lua), so we only send what's set by
-- hand and the specs set by hand, never the assignments themselves.
--   hello    who runs the addon, their version and board format, their spec,
--            the talent buffs they know and their checksum (`sum`).
--            Everyone says it on joining, and answers a hello from someone
--            new, or from someone who just joined or reloaded (`ask`), with
--            their own.
--   ask      "send me your board", from a player who just joined or who
--            missed something
--   board    the host's settings and specs, in answer to an ask, and
--            whether the host lets others suggest changes. A host who hands
--            the board over (`handover`) sends it to a leader coming back.
--   sum      the host's checksum of them, a few seconds after a change and
--            every minute. A player whose own doesn't match asks again.
--   edit     one job's changed settings (`items`, Duties.lua), from the
--            leader or an assistant who changed them, and the job's whole
--            entry for clients from before the items. Everyone checks the
--            sender's rank and drops an edit from anyone else, except a
--            player's own blessing order, which anyone may send for
--            themselves (S.ownItem).
--   reset    every job back to auto
--   spec     a spec the leader set by hand for a player
--   suggest  changes a player who can't make them sends the leader and
--            assistants, and their answer (Suggest.lua)
--   check    on a ready check, which of a player's buffs run out within
--            the fight, or none. The coverage strip shows them (Coverage.lua).
--   camp     the blessings a player's camp buffs stand in for, and how
--            long they last, which only they can read (Tracking.lua). Sent
--            when they change, and with a hello.
--
-- Edits print one line for each of us a few seconds after they stop, like
-- "Bayov (assistant) put Thrall on Windfury Totem and 2 more". It's a print,
-- not a chat message. The HUD says on its own when our assignments change.
--
-- When someone else runs the board, their copy goes in NS.remote and our own
-- saved assignments stay as they were, for the next group we lead. When we
-- run it, the edits go into our own. A board handed over to us when we come
-- back becomes our own too.
--
-- THE WIRE. A message is "1\t<kind>\t<id>\t<part>\t<parts>\t<data>": the
-- protocol, the kind, a number of ours for the message, and which part of it
-- this is, because an addon message holds 255 bytes and a board is longer.
-- The data is a table written by `ser`. Everything goes through one queue,
-- which keeps to the game's limit (10 at once, then 1 a second), waits while
-- the game blocks addon chat in a boss fight, and keeps only the newest of a
-- board or a sum.
--
-- A board of 40 players with Buffs by Spec set for each of them came to 86
-- parts, over a minute to send. So a board names each string once and
-- refers back to it after that (`ser`'s `refs`), which makes it less than
-- half as long. Smaller messages go ahead of a board that's still going
-- out (S.send), and we never send a board to a player whose checksum already
-- matches ours. A board past what the others take isn't sent, and the host
-- hears so.
--
-- OLD CLIENTS. The protocol stays "1", so clients from before the picks had
-- an order still read us and we read them. What a board means changed though
-- (picks in order, "Never", Buffs by Spec), so a hello and a board also
-- carry FORMAT, and S.oldClients names who runs an older one, whose HUD may
-- differ from ours. A client before FORMAT 3 can't read a board that refers
-- back to its strings, so we only send one that does when every player with
-- the addon told us they run 3 or newer.

local _, NS = ...
-- The group we're really in, even in a mock raid (Mock.lua).
local D, R, Du = NS.Data, NS.Roster.real, NS.Duties
local secret, readable = NS.secret, NS.readable

local format = string.format

local S = {}
NS.Sync = S

local PREFIX = "BUFFCO"
local PROTO = "1"
-- What a board means: 1 before the picks had an order and before "Never", 2
-- since, and 3 since Buffs by Spec and boards that refer back to their
-- strings. A client that doesn't say is 1.
local FORMAT = 3
S.FORMAT = FORMAT
-- An addon message holds 255 bytes, and our header before the data takes
-- at most 17 of them.
local CHUNK = 230

-- =============================================================
-- Writing tables as text
-- =============================================================
-- A string is "s<length>:<bytes>", a number "n<digits>;", true and false
-- are "t" and "f", and a table is "{" then each key and value, then "}".
-- Keys go in order, so the same table always comes out the same, which the
-- checksum needs.
--
-- With `refs`, a string written before comes again as "r<n>;", the n-th
-- "s" string of the text, when that's shorter. A board names the same
-- players and buffs over and over, so this makes it much shorter. The
-- reader counts every "s" string it reads, so a string written twice
-- counts twice on both sides.
local function keyOrder(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    return a < b
end

local function ser(v, out, refs)
    out = out or {}
    local t = type(v)
    if t == "string" then
        local s = "s" .. #v .. ":" .. v
        local n = refs and refs.at[v]
        if n and #tostring(n) + 2 < #s then
            out[#out + 1] = "r" .. n .. ";"
        else
            out[#out + 1] = s
            if refs then
                refs.n = refs.n + 1
                refs.at[v] = refs.at[v] or refs.n
            end
        end
    elseif t == "number" then
        out[#out + 1] = "n" .. tostring(v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "t" or "f"
    elseif t == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, keyOrder)
        for _, k in ipairs(keys) do
            ser(k, out, refs)
            ser(v[k], out, refs)
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "f"
    end
    return out
end

-- `compact` refers back to strings, which only clients of FORMAT 3 and
-- newer read.
function S.ser(v, compact)
    return table.concat(ser(v, nil, compact and { n = 0, at = {} } or nil))
end

-- Reads what `ser` wrote. Throws on anything else, so callers pcall it.
--
-- Anyone can send us anything, and a hello is read before we know who sent
-- it. So every part must move us forward. A string whose length is cut off,
-- negative or not a whole number would send us back to read the same text
-- again, forever, like "{ts-5:". We throw on it instead. Tables nest at most
-- MAX_DEPTH deep, which is far more than a board needs.
local MAX_DEPTH = 20

-- `strings` is every "s" string read so far, in order, for "r<n>;".
local function deser(text, i, depth, strings)
    local c = text:sub(i, i)
    if c == "s" then
        local colon = text:find(":", i + 1, true)
        local n = colon and tonumber(text:sub(i + 1, colon - 1))
        if not n or n < 0 or n % 1 ~= 0 or colon + n > #text then error("bad string at " .. i) end
        local v = text:sub(colon + 1, colon + n)
        strings[#strings + 1] = v
        return v, colon + n + 1
    elseif c == "r" then
        local semi = text:find(";", i + 1, true)
        local n = semi and tonumber(text:sub(i + 1, semi - 1))
        local v = n and strings[n]
        if not v then error("bad reference at " .. i) end
        return v, semi + 1
    elseif c == "n" then
        local semi = text:find(";", i + 1, true)
        local n = semi and tonumber(text:sub(i + 1, semi - 1))
        if not n or n ~= n then error("bad number at " .. i) end
        return n, semi + 1
    elseif c == "t" then
        return true, i + 1
    elseif c == "f" then
        return false, i + 1
    elseif c == "{" then
        depth = (depth or 0) + 1
        if depth > MAX_DEPTH then error("too deep at " .. i) end
        local t = {}
        i = i + 1
        while text:sub(i, i) ~= "}" do
            if i > #text then error("cut short") end
            local k, v
            k, i = deser(text, i, depth, strings)
            v, i = deser(text, i, depth, strings)
            t[k] = v
        end
        return t, i + 1
    end
    error("bad data at " .. i)
end

function S.deser(text)
    local ok, v = pcall(deser, text, 1, nil, {})
    if ok then return v end
    return nil
end

local copy = NS.copy

-- Whether whoever runs the board turned suggestions off: our own setting
-- when we run it (even when we took over someone else's board), else what
-- their board said. Until their board comes, we take it they didn't.
function S.closed(state)
    local group = NS.groupState()
    state = state or group
    if state == group and (not R.grouped() or S.isHost()) then return not NS.Options.get("suggest") end
    if state ~= NS.db then return state.closed == true end
    return false
end

-- A checksum of the assignments and specs we go by.
function S.sum(state)
    state = state or NS.groupState()
    local text = S.ser({ duty = state and state.duty or {}, specs = state and state.specs or {},
                         closed = S.closed(state) })
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
    return h
end

-- =============================================================
-- Who runs the addon, and who hosts
-- =============================================================
-- users[name] = { version, fmt, at, hello, answered }: who we heard from.
-- `hello` is true once their hello came, and `fmt` is the board format it
-- said.
local users = {}
S.users = users
-- How a sender's name came in an addon message, to the roster name it is.
local aliases = {}
local joinedAt = nil

local function version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local ok, v = pcall(get or function() end, NS.name, "Version")
    return ok and v or "?"
end

-- The roster member a message's sender is. Forever's names have two parts,
-- and how a sender's name comes in an addon message isn't certain, so we try
-- the ways we know: the name a hello told us, the name as it is, with a
-- dash for the space, without a realm, and the first name alone when only
-- one member has it.
--
-- The first name alone counts only when the first name alone is what came.
-- A sender "Lead Xyz" is not the leader "Lead Er", even though both start
-- with "Lead".
local function memberOf(sender, useAlias)
    local name = useAlias and aliases[sender]
    if name and R.byName(name) then return R.byName(name) end
    if R.byName(sender) then return R.byName(sender) end
    local spaced = sender:gsub("%-", " ")
    if R.byName(spaced) then return R.byName(spaced) end
    local bare = R.bareName(sender)
    if bare and R.byName(bare) then return R.byName(bare) end
    if not bare or bare:find("%s") then return nil end
    local first = bare:match("^([^%-%s]+)")
    local found
    for _, m in ipairs(R.list()) do
        if m.name:match("^(%S+)") == first then
            if found then return nil end
            found = m
        end
    end
    return found
end

function S.member(sender)
    if type(sender) ~= "string" or secret(sender) then return nil end
    return memberOf(sender, true)
end

-- Whether a hello from `sender` may name itself `name`. Anyone can put any
-- name in a hello, so a raider could pose as the leader. We take it only
-- when it is the sender's own name: as it came, without a realm, with dashes
-- for spaces and in any case, or the roster member the sender already is.
local function plain(text) return (text:gsub("%-", " ")):lower() end

local function ownName(sender, name)
    local want = plain(name)
    if plain(sender) == want then return true end
    -- A sender who is a roster member by their full name is that member.
    local exact = R.byName(sender) or R.byName((sender:gsub("%-", " ")))
    if exact then return exact.name == name end
    local bare = R.bareName(sender)
    if bare and plain(bare) == want then return true end
    -- Only the first name came. It names them only when nobody else in the
    -- group has that first name. Otherwise a raider who shares it with an
    -- officer could say hello as the officer, and every message of theirs
    -- would count as the officer's.
    local first = bare and plain(bare)
    if first and not first:find(" ") and want:match("^(%S+)") == first then
        local n = 0
        for _, m in ipairs(R.list()) do
            if plain(m.name):match("^(%S+)") == first then n = n + 1 end
        end
        return n == 1
    end
    local m = memberOf(sender, false)
    return m ~= nil and m.name == name
end

function S.hasAddon(name)
    local me = R.me()
    return (me and me.name == name) or users[name] ~= nil
end

-- Whether member `m` may change assignments: the leader or an assistant in
-- a raid, the leader in a party.
function S.officer(m)
    if not m then return false end
    if R.raid() and _G.IsEveryoneAssistant and IsEveryoneAssistant() then return true end
    return m.rank > 0
end

-- The host's member, worked out the same way on every client. With
-- `withoutMe`, who it would be if we weren't here.
function S.host(withoutMe)
    if not R.grouped() then return not withoutMe and R.me() or nil end
    local leader, assists, others = nil, {}, {}
    for _, m in ipairs(R.list()) do
        if m.online and S.hasAddon(m.name) and not (withoutMe and m.me) then
            if m.rank == 2 then
                leader = m
            elseif m.rank == 1 then
                assists[#assists + 1] = m
            else
                others[#others + 1] = m
            end
        end
    end
    if leader then return leader end
    local byName = function(a, b) return a.name < b.name end
    table.sort(assists, byName)
    if assists[1] then return assists[1] end
    table.sort(others, byName)
    return others[1] or (not withoutMe and R.me()) or nil
end

function S.isHost()
    local h, me = S.host(), R.me()
    return h ~= nil and me ~= nil and h.name == me.name
end

-- Whether the leader or an assistant runs the board. When none of them runs
-- the addon, whoever comes first by name does, and they shouldn't whisper
-- strangers without knowing it.
function S.boardByOfficer()
    return S.officer(S.host())
end

-- The players with the addon whose board format is older than ours, by
-- name. Their HUD may differ from ours, since they read what's set by hand
-- the old way.
function S.oldClients()
    local t = {}
    for name, u in pairs(users) do
        if u.hello and (u.fmt or 1) < FORMAT and R.byName(name) then t[#t + 1] = name end
    end
    table.sort(t)
    return t
end

-- =============================================================
-- Sending
-- =============================================================
local queue = {}
local tokens, refilled = 10, nil
-- Our message numbers start anywhere, so after a /reload the parts of a new
-- message don't mix with the parts of an old one the others still wait on.
local sentId = math.random(0, 9998)
S.queue = queue

local function locked()
    local ci = _G.C_ChatInfo
    if ci and ci.InChatMessagingLockdown then
        local ok, yes = pcall(ci.InChatMessagingLockdown)
        if ok and readable(yes) and yes then return true end
    end
    return false
end
S.locked = locked

function S.channel()
    if IsInGroup and _G.LE_PARTY_CATEGORY_INSTANCE and IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if R.raid() then return "RAID" end
    if R.grouped() then return "PARTY" end
end

-- The game's answers that mean "not now": too many messages, or chat
-- blocked. We keep the message and try again.
local RETRY = { [3] = true, [8] = true, [11] = true }

local function pump()
    local now = GetTime()
    refilled = refilled or now
    tokens = math.min(10, tokens + (now - refilled))
    refilled = now
    if #queue == 0 or locked() then return end
    while #queue > 0 and tokens >= 1 do
        local q = queue[1]
        local channel = S.channel()
        if not channel then
            for i = #queue, 1, -1 do queue[i] = nil end
            return
        end
        local send = C_ChatInfo and C_ChatInfo.SendAddonMessage
        if not send then return end
        local ok, result = pcall(send, PREFIX, q.text, channel)
        if ok and type(result) == "number" and RETRY[result] then
            tokens = 0
            return
        end
        q.msg.started = true
        q.msg.ahead = 0
        table.remove(queue, 1)
        tokens = tokens - 1
    end
end
S.pump = pump

-- The most parts a message may have. The others drop a longer one, so we
-- don't send it at all. A client from before also stops at 100.
local MAX_PARTS = 100
S.MAX_PARTS = MAX_PARTS

-- How many messages may go ahead of a board that's going out, one after
-- another. The others drop a message whose next part takes longer than
-- PART_WAIT (below) to come, and we send one message a second.
local MAX_AHEAD = 10

-- Where a new message goes in the queue: at the end, or ahead of the rest of
-- a board that's going out. It never goes ahead of anything else, so the
-- others still get our edits in the order we made them. And never ahead of
-- a board that hasn't started, which a new edit would come before. Our
-- edits that go ahead of a board are on top of it, and the others put them
-- back on top once it's all there (S.receive).
local function place(key)
    if key == "board" then return #queue + 1 end
    local at = #queue + 1
    while at > 1 and queue[at - 1].key == "board" and queue[at - 1].msg.started do at = at - 1 end
    local board = queue[at] and queue[at].msg
    if not board or board.ahead >= MAX_AHEAD then return #queue + 1 end
    board.ahead = board.ahead + 1
    return at
end

-- Sends `data` as a message of `kind` to the group. A `key` keeps only the
-- newest message with it in the queue. A message whose first part already
-- went stays, though, since the others would wait on the rest of it.
-- `compact` writes it referring back to its strings (S.ser).
--
-- Answers how many parts it has, and doesn't send one of more than
-- MAX_PARTS.
function S.send(kind, data, key, compact)
    -- Nothing from a mock raid reaches the group.
    if NS.mock or not S.channel() then return end
    local text = S.ser(data or {}, compact)
    local parts = math.max(1, math.ceil(#text / CHUNK))
    if parts > MAX_PARTS then return parts end
    if key then
        for i = #queue, 1, -1 do
            if queue[i].key == key and not queue[i].msg.started then table.remove(queue, i) end
        end
    end
    sentId = (sentId % 9999) + 1
    local msg = { started = false, ahead = 0 }
    local at = place(key)
    for i = 1, parts do
        local chunk = text:sub((i - 1) * CHUNK + 1, i * CHUNK)
        table.insert(queue, at + i - 1, { key = key, msg = msg,
                                          text = table.concat({ PROTO, kind, sentId, i, parts, chunk }, "\t") })
    end
    pump()
    return parts
end

-- =============================================================
-- What each message does
-- =============================================================
-- The assignments we last went by, to tell what an edit changed.
local snapshot = {}

local function takeSnapshot()
    local state = NS.groupState()
    snapshot = copy(state and state.duty or {})
end

-- What changed on job `jobId` from entry `old` to `new`, as phrases of
-- something done: "put Bob, else a warlock on Curse of Recklessness".
function S.describe(jobId, old, new)
    local t = {}
    if not D.JOB[jobId] then return t end
    for _, it in ipairs(Du.diff({ [jobId] = old }, { [jobId] = new }, jobId)) do
        t[#t + 1] = Du.changeText(it, true)
    end
    return t
end

-- Edits print once they stop for this long.
local QUIET = 4
-- What each player did lately, by who: { who, phrases }, in order.
local gathered = {}
local gatherId = 0

local function printGathered()
    for _, g in ipairs(gathered) do
        local p, n = g.phrases, #g.phrases
        local text
        if n <= 3 then
            text = NS.andList(p)
        else
            text = format("%s, %s and %d more", p[1], p[2], n - 2)
        end
        NS.print("%s %s.", g.who, text)
    end
    for i = #gathered, 1, -1 do gathered[i] = nil end
end

-- The jobs we give something in on the board now, as a set.
local function givingIn()
    local t = {}
    for id, plan in pairs(Du.board() or {}) do
        for _, a in ipairs(plan.list or {}) do
            if a.giver and a.giver.me then t[id] = true end
        end
    end
    return t
end

-- Whether a change of jobs `jobs` (a set, or nil for every job) touched us:
-- we gave something in one of them before it (`was`, from givingIn) or do
-- now.
local function touches(was, jobs)
    local now = givingIn()
    for _, set in ipairs({ was, now }) do
        for id in pairs(set) do
            if not jobs or jobs[id] then return true end
        end
    end
    return false
end

-- Notes that `m` did each of `phrases`, to print in one line a few seconds
-- after the edits stop.
--
-- The leader and the assistants see every edit, since they share the
-- board. Everyone else sees only the edits that touched their own
-- assignments (`mine`). In a raid of 40 they'd otherwise read every change
-- the officers make while they set the raid up, which mostly isn't theirs.
--
-- Edits we put back on top of a board that came after them (S.receive)
-- printed when they first came, so they don't print again (`quiet`).
local quiet = false

local function log(m, phrases, mine)
    if quiet or not NS.Options.get("logEdits") or #phrases == 0 then return end
    if not mine and not R.canEdit() then return end
    local who = NS.classColored(m.name, m.class)
    local rank = NS.rankWord(m)
    if rank then who = format("%s (%s)", who, rank) end
    local g
    for _, x in ipairs(gathered) do
        if x.who == who then g = x end
    end
    if not g then
        g = { who = who, phrases = {} }
        gathered[#gathered + 1] = g
    end
    for _, p in ipairs(phrases) do g.phrases[#g.phrases + 1] = p end
    gatherId = gatherId + 1
    local id = gatherId
    C_Timer.After(QUIET, function()
        if id == gatherId then printGathered() end
    end)
end

-- Items (Duties.lua) as they go on the wire: { k, a, b, v }.
local function wireItems(items)
    local t = {}
    for i, it in ipairs(items) do t[i] = { k = it.kind, a = it.a, b = it.b, v = it.v } end
    return t
end
S.wireItems = wireItems

-- How long after joining (or a /reload) our hello asks everyone for theirs.
-- By then we've heard who runs the board.
local ASK_WINDOW = 10

-- The copy of the board we keep over a /reload is as new as its last edit.
-- While we run the board from it, like an assistant whose leader went
-- offline, it's as new as now (the ticker at login), so it never runs out
-- while we run the board.
local function touched()
    if NS.remote and NS.db and type(NS.db.remote) == "table" and NS.db.remote.duty == NS.remote.duty then
        NS.db.remote.at = time()
    end
end

-- The state an edit from someone else goes into: the group's. Before the
-- board of whoever runs it reaches us, that would be our own saved
-- assignments, so we keep their edits in a copy of ours until the board
-- comes and replaces it.
local function received()
    if NS.remote or S.isHost() then return NS.groupState() end
    local h = S.host()
    NS.remote = { duty = copy(NS.db.duty), specs = copy(NS.db.specs), host = h and h.name, early = true }
    return NS.remote
end

-- Our own saved board as it was before our first edit in a group we may
-- not run the board of (S.early).
local pristine = nil

-- Our own edit of the group's assignments, before the board of whoever runs
-- it reached us. Suggest.target calls this before each edit.
--
-- When someone else runs the board, the edit goes into the copy we keep
-- until their board comes (received), like their own edits do, and to the
-- group as usual. Our own saved board stays as it was.
--
-- In our first seconds in a group we may think we run the board only
-- because nobody else said hello yet. Then the edit goes into our own saved
-- board, since it may well be ours, but we keep a copy of how it was. When
-- someone else's board comes after all, we put ours back (adopt). A leader
-- always runs the board, so their edits are always their own.
function S.early()
    if NS.mock or NS.remote or not R.grouped() then return end
    if not S.isHost() then
        received()
        return
    end
    local me = R.me()
    if pristine or not joinedAt or S.inGroupFor() >= ASK_WINDOW or not me or me.rank == 2 then return end
    pristine = { duty = copy(NS.db.duty), specs = copy(NS.db.specs) }
end

-- Once we know we run the board, the edits of our first seconds stay.
local function settle()
    if pristine and S.inGroupFor() >= ASK_WINDOW and S.isHost() then pristine = nil end
end

-- Our own edit: send it, and print it like anyone else's.
--
-- An edit carries the settings it changed (`items`), so two officers who
-- change different cells of the blessings at once don't undo each other.
-- It also carries the job's whole entry for clients from before the items.
--
-- Our own blessing order (`what` is "own") goes even when we may not change
-- anything else. It goes alone, since the others take nothing more from us.
local function onEdit(jobId, what)
    if NS.mock then return end
    local me = R.me()
    local own = what == "own"
    if not me or not R.grouped() or not (R.canEdit() or own) then
        takeSnapshot()
        return
    end
    local state = NS.groupState()
    if what == "reset" and not jobId then
        S.send("X", {})
        log(me, { "set every assignment back to auto" })
    else
        local entry = state.duty[jobId]
        local items = Du.diff({ [jobId] = snapshot[jobId] }, { [jobId] = entry }, jobId)
        if own then
            local mine = {}
            for _, it in ipairs(items) do
                if S.ownItem(me.name, it) then mine[#mine + 1] = it end
            end
            items = mine
        end
        local whole = nil
        if R.canEdit() then whole = copy(entry) or false end
        S.send("E", { job = jobId, entry = whole, items = wireItems(items) })
        local phrases = {}
        for i, it in ipairs(items) do phrases[i] = Du.changeText(it, true) end
        log(me, phrases)
    end
    touched()
    takeSnapshot()
    S.sumSoon()
end

local function onSpecEdit(name, tree)
    if NS.mock then return end
    local me = R.me()
    if not me or not R.grouped() or not R.canEdit() then return end
    S.send("P", { name = name, tree = tree or false })
    log(me, { Du.specText(name, tree) })
    touched()
    S.sumSoon()
end

-- Every message's handler, by kind: fn(member, data).
local handlers = {}

function S.handle(kind, fn) handlers[kind] = fn end

-- The talent buffs our last hello said we know, as written by `ser`.
local saidTalents

-- Our hello carries our checksum, so a host whose board we already have
-- doesn't send it again, like when we /reload.
local function sayHello()
    local me = R.me()
    if not me then return end
    -- The spec we learned from our talents, even when the leader set
    -- another by hand: that one comes with the board, and the others need
    -- ours for when it's cleared.
    local tree = me.learnedFrom == "talents" and me.learned or false
    local talents = Du.ownTalents()
    saidTalents = S.ser(talents)
    S.send("H", { name = me.name, ver = version(), fmt = FORMAT, tree = tree, talents = talents, sum = S.sum(),
                  ask = joinedAt ~= nil and S.inGroupFor() < ASK_WINDOW or nil }, "hello")
    if NS.Tracking.campOf(me.name) then S.sendCamp() end
end
S.hello = sayHello

local function ask()
    if S.isHost() then return end
    S.send("Q", { sum = S.sum() }, "ask")
end

local function boardData()
    local state = NS.groupState()
    return { duty = copy(state.duty), specs = copy(state.specs), closed = S.closed(state), fmt = FORMAT }
end

-- Whether every player with the addon reads a board that refers back to
-- its strings: each said hello with FORMAT 3 or newer.
local function allCompact()
    for name, u in pairs(users) do
        if R.byName(name) and not (u.hello and (u.fmt or 1) >= 3) then return false end
    end
    return true
end

-- A board this many parts long is close to the most the others take
-- (MAX_PARTS). We tell the host once in a group when it gets there, and
-- again when it's past it, since the others then stop getting the board.
local WARN_PARTS = 80
local warned = nil

local function sendBoardData(data)
    local parts = S.send("B", data, "board", allCompact())
    if not parts then return end
    if parts > MAX_PARTS then
        if warned ~= "over" then
            warned = "over"
            NS.print("The assignments are too big to send, so the group doesn't get them. Clear some overrides.")
        end
    elseif parts >= WARN_PARTS and not warned then
        warned = "near"
        NS.print("The assignments are almost too big to send to the group. Clear some overrides to make room.")
    end
end

local function sendBoard()
    if not S.isHost() then return end
    settle()
    sendBoardData(boardData())
    S.sumSoon()
end
S.sendBoard = sendBoard

function S.sumSoon()
    NS.soon("syncSum", 3, function()
        if S.isHost() and next(users) then S.send("R", { sum = S.sum() }, "sum") end
    end)
end

-- When we last stopped running the board for a group with others who run the
-- addon, like when the leader came back online. A leader who comes back
-- takes the board over from us, and we hand it to them (handlers.H).
local ranUntil = nil
local HANDOVER_WAIT = 60

-- The talent buffs a hello says its sender knows, kept to their class's.
local function toldTalents(m, list)
    local t = {}
    for id, yes in pairs(type(list) == "table" and list or {}) do
        local b = type(id) == "string" and D.BY_ID[id]
        if b and b.talent and b.class == m.class and yes == true then t[id] = true end
    end
    return t
end

local lastAsk = -100
handlers.H = function(m, data)
    local hosted = S.isHost() and next(users) ~= nil
    local u = users[m.name]
    local new = u == nil or not u.hello
    u = u or {}
    users[m.name] = u
    u.version = type(data.ver) == "string" and data.ver or nil
    u.fmt = tonumber(data.fmt) or 1
    u.at, u.hello = GetTime(), true
    R.told[m.name] = type(data.tree) == "number" and data.tree or nil
    Du.told[m.name] = toldTalents(m, data.talents)
    -- Their spec and talents may have changed the board. Talents aren't
    -- part of what makes a scan count as a change, so we force it.
    R.scanSoon(0.3, true)
    -- Someone new, or someone who just joined or reloaded: they hear our
    -- hello in turn, and the host sends them the board unless they have it.
    if new or (data.ask and GetTime() - (u.answered or -100) > ASK_WINDOW) then
        u.answered = GetTime()
        NS.soon("helloBack", 2, sayHello)
        if S.isHost() and data.sum ~= S.sum() then NS.soon("boardSoon", 3, sendBoard) end
    end
    -- They just joined and take the board over from us, like a leader coming
    -- back. They'd go by their own saved board, which doesn't have what we
    -- changed while they were gone, so we hand them ours first. They only
    -- take it from the leader or an assistant (handlers.B).
    local host = S.host()
    if data.ask and host and host.name == m.name and S.officer(R.me()) and data.sum ~= S.sum()
       and (hosted or (ranUntil and GetTime() - ranUntil < HANDOVER_WAIT)) then
        ranUntil = nil
        -- Our hello goes first, so they know us when the board comes.
        sayHello()
        local b = boardData()
        b.handover = true
        sendBoardData(b)
    end
end

handlers.Q = function(m, data)
    if S.isHost() and data.sum ~= S.sum() then NS.soon("boardSoon", 1, sendBoard) end
end

local function adopt(m, duty, specs, closed)
    if pristine then
        NS.db.duty, NS.db.specs = pristine.duty, pristine.specs
        pristine = nil
    end
    NS.remote = { duty = duty or {}, specs = specs or {}, host = m.name, closed = closed }
    if NS.db then
        NS.db.remote = { duty = NS.remote.duty, specs = NS.remote.specs, host = m.name, closed = closed,
                         at = time() }
    end
    takeSnapshot()
    R.scan()
    Du.update()
end

-- A board handed to us when we come back and run it again. We take it only
-- from the leader or an assistant who would run the board without us, only
-- when its first part came in our first seconds in the group, and only
-- once. A raider runs the board only when no officer runs the addon, and
-- they can't change it, so their copy has nothing we'd want over our own.
--
-- We run the board from here on, so it becomes our own saved board, the one
-- we edit and keep. In NS.remote our edits would never reach our own, and
-- the copy we keep over a /reload expires after ten minutes. So a leader
-- who came back, led for an hour and then reloaded would lose the board.
--
-- It replaces what we had set up ourselves, so it's a step we can undo
-- (Du.keepStep), which puts our own back.
local HANDOVER_TAKE = 30
local handedOver = false

-- When the first part of the message we handle now came (S.receive). A big
-- board takes a while, so a handover counts from when it started.
local startedAt

local function takeOver(m, duty, specs)
    local oldDuty, oldSpecs = NS.db.duty, NS.db.specs
    NS.db.duty, NS.db.specs = duty, specs
    pristine = nil
    NS.remote = nil
    NS.db.remote = nil
    takeSnapshot()
    R.scan()
    Du.update()
    if Du.keepStep(format("take over %s's assignments", m.name), oldDuty, duty, oldSpecs, specs) then
        NS.print("You took over the assignments from %s.", m.name)
    end
end

-- Answers whether we took the board, so S.receive puts the edits that came
-- while it did back on top.
handlers.B = function(m, data)
    if type(data.duty) ~= "table" or type(data.specs) ~= "table" then return end
    if data.handover and S.isHost() then
        local before = S.host(true)
        if handedOver or not before or before.name ~= m.name or not S.officer(m) then return end
        if not joinedAt or (startedAt or GetTime()) - joinedAt > HANDOVER_TAKE then return end
        handedOver = true
        takeOver(m, data.duty, data.specs)
        NS.soon("boardSoon", 1, sendBoard)
        return true
    end
    local host = S.host()
    if not host or host.name ~= m.name or S.isHost() then return end
    -- The board we have already, sent again for someone who joined. A new
    -- copy would cost the leader's assistants their undo, which only works
    -- in the copy it was made in (Duties.lua).
    local closed = data.closed == true
    local r = NS.remote
    if r and not r.early and S.sum({ duty = data.duty, specs = data.specs, closed = closed }) == S.sum() then
        r.host = m.name
        touched()
        return
    end
    adopt(m, data.duty, data.specs, closed)
    return true
end

-- The host's newest checksum and when it came. One that comes while their
-- board is still coming in parts waits for the board (S.receive), since it
-- may be of what the board brings.
local heardSum, heardAt
local boardComing

local function checkSum()
    if heardSum ~= S.sum() and GetTime() - lastAsk > 10 then
        lastAsk = GetTime()
        ask()
    end
end

handlers.R = function(m, data)
    local host = S.host()
    if not host or host.name ~= m.name or S.isHost() then return end
    heardSum, heardAt = data.sum, GetTime()
    if not boardComing(m.name) then checkSum() end
end

-- Whether item `it` (Duties.lua's) is player `name`'s own blessing order:
-- the one setting anyone may change. They may set it themselves (`self`),
-- or put it back to auto.
function S.ownItem(name, it)
    return it.kind == "order" and it.a == "name:" .. name
           and (it.v == nil or type(it.v) == "table" and it.v.self == true)
end

-- Whether edit `data` from `m`, who may not change assignments, is only
-- their own blessing order.
local function ownOnly(m, data)
    if type(data.items) ~= "table" or #data.items == 0 then return false end
    for _, t in ipairs(data.items) do
        local it = Du.cleanItem(t)
        if not it or not S.ownItem(m.name, it) then return false end
    end
    return true
end

handlers.E = function(m, data)
    if type(data.job) ~= "string" or not D.JOB[data.job] then return end
    if not S.officer(m) then
        if not ownOnly(m, data) then return end
        data.entry = nil
    end
    local state = received()
    local job = data.job
    local old = copy(state.duty[job])
    -- Only the settings they changed, so what someone else changed in the
    -- same job stays. When an item is one we can't read, like a kind of
    -- setting newer than our version, it would be lost. Then we take their
    -- whole entry instead, as a client from before the items does.
    local whole = type(data.items) ~= "table"
    local items = {}
    for _, t in ipairs(whole and {} or data.items) do
        local it = Du.cleanItem(t)
        if it and it.job == job then
            items[#items + 1] = it
        elseif data.entry ~= nil then
            whole = true
        end
    end
    if whole then
        state.duty[job] = type(data.entry) == "table" and data.entry or nil
    else
        for _, it in ipairs(items) do Du.putItem(state.duty, it, it.v) end
    end
    Du.changedBy(m.name, { [job] = old }, { [job] = state.duty[job] })
    local was = givingIn()
    touched()
    takeSnapshot()
    Du.update()
    log(m, S.describe(job, old, state.duty[job]), touches(was, { [job] = true }))
    if S.isHost() then S.sumSoon() end
end

-- Ready-check statuses by player name: { at, due = { [buff id] = how many } }.
S.checks = {}

handlers.C = function(m, data)
    if type(data.due) ~= "table" then return end
    local due = {}
    for id, n in pairs(data.due) do
        if type(id) == "string" and D.BY_ID[id] and type(n) == "number" then due[id] = n end
    end
    S.checks[m.name] = { at = GetTime(), due = due }
    NS.signal("checks")
end

-- Tells the group what of ours is due on the pull: { [buff id] = how many }.
function S.sendCheck(due)
    local me = R.me()
    if me then S.checks[me.name] = { at = GetTime(), due = due or {} } end
    S.send("C", { due = due or {} }, "check")
    NS.signal("checks")
end

-- The longest camp buffs last, as far as we take another player's word.
local CAMP_MAX = 4 * 3600

-- Tells the group which blessings our camp buffs stand in for.
function S.sendCamp()
    local me = R.me()
    if not me then return end
    local list = {}
    for id in pairs(NS.Tracking.campOf(me.name) or {}) do list[#list + 1] = id end
    table.sort(list)
    local c = NS.Tracking.camps[me.name]
    local left = #list > 0 and c and c.expires > 0 and math.floor(c.expires - GetTime() + 0.5) or 0
    S.send("K", { camp = list, left = left }, "camp")
end

handlers.K = function(m, data)
    if type(data.camp) ~= "table" then return end
    local ids = {}
    for _, id in ipairs(data.camp) do
        local b = type(id) == "string" and D.BY_ID[id]
        if b and b.camp then ids[id] = true end
    end
    local left = type(data.left) == "number" and data.left > 0 and data.left or CAMP_MAX
    local expires = GetTime() + math.min(left, CAMP_MAX)
    NS.Tracking.setCamp(m.name, ids, expires)
end

-- Our camp buffs changed.
NS.listen("camp", function(name)
    local me = R.me()
    if me and name == me.name and R.grouped() then S.sendCamp() end
end)

-- A new ready check: the statuses of the last one are old.
NS.on("READY_CHECK", function()
    for k in pairs(S.checks) do S.checks[k] = nil end
end)

handlers.X = function(m)
    if not S.officer(m) then return end
    local state = received()
    local old = copy(state.duty)
    -- Like Du.resetAll: a fight's givers set by hand go back to auto too.
    Du.allToAuto(state.duty)
    local jobs = {}
    for _, it in ipairs(Du.diff(old, state.duty)) do jobs[it.job] = true end
    Du.changedBy(m.name, old, state.duty)
    local was = givingIn()
    touched()
    takeSnapshot()
    Du.update()
    log(m, { "set every assignment back to auto" }, touches(was, jobs))
    if S.isHost() then S.sumSoon() end
end

handlers.P = function(m, data)
    if not S.officer(m) or type(data.name) ~= "string" then return end
    local tree = type(data.tree) == "number" and data.tree or nil
    received().specs[data.name] = tree
    local me = R.me()
    log(m, { Du.specText(data.name, tree) }, me ~= nil and me.name == data.name)
    touched()
    R.scan()
    if S.isHost() then S.sumSoon() end
end

-- =============================================================
-- Receiving
-- =============================================================
-- Parts of messages still coming, by sender, kind and message number:
-- { kind, from, n, got, chunks, first, at, after }. Parts that stop coming
-- are dropped after a while, so a message cut short, or one from before the
-- sender's /reload, never mixes with a new one.
--
-- A board is a while in coming, and the edits that come meanwhile are newer
-- than it: the host's go ahead of it (S.send), and another officer's may
-- reach us before the host's board has them. So we keep them (`after`) and
-- put them back on top of the board once it's all there.
local parts = {}
local PART_WAIT = 20
local CHANGES = { E = true, X = true, P = true }

boardComing = function(name)
    for _, p in pairs(parts) do
        if p.kind == "B" and p.from == name then return true end
    end
    return false
end

-- We only send to the group (S.channel), so a message that came any other
-- way, like a whisper from someone outside the group, isn't ours to read.
local GROUP_CHANNELS = { RAID = true, PARTY = true, INSTANCE_CHAT = true }

function S.receive(prefix, text, channel, sender)
    if secret(prefix) or prefix ~= PREFIX or secret(text) or type(text) ~= "string" then return end
    if secret(channel) or not GROUP_CHANNELS[channel] then return end
    local proto, kind, id, i, n, chunk = text:match("^(%d+)\t(%a)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
    if proto ~= PROTO then return end
    i, n = tonumber(i), tonumber(n)
    if i < 1 or i > n or n > MAX_PARTS then return end
    local m
    if kind == "H" then
        -- A hello names its sender, which teaches us how their name comes.
        -- Only their own name, though (ownName).
        --
        -- When names come as the first name alone, two players who share it
        -- come as the same sender. Then the sender is no alias of either,
        -- since a message from them could be from both, and we don't take
        -- the hello either.
        local data = n == 1 and S.deser(chunk) or nil
        if type(data) ~= "table" then data = nil end
        local named = data and type(data.name) == "string" and R.byName(data.name)
        if named and type(sender) == "string" and not secret(sender) and ownName(sender, named.name) then
            local was = aliases[sender]
            if was == nil or was == named.name then
                aliases[sender] = named.name
                m = named
            else
                aliases[sender] = false
                return
            end
        else
            m = S.member(sender)
        end
    else
        m = S.member(sender)
    end
    if not m or m.me then return end
    local now = GetTime()
    for k, x in pairs(parts) do
        if now - x.at > PART_WAIT then parts[k] = nil end
    end
    local key = m.name .. "\1" .. kind .. "\1" .. id
    local p = parts[key]
    if not p or p.n ~= n then
        p = { kind = kind, from = m.name, n = n, got = 0, chunks = {}, first = now }
        parts[key] = p
    end
    p.at = now
    if not p.chunks[i] then
        p.chunks[i] = chunk
        p.got = p.got + 1
    end
    if p.got < p.n then return end
    parts[key] = nil
    local data = S.deser(table.concat(p.chunks))
    if type(data) ~= "table" then return end
    -- Any message tells us they run the addon.
    if kind ~= "H" and not users[m.name] then users[m.name] = { at = GetTime() } end
    local fn = handlers[kind]
    if not fn then return end
    startedAt = p.first
    local took = fn(m, data)
    startedAt = nil
    if CHANGES[kind] then
        for _, x in pairs(parts) do
            if x.kind == "B" then
                x.after = x.after or {}
                x.after[#x.after + 1] = { kind = kind, m = m, data = data }
            end
        end
    elseif kind == "B" and took then
        quiet = true
        local ok, err = pcall(function()
            for _, e in ipairs(p.after or {}) do handlers[e.kind](e.m, e.data) end
        end)
        quiet = false
        if not ok then error(err, 0) end
        -- A checksum that came after the board started is of the board and
        -- what came since, so now we can tell whether we have it all.
        if heardAt and heardAt >= p.first then checkSum() end
    end
end

-- =============================================================
-- Joining and leaving
-- =============================================================
local function joined()
    joinedAt = GetTime()
    handedOver = false
    NS.soon("helloJoin", 1, sayHello)
    NS.soon("askJoin", 3, ask)
end

local function left()
    for k in pairs(users) do users[k] = nil end
    for k in pairs(S.checks) do S.checks[k] = nil end
    for k in pairs(parts) do parts[k] = nil end
    for k in pairs(aliases) do aliases[k] = nil end
    for i = #queue, 1, -1 do queue[i] = nil end
    NS.remote = nil
    if NS.db then NS.db.remote = nil end
    joinedAt, ranUntil = nil, nil
    warned, heardSum, heardAt, pristine = nil, nil, nil, nil
    takeSnapshot()
    NS.signal("groupLeft")
    Du.update()
end

-- How long we've been in this group, for the whispers, which wait until
-- we've heard who runs the addon.
function S.inGroupFor()
    return joinedAt and GetTime() - joinedAt or 0
end

-- R is the real group (Roster.lua), so a mock raid we had open before
-- joining a group doesn't count as being in one.
local wasGrouped = false
local wasHost = false
NS.listen("roster", function()
    local grouped = R.grouped()
    if grouped and not wasGrouped then joined() end
    if not grouped and wasGrouped then left() end
    wasGrouped = grouped
    -- Someone who said hello may have left.
    for name in pairs(users) do
        if not R.byName(name) then users[name] = nil end
    end
    for sender, name in pairs(aliases) do
        if name and not R.byName(name) then aliases[sender] = nil end
    end
    local host = grouped and S.isHost()
    if host then
        settle()
        touched()
    end
    if host and not wasHost and next(users) then NS.soon("boardSoon", 2, sendBoard) end
    if wasHost and not host and grouped and next(users) then ranUntil = GetTime() end
    wasHost = host
end)

NS.listen("loaded", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
    -- After a /reload in a group, the board of whoever runs it is back until
    -- they send it again. Or it's the board we run, when we took over
    -- running it from someone else's copy (touched).
    local r = NS.db.remote
    if type(r) == "table" and type(r.duty) == "table" and type(r.specs) == "table"
       and time() - (r.at or 0) < 600 then
        NS.remote = { duty = r.duty, specs = r.specs, host = r.host, closed = r.closed == true }
    else
        NS.db.remote = nil
    end
    takeSnapshot()
end)

NS.listen("login", function()
    if not R.grouped() and NS.remote then
        NS.remote = nil
        NS.db.remote = nil
        Du.update()
    end
    C_Timer.NewTicker(0.25, pump)
    C_Timer.NewTicker(60, function()
        if not (R.grouped() and S.isHost()) then return end
        settle()
        touched()
        if next(users) then S.send("R", { sum = S.sum() }, "sum") end
    end)
end)

NS.on("CHAT_MSG_ADDON", function(_, ...) S.receive(...) end)
-- When we run the board, turning suggestions on or off reaches the group
-- with the board.
NS.listen("option", function(key)
    if (key == nil or key == "suggest") and R.grouped() and S.isHost() and next(users) then sendBoard() end
end)
NS.listen("edit", onEdit)
NS.listen("specEdit", onSpecEdit)
NS.on("PLAYER_TALENT_UPDATE", function() NS.soon("helloTalents", 2, sayHello) end)
NS.on("TRAIT_CONFIG_UPDATED", function() NS.soon("helloTalents", 2, sayHello) end)
-- The spellbook changes often (a druid's forms), and our talents rarely, so
-- we only say hello again when the talent buffs we know changed.
NS.on("SPELLS_CHANGED", function()
    NS.soon("spellsChanged", 2, function()
        if saidTalents == nil or S.ser(Du.ownTalents()) == saidTalents then return end
        Du.update()
        sayHello()
    end)
end)

NS.command("sync", "ask the Assignments Leader for the assignments again", function()
    if S.isHost() then
        sendBoard()
        NS.print("You're the Assignments Leader. Sent the assignments to the group.")
    else
        ask()
        local h = S.host()
        NS.print("Asked %s for the assignments.", h and h.name or "the Assignments Leader")
    end
end)
