-- Changing the group: moving players between parties, the leader, the
-- assistants, the main tanks and main assists, raid roles, and removing
-- someone. The raid pane (RaidPane.lua) offers these, so it can stand in for
-- the game's own raid window.
--
-- Each action works on a member of the roster (Roster.lua). In a real group
-- it calls the game, which tells everyone, and the roster changes when the
-- game says so. In a mock raid (Mock.lua) it changes the mock.
--
-- What we may do follows the game's rules. The leader may do anything. An
-- assistant may move players, mark main tanks and assists, set roles and
-- remove anyone who isn't an assistant. In a party only the leader changes
-- anything but their own role. In a mock raid we may do anything.
--
-- In combat the game won't move players or change ranks, so we don't offer
-- them then. A layout that moves many players at once (G.arrange) goes one
-- move at a time, and pauses in combat until it ends.

local _, NS = ...
local R = NS.Roster

local G = {}
NS.Group = G

local format = string.format

-- =============================================================
-- What we may do
-- =============================================================
-- Our rank in the group we're changing: 2 the leader, 1 an assistant.
local function myRank()
    if NS.mock then return 2 end
    local me = R.real.me()
    local rank = me and me.rank or 0
    if rank < 1 and R.real.raid() and _G.IsEveryoneAssistant and IsEveryoneAssistant() then rank = 1 end
    return rank
end

function G.isLeader() return myRank() >= 2 end

-- Whether raid changes wait for the end of combat. A mock raid isn't the
-- game's, so it never waits.
function G.locked()
    if NS.mock then return false end
    return _G.InCombatLockdown ~= nil and InCombatLockdown() and true or false
end

-- Whether we may move players between parties, now or once combat ends.
local function mayArrange()
    if not R.raid() then return NS.mock == true end
    return myRank() >= 1
end

G.mayArrange = mayArrange

-- Whether we may move players between parties now.
function G.canArrange() return mayArrange() and not G.locked() end

-- Whether we may make someone leader or an assistant, and turn "everyone is
-- an assistant" on or off.
function G.canPromote() return R.grouped() and myRank() >= 2 and not G.locked() end

-- Whether we may mark `m` as a main tank or main assist. A raid only.
function G.canMark()
    return R.raid() and myRank() >= 1 and not G.locked()
end

-- Whether we may set `m`'s raid role.
function G.canRole(m)
    if m.me then return R.grouped() end
    return myRank() >= (R.raid() and 1 or 2)
end

-- Whether we may remove `m` from the group.
function G.canRemove(m)
    if m.me or not R.grouped() or G.locked() then return false end
    local rank = myRank()
    return rank >= 2 or (rank >= 1 and R.raid() and (m.rank or 0) == 0)
end

-- Whether we may turn a party into a raid.
function G.canConvert() return not NS.mock and R.grouped() and not R.raid() and myRank() >= 2 end

-- Whether we may start a ready check.
function G.canReadyCheck() return not NS.mock and R.grouped() and myRank() >= 1 end

-- Whether we may invite players: solo, as a party's leader, or as the
-- leader or an assistant of a raid.
function G.canInvite()
    if NS.mock then return false end
    if R.real.raid() then return myRank() >= 1 end
    return not R.real.grouped() or myRank() >= 2
end

-- =============================================================
-- The game's calls
-- =============================================================
-- Calls the game's `fn` with `...`. A call the game refuses, or one this
-- client doesn't have, says so in the chat frame rather than breaking.
local function call(what, fn, ...)
    if type(fn) ~= "function" then
        NS.print("Can't %s on this client.", what)
        return false
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        NS.print("Couldn't %s (%s).", what, tostring(err))
        return false
    end
    return true
end

local function api(name, space)
    local t = space and _G[space]
    return t and t[name] or _G[name]
end

-- The raid index of `m`, from their unit "raid7".
local function index(m)
    return tonumber(tostring(m.unit or ""):match("^raid(%d+)$"))
end

-- =============================================================
-- Actions
-- =============================================================
-- Moves `m` to party `g`. Returns false when it's full.
function G.move(m, g)
    if not G.canArrange() or m.group == g then return false end
    local n = 0
    for _, x in ipairs(R.list()) do
        if x.group == g then n = n + 1 end
    end
    if n >= 5 then return false end
    if NS.mock then return NS.Mock.move(m.name, g) end
    local i = index(m)
    return i ~= nil and call("move players", api("SetRaidSubgroup"), i, g)
end

-- Swaps the parties of `a` and `b`.
function G.swap(a, b)
    if not G.canArrange() or a.group == b.group then return false end
    if NS.mock then return NS.Mock.swap(a.name, b.name) end
    local i, j = index(a), index(b)
    return i ~= nil and j ~= nil and call("move players", api("SwapRaidSubgroup"), i, j)
end

function G.lead(m)
    if not G.canPromote() or m.me then return false end
    if NS.mock then return NS.Mock.setRank(m.name, 2) end
    return call("change the leader", api("PromoteToLeader"), m.unit)
end

-- Makes `m` an assistant, or not (`on` false). A party has no assistants,
-- so it's a raid only.
function G.assist(m, on)
    if not G.canPromote() or not R.raid() or m.me or (m.rank or 0) >= 2 then return false end
    if NS.mock then return NS.Mock.setRank(m.name, on and 1 or 0) end
    if on then return call("promote", api("PromoteToAssistant"), m.unit) end
    return call("demote", api("DemoteAssistant"), m.unit)
end

-- Marks `m` as the main tank or main assist (`mark`), or clears it.
function G.mark(m, mark, on)
    if not G.canMark() then return false end
    if NS.mock then return NS.Mock.setMark(m.name, mark, on) end
    if on then return call("set the " .. mark:lower(), api("SetPartyAssignment"), mark, m.unit) end
    return call("clear the " .. mark:lower(), api("ClearPartyAssignment"), mark, m.unit)
end

-- Sets `m`'s raid role: "TANK", "HEALER", "DAMAGER", or nil for none.
function G.role(m, role)
    if not G.canRole(m) then return false end
    if NS.mock then return NS.Mock.setRole(m.name, role) end
    return call("set roles", api("UnitSetRole"), m.unit, role or "NONE")
end

function G.remove(m)
    if not G.canRemove(m) then return false end
    if NS.mock then return NS.Mock.remove(m.name) end
    return call("remove players", api("UninviteUnit", "C_PartyInfo"), m.unit)
end

-- Whether everyone is an assistant, and turning it on or off.
function G.allAssist()
    if NS.mock then return NS.Mock.allAssist() end
    return _G.IsEveryoneAssistant and IsEveryoneAssistant() and true or false
end

function G.setAllAssist(on)
    if not G.canPromote() then return false end
    if NS.mock then return NS.Mock.setAllAssist(on) end
    return call("change assistants", api("SetEveryoneIsAssistant"), on and true or false)
end

function G.convert()
    if not G.canConvert() then return false end
    return call("make a raid", api("ConvertToRaid", "C_PartyInfo"))
end

function G.readyCheck()
    if not G.canReadyCheck() then return false end
    return call("start a ready check", api("DoReadyCheck"))
end

-- =============================================================
-- Moving many players
-- =============================================================
-- A layout (Arrange.lua's, or a plan's) moves many players at once. The game
-- takes one move at a time and says when it's done with GROUP_ROSTER_UPDATE,
-- so we keep a queue. We make one move, wait until the roster shows it, look
-- at the raid again and make the next. In combat the queue waits, and it goes
-- on when combat ends. In a mock raid the whole layout happens at once.
--
-- Any change to the raid fires GROUP_ROSTER_UPDATE, like someone joining or
-- a role changing, so an update alone doesn't mean the game made our move.
-- When the server lags, the roster still shows the old parties for a while,
-- and if we looked again then we'd send the same swap a second time, which
-- swaps the two back. So we remember where the last move should put each
-- player it moves, and go on only once the roster shows them there. When
-- STEP_WAIT passes without that, the game didn't make the move, and we stop
-- and say so rather than guess.
--
-- `want` is { [name] = party }. A player it doesn't name stays where they
-- are, unless a swap moves them out of the way.
local STEP_WAIT = 5
local MAX_STEPS = 80
local queue

-- The next move toward `want`, from the parties in `groups` ({ [name] =
-- party }): the first player not in their party yet moves there when it has
-- room. Otherwise they swap with someone there who belongs elsewhere.
-- Returns "move", name, party or "swap", name, name.
local function nextMove(want, groups)
    local count, list = {}, {}
    for name, g in pairs(groups) do
        count[g] = (count[g] or 0) + 1
        list[#list + 1] = name
    end
    table.sort(list)
    local names = {}
    for name in pairs(want) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local at, g = groups[name], want[name]
        if at and at ~= g then
            if (count[g] or 0) < 5 then return "move", name, g end
            for _, x in ipairs(list) do
                if groups[x] == g and want[x] ~= g then return "swap", name, x end
            end
        end
    end
end

-- Everyone's party now, by name.
local function groupsNow()
    local t = {}
    for _, m in ipairs(R.list()) do t[m.name] = m.group end
    return t
end

-- Where the queue would put everyone in `members` (the roster) for `want`,
-- move by move, without moving anyone: { [name] = party }. The pane shows
-- it before a plan is applied.
function G.layout(want, members)
    local groups = {}
    for _, m in ipairs(members or R.list()) do groups[m.name] = m.group end
    for _ = 1, MAX_STEPS do
        local kind, a, b = nextMove(want, groups)
        if not kind then break end
        if kind == "move" then
            groups[a] = b
        else
            groups[a], groups[b] = groups[b], groups[a]
        end
    end
    return groups
end

local function finish(why)
    if not queue then return end
    queue = nil
    if why then NS.print(why) end
    NS.signal("arrange")
end

-- Whether the roster shows the parties the last move should have made.
local function arrived(expect)
    for name, g in pairs(expect) do
        local m = R.byName(name)
        if m and m.group ~= g then return false end
    end
    return true
end

-- How many players named in `want` aren't in their party yet.
local function left(want)
    local n = 0
    for name, g in pairs(want) do
        local m = R.byName(name)
        if m and m.group ~= g then n = n + 1 end
    end
    return n
end

-- Looks at the raid and makes the next move. `timedOut` is true when
-- STEP_WAIT passed since the last move.
local function step(timedOut)
    if not queue or G.locked() then return end
    if not mayArrange() then return finish("Stopped moving players. You can't move them any more.") end
    R.scan()
    if queue.expect then
        if not arrived(queue.expect) then
            if timedOut then return finish("Stopped moving players. The game didn't make the last move.") end
            return
        end
        queue.expect = nil
    end
    local kind, a, b = nextMove(queue.want, groupsNow())
    if not kind then
        local n = left(queue.want)
        return finish(n > 0 and format("Stopped moving players. %d couldn't get into their group.", n) or nil)
    end
    if queue.steps >= MAX_STEPS then
        return finish(format("Stopped moving players after %d moves.", MAX_STEPS))
    end
    queue.steps = queue.steps + 1
    local ma, mb = R.byName(a), kind == "swap" and R.byName(b) or nil
    local ok
    if kind == "move" then
        ok = G.move(ma, b)
        queue.expect = { [a] = b }
    else
        queue.expect = { [a] = mb.group, [b] = ma.group }
        ok = G.swap(ma, mb)
    end
    if not ok then return finish("Stopped moving players. The game refused a move.") end
    -- When no update comes, we look again after STEP_WAIT anyway, so one
    -- lost update can't hold the queue up for good. Only for this queue:
    -- after we stop and arrange again, the new queue's step count may match.
    local q, n = queue, queue.steps
    C_Timer.After(STEP_WAIT, function()
        if queue == q and queue.steps == n and queue.expect then step(true) end
    end)
    NS.signal("arrange")
end

-- Moves everyone to their party in `want`. Returns whether it started. In
-- combat it starts when combat ends.
function G.arrange(want)
    if not mayArrange() then return false end
    if NS.mock then return NS.Mock.arrange(want) end
    queue = { want = want, steps = 0 }
    NS.signal("arrange")
    step()
    return true
end

-- How many players the queue still has to move, or nil when there's no
-- queue.
function G.arranging()
    if not queue then return nil end
    return left(queue.want)
end

function G.stopArranging() finish() end

NS.on("GROUP_ROSTER_UPDATE", function()
    if queue and queue.expect then NS.soon("arrange", 0.5, step) end
end)
-- The game refuses moves in combat, so a move we sent just before it began
-- may never come. After combat we look afresh.
NS.on("PLAYER_REGEN_ENABLED", function()
    if not queue then return end
    NS.soon("arrangeAfterCombat", 0.5, function()
        if queue and queue.expect and not arrived(queue.expect) then queue.expect = nil end
        step()
    end)
end)
NS.on("GROUP_LEFT", function() finish() end)

-- =============================================================
-- Invites
-- =============================================================
-- Invites `names` (Forever's "First Last", as the roster keeps them). A
-- party holds 5, so outside a raid we invite only as many as fit and keep
-- the rest. When we're in a party already we make it a raid at once, and
-- solo we make it a raid once someone has joined. Then we invite the rest.
-- Returns how many we invited now.
--
-- The rest wait INVITE_WAIT at most. When nobody joins in that time, or we
-- leave the group, they're forgotten, so a raid we form much later doesn't
-- invite them out of nowhere.
local INVITE_WAIT = 120
local invites

local function inviteNow(names)
    local room = #names
    if not R.real.raid() then room = math.max(0, 5 - math.max(1, #R.real.list())) end
    local sent, rest = 0, {}
    for i, name in ipairs(names) do
        if i <= room then
            if call("invite players", api("InviteUnit", "C_PartyInfo"), name) then sent = sent + 1 end
        else
            rest[#rest + 1] = name
        end
    end
    invites = #rest > 0 and { names = rest, at = GetTime() } or nil
    if invites and R.real.grouped() and not R.real.raid() then G.convert() end
    return sent
end

-- Forgets the players still waiting when they waited too long.
local function expire()
    if invites and GetTime() - invites.at > INVITE_WAIT then invites = nil end
end

function G.invite(names)
    if not G.canInvite() or #names == 0 then return 0 end
    return inviteNow(names)
end

-- How many players still wait for a raid to be invited.
function G.invitesLeft()
    expire()
    return invites and #invites.names or 0
end

NS.on("GROUP_ROSTER_UPDATE", function()
    if not invites then return end
    NS.soon("invites", 0.5, function()
        expire()
        if not invites then return end
        if R.real.raid() then
            if G.canInvite() then inviteNow(invites.names) end
        elseif R.real.grouped() and #R.real.list() >= 2 then
            G.convert()
        end
    end)
end)
local function forget() invites = nil end
NS.on("GROUP_LEFT", forget)
NS.listen("groupLeft", forget)
