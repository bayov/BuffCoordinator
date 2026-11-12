-- Who is in the group: names, classes, parties, specs and ranks.
--
-- NAMES. On Forever a character has a first and a last name, "Bayov
-- Windborne", and UnitName answers them as two values. We join them, and
-- that's the name we whisper and the name an assignment stores.
--
-- SPECS decide what each player wants and who gives a talent buff. We learn
-- them from, best first:
--   1. a spec the leader set by hand (`db.specs`)
--   2. our own talents, for us
--   3. FojjiCore's spec messages ("FJSPEC"), which every client hears, so
--      never FojjiCore's own lookup, which only our client has
--   4. the role the raid leader gave them (a druid tank is Feral)
-- Without any of that a player only has the tags every spec of their class
-- shares, so a druid we know nothing about never gets Intellect.

local _, NS = ...
local D = NS.Data
local secret, readable = NS.secret, NS.readable
local max = math.max


local R = {}
NS.Roster = R

-- =============================================================
-- Names
-- =============================================================
-- A unit's "First Last" name, without a realm (Shared/Util.lua).
R.unitName = NS.Util.unitName

-- A sender's name from an addon message, without a realm.
function R.bareName(sender)
    if type(sender) ~= "string" or secret(sender) then return nil end
    return (sender:gsub("%-[^%-]*$", ""))
end

-- =============================================================
-- Specs
-- =============================================================
function R.spec(class, tree)
    local list = D.SPECS[class]
    return list and tree and list[tree] or nil
end

function R.treeOfKey(class, key)
    for i, s in ipairs(D.SPECS[class] or {}) do
        if s.key == key then return i end
    end
end

-- The tags every spec of a class shares.
local commonTags = {}
local function common(class)
    if commonTags[class] then return commonTags[class] end
    local list = D.SPECS[class] or {}
    local t = {}
    for _, tag in ipairs(list[1] and list[1].tags or {}) do t[tag] = true end
    for i = 2, #list do
        local has = {}
        for _, tag in ipairs(list[i].tags) do has[tag] = true end
        for tag in pairs(t) do
            if not has[tag] then t[tag] = nil end
        end
    end
    commonTags[class] = t
    return t
end

-- The role every spec of a class has, like melee for a rogue, or nil when the
-- specs differ.
local function commonRole(class)
    local role
    for _, s in ipairs(D.SPECS[class] or {}) do
        if role and s.role ~= role then return nil end
        role = s.role
    end
    return role
end

-- Our own leading talent tree. Forever's talents are one trait tree with the
-- three old trees as groups, and the game says the points spent in each.
-- Older clients answer GetTalentTabInfo.
function R.ownTree()
    local best, bestPts, tied = nil, 0, false
    local points = {}
    local T = _G.C_Traits
    local ok = pcall(function()
        local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and
                         C_ClassTalents.GetActiveConfigID()
        local config = configID and T and T.GetConfigInfo(configID)
        local treeID = config and config.treeIDs and config.treeIDs[1]
        if not treeID then return end
        local groups = T.GetGroupDisplayInfoByTreeID(treeID)
        if type(groups) ~= "table" or #groups ~= 3 then return end
        local ids = {}
        for i, g in ipairs(groups) do ids[i] = g.groupID end
        local spent = {}
        for _, info in ipairs(T.GetGroupCurrencyInfo(configID, ids) or {}) do
            local c = info.currencyInfos and info.currencyInfos[1]
            if info.traitNodeGroupID then spent[info.traitNodeGroupID] = c and tonumber(c.spent) or 0 end
        end
        for i, g in ipairs(groups) do points[i] = spent[g.groupID] or 0 end
    end)
    if not ok or #points == 0 then
        for tab = 1, 3 do
            if _G.GetTalentTabInfo then
                local okT, a, b, c, d, e = pcall(_G.GetTalentTabInfo, tab)
                -- The points are the third value on old clients, the fifth on
                -- newer ones.
                local n = okT and (tonumber(e) or tonumber(c)) or 0
                points[tab] = n
            end
        end
    end
    for tab, n in ipairs(points) do
        if n > bestPts then
            best, bestPts, tied = tab, n, false
        elseif n == bestPts and n > 0 then
            tied = true
        end
    end
    if tied then return nil end
    return best
end

-- The specs FojjiCore's messages told us, by player name: the spec's key,
-- like "fury".
R.fjspec = {}
-- The specs players running Buff Coordinator told us, by name: a tree.
R.told = {}

local function assignedRole(unit)
    if not UnitGroupRolesAssigned then return nil end
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    if not ok or not readable(role) or role == "NONE" then return nil end
    return role
end

local ownTree
-- What we learned of a player's spec, leaving out one set by hand: the tree
-- number and where from ("talents", "told", "fojji" or "role"), or nil.
local function learned(m)
    if m.me and ownTree then return ownTree, "talents" end
    local told = R.told[m.name]
    if told and R.spec(m.class, told) then return told, "told" end
    local key = R.fjspec[m.name]
    local tree = key and R.treeOfKey(m.class, key)
    if tree then return tree, "fojji" end
    local byRole = m.assigned and D.ROLE_SPEC[m.class] and D.ROLE_SPEC[m.class][m.assigned]
    if byRole then return byRole, "role" end
    return nil
end

-- A player's spec as the tree number, and where we learned it: "set",
-- "talents", "told", "fojji" or "role". nil when we don't know.
--
-- A spec set by hand wins over everything we learn, and stays until it's
-- cleared. So after a respec it can be wrong, and R.describe keeps what we
-- learned beside it (`learned`), for the raid pane to say so.
function R.specOf(m)
    local state = NS.edited()
    local set = state and state.specs[m.name]
    if set and R.spec(m.class, set) then return set, "set" end
    return learned(m)
end

function R.setSpec(name, tree)
    local state = NS.writable()
    if not state then return end
    local old = state.specs[name]
    state.specs[name] = tree
    NS.Duties.keepSpec(name, old, tree)
    if NS.draft then
        NS.signal("draft")
        return
    end
    R.scan()
    NS.signal("specEdit", name, tree)
end

-- Fills in a member's spec, role and tags.
function R.describe(m)
    local tree, from = R.specOf(m)
    m.spec, m.specFrom = tree, from
    if from == "set" then
        m.learned, m.learnedFrom = learned(m)
    else
        m.learned, m.learnedFrom = tree, from
    end
    local s = R.spec(m.class, tree)
    local tags = {}
    if s then
        for _, tag in ipairs(s.tags) do tags[tag] = true end
        m.role = s.role
        m.specKey = s.key
    else
        for tag in pairs(common(m.class)) do tags[tag] = true end
        m.role = commonRole(m.class)
        m.specKey = nil
    end
    -- A Feral druid tanks or deals damage in the same tree, so the role the
    -- raid leader gave says which: the Tank role, or the main tank mark.
    if m.assigned == "TANK" or m.mark == "MAINTANK" then
        tags.tank = true
        m.role = "tank"
    elseif m.assigned == "HEALER" then
        tags.healer = true
        m.role = m.role or "healer"
    end
    m.tags = tags
end

-- =============================================================
-- The roster
-- =============================================================
-- Everyone in the group, us included, as
--   { unit, name, class, group, me, online, dead, visible, assigned, rank,
--     mark, level, zone, spec, specFrom, learned, learnedFrom, specKey, role,
--     tags }
-- `group` is the party number in a raid, and 1 in a party. `rank` is 2 for
-- the leader, 1 for an assistant and 0 for everyone else. `mark` is "MAINTANK"
-- or "MAINASSIST" in a raid, and `assigned` the raid role ("TANK",
-- "HEALER" or "DAMAGER").
local roster, byName, me = {}, {}, nil
R.list = function() return roster end
R.byName = function(name) return byName[name] end
R.me = function() return me end

-- The group we're really in, even in a mock raid, for what we send and take
-- from it (Sync.lua). It answers like R itself.
local group, groupByName, groupMe = {}, {}, nil
R.real = setmetatable({
    list = function() return group end,
    byName = function(name) return groupByName[name] end,
    me = function() return groupMe end,
}, { __index = R })

local function member(unit, group, rank, mark, zone)
    if not UnitExists(unit) then return nil end
    local name = R.unitName(unit)
    local _, class = UnitClass(unit)
    if not name or not readable(class) then return nil end
    local m = { unit = unit, name = name, class = class, group = group or 1, rank = rank or 0,
                me = UnitIsUnit and UnitIsUnit(unit, "player") or unit == "player" }
    local online = not UnitIsConnected or UnitIsConnected(unit)
    m.online = not readable(online) or online and true or false
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    m.dead = readable(dead) and dead and true or false
    local vis = not UnitIsVisible or UnitIsVisible(unit)
    m.visible = not readable(vis) or vis and true or false
    m.assigned = assignedRole(unit)
    local level = UnitLevel and UnitLevel(unit)
    m.level = readable(level) and tonumber(level) or nil
    m.mark = (mark == "MAINTANK" or mark == "MAINASSIST") and mark or nil
    m.zone = readable(zone) and type(zone) == "string" and zone or nil
    NS.asGroup(R.describe, m)
    return m
end

local function partyRank(unit)
    if UnitIsGroupLeader and UnitIsGroupLeader(unit) then return 2 end
    return 0
end

-- A mock raid counts as a raid we lead.
function R.real.grouped()
    return (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or false
end

function R.real.raid()
    return IsInRaid and IsInRaid() or false
end

function R.grouped() return NS.mock ~= nil or R.real.grouped() end
function R.raid()
    if NS.mock then return not NS.Mock.party() end
    return R.real.raid()
end

-- The mock raid: us, and its made-up players. They aren't real units,
-- so we never read their buffs (`visible` false). Everyone in it is level
-- 60, us too, since a mock raid is for planning the raids at the top.
local MOCK_LEVEL = 60

local function mockList()
    local Mo = NS.Mock
    local list = {}
    local own = Mo.self()
    local everyone = Mo.allAssist() and 1 or 0
    local m = member("player", own.group, max(own.rank or 0, everyone))
    if m then
        m.mark, m.assigned = own.mark, own.role
        m.level = MOCK_LEVEL
        NS.asGroup(R.describe, m)
        list[1] = m
    end
    for i, p in ipairs(Mo.members()) do
        local x = { unit = "mock" .. i, name = p.name, class = p.class, group = p.group,
                    rank = max(p.rank or 0, everyone), mark = p.mark, assigned = p.role, level = MOCK_LEVEL,
                    me = false, online = true, dead = false, visible = false }
        NS.asGroup(R.describe, x)
        list[#list + 1] = x
    end
    return list
end

-- What a scan's listeners care about, as one string: each member's unit,
-- name, party, rank, whether they're online or dead, class, spec and where
-- it's from, the raid role they were given and main tank or assist. Every
-- GROUP_ROSTER_UPDATE and UNIT_CONNECTION scans, and the "roster" signal
-- works out the whole board, the HUD, the page and the whisper timer again.
-- So a scan that finds all of it as it was doesn't signal.
local last

local function signature(list)
    local t = {}
    for _, m in ipairs(list) do
        t[#t + 1] = table.concat({ m.unit, m.name, m.group, m.rank or 0, m.online and 1 or 0, m.dead and 1 or 0,
                                   m.class, m.spec or "", m.specFrom or "", m.learned or "", m.assigned or "",
                                   m.mark or "", m.me and 1 or 0, m.level or 0 }, "\t")
    end
    return table.concat(t, "\n")
end

-- Copies what `new` says into the records of `old`, the same players in the
-- same order. Others hold on to the records, like Tracking's players by
-- unit, so an unchanged scan keeps them and only freshens what we don't
-- compare, like the zone.
local function refresh(old, new)
    for i, m in ipairs(new) do
        local o = old[i]
        for k in pairs(o) do
            if m[k] == nil then o[k] = nil end
        end
        for k, v in pairs(m) do o[k] = v end
    end
end

-- A scan we put off until combat ends: nil for none, else whether it was
-- forced.
local held = nil

-- Whether a scan keeps the players we have rather than asking the game.
--
-- In combat the game can hide a player's name, class or level from us. A
-- scan then would drop those players or forget their levels, and the board
-- would lose their assignments until the fight ends. That made icons on the
-- HUD lose their counts in the middle of a fight. So in a group in combat we
-- keep the players we have, and scan for real when combat ends. Deaths still
-- show, since Tracking.lua marks them on these same players.
local function holding()
    return InCombatLockdown and InCombatLockdown() and R.real.grouped() and #group > 1 or false
end

-- Scans the group again, and signals "roster" when something changed.
-- `force` signals either way.
function R.scan(force)
    ownTree = R.ownTree()
    if holding() then
        held = (held or force) and true or false
        -- A spec set by hand or a hello's talents still count now.
        for _, m in ipairs(group) do NS.asGroup(R.describe, m) end
        local sig = "real\n" .. signature(group)
        if not force and sig == last then return roster end
        last = sig
        NS.signal("roster")
        return roster
    end
    held = nil
    local list = {}
    if R.real.raid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            local sub, rank, mark, zone = 1, 0, nil, nil
            if GetRaidRosterInfo then
                local _, r, g, _, _, _, z, _, _, role = GetRaidRosterInfo(i)
                if readable(g) then sub = g end
                if readable(r) then rank = r end
                if readable(role) then mark = role end
                zone = z
            end
            local m = member("raid" .. i, sub, rank, mark, zone)
            if m then list[#list + 1] = m end
        end
    else
        local m = member("player", 1, partyRank("player"))
        if m then list[#list + 1] = m end
        for i = 1, 4 do
            local p = member("party" .. i, 1, partyRank("party" .. i))
            if p then list[#list + 1] = p end
        end
    end
    local shown = NS.mock and mockList() or list
    local sig = (NS.mock and "mock\n" .. signature(list) .. "\n\n" or "real\n") .. signature(shown)
    local same = not force and sig == last
    if same then
        refresh(group, list)
        if shown ~= list then refresh(roster, shown) end
    else
        last = sig
        group, groupByName, groupMe = list, {}, nil
        for _, m in ipairs(list) do
            groupByName[m.name] = m
            if m.me then groupMe = m end
        end
        byName, me = {}, nil
        for _, m in ipairs(shown) do
            byName[m.name] = m
            if m.me then me = m end
        end
        roster = shown
    end
    -- Everyone we group with is remembered, so an assignment can name them
    -- before they join the next raid.
    if NS.db and #group > 1 then
        local now = time()
        for _, m in ipairs(group) do
            local p = NS.db.people[m.name] or {}
            p.class, p.spec, p.seen = m.class, m.spec or p.spec, now
            NS.db.people[m.name] = p
        end
    end
    if not same then NS.signal("roster") end
    return roster
end

-- Scans the group again in `delay` seconds. Many events ask for a scan at
-- once, so they share one wait, and the last one sets when it runs.
--
-- A scan that must signal (`force`) stays forced until it runs. Sync.lua
-- forces one when a hello tells us someone's talents, since talents aren't
-- part of what a scan compares. When a GROUP_ROSTER_UPDATE asked for a plain
-- scan right after, the forced one used to be lost, and the board never
-- learned the talent.
local forceScan = false

function R.scanSoon(delay, force)
    if force then forceScan = true end
    NS.soon("roster", delay, function()
        local f = forceScan
        forceScan = false
        R.scan(f)
    end)
end

-- Whether we may change assignments: the leader or an assistant in a raid,
-- the leader in a party, or anyone while solo.
function R.real.canEdit()
    if not R.real.grouped() then return true end
    if R.real.raid() and _G.IsEveryoneAssistant and IsEveryoneAssistant() then return true end
    return groupMe ~= nil and groupMe.rank > 0
end

function R.canEdit() return NS.mock ~= nil or R.real.canEdit() end

-- How far apart two players may be and still count as near each other.
R.NEAR = 300

-- Where the game says `unit` is: x, y and the instance, or nil when it
-- won't say. In a dungeon or raid it doesn't say for other players.
local function position(unit)
    if not _G.UnitPosition then return nil end
    local y, x, _, inst = UnitPosition(unit)
    if not readable(x) or not readable(y) or not readable(inst) or not x or not y then return nil end
    return x, y, inst
end

-- The map `unit` is on, or nil when the game won't say.
local function mapOf(unit)
    local M = _G.C_Map
    local map = M and M.GetBestMapForUnit and M.GetBestMapForUnit(unit)
    return readable(map) and map or nil
end

-- Whether players `a` and `b` are within NEAR yards of each other.
--
-- In a dungeon or raid the game hides where the others stand, so there the
-- same map is near enough. When the game says nothing at all we count them
-- as near, so a whisper isn't held back for good on a client that hides it.
function R.near(a, b)
    if a == b or a.name == b.name then return true end
    if type(a.unit) ~= "string" or type(b.unit) ~= "string" then return true end
    local ax, ay, ai = position(a.unit)
    local bx, by, bi = position(b.unit)
    if ax and bx then
        return ai == bi and (ax - bx) ^ 2 + (ay - by) ^ 2 <= R.NEAR ^ 2
    end
    local am, bm = mapOf(a.unit), mapOf(b.unit)
    if am and bm then return am == bm end
    return true
end

-- Whether player `m` is next to us: within buff range, about 40 yards.
--
-- R.near isn't enough for this. When the game hides where other players
-- stand, R.near falls back to "on the same map", and then a whisper went to
-- a giver across the zone. The game still
-- says whether a group member is in range. When it won't, we ask whether they
-- are in sight (about 100 yards), and only then fall back to R.near.
function R.close(m)
    if m.me then return true end
    local unit = m.unit
    if type(unit) ~= "string" then return true end
    if _G.UnitInRange then
        local ok, yes, checked = pcall(UnitInRange, unit)
        if ok and readable(yes) and readable(checked) and checked then return yes == true end
    end
    if _G.UnitIsVisible then
        local vis = UnitIsVisible(unit)
        if readable(vis) and vis ~= nil then return vis == true end
    end
    local me = R.me()
    return not me or R.near(me, m)
end

-- What we know of player `name`, here or not: { name, class, spec }. One
-- who isn't here is someone we grouped with before, or a player of the
-- plan in use, made up or real.
function R.known(name)
    local m = R.byName(name)
    if m then return m end
    local p = NS.db and NS.db.people[name]
    if type(p) == "table" and p.class then return p end
    return NS.Plans and NS.Plans.player(name) or nil
end

-- The players we grouped with before, not here now, of one of `classes`
-- (a set), by name: { name, class, spec }.
function R.remembered(classes)
    local t = {}
    for name, p in pairs(NS.db and NS.db.people or {}) do
        if (not classes or classes[p.class]) and not byName[name] then
            t[#t + 1] = { name = name, class = p.class, spec = p.spec }
        end
    end
    table.sort(t, function(a, b) return a.name < b.name end)
    return t
end

-- People not seen for 60 days are forgotten, unless something we keep names
-- them: our own assignments, the copy of whoever else runs the board, the
-- mock raid or a plan.
local FORGET_AFTER = 60 * 24 * 3600

local function prune()
    local named = {}
    local function add(n)
        if type(n) == "string" then named[n] = true end
    end
    local function pick(p)
        local name = type(p) == "string" and p:match("^name:(.+)$")
        if name then named[name] = true end
    end
    local function keys(t, fn)
        for k in pairs(type(t) == "table" and t or {}) do fn(k) end
    end
    local function duty(t)
        for _, d in pairs(type(t) == "table" and t or {}) do
            if type(d) == "table" then
                keys(d.picks, pick)
                keys(d.never, pick)
                -- A blessing order and Buffs by Spec can be a player's own.
                keys(d.order, pick)
                keys(d.want, pick)
                -- A choice, a totem, a blessing by class and a paladin
                -- override are by the giver's name.
                keys(d.choice, add)
                keys(d.matrix, add)
                keys(d.assign, function(n)
                    add(n)
                    keys(type(d.assign[n]) == "table" and d.assign[n] or nil, pick)
                end)
                -- A fight's resistance giver set by hand.
                for _, f in pairs(type(d.fights) == "table" and d.fights or {}) do
                    for _, x in pairs(type(f) == "table" and f or {}) do
                        if type(x) == "table" then add(x.giver) end
                    end
                end
            end
        end
    end
    -- Our own state and the copy of someone else's: { duty, specs }. A mock
    -- raid and a plan also have their players (`members`) and the ones kept
    -- in their party (`pins`). Saves from before called the mock raid
    -- planner or sandbox.
    local function state(t)
        if type(t) ~= "table" then return end
        duty(t.duty)
        keys(t.specs, add)
        keys(t.pins, add)
        for _, p in pairs(type(t.members) == "table" and t.members or {}) do
            if type(p) == "table" then add(p.name) end
        end
    end
    state(NS.db)
    state(NS.db.remote)
    for _, k in ipairs({ "mock", "planner", "sandbox" }) do state(NS.db[k]) end
    for _, plan in pairs(type(NS.db.plans) == "table" and NS.db.plans or {}) do state(plan) end
    local now = time()
    for name, p in pairs(NS.db.people) do
        if type(p) ~= "table" or (not named[name] and now - (p.seen or 0) > FORGET_AFTER) then
            NS.db.people[name] = nil
        end
    end
end

-- =============================================================
-- FojjiCore's spec messages
-- =============================================================
-- "Q" asks for specs, and "S\t<CLASS>\t<key>\t<depth>\t<keys>" answers.
-- FojjiCore answers for its own players.
--
-- We never answer, since the protocol is FojjiCore's, and our own players
-- tell each other their specs in Sync.lua's hello. But without FojjiCore
-- loaded we ask once, a few seconds after we join a group or log in in one.
-- Otherwise we'd only hear of the FojjiCore players already in the group
-- when one of them changes talents or someone else joins. With FojjiCore
-- loaded we don't, because it asks for itself. Its players answer at most
-- once every 3 seconds, so one question per join is enough.
local FJ_PREFIX = "FJSPEC"
local ASK_AFTER = 5

-- Asks the group for their specs. The raid pane asks again when the leader
-- wants to, FojjiCore or not. Returns whether we asked.
function R.askSpecs()
    if not R.real.grouped() then return false end
    local channel = NS.Sync and NS.Sync.channel and NS.Sync.channel()
    if not (channel and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    return pcall(C_ChatInfo.SendAddonMessage, FJ_PREFIX, "Q", channel) and true or false
end

local function askSpecs()
    if _G.FojjiCore then return end
    R.askSpecs()
end

local wasGrouped = false
local function joined()
    local grouped = R.real.grouped()
    if grouped and not wasGrouped then C_Timer.After(ASK_AFTER, askSpecs) end
    wasGrouped = grouped
end

-- A spec counts only from a player in our group, by the roster name the
-- sender is (Sync's S.member, since names come in many ways), and only for
-- their own class. Anyone can whisper us an addon message, so we take only
-- the group's channels.
local GROUP_CHANNELS = { RAID = true, PARTY = true, INSTANCE_CHAT = true }

local function onAddonMessage(_, prefix, msg, channel, sender)
    if secret(prefix) or prefix ~= FJ_PREFIX or secret(msg) or type(msg) ~= "string" then return end
    if secret(channel) or not GROUP_CHANNELS[channel] then return end
    local kind, class, key = msg:match("^(%a)\t(%u+)\t([^\t]*)")
    if kind ~= "S" then return end
    local m = NS.Sync.member(sender)
    if not m or m.class ~= class then return end
    if key and key ~= "" then
        R.fjspec[m.name] = key
    else
        R.fjspec[m.name] = nil
    end
    R.scanSoon(0.5)
end

-- =============================================================
-- Events
-- =============================================================
NS.listen("loaded", function()
    prune()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, FJ_PREFIX)
    end
end)

local function rescan() R.scanSoon(0.3) end
NS.listen("login", R.scan)
NS.listen("login", joined)
NS.on("GROUP_ROSTER_UPDATE", rescan)
NS.on("GROUP_ROSTER_UPDATE", joined)
NS.on("PLAYER_ENTERING_WORLD", rescan)
NS.on("PLAYER_ROLES_ASSIGNED", rescan)
NS.on("UNIT_CONNECTION", rescan)
-- A level up can bring a buff or a better rank of one (Duties.lua).
NS.on("UNIT_LEVEL", rescan)
NS.on("PLAYER_LEVEL_UP", rescan)
NS.on("PLAYER_TALENT_UPDATE", rescan)
NS.on("TRAIT_CONFIG_UPDATED", rescan)
NS.on("CHAT_MSG_ADDON", onAddonMessage)
-- The scans combat put off (R.scan).
NS.on("PLAYER_REGEN_ENABLED", function()
    if held ~= nil then R.scan(held) end
end)
NS.on("GROUP_LEFT", function()
    for k in pairs(R.fjspec) do R.fjspec[k] = nil end
    for k in pairs(R.told) do R.told[k] = nil end
end)
