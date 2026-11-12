-- Whispering players without the addon their assignments.
--
-- Only the client that runs the board whispers (Sync.lua), so nobody gets
-- the same whisper twice. That's the leader when they have the addon, else
-- an assistant, else whoever comes first by name. It doesn't have to be the
-- leader or an assistant: when we're the only one with the addon, nobody
-- else can tell players what's missing (the user asked for this). The first
-- time we whisper in a group we say so in chat.
--
-- A player gets their whole list when their assignments change, 20 seconds
-- after the last change, and out of combat. While a raid forms the board
-- changes with every join, so a shorter wait would whisper a list that's
-- already old. The Assignments page has a button for it. On a ready check a
-- giver only hears what's missing: "[BC] Fortitude missing on: Grom, Jaina
-- (party 3), Thrall, Uther". A leader or an assistant can nudge a giver the
-- same way from the coverage strip, once every 30 seconds each. Anyone may whisper us
-- "!bc" for their assignments.
--
-- A giver also hears when their long buffs or blessings run out: once when
-- they run out soon, and again when they ran out or are missing (W.expiry).
-- Players with the addon see both on their HUD instead.
--
-- In a party (five or fewer, Tracking's Tr.party) we only whisper about buffs
-- running out or missing. Any blessing or totem will do there (Tracking.lua),
-- so a list of assignments or a ready check would only be noise. The button, a
-- nudge and "!bc" still answer, since someone asked.
--
-- We never whisper a player the same text twice within a minute on our own,
-- like on two ready checks in a row. A nudge, the button and "!bc" are
-- asked for, so they always go out.
--
-- A player without the addon has never heard of it. So the first whisper
-- they get from us in a group says "[Buff Coordinator]" in full and ends
-- with how to ask again ("!bc"). The ones after say "[BC]". A player whose
-- assignments were all taken away hears that once, so they don't keep
-- doing what we last told them.
--
-- We wait a little after joining a group, until we've heard who runs the
-- addon. Without that, everyone would look like they don't.
--
-- What we last whispered each player and who we introduced ourselves to
-- are kept over a /reload (`db.whispers`: { said, introduced, at }). The
-- board is worked out again after a /reload, and without them we'd whisper
-- every player without the addon their whole list again, intro and all.
-- They're for the group we're in, so they go when we leave it, and after
-- half an hour (KEEP) in which we didn't run the board, like after a relog
-- into another group.

local _, NS = ...
local D, R, Du, Tr, S, O = NS.Data, NS.Roster, NS.Duties, NS.Tracking, NS.Sync, NS.Options

local format = string.format

local W = {}
NS.Whisper = W

local MAX_LINE = 240
local SETTLE = 10
local GAP = 0.4
-- How long after the last board change we whisper assignments.
local BOARD_WAIT = 20
-- A text a player already had from us this recently isn't sent again.
local REPEAT_AFTER = 60
-- How often a leader can nudge the same giver.
local NUDGE_EVERY = 30

-- What we last whispered each player, so a whisper only goes out when it
-- would say something new.
local said = {}
-- The last whisper each player had from us, as { text, at }.
local last = {}
-- When we last nudged each giver.
local nudged = {}
-- How long what we whispered is kept while we don't run the board.
local KEEP = 30 * 60

local classWord, list = NS.classWord, NS.andList

-- A paladin's blessings in words: "Kings on everyone", or "Wisdom on mages
-- and priests, Might on warriors", then the single ones.
local function blessingsText(a)
    local byBlessing, order = {}, {}
    local classes = {}
    for class in pairs(a.byClass or {}) do classes[#classes + 1] = class end
    table.sort(classes, function(a, b) return D.CLASS_RANK[a] < D.CLASS_RANK[b] end)
    for _, class in ipairs(classes) do
        local id = a.byClass[class]
        if not byBlessing[id] then
            byBlessing[id] = {}
            order[#order + 1] = id
        end
        table.insert(byBlessing[id], classWord(class))
    end
    local present = {}
    for _, m in ipairs(R.list()) do present[m.class] = true end
    local nClasses = 0
    for _ in pairs(present) do nClasses = nClasses + 1 end
    local parts = {}
    for _, id in ipairs(order) do
        local who = #byBlessing[id] == nClasses and "everyone" or list(byBlessing[id])
        parts[#parts + 1] = format("%s on %s", NS.Buffer.short(Tr.title(D.BY_ID[id])), who)
    end
    local singles = {}
    for name, id in pairs(a.bless) do
        local m = R.byName(name)
        if m and a.byClass[m.class] ~= id then
            singles[#singles + 1] = format("%s on %s", NS.Buffer.short(Tr.title(D.BY_ID[id])), name)
        end
    end
    table.sort(singles)
    if #singles > 0 then parts[#parts + 1] = "then " .. list(singles) end
    return table.concat(parts, ", ")
end

-- One assignment in words.
local function assignmentText(a)
    if a.bless then return blessingsText(a) end
    local name = NS.Buffer.short(Tr.title(a.buff))
    if a.job.scope == "target" then return name .. " on the target" end
    if a.job.kind == "resist" then return format("%s for %s", name, Du.fight() or "this fight") end
    if a.party and R.raid() then return format("%s for group %d", name, a.party) end
    return name
end
W.assignmentText = assignmentText

-- The whisper for player `name`, or nil when they have no duties.
function W.text(name)
    local parts = {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.plan(job.id)
        for _, a in ipairs(plan and plan.active and plan.list or {}) do
            if a.giver.name == name then parts[#parts + 1] = assignmentText(a) end
        end
    end
    if #parts == 0 then return nil end
    return "[BC] Your assignments: " .. table.concat(parts, ". ") .. "."
end

-- How many names a missing line lists before "and 3 more".
local MAX_NAMES = 8

-- The players of list `ms` for a whisper to `giver`: "Grom, Jaina (group
-- 3), Thrall". A player in another party of the raid has their party after
-- the name.
local function namesText(ms, giver)
    local names = {}
    for i, m in ipairs(ms) do
        if i > MAX_NAMES then
            names[#names + 1] = format("and %d more", #ms - MAX_NAMES)
            break
        end
        local away = R.raid() and m.group ~= giver.group
        names[#names + 1] = away and format("%s (group %d)", m.name, m.group) or m.name
    end
    return table.concat(names, ", ")
end

-- What assignment `a` is missing, in a whisper to its giver: "[BC]
-- Fortitude missing on: Grom, Jaina (party 3), Thrall, Uther". A player in
-- another party of the raid has their party after the name. nil when
-- nothing is missing. Shouts and totems go up in the fight, so only long
-- buffs and blessings count.
function W.missingText(a)
    local long = a.bless or (a.buff and a.buff.kind == "long")
    if not long or a.spare then return nil end
    local order, byBuff = {}, {}
    for _, t in ipairs(Tr.status(a).missing) do
        if not t.soon then
            local list = byBuff[t.b.id]
            if not list then
                list = { b = t.b }
                byBuff[t.b.id] = list
                order[#order + 1] = list
            end
            list[#list + 1] = t.m
        end
    end
    if #order == 0 then return nil end
    local parts = {}
    for _, list in ipairs(order) do
        parts[#parts + 1] = format("%s missing on: %s", NS.Buffer.short(Tr.title(list.b)),
                                   namesText(list, a.giver))
    end
    return "[BC] " .. table.concat(parts, ". ")
end

-- `text` cut into lines a chat message holds, at word breaks. A word longer
-- than a line is cut where it must be, but never inside a letter of more
-- than one byte, like an accented one in a name.
function W.lines(text)
    local lines = {}
    while #text > MAX_LINE do
        local space = text:sub(1, MAX_LINE + 1):match("^.*()%s")
        if space and space > 1 then
            lines[#lines + 1] = text:sub(1, space - 1)
            text = text:sub(space + 1)
        else
            -- A byte from 128 to 191 goes on with a letter the bytes before
            -- it began.
            local cut = MAX_LINE
            local b = text:byte(cut + 1)
            while cut > 1 and b >= 128 and b < 192 do
                cut = cut - 1
                b = text:byte(cut + 1)
            end
            lines[#lines + 1] = text:sub(1, cut)
            text = text:sub(cut + 1)
        end
    end
    lines[#lines + 1] = text
    return lines
end

-- =============================================================
-- Sending
-- =============================================================
local outbox = {}
local sending = false

local function chatSend(msg, target)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    if not send then return end
    local ok, err = pcall(send, msg, "WHISPER", nil, target)
    if not ok then NS.print("Couldn't whisper %s: %s.", target, tostring(err)) end
end

-- Sends the outbox one whisper at a time, a little apart. The game blocks
-- chat in some fights, so we wait then.
local function drain()
    if #outbox == 0 then
        sending = false
        return
    end
    sending = true
    if S.locked() then
        C_Timer.After(2, drain)
        return
    end
    local w = table.remove(outbox, 1)
    chatSend(w.msg, w.target)
    C_Timer.After(GAP, drain)
end

-- The players who had a whisper from us in this group, by name, so the
-- first one introduces us.
local introduced = {}

-- Keeps `said` and `introduced` in the saved variables, as of now.
local function kept()
    local k = NS.db.whispers
    if type(k) ~= "table" then
        k = { said = said, introduced = introduced }
        NS.db.whispers = k
    end
    k.at = time()
end

local function forget()
    for k in pairs(said) do said[k] = nil end
    for k in pairs(introduced) do introduced[k] = nil end
    if NS.db then NS.db.whispers = nil end
end

local TAG = "[BC] "
local INTRO = "[Buff Coordinator] "
local OUTRO = " Whisper me !bc to see this again."

-- `text` (which starts with TAG) as the first whisper a player gets from us.
local function introduce(text)
    local body = text:sub(1, #TAG) == TAG and text:sub(#TAG + 1) or text
    if not body:find("[.!?]$") then body = body .. "." end
    return INTRO .. body .. OUTRO
end

-- Whispers `text` to `name`, or to `to` when the game named them some other
-- way (a "!bc" whisper's sender). With `fresh`, not when they had the same
-- text from us within the last minute, and then it says false.
local function queue(name, text, fresh, to)
    local now = GetTime()
    local l = last[name]
    if fresh and l and l.text == text and now - l.at < REPEAT_AFTER then return false end
    last[name] = { text = text, at = now }
    kept()
    local msg = text
    if not introduced[name] then
        introduced[name] = true
        msg = introduce(text)
    end
    for _, line in ipairs(W.lines(msg)) do outbox[#outbox + 1] = { msg = line, target = to or name } end
    if not sending then drain() end
    return true
end

-- Whether we may whisper on our own: we run the board and the setting
-- `key` is on.
function W.allowed(key)
    return O.get(key) and S.isHost() and true or false
end

-- The first time we whisper in a group, we say so.
local told = false

local function tell()
    if told then return end
    told = true
    local n = 0
    for _, m in ipairs(R.list()) do
        if not m.me and m.online and not S.hasAddon(m.name) then n = n + 1 end
    end
    NS.print("You're the Assignments Leader, so you whisper the %s without the addon. Turn this off in Settings.",
             n == 1 and "1 player" or format("%d players", n))
end

local NONE_NOW = TAG .. "You have no assignments now."

-- Whispers each player without the addon their duties, when they changed
-- since we last did, or always with `again`. `force` sends even when we
-- don't run the board (the button on the Assignments page). In combat it
-- waits until combat ends, and a forced one stays forced.
function W.all(again, force)
    if NS.mock or not R.grouped() then return 0 end
    if not force then
        if not W.allowed("whisper") or Tr.party() then return 0 end
        if S.inGroupFor() < SETTLE then
            NS.soon("whisperSettle", SETTLE, function() W.all(again) end)
            return 0
        end
    end
    if InCombatLockdown() then
        if force then
            W.forced = true
        else
            W.pending = true
        end
        return 0
    end
    kept()
    local n = 0
    for _, m in ipairs(R.list()) do
        if not m.me and m.online and not S.hasAddon(m.name) then
            local text = W.text(m.name)
            if text and (again or said[m.name] ~= text) then
                said[m.name] = text
                if queue(m.name, text, not force) then n = n + 1 end
            elseif not text and said[m.name] and said[m.name] ~= NONE_NOW then
                -- We told them assignments they no longer have.
                said[m.name] = NONE_NOW
                if queue(m.name, NONE_NOW, not force) then n = n + 1 end
            end
        end
    end
    if n > 0 and not force then tell() end
    return n
end

-- The "Whisper assignments" button and /bbc whisper: whispers everyone
-- without the addon their assignments now, even when we don't run the
-- board. Only the leader, the assistants and whoever runs the board may,
-- like the button. In combat
-- it whispers once combat ends. Says what it did in chat, and returns how
-- many players it whispered, or nil when it didn't (yet).
function W.request()
    if NS.mock then
        NS.print("End the mock raid to whisper the group.")
        return nil
    end
    if not R.real.grouped() then
        NS.print("You're not in a group.")
        return nil
    end
    if not R.real.canEdit() and not S.isHost() then
        NS.print("Only the leader, an assistant or the Assignments Leader can whisper.")
        return nil
    end
    local without = 0
    for _, m in ipairs(R.real.list()) do
        if not m.me and m.online and not S.hasAddon(m.name) then without = without + 1 end
    end
    if without == 0 then
        NS.print("Everyone here has the addon.")
        return nil
    end
    if InCombatLockdown() then
        W.forced = true
        NS.print("Whispers go out after combat.")
        return nil
    end
    local n = W.all(true, true)
    NS.print(n == 1 and "Whispered 1 player." or "Whispered %d players.", n)
    return n
end

-- On a ready check: whispers each giver without the addon what their
-- assignments are missing. A giver with nothing missing hears nothing, and
-- so does one who isn't next to us (R.close, Roster.lua).
function W.ready()
    if NS.mock or not R.grouped() or not W.allowed("whisperReady") or InCombatLockdown() then return 0 end
    if Tr.party() then return 0 end
    -- Right after we join or /reload we haven't heard who runs the addon
    -- yet, so we'd think we run the board and whisper everyone.
    if S.inGroupFor() < SETTLE then return 0 end
    Tr.readAll(true)
    local texts, order = {}, {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.plan(job.id)
        for _, a in ipairs(plan and plan.active and plan.list or {}) do
            local g = a.giver
            if not g.me and g.online and not S.hasAddon(g.name) and R.close(g) then
                local text = W.missingText(a)
                if text then
                    if not texts[g.name] then order[#order + 1] = g.name end
                    texts[g.name] = texts[g.name] and texts[g.name] .. ". " .. text:sub(#TAG + 1) or text
                end
            end
        end
    end
    local n = 0
    for _, name in ipairs(order) do
        if queue(name, texts[name], true) then n = n + 1 end
    end
    if n > 0 then tell() end
    return n
end

-- Whispers the giver of assignment `a` what it's missing, for a leader's
-- nudge. False when nothing is, and then how many seconds until we nudge
-- them again when we just did. A debuff's nudge says its own `text`, and
-- goes in combat too, since that's when a debuff matters.
function W.nudge(a, text)
    local fight = text ~= nil
    text = text or W.missingText(a)
    if not text or a.giver.me or (InCombatLockdown() and not fight) then return false end
    local now = GetTime()
    local at = nudged[a.giver.name]
    if at and now - at < NUDGE_EVERY then return false, math.ceil(NUDGE_EVERY - (now - at)) end
    queue(a.giver.name, text)
    nudged[a.giver.name] = now
    return true
end

-- A player whispered us "!bc": when we run the board, they hear their
-- assignments. Once every few seconds each, so it can't flood. The answer
-- goes to who whispered, as the game named them, never to someone else in
-- the group whose name looks like theirs.
local asked = {}
local ASK_GAP = 10

function W.answer(text, sender)
    if NS.secret(text) or type(text) ~= "string" or text:lower():match("^%s*(.-)%s*$") ~= "!bc" then return end
    if NS.mock or not R.grouped() or not S.isHost() then return end
    local m = S.member(sender)
    if not m or m.me then return end
    local now = GetTime()
    if asked[m.name] and now - asked[m.name] < ASK_GAP then return end
    asked[m.name] = now
    -- They know how to ask, so the answer needn't tell them.
    introduced[m.name] = true
    queue(m.name, W.text(m.name) or TAG .. "You have no assignments.", false, sender)
end

-- =============================================================
-- Buffs running out
-- =============================================================
-- A giver without the addon hears when the long buffs and blessings they
-- put up run out soon, like "[BC] Fortitude runs out in 5 min on: Grom,
-- Jaina (group 3), Thrall, Uther", and again when they ran out: "[BC]
-- Fortitude ran out on: Grom, Thrall".
--
-- We go by each player's buff, so we tell the giver once for each cast. A
-- new cast lasts longer than the one before, and that starts it over.
--
-- "Soon" is the last twentieth of the cast (SOON_SHARE), so the warning
-- fits how long the buff lasts. A 1-hour Prayer of Fortitude warns at 3
-- minutes, and Thorns, which lasts 10 minutes, at 30 seconds. When we can't
-- tell how long the cast lasts, we use the "Rebuff under" setting (2
-- minutes at most in a party, PARTY_SOON).
--
-- A player who doesn't have the buff at all gets a minute (MISSING_AFTER)
-- before we say "[BC] Fortitude missing on: Grom, Thrall". That's a
-- player who just joined, who came back from the dead, or whom the giver
-- never buffed. The minute lets the giver get to them on their own. In a
-- party a buff that ran out also waits that minute and is told as missing,
-- since a party rebuffs as it goes rather than all at once before a pull.
--
-- We only whisper a giver next to us, within buff range (R.close,
-- Roster.lua), about the players next to us too. A giver across the zone
-- can't cast on them anyway. When they come back we look at them afresh, so they hear what's
-- missing after the same minute.
--
-- Buffs cast one by one run out one by one. So a giver hears from us at most
-- once a minute (EXPIRY_GAP), and the "runs out" line also names whose buff
-- runs out within a minute after that (EXPIRY_AHEAD), or less for a short
-- buff. A Prayer of Fortitude
-- on each party then makes one whisper rather than eight.
--
-- Out of combat only, like the rest. What ran out in a fight is said once
-- it ends.
local EXPIRY_EVERY = 5
local EXPIRY_GAP = 60
local EXPIRY_AHEAD = 60
local PARTY_SOON = 120
local MISSING_AFTER = 60
local SOON_SHARE = 0.05
-- What we know of each giver's buff on each player, by "giver\tbuff\tplayer":
-- { g, m, b, ends, warn, soon, gone, missing, lacks }. `warn` is how many
-- seconds before `ends` we say it runs out. `soon` and `gone` are "due"
-- until we said them, then "told". `missing` is set when `gone` says the
-- buff is missing rather than that it ran out. `lacks` is when we first saw
-- the buff missing. `ends` is 0 when we never saw it up.
local watch = {}
-- When we last told each giver their buffs run out.
local expiryAt = {}

-- An empty list for a plan that's off. We look every few seconds, so it's
-- made once. Nothing writes to it.
local NONE = {}

-- The givers we may tell, with their assignments of long buffs and
-- blessings: { [name] = { giver, a, ... } }.
local function expiryGivers()
    local givers = {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.plan(job.id)
        for _, a in ipairs(plan and plan.active and plan.list or NONE) do
            local g = a.giver
            local long = a.bless or (a.buff and a.buff.kind == "long")
            if long and not a.spare and not a.backup and not g.me and g.online and not S.hasAddon(g.name) then
                local list = givers[g.name] or { giver = g }
                givers[g.name] = list
                list[#list + 1] = a
            end
        end
    end
    return givers
end

-- `left` seconds as a whisper says them: "40 s" under a minute, else "3 min".
local function leftText(left)
    if left < 60 then return format("%d s", math.max(1, math.ceil(left))) end
    return format("%d min", math.ceil(left / 60))
end

-- The "runs out", "ran out" and "missing" lines of the entries `list` of
-- `giver`.
local function expiryText(giver, list, now)
    local soon, gone, missing, order = {}, {}, {}, {}
    for _, w in ipairs(list) do
        local by = w.gone ~= "due" and soon or w.missing and missing or gone
        local e = by[w.b.id]
        if not e then
            e = { b = w.b, left = math.huge }
            by[w.b.id] = e
            order[#order + 1] = { by = by, id = w.b.id }
        end
        e[#e + 1] = w.m
        if by == soon then e.left = math.min(e.left, w.ends - now) end
    end
    local parts = {}
    for _, o in ipairs(order) do
        local e = o.by[o.id]
        table.sort(e, function(x, y) return x.name < y.name end)
        local name = NS.Buffer.short(Tr.title(e.b))
        if o.by == soon then
            parts[#parts + 1] = format("%s runs out in %s on: %s", name, leftText(e.left), namesText(e, giver))
        elseif o.by == missing then
            parts[#parts + 1] = format("%s missing on: %s", name, namesText(e, giver))
        else
            parts[#parts + 1] = format("%s ran out on: %s", name, namesText(e, giver))
        end
    end
    return TAG .. table.concat(parts, ". ")
end

-- Looks at every giver's buffs, and whispers those who have one running out,
-- just ran out or missing. Returns how many we whispered.
function W.expiry()
    if NS.mock or not R.grouped() or not W.allowed("whisperExpiry") or InCombatLockdown() then return 0 end
    if S.inGroupFor() < SETTLE then return 0 end
    local now = GetTime()
    local at = (O.get("rebuffMinutes") or 0) * 60
    local seen, due = {}, {}
    local party = Tr.party()
    if party then at = math.min(at, PARTY_SOON) end
    for name, list in pairs(expiryGivers()) do
        local g = list.giver
        local near = R.close(g)
        for _, a in ipairs(near and list or NONE) do
            for _, t in ipairs(Du.targets(a)) do
                -- In a party what they have may be another blessing than
                -- the plan's, and that's the one to warn about.
                local m, s, b = t.m, nil, t.b
                if not m.dead and R.close(m) then s, b = Tr.standIn(a, m, t.b) end
                local key = name .. "\t" .. b.id .. "\t" .. m.name
                local w = watch[key]
                if s and s.up and s.expires > 0 then
                    -- A new cast. What we read of the same one can be a
                    -- second or two off what we counted from our own cast.
                    if not w or s.expires > w.ends + 5 then
                        w = { g = g, m = m, b = b, ends = s.expires }
                        watch[key] = w
                    end
                    w.ends = s.expires
                    local dur = tonumber(s.duration) or 0
                    w.warn = dur > 0 and dur * SOON_SHARE or at
                    seen[key] = true
                    if not w.soon and s.expires - now <= w.warn then w.soon = "due" end
                elseif s and not s.up then
                    if not w then
                        w = { g = g, m = m, b = b, ends = 0 }
                        watch[key] = w
                    end
                    seen[key] = true
                    w.lacks = w.lacks or now
                    -- Ran out before we said it runs out: only that it did.
                    if w.soon == "due" then w.soon = "told" end
                    if w.gone then
                        -- Told already, or due to be.
                    elseif w.ends > 0 and not party then
                        w.gone = "due"
                    elseif now - w.lacks >= MISSING_AFTER then
                        w.gone, w.missing = "due", true
                    end
                end
                if seen[key] and (w.soon == "due" or w.gone == "due") then due[name] = true end
            end
        end
    end
    -- What we no longer look at: a player who left, died, went away from
    -- us or got another giver, or a giver who went offline, away from us or
    -- got the addon.
    for key in pairs(watch) do
        if not seen[key] then watch[key] = nil end
    end
    local n = 0
    for name in pairs(due) do
        if not expiryAt[name] or now - expiryAt[name] >= EXPIRY_GAP then
            local list, giver = {}, nil
            for key, w in pairs(watch) do
                if w.g.name == name then
                    giver = w.g
                    local warn = w.warn or at
                    local ahead = not w.soon and not w.gone and w.ends > now
                                  and w.ends - now <= warn + math.min(EXPIRY_AHEAD, warn)
                    if w.gone == "due" or w.soon == "due" or ahead then list[#list + 1] = w end
                end
            end
            local text = giver and #list > 0 and expiryText(giver, list, now)
            for _, w in ipairs(list) do
                if w.gone == "due" then w.gone = "told" else w.soon = "told" end
            end
            if text and queue(name, text, true) then
                expiryAt[name] = now
                n = n + 1
            end
        end
    end
    if n > 0 then tell() end
    return n
end

-- Each board change starts the wait over, and only the last one whispers.
local boardChanges = 0
NS.listen("board", function()
    boardChanges = boardChanges + 1
    local mine = boardChanges
    C_Timer.After(BOARD_WAIT, function()
        if mine == boardChanges then W.all(false) end
    end)
end)
NS.on("PLAYER_REGEN_ENABLED", function()
    if W.forced then
        -- Someone pressed the button or typed /bbc whisper in combat.
        W.forced, W.pending = false, false
        local n = W.all(true, true)
        NS.print(n == 1 and "Whispered 1 player." or "Whispered %d players.", n)
    elseif W.pending then
        W.pending = false
        W.all(false)
    end
end)
NS.on("READY_CHECK", function() W.ready() end)
NS.on("CHAT_MSG_WHISPER", function(_, text, sender) W.answer(text, sender) end)
NS.on("GROUP_LEFT", function()
    forget()
    for k in pairs(asked) do asked[k] = nil end
    for k in pairs(last) do last[k] = nil end
    for k in pairs(nudged) do nudged[k] = nil end
    for k in pairs(watch) do watch[k] = nil end
    for k in pairs(expiryAt) do expiryAt[k] = nil end
    for i = #outbox, 1, -1 do outbox[i] = nil end
    told, W.forced, W.pending = false, false, false
end)
-- What we whispered in this group before a /reload.
NS.listen("loaded", function()
    local k = NS.db.whispers
    if type(k) ~= "table" or type(k.said) ~= "table" or type(k.introduced) ~= "table"
       or time() - (tonumber(k.at) or 0) > KEEP then
        NS.db.whispers = nil
        return
    end
    for name, text in pairs(k.said) do
        if type(name) == "string" and type(text) == "string" then said[name] = text end
    end
    for name, yes in pairs(k.introduced) do
        if type(name) == "string" and yes == true then introduced[name] = true end
    end
    k.said, k.introduced = said, introduced
end)
NS.listen("login", function()
    if not R.real.grouped() then forget() end
    C_Timer.NewTicker(EXPIRY_EVERY, function() W.expiry() end)
end)

NS.command("whisper", "whisper players without the addon their assignments", function() W.request() end)
