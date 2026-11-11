-- Who has the buffs of our assignments, and the debuffs on the target.
--
-- READING. We go through every aura on a player once and match each to our
-- buffs by spell ID or name, which covers every rank, the group version and
-- the client's own copies of a spell. In combat, and in some instances out of
-- combat, the game hides auras from addons. A buff we can't read is unknown,
-- never missing, and we keep what we read last. We count down from it, so a
-- buff that runs out in combat still shows as missing. When we cast one of our
-- buffs we count it as up at once, before the game tells us. That works in
-- combat too, on whoever the game says the cast went to, which is how a
-- mouseover cast in combat counts.
--
-- WHAT COMBAT STILL TELLS US. UNIT_AURA still comes in combat, and says by
-- instance ID which auras left a unit. We keep the instance of each buff we
-- read before the pull, so one that leaves (dispelled, purged or clicked off)
-- is missing from then. An aura that came in the same change and that we
-- can't read may be the same buff from someone else, like another priest's
-- Fortitude over ours, so then we keep what we had. A new or changed aura
-- the game lets us read counts at once. Our own totems the game tells us
-- about in combat too (PLAYER_TOTEM_UPDATE, GetTotemInfo), so a totem that
-- was killed or that we replaced shows as missing (Tr.totemRead).
--
-- THE TARGET. We keep what we knew of each target by its GUID for a while
-- after we switch away. In combat we can't read it again, so tabbing to an
-- add and back to the boss keeps the boss's debuffs.
--
-- DOWNRANK. A buff of a lower rank than its assigned giver should have at
-- their level still counts as up, but the icons and tooltips say DOWNRANK.
-- Their level is all we can go by for other players, since we can't see which
-- ranks they trained (Tr.lowRank).
--
-- CAMP BUFFS. Sitting at a campfire gives a buff for each feature that stood
-- there, and each one is a weaker copy of a class buff, like the Fish Bowl's
-- stats and Kings. The class buff replaces it, so we ask for the class buff
-- whenever that gives up nothing. A priest, a druid or a mage can give all of
-- their buffs, so their duties ignore camp buffs.
--
-- Paladins are the exception, since each gives a player only one blessing. A
-- hunter wants three, so two paladins can't give them all and a camp buff is
-- worth keeping. So the paladins give a player the blessings their camp buffs
-- don't stand in for first, and a camp one only with a paladin to spare
-- (Duties.lua). With two paladins a hunter with the Fish Bowl gets Might and
-- Wisdom and keeps the Fish Bowl, and a warrior gets Kings over it.
--
-- The game hides those buffs from the aura list, and only the text of the Camp
-- Benefits aura says which ones we have. That text decides its lines by the
-- buffs of whoever reads it, as far as we can tell, so it says nothing of other
-- players. So each of us reads their own (Tr.readCamp) and tells the group
-- (Sync.lua). A player who doesn't run the addon gets every blessing as if
-- they had no camp buffs.
--
-- What we read goes to disk on a /reload, and comes back when the reload
-- was a few minutes ago at most.
--
-- ANY BLESSING OR TOTEM IN A PARTY. In a raid the paladins split the
-- blessings so that each player gets the ones they want most, and a player
-- with Might where the plan says Kings is missing Kings. The shamans split
-- the totems the same way. In a party of five there's nothing to split, so
-- the paladin may give each player whichever blessing they like, and the
-- shaman may put down whichever totem of the element they like. There a
-- player counts as covered when they have the planned buff, or another
-- blessing (or a totem buff of the same element) that no other giver
-- claimed (Tr.standIn). A raid group of five or fewer is a party too. So we read every blessing and totem buff in a
-- party. Our own totems we also ask the game for, since Tremor or Searing
-- puts no buff on anyone.
--
-- DYING takes every buff. When a player dies we count each buff we track on
-- them as missing from that moment, even in combat where we can't read them.
-- So after a rez they show as missing, not unknown, and a buff we read
-- before the fight doesn't look up on them.
--
-- WHOSE BUFFS. We read the buffs of our own assignments. While the window is
-- open, for the coverage strip of a leader or an assistant (Coverage.lua),
-- while Group buffs shows (GroupBuffs.lua), and when we run the board and
-- whisper (on ready checks or when buffs run out), we read every
-- assignment's too.
--
-- WHEN. A player's buffs changing (UNIT_AURA) reads that player alone, a
-- moment later. Nothing tells us when someone comes into sight or range, so
-- every few seconds out of combat we read everyone. With every assignment's
-- buffs that's up to 40 players times every buff, so it waits 2 seconds
-- after the first ask.
--
-- COST. While auras are hidden (in combat) we don't read at all, since every
-- read would come back unknown. We only go through what each UNIT_AURA says
-- changed. We tell the rest of the addon ("tracking") only when a read
-- changed something, and a paint works out each assignment's status once
-- (Tr.memoize).
--
-- THE PULL CHECK. On a ready check, a long buff that runs out within a
-- fight (the "Fight length" setting) counts as due, for a couple of minutes
-- or until the pull. The HUD says what to refresh (HUD.lua).

local _, NS = ...
local D, R = NS.Data, NS.Roster
local secret, readable = NS.secret, NS.readable

local floor, max = math.floor, math.max
local format = string.format

local Tr = {}
NS.Tracking = Tr

-- =============================================================
-- Names, icons and spell IDs
-- =============================================================
local function spellName(id)
    local get = (C_Spell and C_Spell.GetSpellName) or nil
    local ok, name
    if get then
        ok, name = pcall(get, id)
    elseif _G.GetSpellInfo then
        ok, name = pcall(_G.GetSpellInfo, id)
    end
    if ok and type(name) == "string" and not secret(name) and name ~= "" then return name end
    return nil
end
Tr.spellName = spellName

-- The names a buff goes by on a unit: the game's name of its first spell
-- (or ours), and the names of its other spells in `names`. Kept once the
-- game knew them all.
local namesOf = {}
function Tr.names(b)
    local known = namesOf[b.id]
    if known then return known end
    local list, seen, whole = {}, {}, true
    local function add(n)
        if n and not seen[n] then
            seen[n] = true
            list[#list + 1] = n
        end
    end
    local first = spellName(b.spells[1])
    if not first then whole = false end
    add(first or b.name)
    for _, id in ipairs(b.names or {}) do
        local n = spellName(id)
        if n then add(n) else whole = false end
    end
    if whole then namesOf[b.id] = list end
    return list
end

function Tr.title(b)
    return Tr.names(b)[1] or b.name
end

local iconOf = {}
function Tr.icon(b)
    local known = iconOf[b.id]
    if known then return known end
    local tex
    local get = C_Spell and C_Spell.GetSpellTexture
    if get then
        local ok, t = pcall(get, b.spells[1])
        if ok and t and not secret(t) then tex = t end
    end
    iconOf[b.id] = tex or b.icon
    return iconOf[b.id]
end

-- The spell IDs the game's aura display looks for: the data's, and any we
-- read on a player that the data didn't have.
local learned = {}
function Tr.spellIds(b)
    local set = {}
    for _, id in ipairs(b.spells) do set[id] = true end
    for id in pairs(learned[b.id] or {}) do set[id] = true end
    return set
end

-- The buff of one of our spell IDs, for a cast we just made. A totem's cast
-- isn't the buff it puts on players (Strength of Earth Totem puts up
-- Strength of Earth), and neither is Moonkin Form, so we know each buff by
-- its spells, its other names and its cast. A rank the data doesn't list
-- goes by its name, which is any of the buff's names.
local bySpell
local function buffOfSpell(id)
    if not bySpell then
        bySpell = {}
        local function add(s, b)
            if type(s) == "number" and not bySpell[s] then bySpell[s] = b end
        end
        for _, list in ipairs({ D.BUFFS, D.DEBUFFS }) do
            for _, b in ipairs(list) do
                for _, s in ipairs(b.spells) do add(s, b) end
                for _, s in ipairs(b.names or {}) do add(s, b) end
                add(b.cast, b)
            end
        end
    end
    local b = bySpell[id]
    if b then return b end
    local name = spellName(id)
    if not name then return nil end
    for _, list in ipairs({ D.BUFFS, D.DEBUFFS }) do
        for _, x in ipairs(list) do
            for _, n in ipairs(Tr.names(x)) do
                if n == name then return x end
            end
        end
    end
end

-- =============================================================
-- Whether the game hides auras
-- =============================================================
function Tr.hidden()
    if InCombatLockdown and InCombatLockdown() then return true end
    local S = _G.C_Secrets
    if S and S.ShouldAurasBeSecret then
        local ok, yes = pcall(S.ShouldAurasBeSecret)
        if ok and yes == true then return true end
    end
    return false
end

-- =============================================================
-- Reading
-- =============================================================
-- What we read last on each player, by name: `seen[name][buff id]` is
--   { up, expires, duration, stacks, at }
local seen = {}
Tr.seen = seen
-- The target's debuffs, read the same way, kept while it's the same target.
local onTarget = {}
-- The target's GUID, when the game tells us.
local targetGuid
-- What we knew of the targets we had before, by GUID: { reads, at }. In
-- combat we can't read the target, so tabbing to an add and back to the boss
-- used to forget the Sunder Armor we put on it. Kept for KEEP_TARGET_FOR
-- seconds after we switched away.
local earlier = {}
local KEEP_TARGET_FOR = 600
-- How long each buff lasts, from the last time we read it, for a buff we
-- just cast.
local lasts = {}

-- The most auras we go through on one unit. The list ends sooner, this is
-- only in case it never does.
local MAX_AURAS = 255

-- Every aura on `unit` we can read, and whether some we couldn't. A buff that
-- isn't in the list is then unknown, not missing.
local function aurasOn(unit, filter)
    local list, unsure = {}, false
    local ua = _G.C_UnitAuras
    if ua and ua.GetAuraDataByIndex then
        for i = 1, MAX_AURAS do
            local ok, a = pcall(ua.GetAuraDataByIndex, unit, i, filter)
            if not ok or secret(a) then return list, true end
            if not a then return list, unsure end
            if secret(a.name) or secret(a.spellId) or secret(a.expirationTime) or secret(a.duration) then
                unsure = true
            else
                list[#list + 1] = a
            end
        end
        return list, unsure
    end
    local get = filter == "HARMFUL" and _G.UnitDebuff or _G.UnitBuff
    if not get then return list, true end
    for i = 1, 40 do
        local ok, n, icon, count, _, duration, expires, src, _, _, spellId = pcall(get, unit, i)
        if not ok then return list, true end
        if not n then return list, unsure end
        if secret(n) then return list, true end
        list[#list + 1] = { name = n, icon = icon, applications = count, duration = duration,
                            expirationTime = expires, sourceUnit = src, spellId = spellId }
    end
    return list, unsure
end

-- The "Rank 3" the game gives spell `id` as a number, kept once it said.
local rankWords = {}
local function rankWord(id)
    local known = rankWords[id]
    if known ~= nil then return known end
    local get = (C_Spell and C_Spell.GetSpellSubtext) or _G.GetSpellSubtext
    if not get then return nil end
    local ok, text = pcall(get, id)
    if not ok or type(text) ~= "string" or secret(text) or text == "" then return nil end
    rankWords[id] = tonumber(text:match("(%d+)$")) or false
    return rankWords[id]
end

-- Which rank of `b` aura spell `id` is, and the level it's learned at. A totem
-- buff isn't the spell in b.ranks, which is the totem's cast, so past our
-- data we go by the rank the game names. nil for a copy with no rank, like
-- an NPC's, which we can't compare.
local function rankOf(b, id)
    if not b.ranks or not readable(id) then return nil end
    local rank, level = NS.Duties.rankOfSpell(b, id)
    if rank then return rank, level end
    local word = rankWord(id)
    level = word and b.ranks[2 * word]
    if level then return word, level end
    return nil
end

-- Each buff's spell IDs and names as sets, to match an aura to it. Kept with
-- the names (Tr.names), once the game knew them all.
local matchOf = {}
local function matcher(b)
    local known = matchOf[b.id]
    if known then return known end
    local m = { ids = {}, names = {} }
    for _, id in ipairs(b.spells) do m.ids[id] = true end
    for _, n in ipairs(Tr.names(b)) do m.names[n] = true end
    if namesOf[b.id] then matchOf[b.id] = m end
    return m
end

local function learnId(b, id)
    if not readable(id) then return end
    for _, known in ipairs(b.spells) do
        if known == id then return end
    end
    learned[b.id] = learned[b.id] or {}
    learned[b.id][id] = true
end

-- The Camp Benefits spell.
-- source: wago Spell 1229741 1.60.1.70685
local CAMP_BENEFITS = 1229741

-- The text of aura `a` on `unit`, or nil when the game won't say.
local function auraText(unit, a)
    local TI = _G.C_TooltipInfo
    local instance = a.auraInstanceID
    if not (TI and TI.GetUnitBuffByAuraInstanceID and readable(instance) and instance) then return nil end
    local ok, data = pcall(TI.GetUnitBuffByAuraInstanceID, unit, instance)
    if not ok or secret(data) or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local text = {}
    for _, line in ipairs(data.lines) do
        local left = line.leftText
        if type(left) == "string" and not secret(left) then text[#text + 1] = left end
    end
    return #text > 0 and table.concat(text, "\n") or nil
end

-- The blessings each player's camp buffs stand in for, by name:
-- { ids = { [blessing id] = true }, expires }. Ours we read (Tr.readCamp),
-- the others' they tell us (Sync.lua). `expires` is 0 when it doesn't run out.
local camps = {}
Tr.camps = camps
-- A number for each player's latest camp buffs, so the timer of older ones
-- that ran out doesn't clear newer ones.
local campGen = {}

-- The blessings player `name`'s camp buffs stand in for right now, as
-- { [blessing id] = true }, or nil.
function Tr.campOf(name)
    local c = camps[name]
    if not c or (c.expires > 0 and c.expires <= GetTime()) then return nil end
    return c.ids
end

-- Player `name`'s camp buffs stand in for blessings `ids` until `expires`.
-- When that changed what we knew, the board is worked out again ("camp"),
-- and once more when they run out.
function Tr.setCamp(name, ids, expires)
    local now = GetTime()
    local old = Tr.campOf(name) or {}
    local was = camps[name]
    local same = true
    for id in pairs(old) do same = same and ids[id] == true end
    for id in pairs(ids) do same = same and old[id] == true end
    -- Sitting at the fire again makes them last longer, which the others
    -- should hear. A few seconds either way is only how late a message came.
    if same and (next(ids) == nil or math.abs((was and was.expires or 0) - expires) < 5) then return end
    camps[name] = next(ids) and { ids = ids, expires = expires } or nil
    campGen[name] = (campGen[name] or 0) + 1
    if next(ids) and expires > now then
        local gen = campGen[name]
        C_Timer.After(expires - now + 0.5, function()
            if campGen[name] ~= gen or Tr.campOf(name) then return end
            camps[name] = nil
            NS.signal("camp", name)
        end)
    end
    NS.signal("camp", name)
end

-- Reads which blessings our own camp buffs stand in for, from the text of
-- Camp Benefits among `auras`, what aurasOn said of our `unit`. When the game
-- won't give the text we keep what we read last.
local function campFrom(me, unit, auras, unsure)
    for _, a in ipairs(auras) do
        if a.spellId == CAMP_BENEFITS then
            local text = auraText(unit, a)
            if not text then return end
            local ids = {}
            for _, b in ipairs(D.BUFFS) do
                if b.camp and text:find(b.camp .. ":", 1, true) then ids[b.id] = true end
            end
            Tr.setCamp(me.name, ids, a.expirationTime or 0)
            return
        end
    end
    if not unsure then Tr.setCamp(me.name, {}, 0) end
end

-- Reads our own camp buffs alone, for when we have no duty whose buffs
-- would read them too (Tr.readMember).
function Tr.readCamp()
    local me = R.me()
    if not me or Tr.hidden() then return end
    local auras, unsure = aurasOn("player", "HELPFUL")
    campFrom(me, "player", auras, unsure)
end

-- Leaving the group, the others' camp buffs are nothing to us.
NS.listen("groupLeft", function()
    local me = R.me()
    for name in pairs(camps) do
        if not (me and name == me.name) then camps[name], campGen[name] = nil, nil end
    end
end)

-- Reads buff or debuff `b` from `auras`, what aurasOn said of the unit:
-- { up, expires, duration, stacks, rank, level } or nil when we can't tell.
-- `rank` is which of b.ranks it is and `level` the level that's learned at,
-- when we can tell. With two of them up, the better rank is the one that
-- counts.
--
-- `old` is what we read last. When this read says exactly the same, we hand
-- `old` back with only its time of reading moved on. We read every player's
-- buffs every few seconds and on every UNIT_AURA, and nearly always nothing
-- changed, so a new table each time was most of our garbage.
local function readOne(b, auras, unsure, old)
    local want = matcher(b)
    local a, rank, level
    for _, x in ipairs(auras) do
        if want.ids[x.spellId] or want.names[x.name] then
            local r, lv = rankOf(b, x.spellId)
            if not a or (lv or -1) > (level or -1) then a, rank, level = x, r, lv end
        end
    end
    if a then
        learnId(b, a.spellId)
        -- Who cast it and how many stacks can be secret when the rest
        -- isn't, and comparing a secret value is an error.
        local src = a.sourceUnit
        local stacks = readable(a.applications) and a.applications or 0
        local duration = a.duration or 0
        if duration > 0 then lasts[b.id] = duration end
        local expires = a.expirationTime or 0
        local ours = type(src) == "string" and readable(src) and src == "player" or nil
        local instance = a.auraInstanceID
        instance = readable(instance) and instance or nil
        if old and old.up and old.expires == expires and old.duration == duration and old.stacks == stacks
           and old.ours == ours and old.rank == rank and old.level == level and old.instance == instance
           and old.since == nil then
            old.at = GetTime()
            return old
        end
        return { up = true, expires = expires, duration = duration, stacks = stacks, at = GetTime(),
                 ours = ours, rank = rank, level = level, instance = instance }
    end
    if unsure then return nil end
    -- A missing buff keeps `since` (when it went missing), which is what
    -- readMember would give the new read too.
    --
    -- A record restored after a /reload has no `since` yet. We don't reuse it,
    -- so readMember treats the read as new and stamps `since`. Otherwise a
    -- backup with a delay would never see the buff as missing.
    if old and not old.up and old.since and old.expires == 0 and old.duration == 0 and old.stacks == 0
       and old.ours == nil and old.rank == nil and old.level == nil and old.instance == nil then
        old.at = GetTime()
        return old
    end
    return { up = false, expires = 0, duration = 0, stacks = 0, at = GetTime() }
end

-- Whether we read every assignment's buffs, not only our own: while the
-- window, the coverage strip or Group buffs shows them, or when we run the board and
-- whisper givers what's missing on a ready check.
function Tr.readsAll()
    if NS.Config and NS.Config.shown() then return true end
    if NS.Coverage and NS.Coverage.reading() then return true end
    if NS.GroupBuffs and NS.GroupBuffs.reading() then return true end
    local S = NS.Sync
    return R.grouped() and not NS.mock and S ~= nil and S.isHost()
           and (NS.Options.get("whisperReady") or NS.Options.get("whisperExpiry")) or false
end

-- The buffs we read on players: those of our duties, which is all the HUD
-- needs, or with `all` every duty's.
--
-- We ask for them on every read and on every UNIT_AURA in combat. They only
-- change with the board, and with whether we're a party (Tr.party). Du.update
-- makes a new board and a new list of ours each time, so we keep each set
-- until either table is a different one. Nobody changes a set we hand out.
local buffSets = {}
local function ourBuffs(all)
    local mine, board, party = NS.Duties.mine(), NS.Duties.board(), Tr.party()
    if buffSets.mine ~= mine or buffSets.board ~= board then
        for k in pairs(buffSets) do buffSets[k] = nil end
        buffSets.mine, buffSets.board = mine, board
    end
    local key = (all and "all" or "ours") .. (party and "Party" or "")
    if buffSets[key] then return buffSets[key] end
    local set = {}
    buffSets[key] = set
    local list = NS.Duties.mine()
    if all then
        list = {}
        for _, plan in pairs(NS.Duties.board() or {}) do
            for _, a in ipairs(plan.active and plan.list or {}) do list[#list + 1] = a end
        end
        -- Our backups too, which the board's lists leave out.
        for _, a in ipairs(NS.Duties.mine()) do list[#list + 1] = a end
    end
    for _, a in ipairs(list) do
        if a.bless then
            for _, id in pairs(a.bless) do set[id] = D.BY_ID[id] end
            -- In a party any blessing will do, so we read them all.
            if Tr.party() then
                for _, id in ipairs(D.JOB.blessings.options) do set[id] = D.BY_ID[id] end
            end
        elseif a.spare then
            for _, x in ipairs(a.spare) do set[x.b.id] = x.b end
        elseif a.buff and not a.buff.debuff then
            set[a.buff.id] = a.buff
            -- In a party any totem of the element will do.
            if a.buff.element and Tr.party() then
                for _, b in ipairs(D.BUFFS) do
                    if b.element == a.buff.element then set[b.id] = b end
                end
            end
        end
    end
    return set
end

-- When each player died, while they're dead.
local diedAt = {}
Tr.diedAt = diedAt

-- Whether `unit` is a hunter playing dead. Feign Death keeps every buff,
-- so it isn't a death.
local function feigning(unit)
    local fd = _G.UnitIsFeignDeath and UnitIsFeignDeath(unit)
    return readable(fd) and fd and true or false
end

-- Whether a read changed anything since the last time we told the rest of
-- the addon.
local dirty = false

-- What the game says of `m` right now. The roster only looks when the
-- group changes, so who is dead or in sight would go stale.
local function refresh(m)
    if type(m.unit) ~= "string" then return end
    local vis = UnitIsVisible and UnitIsVisible(m.unit)
    if readable(vis) then m.visible = vis and true or false end
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(m.unit)
    if readable(dead) then
        dead = dead and not feigning(m.unit) and true or false
        if m.dead ~= dead then dirty = true end
        m.dead = dead
    end
end

-- Whether two reads of a buff say the same.
local function same(x, y)
    return x ~= nil and y ~= nil and x.up == y.up and x.expires == y.expires and x.stacks == y.stacks
           and x.ours == y.ours and x.level == y.level
end

-- Player `m` died at `at`: every buff we track on them is missing from then.
function Tr.died(m, at)
    at = at or GetTime()
    diedAt[m.name] = diedAt[m.name] or at
    local t = seen[m.name] or {}
    for id in pairs(ourBuffs(true)) do
        local r = t[id]
        if not (r and not r.up) then
            t[id] = { up = false, expires = 0, duration = 0, stacks = 0, at = at, since = at }
        end
    end
    for id, r in pairs(t) do
        if r.up then t[id] = { up = false, expires = 0, duration = 0, stacks = 0, at = at, since = at } end
    end
    seen[m.name] = t
    dirty = true
end

function Tr.readMember(m, buffs)
    refresh(m)
    if m.dead then
        if not diedAt[m.name] then Tr.died(m) end
        return
    end
    diedAt[m.name] = nil
    if not m.online or not m.visible then return end
    local t = seen[m.name] or {}
    local auras, unsure = aurasOn(m.unit, "HELPFUL")
    if m.me then campFrom(m, m.unit, auras, unsure) end
    for id, b in pairs(buffs or ourBuffs()) do
        local old = t[id]
        local r = readOne(b, auras, unsure, old)
        if r and r ~= old then
            -- When it went missing, kept while it stays missing.
            if not r.up then
                r.since = old and not old.up and old.since
                          or old and old.up and old.expires > 0 and old.expires <= r.at and old.expires
                          or r.at
            end
            if not same(old, r) then dirty = true end
            t[id] = r
        end
    end
    seen[m.name] = t
end

function Tr.readAll(all)
    local buffs = ourBuffs(all)
    if next(buffs) == nil then
        Tr.readCamp()
        return
    end
    for _, m in ipairs(R.list()) do Tr.readMember(m, buffs) end
end

-- The debuffs we read on the target: every one the active assignments put
-- there, ours and the others', for Target debuffs (TargetDebuffs.lua). They
-- are a handful, so we always read them all.
local function targetDebuffs()
    local set = {}
    for _, a in ipairs(NS.Duties.mine()) do
        if a.buff and a.buff.debuff then set[a.buff.id] = a.buff end
    end
    for _, job in ipairs(D.JOBS) do
        local plan = job.scope == "target" and NS.Duties.plan(job.id)
        if plan and plan.active then
            for _, a in ipairs(plan.list) do
                if a.buff and a.buff.debuff then set[a.buff.id] = a.buff end
            end
        end
    end
    return set
end

-- The GUID of `unit`, or nil when the game won't say.
local function guidOf(unit)
    local get = _G.UnitGUID
    if not get then return nil end
    local ok, g = pcall(get, unit)
    if ok and type(g) == "string" and readable(g) and g ~= "" then return g end
    return nil
end

-- The target changed. We put away what we knew of the last one and take out
-- what we knew of the new one.
local function switchTarget()
    local now = GetTime()
    if targetGuid and next(onTarget) then earlier[targetGuid] = { reads = onTarget, at = now } end
    for g, e in pairs(earlier) do
        if now - e.at > KEEP_TARGET_FOR then earlier[g] = nil end
    end
    local g = UnitExists("target") and guidOf("target") or nil
    local e = g and earlier[g]
    if e then earlier[g] = nil end
    onTarget = e and e.reads or {}
    targetGuid = g
end

function Tr.readTarget()
    if not UnitExists("target") then return end
    local list = targetDebuffs()
    if next(list) == nil then return end
    local auras, unsure = aurasOn("target", "HARMFUL")
    for _, b in pairs(list) do
        local r = readOne(b, auras, unsure, onTarget[b.id])
        if r then
            if not same(onTarget[b.id], r) then dirty = true end
            onTarget[b.id] = r
        end
    end
end

-- What we know of buff `id` on player `name` right now: the read, with a
-- buff that ran out since counting as missing. nil when we don't know.
-- The "ran out" answer Tr.state gives for each read, made once. The HUD asks
-- for every player's buffs twice a second, and a buff that ran out stays
-- that way until we read the player again.
local ranOut = setmetatable({}, { __mode = "k" })

function Tr.state(name, id)
    local t = seen[name]
    local r = t and t[id]
    if not r then return nil end
    if r.up and r.expires > 0 and r.expires <= GetTime() then
        local gone = ranOut[r]
        if not gone or gone.since ~= r.expires then
            gone = { up = false, expires = 0, duration = 0, stacks = 0, since = r.expires }
            ranOut[r] = gone
        end
        return gone
    end
    return r
end

-- Whether player `name` has a blessing of ours, so a backup paladin doesn't
-- put a second one on them.
function Tr.blessedByUs(name)
    for id, r in pairs(seen[name] or {}) do
        local b = D.BY_ID[id]
        if b and b.family == "blessing" and r.ours then
            local s = Tr.state(name, id)
            if s and s.up then return true end
        end
    end
    return false
end

function Tr.targetState(id)
    local r = onTarget[id]
    if not r then return nil end
    if r.up and r.expires > 0 and r.expires <= GetTime() then
        return { up = false, expires = 0, duration = 0, stacks = 0 }
    end
    return r
end

-- How long a buff we just cast counts as up: as long as it lasted the last
-- time we read it, or what the data says when we never read it. A totem
-- counts for as long as it stands. The buff it puts on players can be much
-- shorter and come back with each pulse, like Windfury's 10 seconds, so the
-- last read would have it run out a few seconds into the fight. 0 is an aura,
-- which stays up.
local function lifetime(b)
    if b.element then return b.duration or 0 end
    return lasts[b.id] or b.duration or 0
end

-- We just put buff `b` on `name` (or on the target, with no name). It counts
-- as up for its lifetime from now.
function Tr.cast(name, b)
    local now = GetTime()
    local d = lifetime(b)
    local r = { up = true, expires = d > 0 and now + d or 0, duration = d,
                stacks = 1, at = now, ours = true }
    if b.debuff then
        local old = onTarget[b.id]
        if old and old.up and b.stacks then r.stacks = math.min(b.stacks, (old.stacks or 0) + 1) end
        onTarget[b.id] = r
    elseif name then
        seen[name] = seen[name] or {}
        seen[name][b.id] = r
    end
    NS.signal("tracking")
end

-- =============================================================
-- Status of a duty
-- =============================================================
-- The pull check lasts this long after a ready check, or until the pull.
local PULL_FOR = 120
-- When the pull check ends, while one is on.
Tr.pullUntil = nil

function Tr.pulling()
    if Tr.pullUntil and GetTime() >= Tr.pullUntil then Tr.pullUntil = nil end
    return Tr.pullUntil ~= nil
end

-- How long before a long buff runs out we count it as needing a rebuff.
-- During the pull check, a whole fight.
function Tr.rebuffAt(b)
    if b.kind ~= "long" then return 0 end
    local at = (NS.Options.get("rebuffMinutes") or 0) * 60
    if Tr.pulling() then at = max(at, (NS.Options.get("fightMinutes") or 0) * 60) end
    return at
end

local function isBoss(cls)
    if cls == "worldboss" then return true end
    local lvl = UnitLevel("target")
    return readable(lvl) and lvl == -1
end

-- Whether the target is one we put debuffs on: an enemy that's a boss or an
-- elite. In a raid instance only a boss, unless the "Debuffs on bosses
-- only" setting is off, so Sunder Armor doesn't light up on every trash pull.
function Tr.targetWanted()
    if not UnitExists("target") then return false end
    local ok, can = pcall(UnitCanAttack, "player", "target")
    if not ok or not readable(can) or not can then return false end
    -- The game still lets us attack a dead mob, but there's nothing left to
    -- debuff on it.
    local okDead, dead = pcall(UnitIsDeadOrGhost, "target")
    if okDead and readable(dead) and dead then return false end
    local cls = UnitClassification and UnitClassification("target")
    if not readable(cls) then return true end
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    if inside and kind == "raid" and NS.Options.get("debuffBossesOnly") then return isBoss(cls) end
    if cls == "elite" or cls == "rareelite" then return true end
    return isBoss(cls)
end

-- Assignment `a` right now:
--   have, want      how many of its players have the buff
--   missing         { m, b, soon, since } for each player missing it, or
--                   with it about to run out (soon), in the order we buff
--                   them. `since` is when it went missing. For a backup,
--                   only the ones missing it for longer than the "Backups
--                   step in after" setting.
--   dead            { m, b } for each dead player it's for, who doesn't
--                   count in `want`
--   unknown         how many we never read
--   oldest          when the first of `missing` went missing, or nil
--   expires         when the first buff runs out
--   by              { [buff id] = { have, want } } for blessings
--   low             { m, b, rank, want } for each player with a lower rank
--                   than the giver should have (Tr.lowRank). They count in
--                   `have`. When a cast of ours would make it better they're
--                   in `missing` too, with `soon` and `low`.
-- A debuff has `up`, `expires`, `duration`, `stacks` and `unknown` instead,
-- and `wanted` says whether the target is one for it.
-- While a paint runs, the status of each assignment it already asked for.
local memo

-- Turns on remembering each assignment's status (`on`), or forgets them.
-- Nothing a status reads changes in the middle of one paint.
function Tr.memoize(on)
    memo = on and {} or nil
end

-- Whether we know spell `id`, to tell which ranks we trained.
local function knows(id)
    local known = _G.IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown) or _G.IsSpellKnown
    if not known then return false end
    local ok, yes = pcall(known, id)
    return ok and yes == true
end
Tr.knows = knows

-- The best rank of `b` we can put on player `m`: the highest we trained
-- that they can take (Du.rankFor), as (rank, its spell). nil for a buff
-- without ranks.
function Tr.ourRank(b, m)
    local me = R.me()
    local i, spell = NS.Duties.rankFor(b, me and me.level, m and m.level, knows)
    return i, spell
end

-- Whether read `s` of `b` on player `m` is a lower rank than ours, so a
-- cast of ours would make it better. A long buff only: a totem's or an
-- aura's buff isn't the spell we cast.
function Tr.betterRank(b, m, s)
    if b.kind ~= "long" or not s.rank then return false end
    local i = Tr.ourRank(b, m)
    return i ~= nil and i > s.rank
end

-- The word on an icon whose buff is of too low a rank.
Tr.DOWNRANK = "DOWNRANK"

-- The rank assignment `a`'s giver should have put on player `m` at their
-- level, when read `s` of `b` is below it. Otherwise nil, and also when we
-- can't compare: a copy of the spell with no rank, or a giver whose level we
-- don't know. A backup's level says nothing, since someone else is on it.
function Tr.lowRank(a, b, m, s)
    if a.backup or not s.level then return nil end
    local level = a.giver and a.giver.level
    if not level then return nil end
    -- Totems, auras and shouts reach everyone in range, whatever their level.
    local i, _, at = NS.Duties.rankFor(b, level, b.kind == "long" and m.level or nil)
    if i and i > 0 and at > s.level then return i end
    return nil
end

-- Who in `low` (status `low` lists put together) has a buff of too low a
-- rank, as "Tor rank 2/4" for each, or nil when nobody does. With several
-- buffs in it, each says which.
local function lowParts(low, limit)
    if not low or #low == 0 then return nil end
    limit = limit or 12
    local several, parts = false, {}
    for _, t in ipairs(low) do several = several or t.b ~= low[1].b end
    for i, t in ipairs(low) do
        if i > limit then
            parts[#parts + 1] = format("and %d more", #low - limit)
            break
        end
        local what = several and NS.Buffer.short(Tr.title(t.b)) .. " " or ""
        parts[i] = format("%s %srank %d/%d", NS.who(t.m), what, t.rank or 0, t.want)
    end
    return parts
end

-- A tooltip line of them, like "DOWNRANK: Tor rank 2/4, Lia rank 1/4".
function Tr.lowLine(low, limit)
    local parts = lowParts(low, limit)
    return parts and format("%s: %s", Tr.DOWNRANK, table.concat(parts, ", ")) or nil
end

-- The same as tooltip lines, "DOWNRANK:" and then a line for each player.
function Tr.lowLines(low, limit)
    local parts = lowParts(low, limit)
    if not parts then return nil end
    table.insert(parts, 1, Tr.DOWNRANK .. ":")
    return parts
end

-- Whether assignments `x` and `a` have the same giver. The board and our
-- own list may hold copies of a member, so we go by name.
local function sameGiver(x, a)
    return x.giver ~= nil and a.giver ~= nil and x.giver.name == a.giver.name
end

-- The game's totem slot of each element.
local TOTEM_SLOT = { fire = 1, earth = 2, water = 3, air = 4 }

-- Our own totem of `element` while it stands, as a read that's up, or nil.
local function ourTotem(element)
    local slot = TOTEM_SLOT[element]
    if not slot or not _G.GetTotemInfo then return nil end
    local have, _, start, duration = GetTotemInfo(slot)
    if not (readable(have) and readable(start) and readable(duration)) or not have then return nil end
    if not start or start <= 0 or not duration or duration <= 0 then return nil end
    local expires = start + duration
    if expires <= GetTime() then return nil end
    return { up = true, expires = expires, duration = duration, stacks = 1, ours = true }
end

-- Which of our totems stands in each slot, as { b, expires }, false for
-- none, or nil while the game never said. `b` is nil for a totem we can't
-- name.
local standing = {}
-- When each of our totems went away (replaced, killed or ran out), by buff id.
local totemGone = {}
-- The totem we cast last of each element: { b, at }.
local castTotem = {}
-- When we last read each totem slot, standing or empty.
local slotSeen = {}
-- Goes up whenever one of our totems may have changed, so a countdown the
-- game draws for a totem knows to ask for its time again (Tr.totemVersion).
local totemVersion = 0

-- A totem's buff on players can outlast the totem by this long at most.
-- Windfury's pulse gives 10 seconds, which is how twisting it with Grace of
-- Air works.
local TOTEM_TAIL = 10

-- Which of our buffs is the totem of `element` that went down at `start`,
-- as GetTotemInfo names it. The name carries a rank ("Windfury Totem III"),
-- so we match the start of it. When the game won't say, it's the one we
-- just cast.
local function totemBuff(element, name, start, spellId)
    if readable(spellId) and type(spellId) == "number" then
        local b = buffOfSpell(spellId)
        if b and b.element == element then return b end
    end
    if readable(name) and type(name) == "string" and name ~= "" then
        for _, b in ipairs(D.BUFFS) do
            if b.element == element then
                for _, n in ipairs({ b.cast and spellName(b.cast) or false, b.ask or false, Tr.title(b) }) do
                    if n and name:sub(1, #n) == n then return b end
                end
            end
        end
    end
    local c = castTotem[element]
    if c and math.abs(start - c.at) < 2 then return c.b end
    return nil
end

-- What stands in our totem slot of `element` (as `standing` holds it), or
-- nil when the game won't say.
local function readSlot(element)
    if not _G.GetTotemInfo then return nil end
    local ok, have, name, start, duration, _, _, spellId = pcall(GetTotemInfo, TOTEM_SLOT[element])
    if not ok or not (readable(have) and readable(start) and readable(duration)) then return nil end
    if not have or not start or start <= 0 or not duration or duration <= 0 then return false end
    local expires = start + duration
    if expires <= GetTime() then return false end
    return { b = totemBuff(element, name, start, spellId), expires = expires }
end

-- Looks at our totem slot of `element` again, and notes when a totem of
-- ours left it.
local function updateSlot(element)
    local slot = TOTEM_SLOT[element]
    local new = readSlot(element)
    if new == nil then return end
    slotSeen[slot] = GetTime()
    local old = standing[slot]
    if old and old.b and not (new and new.b == old.b) then
        totemGone[old.b.id] = math.min(GetTime(), old.expires)
    end
    if new and new.b then totemGone[new.b.id] = nil end
    standing[slot] = new
    dirty = true
end

-- The game's totem slot of our totem `b`, when it's the last totem we know
-- went into the slot of its element, else nil.
--
-- In combat the game hides the slot from us, but every totem we drop is our
-- own cast, which we do see. So a cast after our last read of the slot says
-- what went in. The slot may be empty by now, when the totem was killed, and
-- then the game's countdown for it is empty too.
function Tr.liveTotem(b)
    local element = b and b.element
    local slot = element and TOTEM_SLOT[element]
    if not slot then return nil end
    local cast, seen = castTotem[element], slotSeen[slot]
    local last
    if cast and not (seen and seen >= cast.at) then
        last = cast.b
    else
        last = standing[slot] and standing[slot].b
    end
    return last == b and slot or nil
end

-- A number that goes up whenever one of our totems may have changed.
function Tr.totemVersion() return totemVersion end

-- Our own totem of `b` while auras are hidden, as a read: up while it stands
-- and for the tail of its last pulse, then missing. nil when we never saw it
-- stand, and then what we read and cast counts.
function Tr.totemRead(b)
    local t = standing[TOTEM_SLOT[b.element]]
    local now = GetTime()
    if t and t.b == b and t.expires > now then
        return { up = true, expires = t.expires, duration = b.duration or 0, stacks = 1, ours = true }
    end
    local gone = totemGone[b.id]
    if t and t.b == b then gone = t.expires end
    if not gone then return nil end
    local tail = gone + math.min(lasts[b.id] or 0, TOTEM_TAIL)
    if tail > now then
        return { up = true, expires = tail, duration = tail - gone, stacks = 1, ours = true }
    end
    return { up = false, expires = 0, duration = 0, stacks = 0, since = tail }
end

-- What we read of buff `b` that assignment `a` gives player `m`, and which
-- buff that is. In a raid it's `b` itself, and so it is for anything but a
-- blessing or a totem.
--
-- In a party (Tr.party) any blessing will do, so when `b` isn't up we take
-- another blessing that's up on them and no other paladin has claimed. With
-- one paladin that's any blessing at all. With two, Kings from one and Might
-- from the other, a player with Wisdom and Might counts as blessed by both,
-- and one with only Wisdom by the first of them. A totem is the same within
-- its element: Stoneskin counts for Strength of Earth. Our own totem of the
-- element counts for everyone while it stands, even one with no buff, like
-- Tremor.
--
-- While auras are hidden, our own totem goes by what the game says stands
-- (Tr.totemRead) rather than by what we read before the pull.
--
-- The HUD asks this for every player twice a second, so the lists below are
-- kept between calls and emptied at the start of each. None of them leaves
-- this function, and nothing it calls comes back here.
local EMPTY = {}
local planned, plannedCount, claimed, spare = {}, 0, {}, {}
-- The records `planned` holds, kept for the next call.
local plannedPool = {}
-- The buff IDs of each totem element, from the data, which never changes.
local elementIds = {}

local function addPlanned(name, id, us)
    plannedCount = plannedCount + 1
    local p = plannedPool[plannedCount]
    if not p then
        p = {}
        plannedPool[plannedCount] = p
    end
    p.name, p.id, p.us = name, id, us
    planned[plannedCount] = p
end

local function byName(x, y) return x.name < y.name end

local function idsOf(element)
    local list = elementIds[element]
    if not list then
        list = {}
        for _, o in ipairs(D.BUFFS) do
            if o.element == element then list[#list + 1] = o.id end
        end
        elementIds[element] = list
    end
    return list
end

function Tr.standIn(a, m, b)
    local s = Tr.state(m.name, b.id)
    local totem = not a.bless and b.element and not a.backup
    if totem and a.giver and a.giver.me and Tr.hidden() then
        local t = Tr.totemRead(b)
        -- In a party another totem of ours of the element still does (below).
        if t and (t.up or not Tr.party()) then return t, b end
        s = t or s
    end
    if not (a.bless or totem) or not Tr.party() or (s and s.up) then return s, b end
    -- What each giver's plan puts on them of this kind, us included.
    for i = plannedCount, 1, -1 do planned[i] = nil end
    plannedCount = 0
    addPlanned(a.giver and a.giver.name or "", b.id, true)
    local list
    if a.bless then
        local blessings = NS.Duties.plan("blessings")
        for _, x in ipairs(blessings and blessings.list or EMPTY) do
            local id = x.bless and not sameGiver(x, a) and x.bless[m.name]
            if id then addPlanned(x.giver.name, id) end
        end
        list = D.JOB.blessings.options
    else
        for _, p in pairs(NS.Duties.board() or EMPTY) do
            for _, x in ipairs(p.active and p.list or EMPTY) do
                if x.buff and x.buff.element == b.element and not sameGiver(x, a) and not x.backup
                   and (not x.party or x.party == m.group) then
                    addPlanned(x.giver.name, x.buff.id)
                end
            end
        end
        list = idsOf(b.element)
        if a.giver and a.giver.me then
            local mine = ourTotem(b.element)
            if mine then return mine, b end
        end
    end
    -- A giver whose own buff is up has it. The other buffs up on them go to
    -- the givers whose own isn't, one each, in the order of their names.
    table.sort(planned, byName)
    for id in pairs(claimed) do claimed[id] = nil end
    for i = #spare, 1, -1 do spare[i] = nil end
    for _, p in ipairs(planned) do
        local o = Tr.state(m.name, p.id)
        if o and o.up then claimed[p.id] = true end
    end
    for _, id in ipairs(list) do
        if not claimed[id] then
            local o = Tr.state(m.name, id)
            if o and o.up then spare[#spare + 1] = id end
        end
    end
    local i = 0
    for _, p in ipairs(planned) do
        if not claimed[p.id] then
            i = i + 1
            if p.us then
                local id = spare[i]
                if id then return Tr.state(m.name, id), D.BY_ID[id] end
                break
            end
        end
    end
    return s, b
end

-- Whether we're in a party, where any blessing or totem will do. A raid
-- group of five or fewer counts too, since some make one for a dungeon.
function Tr.party()
    return not R.raid() or #R.list() <= 5
end

local status

function Tr.status(a)
    if not memo then return status(a) end
    local st = memo[a]
    if not st then
        st = status(a)
        memo[a] = st
    end
    return st
end

status = function(a)
    local now = GetTime()
    if a.buff and a.buff.debuff then
        local s = Tr.targetState(a.buff.id)
        return { debuff = true, wanted = Tr.targetWanted(), up = s and s.up or false,
                 expires = s and s.expires or 0, duration = s and s.duration or 0,
                 stacks = s and s.stacks or 0, unknown = s == nil }
    end
    local st = { have = 0, want = 0, missing = {}, dead = {}, unknown = 0, expires = 0, by = {}, low = {} }
    local wait = a.backup and (NS.Options.get("backupDelay") or 0) or nil
    for _, t in ipairs(NS.Duties.targets(a)) do
        local m, b = t.m, t.b
        local by = st.by[b.id] or { have = 0, want = 0 }
        st.by[b.id] = by
        if m.dead then
            st.dead[#st.dead + 1] = { m = m, b = b }
        else
            st.want, by.want = st.want + 1, by.want + 1
            -- A player out of sight keeps what we read last, counting down.
            -- `up` is what they have, which in a party may be another
            -- blessing or totem than `b`. The lists below still name `b`,
            -- since the counts and the windows go by the plan's buff.
            local s, up = Tr.standIn(a, m, b)
            if not s then
                st.unknown = st.unknown + 1
            elseif s.up then
                local left = s.expires > 0 and s.expires - now or math.huge
                local want = Tr.lowRank(a, up, m, s)
                if want then st.low[#st.low + 1] = { m = m, b = b, rank = s.rank, want = want } end
                local better = a.giver and a.giver.me and Tr.betterRank(up, m, s)
                if better and not wait then
                    -- They have it, and a cast of ours would make it better.
                    st.have, by.have = st.have + 1, by.have + 1
                    st.missing[#st.missing + 1] = { m = m, b = b, soon = true, low = s.rank }
                elseif left <= Tr.rebuffAt(up) and not wait then
                    st.missing[#st.missing + 1] = { m = m, b = b, soon = true }
                else
                    st.have, by.have = st.have + 1, by.have + 1
                end
                if s.expires > 0 and (st.expires == 0 or s.expires < st.expires) then
                    st.expires = s.expires
                end
            elseif not wait or now - (s.since or now) >= wait then
                local since = s.since or now
                st.missing[#st.missing + 1] = { m = m, b = b, since = since }
                if not st.oldest or since < st.oldest then st.oldest = since end
            end
        end
    end
    return st
end

-- =============================================================
-- Kept across a /reload
-- =============================================================
local KEPT_FOR = 300

local function keep()
    if not NS.db then return end
    local now, wall = GetTime(), time()
    local t = {}
    for name, bufs in pairs(seen) do
        local mine = {}
        for id, r in pairs(bufs) do
            mine[id] = { up = r.up, duration = r.duration, stacks = r.stacks, rank = r.rank, level = r.level,
                         ends = r.expires > 0 and floor(wall + (r.expires - now) + 0.5) or 0 }
        end
        t[name] = mine
    end
    NS.db.kept = { saved = wall, seen = t, lasts = lasts }
end

local function restore()
    local k = NS.db and NS.db.kept
    if NS.db then NS.db.kept = nil end
    if type(k) ~= "table" or type(k.saved) ~= "number" or type(k.seen) ~= "table" then return end
    local now, wall = GetTime(), time()
    if wall - k.saved > KEPT_FOR then return end
    for id, d in pairs(type(k.lasts) == "table" and k.lasts or {}) do lasts[id] = d end
    for name, bufs in pairs(k.seen) do
        local t = seen[name] or {}
        for id, d in pairs(bufs) do
            if t[id] == nil and type(d) == "table" then
                local ends = tonumber(d.ends) or 0
                t[id] = { up = d.up == true, expires = ends == 0 and 0 or now + (ends - wall),
                          duration = d.duration or 0, stacks = d.stacks or 0, at = now,
                          rank = d.rank, level = d.level }
            end
        end
        seen[name] = t
    end
end

-- =============================================================
-- Events
-- =============================================================
local function changed()
    dirty = false
    NS.signal("tracking")
end

-- Tells the rest of the addon when a read changed something.
local function changedIfRead()
    if dirty then changed() end
end

-- Every assignment's buffs are many more reads, so they wait longer.
local READ_ALL_EVERY = 2

-- Runs `fn` once, `delay` seconds after the first call with `key`, however
-- many calls come in between. In a raid UNIT_AURA never stops for long, so a
-- wait that starts over on each call might never run.
local waiting = {}
local function within(key, delay, fn)
    if waiting[key] then return end
    waiting[key] = true
    C_Timer.After(delay, function()
        waiting[key] = nil
        fn()
    end)
end

local function readSoon()
    if Tr.hidden() then return end
    within("read", 0.2, function()
        if Tr.hidden() then return end
        Tr.readAll()
        changedIfRead()
    end)
    if Tr.readsAll() then
        within("readEvery", READ_ALL_EVERY, function()
            if Tr.hidden() then return end
            Tr.readAll(true)
            changedIfRead()
        end)
    end
end
Tr.readSoon = readSoon

-- The roster's members by unit, for the health events.
local byUnit = {}
NS.listen("roster", function()
    byUnit = {}
    for _, m in ipairs(R.list()) do byUnit[m.unit] = m end
end)

-- A player died or came back. We look on every health change, since we
-- can't read deaths any other way in combat. A raid fight sends many of
-- them, and nearly all are damage and heals, so we ask the game one thing
-- and go on only when the answer differs from what we knew. Whether a hunter
-- is playing dead we only ask when the game says they're dead.
NS.on("UNIT_HEALTH", function(_, unit)
    if type(unit) ~= "string" or secret(unit) then return end
    local m = byUnit[unit]
    if not m then return end
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if not readable(dead) then return end
    dead = dead and not feigning(unit) and true or false
    if dead == m.dead and (not dead or diedAt[m.name]) then return end
    m.dead = dead
    if dead then
        Tr.died(m)
    else
        diedAt[m.name] = nil
    end
    changed()
end)

NS.listen("loaded", restore)
NS.on("PLAYER_LOGOUT", keep)
NS.listen("board", readSoon)

-- The players whose buffs changed since we last read, by unit.
local touched = {}

-- Reads the players of `touched`. In a raid UNIT_AURA comes for someone
-- several times a second, and a read of everyone each time would be every
-- buff on up to 40 players. So we read only those it came for. Who comes
-- into sight or range sends nothing, which the sweep every few seconds
-- catches (below).
local function readTouched()
    local hidden = Tr.hidden()
    local buffs = not hidden and ourBuffs(Tr.readsAll()) or {}
    local me, done = R.me(), {}
    for unit in pairs(touched) do
        touched[unit] = nil
        -- In a raid we're "raid" something, and "player" too.
        local m = byUnit[unit] or (unit == "player" and me) or nil
        -- Our camp buffs count even when we have no duty to read us for.
        if m and m == me and not hidden and next(buffs) == nil and not done.camp then
            done.camp = true
            Tr.readCamp()
        end
        if m and not done[m] and next(buffs) ~= nil then
            done[m] = true
            Tr.readMember(m, buffs)
        end
    end
    changedIfRead()
end

-- Whether we may read aura `a` of a UNIT_AURA change.
local function clear(a)
    return type(a) == "table" and not secret(a) and not secret(a.name) and not secret(a.spellId)
           and not secret(a.expirationTime) and not secret(a.duration)
end

-- What UNIT_AURA's `info` says changed on `unit` while auras are hidden (see
-- WHAT COMBAT STILL TELLS US at the top).
local function fromChange(unit, info)
    if info.isFullUpdate == true then return end
    local reads, buffs
    if unit == "target" then
        reads, buffs = onTarget, targetDebuffs
    else
        local m = byUnit[unit] or (unit == "player" and R.me()) or nil
        if not m or m.dead then return end
        seen[m.name] = seen[m.name] or {}
        reads, buffs = seen[m.name], function() return ourBuffs(Tr.readsAll()) end
    end
    local now = GetTime()
    local added, blind = {}, false
    local list = info.addedAuras
    if type(list) == "table" and not secret(list) then
        for _, a in ipairs(list) do
            if clear(a) then added[#added + 1] = a else blind = true end
        end
    elseif list ~= nil then
        blind = true
    end
    local get = _G.C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    list = info.updatedAuraInstanceIDs
    if get and type(list) == "table" and not secret(list) then
        for _, instance in ipairs(list) do
            for _, r in pairs(readable(instance) and reads or {}) do
                if r.instance == instance then
                    local ok, a = pcall(get, unit, instance)
                    if ok and clear(a) then added[#added + 1] = a end
                    break
                end
            end
        end
    end
    if #added > 0 then
        for id, b in pairs(buffs()) do
            local r = readOne(b, added, true)
            if r then
                if not same(reads[id], r) then dirty = true end
                reads[id] = r
            end
        end
    end
    list = info.removedAuraInstanceIDs
    if blind or type(list) ~= "table" or secret(list) then return end
    for _, instance in ipairs(list) do
        for id, r in pairs(readable(instance) and reads or {}) do
            if r.up and r.instance == instance then
                reads[id] = { up = false, expires = 0, duration = 0, stacks = 0, at = now, since = now }
                dirty = true
            end
        end
    end
end

local function readTargetNow()
    Tr.readTarget()
    changedIfRead()
end

NS.on("UNIT_AURA", function(_, unit, info)
    if type(unit) == "string" and not secret(unit) and type(info) == "table" and not secret(info)
       and Tr.hidden() and (unit == "player" or unit == "target" or unit:find("^party") or unit:find("^raid")) then
        -- The game's answers in combat are new to us, so one we didn't
        -- foresee mustn't become an error on the player's screen.
        pcall(fromChange, unit, info)
        changedIfRead()
        return
    end
    if unit == "target" then
        if Tr.hidden() then return end
        within("readTarget", 0.1, readTargetNow)
        return
    end
    if type(unit) ~= "string" or secret(unit) then return end
    if unit == "player" or unit:find("^party") or unit:find("^raid") then
        if Tr.hidden() then return end
        touched[unit] = true
        within("readTouched", 0.2, readTouched)
    end
end)

NS.on("PLAYER_TARGET_CHANGED", function()
    switchTarget()
    Tr.readTarget()
    changed()
end)

NS.on("PLAYER_REGEN_ENABLED", readSoon)

-- One of our totems went down or away. The game says which slot, and we
-- look at every one when it doesn't.
NS.on("PLAYER_TOTEM_UPDATE", function(_, slot)
    totemVersion = totemVersion + 1
    for element, s in pairs(TOTEM_SLOT) do
        if not readable(slot) or slot == s then updateSlot(element) end
    end
    changedIfRead()
end)
NS.listen("login", function()
    for element in pairs(TOTEM_SLOT) do updateSlot(element) end
end)

-- Nothing tells us when a player comes into sight or range, so we look
-- again now and then out of combat.
NS.listen("login", function()
    C_Timer.NewTicker(5, function()
        if not (InCombatLockdown and InCombatLockdown()) and R.grouped() then readSoon() end
    end)
end)

-- The pull check.
NS.on("READY_CHECK", function()
    if not NS.Options.get("pullCheck") then return end
    Tr.pullUntil = GetTime() + PULL_FOR
    Tr.readAll(Tr.readsAll())
    changed()
    NS.signal("pullCheck")
end)
NS.on("PLAYER_REGEN_DISABLED", function()
    if Tr.pulling() then
        Tr.pullUntil = nil
        NS.signal("pullCheck")
    end
end)

-- What of our own is due on the pull: { b, names = { m, ... } } for each
-- long buff of ours that someone is missing or that runs out within the
-- fight, in our duties' order. Our backups don't count.
function Tr.due()
    local list, byBuff = {}, {}
    for _, a in ipairs(NS.Duties.mine()) do
        local long = a.bless or (a.buff and a.buff.kind == "long")
        if long and not a.backup and not a.spare then
            for _, t in ipairs(Tr.status(a).missing) do
                local d = byBuff[t.b.id]
                if not d then
                    d = { b = t.b, names = {} }
                    byBuff[t.b.id] = d
                    list[#list + 1] = d
                end
                d.names[#d.names + 1] = t.m
            end
        end
    end
    return list
end

-- Who each of our casts went to, by cast GUID, as the game names them when
-- the cast starts.
local sentTo, sentCount = {}, 0

NS.on("UNIT_SPELLCAST_SENT", function(_, unit, target, castGuid)
    if unit ~= "player" or not readable(castGuid) or castGuid == nil then return end
    if type(target) ~= "string" or not readable(target) or target == "" then return end
    -- A cast that never ends (an interrupt sends no SUCCEEDED) stays in the
    -- list, so it starts over now and then.
    if sentCount >= 20 then sentTo, sentCount = {}, 0 end
    sentTo[castGuid] = target
    sentCount = sentCount + 1
end)

-- Whether spell `id` is the group version of long buff `b`, like Prayer of
-- Fortitude.
local function groupCast(b, id)
    if not b.group then return false end
    if id == b.group then return true end
    local name = spellName(id)
    return name ~= nil and name == spellName(b.group)
end

-- Counts long buff `b` on everyone our assignments of it are for, for a
-- group version.
local function castOnAll(b)
    for _, a in ipairs(NS.Duties.mine()) do
        if a.buff == b then
            for _, t in ipairs(NS.Duties.targets(a)) do Tr.cast(t.m.name, b) end
        end
    end
end

-- Our own casts. The auto-buffer says who it aimed at (Buffer.lua). A cast it
-- didn't aim, on our mouseover in combat or from our own action bars, goes
-- by the name the game gave when the cast started.
NS.on("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, castGuid, spellId)
    if unit ~= "player" or not readable(spellId) then return end
    local to = readable(castGuid) and castGuid ~= nil and sentTo[castGuid] or nil
    if to then
        sentTo[castGuid] = nil
        sentCount = sentCount - 1
    end
    local b = buffOfSpell(spellId)
    if not b then return end
    if b.debuff then
        Tr.cast(nil, b)
        return
    end
    -- A shout or a totem reaches everyone it's for at once.
    if b.kind == "short" then
        if b.element then
            castTotem[b.element] = { b = b, at = GetTime() }
            totemVersion = totemVersion + 1
            updateSlot(b.element)
        end
        for _, a in ipairs(NS.Duties.mine()) do
            if a.buff == b then
                for _, t in ipairs(NS.Duties.targets(a)) do Tr.cast(t.m.name, b) end
            end
        end
        return
    end
    local aim = Tr.aim
    if aim and aim.b == b and GetTime() - aim.at < 10 then
        if aim.all then
            -- A group version reaches everyone it's for.
            castOnAll(b)
        else
            Tr.cast(aim.name, b)
        end
        Tr.aim = nil
    elseif groupCast(b, spellId) then
        castOnAll(b)
    elseif to then
        local m = R.byName(to) or (NS.Sync and NS.Sync.member(to))
        if m then Tr.cast(m.name, b) end
    end
end)

Tr.keep, Tr.restore, Tr.buffOfSpell, Tr.ourBuffs = keep, restore, buffOfSpell, ourBuffs
