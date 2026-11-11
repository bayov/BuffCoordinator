-- What the overrides cost, how each one went (the constraints), what the
-- raid misses (the gaps), and who an assignment covers. It all reads the
-- board Duties.lua works out, through the few of its pieces it hands us as
-- Du.inner.

local _, NS = ...
local D, R, Du = NS.Data, NS.Roster, NS.Duties

local format = string.format
local copy = NS.copy
local andList = NS.andList
local className = NS.className
local classWord = NS.classWord
local upperFirst = NS.upperFirst

local I = Du.inner
local CODES, barred, bname, buffWord = I.CODES, I.barred, I.bname, I.buffWord
local byGroup, isHand, itemsOf, orderKeyWord = I.byGroup, I.isHand, I.itemsOf, I.orderKeyWord
local wanted, computeWith = I.wanted, I.computeWith

-- =============================================================
-- What the overrides cost
-- =============================================================
-- Auto gives everyone what they want as well as it can, by their priority
-- (Blessing Priority, and the data's wants for the rest). An override is a
-- constraint auto works around, and it may leave the raid worse off than
-- auto alone would: someone misses a buff, or gets one they rank lower in
-- place of one they rank higher. That's what we warn about. A change of
-- priority never warns, since it changes what auto aims for, not how well
-- it gets there.
--
-- So we work the board out again without any override (keeping the
-- priorities, what's turned on or off, and the fights), and compare what
-- each player and the target end up with. Each loss belongs to the override
-- that gives it back when it alone is taken away. A loss that no single
-- override gives back (two overrides that each cause it) belongs to every
-- override of its job.
--
-- A loss is red when it leaves someone without a buff ("Rogues miss
-- Might.") and orange when they get one they rank lower instead ("Sham Enh
-- gets Wisdom instead of Might."). The comparison is only worked out when
-- the window asks for it, and kept until the board changes.

-- The overrides a loss can belong to. A blessing order is priority, and a
-- fight's giver set by hand has its own cost on the Assignments page.
local COSTLESS = { on = true, order = true, want = true, fight = true, resist = true, fighton = true }

local function overridesOf(duty)
    local t = {}
    for _, it in ipairs(itemsOf(duty)) do
        if not COSTLESS[it.kind] and isHand(it, it.value) then t[#t + 1] = it end
    end
    return t
end

-- `duty` without its overrides.
local function bare(duty)
    local t = copy(duty)
    for _, it in ipairs(overridesOf(duty)) do Du.putItem(t, it, nil) end
    return t
end

-- What board `b` gives: { [name] = { [buff id] = true }, target = { [debuff
-- id] = true } }. A buff counts on those it reaches who want it, and a
-- blessing on whoever it's given to. The resistances only go up for a
-- fight, which has its own cost.
local function outcomeOf(b, members)
    local got, target = {}, {}
    for _, m in ipairs(members) do
        if m.online then got[m.name] = {} end
    end
    for _, job in ipairs(D.JOBS) do
        local plan = b[job.id]
        if plan and plan.active and job.kind ~= "resist" then
            for _, a in ipairs(plan.list) do
                if a.bless then
                    for name, id in pairs(a.bless) do
                        if got[name] then got[name][id] = true end
                    end
                elseif a.buff and a.buff.debuff then
                    target[a.buff.id] = true
                elseif a.buff then
                    for _, m in ipairs(members) do
                        if got[m.name] and (not a.party or m.group == a.party) and Du.wants(m, a.buff)
                           and not (a.except and Du.wants(m, a.except)) then
                            got[m.name][a.buff.id] = true
                        end
                    end
                end
            end
        end
    end
    return { got = got, target = target }
end

-- Where player `m` ranks buff `b` among those of its family, 1 first, or
-- nil when they don't want it. A blessing goes by Blessing Priority, the
-- rest by the data's order for their role.
local function rankOf(m, b)
    if b.family == "blessing" then
        for i, id in ipairs(Du.blessOrder(m)) do
            if id == b.id then return i end
        end
        return nil
    end
    local fam = b.family and D.FAMILIES[b.family]
    local order = fam and fam.order and (fam.order[m.role] or fam.order.unknown)
    for i, id in ipairs(order or {}) do
        if id == b.id then return i end
    end
    return Du.wants(m, b) and 99 or nil
end

-- Two debuffs that do the same, so one in place of the other is no loss:
-- Faerie Fire and Curse of Recklessness, or the two attack power debuffs.
local function sameEffect(a, b)
    if a.clash and a.clash == b.clash then return true end
    local fam = a.family and a.family == b.family and D.FAMILIES[a.family]
    return fam and fam.per == "one" and not fam.strict or false
end

-- What outcome `now` lacks that outcome `was` has, as { [key] = loss }, a
-- loss being { name (nil for the target), id, instead, level }.
local function lossesOf(now, was, byName)
    local out = {}
    for name, had in pairs(was.got) do
        local m, has = byName[name], now.got[name] or {}
        local lost, gained = {}, {}
        for id in pairs(had) do
            local b = D.BY_ID[id]
            if not has[id] and rankOf(m, b) then lost[#lost + 1] = { b = b, r = rankOf(m, b) } end
        end
        for id in pairs(has) do
            local b = D.BY_ID[id]
            if not had[id] and b.family and rankOf(m, b) then gained[#gained + 1] = { b = b, r = rankOf(m, b) } end
        end
        table.sort(lost, function(x, y) return x.r < y.r end)
        table.sort(gained, function(x, y) return x.r < y.r end)
        -- Whether they still have one of flex family `fam` they want.
        local function flexHeld(fam)
            if not (D.FAMILIES[fam] and D.FAMILIES[fam].flex) then return false end
            for id in pairs(has) do
                local b = D.BY_ID[id]
                if b.family == fam and rankOf(m, b) then return true end
            end
            return false
        end
        for _, l in ipairs(lost) do
            local instead
            for i, g in ipairs(gained) do
                if g.b.family == l.b.family then
                    instead = table.remove(gained, i)
                    break
                end
            end
            -- One they rank at least as high in its place is no loss, and
            -- any one they want of a flex family isn't either.
            if not (instead and instead.r <= l.r) and not flexHeld(l.b.family) then
                out[name .. "\1" .. l.b.id] = { name = name, id = l.b.id, instead = instead and instead.b.id,
                                                level = instead and "low" or "bad" }
            end
        end
    end
    -- On the target, a new debuff takes the place of a lost one when they
    -- share a slot: they clash, like Faerie Fire and Curse of Recklessness,
    -- or they're of one family, like a warlock's curse. Each new debuff
    -- takes the place of one lost debuff at most, and one that does the same
    -- is matched first. So when a warlock goes from Elements to Recklessness
    -- while Faerie Fire goes, Recklessness stands in for Faerie Fire (no
    -- loss) and Elements is missing.
    local function gone(a, b)
        local list = {}
        for id in pairs(a.target) do
            if not b.target[id] then list[#list + 1] = id end
        end
        table.sort(list, function(x, y) return tostring(x) < tostring(y) end)
        return list
    end
    local fresh, lost, instead = gone(now, was), gone(was, now), {}
    for _, same in ipairs({ true, false }) do
        for _, id in ipairs(lost) do
            local b = D.BY_ID[id]
            for i, id2 in ipairs(instead[id] == nil and fresh or {}) do
                local b2 = D.BY_ID[id2]
                local slot = (b.clash and b.clash == b2.clash) or (b.family and b.family == b2.family)
                if slot and sameEffect(b, b2) == same then
                    instead[id] = table.remove(fresh, i)
                    break
                end
            end
        end
    end
    for _, id in ipairs(lost) do
        local x = instead[id]
        if not (x and sameEffect(D.BY_ID[id], D.BY_ID[x])) then
            out["\1" .. id] = { id = id, instead = x, level = x and "low" or "bad" }
        end
    end
    return out
end

-- The families outcomes `a` and `b` differ in, as a set of family keys
-- (and "clash:" keys for the clash pairs), to tell which overrides touch a
-- loss.
local function famKeys(x)
    local b = D.BY_ID[x]
    local keys = { b and b.family or x }
    if b and b.clash then keys[2] = "clash:" .. b.clash end
    return keys
end

local function differ(a, b)
    local fams = {}
    local function mark(id)
        for _, k in ipairs(famKeys(id)) do fams[k] = true end
    end
    local function each(x, y)
        for id in pairs(x) do
            if not y[id] then mark(id) end
        end
    end
    for name, g in pairs(a.got) do
        each(g, b.got[name] or {})
        each(b.got[name] or {}, g)
    end
    each(a.target, b.target)
    each(b.target, a.target)
    return fams
end

local function touches(fams, l)
    for _, k in ipairs(famKeys(l.id)) do
        if fams[k] then return true end
    end
    return false
end

local function short(id)
    return (bname(D.BY_ID[id]):gsub("^Blessing of ", ""))
end

-- Players `names` in words: "everyone" when it's everyone here, a class's
-- plural when it's all of them here ("warriors"), else their names, or "5
-- players" past four. The second value is whether it's one player.
local function whoWords(names, members)
    local set, byClass, here, online = {}, {}, {}, 0
    for _, n in ipairs(names) do set[n] = true end
    for _, m in ipairs(members) do
        if m.online then
            online = online + 1
            here[m.class] = (here[m.class] or 0) + 1
            if set[m.name] then
                byClass[m.class] = byClass[m.class] or {}
                table.insert(byClass[m.class], m.name)
            end
        end
    end
    if #names > 1 and #names == online then return "everyone", true end
    local parts, classes = {}, {}
    for class in pairs(byClass) do classes[#classes + 1] = class end
    table.sort(classes, function(a, b) return D.CLASS_RANK[a] < D.CLASS_RANK[b] end)
    for _, class in ipairs(classes) do
        local list = byClass[class]
        if #list > 1 and #list == here[class] then
            parts[#parts + 1] = classWord(class)
        else
            table.sort(list)
            for _, n in ipairs(list) do parts[#parts + 1] = n end
        end
    end
    if #parts > 4 then return format("%d players", #names), false end
    return andList(parts), #names == 1
end

-- Losses `list` as sentences, the same loss of several players in one.
local function lossLines(list, members)
    local groups, keys = {}, {}
    for _, l in ipairs(list) do
        local k = (l.name and "p" or "t") .. "\1" .. l.level .. "\1" .. l.id .. "\1" .. (l.instead or "")
        if not groups[k] then
            groups[k] = { l = l, names = {} }
            keys[#keys + 1] = k
        end
        if l.name then table.insert(groups[k].names, l.name) end
    end
    table.sort(keys)
    local lines = {}
    for _, k in ipairs(keys) do
        local g = groups[k]
        local l = g.l
        if not l.name then
            lines[#lines + 1] = l.instead
                                and format("%s goes on the target instead of %s.", short(l.instead), short(l.id))
                                or format("No %s on the target.", short(l.id))
        else
            local who, one = whoWords(g.names, members)
            who = upperFirst(who)
            if l.instead then
                lines[#lines + 1] = format("%s %s %s instead of %s.", who, one and "gets" or "get", short(l.instead),
                                           short(l.id))
            else
                lines[#lines + 1] = format("%s %s %s.", who, one and "misses" or "miss", short(l.id))
            end
        end
    end
    return lines
end

-- What the costs were worked out from, as one string: the duty table and
-- the roster. A board signal with the same of both (a join that changed
-- nothing, a resent board) keeps the costs we have.
local function flat(v, out)
    if type(v) ~= "table" then
        out[#out + 1] = tostring(v)
        return
    end
    out[#out + 1] = "{"
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    for _, k in ipairs(keys) do
        out[#out + 1] = tostring(k)
        out[#out + 1] = "="
        flat(v[k], out)
    end
    out[#out + 1] = "}"
end

local function fingerprint(duty, members)
    local out = {}
    flat(duty, out)
    for _, m in ipairs(members) do
        out[#out + 1] = format("|%s,%s,%s,%s,%s,%s", m.name, tostring(m.class), tostring(m.spec),
                               tostring(m.online), tostring(m.group), tostring(m.role))
    end
    return table.concat(out)
end

local costs, checked

-- What the overrides on the board the window shows cost:
--   byKey     { [item key] = { level = "bad" or "low", lines, ids, text } },
--             `ids` the buffs it costs ({ [id] = level }) and `text` the
--             override in words
--   byMember  { [name] = "bad" or "low" }, the players who lose something
--   byFamily  { [family] = { [name] = "bad" or "low" } }, the same by family
--   byJob     { [job id] = "bad" or "low" }, the jobs with a costly override
--   byLoss    { [name .. "\1" .. buff id] = { level, instead, texts } }, each
--             player's loss with the overrides it belongs to, in words
-- Worked out on the first ask after the board changes, and only again when
-- the overrides or the roster changed.
--
-- Taking each override away on its own costs a whole board each, and a
-- raid with blessings set for every paladin has dozens. So we first take
-- away a whole job's overrides at once. A job whose overrides together
-- give nothing back has none of the losses, and we skip its overrides.
-- Then the same with one giver's overrides (a paladin's blessings, a
-- shaman's totems), and only then each override.
function Du.costs()
    if costs and checked then return costs end
    local state = NS.edited()
    local duty = state and state.duty or {}
    local members = Du.shownMembers()
    local sig = fingerprint(duty, members)
    checked = true
    if costs and costs.sig == sig then return costs end
    costs = { byKey = {}, byMember = {}, byFamily = {}, byJob = {}, byLoss = {}, sig = sig }
    local list = overridesOf(duty)
    if #list == 0 then return costs end
    local byName = {}
    for _, m in ipairs(members) do byName[m.name] = m end
    local base = outcomeOf(computeWith(bare(duty), members), members)
    local nowOut = outcomeOf(computeWith(duty, members), members)
    local all = lossesOf(nowOut, base, byName)
    if not next(all) then return costs end
    local mine, has, owned, whose = {}, {}, {}, {}
    local function own(it, k, l)
        has[it.key] = has[it.key] or {}
        if has[it.key][k] then return end
        has[it.key][k] = true
        mine[it.key] = mine[it.key] or {}
        table.insert(mine[it.key], l)
        owned[k] = true
        whose[k] = whose[k] or {}
        table.insert(whose[k], it)
    end
    -- What taking overrides `items` away gives back, and the families it
    -- changes.
    local function without(items)
        local d = copy(duty)
        for _, it in ipairs(items) do Du.putItem(d, it, nil) end
        local out = outcomeOf(computeWith(d, members), members)
        local back = {}
        for k in pairs(lossesOf(out, base, byName)) do back[k] = true end
        local got = {}
        for k in pairs(all) do
            if not back[k] then got[k] = true end
        end
        return got, differ(out, nowOut)
    end
    local function group(items, keyOf)
        local keys, by = {}, {}
        for _, it in ipairs(items) do
            local k = keyOf(it)
            if not by[k] then
                by[k] = {}
                keys[#keys + 1] = k
            end
            table.insert(by[k], it)
        end
        return keys, by
    end
    local function giverOf(it)
        if it.kind == "bless" or it.kind == "assign" or it.kind == "totem" or it.kind == "choice" then return it.a end
        return it.key
    end
    -- Gives the losses `got` (from taking away `items`) to the overrides
    -- among them, going down one level when there are several. A loss the
    -- whole group gives back but none of its parts does belongs to every
    -- override in the group.
    local function split(items, got, level)
        if not next(got) then return end
        if #items == 1 then
            for k in pairs(got) do own(items[1], k, all[k]) end
            return
        end
        local keys, by = group(items, level == "job" and giverOf or function(it) return it.key end)
        if #keys == 1 then return split(items, got, "giver") end
        for _, k in ipairs(keys) do
            split(by[k], without(by[k]), "giver")
        end
        for k in pairs(got) do
            local placed = false
            for _, it in ipairs(items) do
                if has[it.key] and has[it.key][k] then placed = true end
            end
            if not placed then
                for _, it in ipairs(items) do own(it, k, all[k]) end
            end
        end
    end
    local jobKeys, byJob = group(list, function(it) return it.job end)
    local changes = {}
    for _, job in ipairs(jobKeys) do
        local got, fams = without(byJob[job])
        changes[job] = fams
        split(byJob[job], got, "job")
    end
    -- A loss no override gives back on its own (two overrides in different
    -- jobs that cause it together) goes to the overrides of its job, else to
    -- those whose job changes its family, else to every override.
    for k, l in pairs(all) do
        if not owned[k] then
            local to = {}
            for _, it in ipairs(list) do
                if it.job == D.BY_ID[l.id].job then to[#to + 1] = it end
            end
            if #to == 0 then
                for _, it in ipairs(list) do
                    if touches(changes[it.job], l) then to[#to + 1] = it end
                end
            end
            if #to == 0 then to = list end
            for _, it in ipairs(to) do own(it, k, l) end
        end
        if l.name then
            if costs.byMember[l.name] ~= "bad" then costs.byMember[l.name] = l.level end
            local fam = D.BY_ID[l.id].family or l.id
            costs.byFamily[fam] = costs.byFamily[fam] or {}
            if costs.byFamily[fam][l.name] ~= "bad" then costs.byFamily[fam][l.name] = l.level end
        end
    end
    for _, it in ipairs(list) do
        local ls = mine[it.key]
        if ls then
            local level, ids = "low", {}
            for _, l in ipairs(ls) do
                if l.level == "bad" then level = "bad" end
                ids[l.id] = ids[l.id] == "bad" and "bad" or l.level
            end
            costs.byKey[it.key] = { level = level, lines = lossLines(ls, members), ids = ids,
                                    text = Du.itemText(it, it.value) }
            if costs.byJob[it.job] ~= "bad" then costs.byJob[it.job] = level end
        end
    end
    for k, its in pairs(whose) do
        local l = all[k]
        if l.name then
            local texts = {}
            for _, it in ipairs(its) do texts[#texts + 1] = Du.itemText(it, it.value) end
            table.sort(texts)
            costs.byLoss[k] = { level = l.level, instead = l.instead, texts = texts }
        end
    end
    return costs
end

NS.listen("draft", function() checked = false end)
NS.listen("board", function() checked = false end)

-- =============================================================
-- Constraints
-- =============================================================
-- One entry per thing set by hand on the board the window shows, in job
-- order:
--   { key, kind, jobId, text, status, reason, fixes, remove }
-- `status` says how it went:
--   applied   auto went by it
--   absent    who it's about isn't here
--   idle      it's done, but nobody here needs it, so it does nothing
--   blocked   they're here, but it couldn't be done
--   costly    it's done, but leaves someone without a buff auto would have
--             given them (Du.costs)
--   low       it's done, but someone gets a buff they rank lower in place
--             of one they rank higher
-- `reason` says why in a sentence when it isn't applied. `fixes` is a list of
-- { text, fn } to offer, and `remove` takes it off (back to auto).
local function hereWhy(byName, name)
    local m = byName[name]
    if not m then return nil, format("%s isn't here.", name) end
    if not m.online then return nil, format("%s is offline.", name) end
    return m
end

local function assignmentOf(plan, name, test)
    for _, a in ipairs(plan and plan.list or {}) do
        if a.giver.name == name and (not test or test(a)) then return a end
    end
end

local function offWhy(plan, job)
    if plan and plan.code == "off" then return format("%s is turned off.", Du.title(job)) end
    return plan and plan.why or CODES.nobody
end

local statusOf

-- The status of a setting for a whole spec (`holder`, like "spec:PALADIN:1").
-- It goes by its players here who have none of their own, and it's done
-- when it's done for one of them.
local function specStatus(it, holder, byName, members)
    local _, class, tree = Du.splitPick(holder)
    local any, first = false, nil
    for _, m in ipairs(members) do
        if m.online and m.class == class and m.spec == tonumber(tree) then
            any = true
            local own
            if it.kind == "assign" then
                own = Du.assignOf(m.name, it.b)
            elseif it.kind == "totem" then
                own = Du.totem(m.name, it.b)
            else
                own = Du.choice(it.job, m.name)
            end
            if not own then
                local one = { kind = it.kind, job = it.job, value = it.value, a = it.a, b = it.b }
                if it.kind == "choice" then one.b = m.name else one.a = m.name end
                local st, why, fixes = statusOf(one, byName, members)
                if st == "applied" then return st end
                first = first or { st, why, fixes }
            end
        end
    end
    if not any then return "absent", format("No %s here.", Du.pickWords(holder, false)) end
    if not first then return "idle", "Each of them has their own." end
    return first[1], first[2], first[3]
end

function statusOf(it, byName, members)
    local job = D.JOB[it.job]
    local plan = Du.shown(it.job)
    local kind, v = it.kind, it.value
    if kind == "never" then return "applied" end
    -- Nobody here wants the buff, so what's set by hand for it has nothing
    -- to do. That's nothing to fix.
    if plan and not plan.active and plan.code == "unwanted" then return "idle", "Nobody here needs it." end
    if kind == "picks" then
        if plan and plan.code == "off" then
            return "blocked", offWhy(plan, job), { { text = "Turn it on", fn = function() Du.setEnabled(job, true) end } }
        end
        local p = plan and plan.picked
        if p then return p.status, p.status ~= "applied" and p.reason or nil, p.fixes end
        return "blocked", offWhy(plan, job)
    end
    if kind == "order" or kind == "want" then
        local name = it.a:match("^name:(.+)$")
        if name then
            local m, why = hereWhy(byName, name)
            if not m then return "absent", why end
        else
            local class, tree = it.a:match("^(%u+):?(%d*)$")
            local found = false
            for _, m in ipairs(members) do
                if m.online and m.class == class and (tree == "" or m.spec == tonumber(tree)) then found = true end
            end
            if not found then return "absent", format("No %s here.", orderKeyWord(it.a):lower()) end
        end
        if kind == "order" and plan and not plan.active then return "blocked", offWhy(plan, job) end
        return "applied"
    end
    if kind == "resist" then
        local p = Du.preview(it.a)
        local s = p and p.schools and p.schools[it.b]
        if s and s.set then return "applied" end
        local m = byName[v.giver]
        local why = p and p.handWhy and p.handWhy[it.b]
        if not m or not m.online then return "absent", why or select(2, hereWhy(byName, v.giver)) end
        return "blocked", why or format("%s can't put it up.", v.giver)
    end
    local holder = (kind == "assign" or kind == "totem") and it.a or kind == "choice" and it.b or nil
    if Du.isSpecKey(holder) then return specStatus(it, holder, byName, members) end
    if kind == "assign" then
        local m, why = hereWhy(byName, it.a)
        if not m then return "absent", why end
        if plan and not plan.active then return "blocked", offWhy(plan, job) end
        if not (plan.pool and plan.pool[it.a]) then
            return "blocked", plan.poolWhy and plan.poolWhy[it.a] or format("%s isn't blessing.", it.a)
        end
        local w = plan.assignWhy and plan.assignWhy[it.a] and plan.assignWhy[it.a][it.b]
        if w then return w.level == "bad" and "blocked" or "idle", table.concat(w.lines, " ") end
        return "applied"
    end
    -- A choice, a totem or a blessing cell: about one player.
    local name = kind == "choice" and it.b or it.a
    local m, why = hereWhy(byName, name)
    if not m then return "absent", why end
    if kind == "bless" then
        local any = false
        for _, x in ipairs(members) do
            if x.online and x.class == it.b then any = true end
        end
        if not any then return "absent", format("No %s here.", classWord(it.b)) end
    end
    if plan and not plan.active then return "blocked", offWhy(plan, job) end
    if kind == "choice" then
        if v == "none" then return "applied" end
        if assignmentOf(plan, name, function(a) return a.buff and a.buff.id == v end) then return "applied" end
        return "blocked", plan.choiceWhy and plan.choiceWhy[name]
                          or format("%s can't put up %s.", name, buffWord(v))
    end
    if kind == "totem" then
        if v == "none" then return "applied" end
        if assignmentOf(plan, name, function(a) return a.buff and a.buff.id == v end) then return "applied" end
        return "blocked", plan.cellWhy and plan.cellWhy[name .. "\1" .. it.b]
                          or format("%s can't put down %s.", name, buffWord(v))
    end
    if kind == "bless" then
        if not (plan.pool and plan.pool[name]) then
            return "blocked", plan.poolWhy and plan.poolWhy[name] or format("%s isn't blessing.", name)
        end
        local g = plan.byClass and plan.byClass[name]
        if v == "none" or (g and g[it.b] == v) then return "applied" end
        return "blocked", plan.cellWhy and plan.cellWhy[name .. "\1" .. it.b]
                          or format("%s can't give %s.", name, buffWord(v))
    end
    return "applied"
end

function Du.constraints()
    local state = NS.edited()
    local members = Du.shownMembers()
    local byName = {}
    for _, m in ipairs(members) do byName[m.name] = m end
    local out = {}
    for _, it in ipairs(itemsOf(state and state.duty or {})) do
        -- An assignment turned on or off by hand is listed too, when that
        -- isn't how it starts ("Thorns is turned off"), so the leader can
        -- find it again. Its cross puts it back as it starts.
        local job = D.JOB[it.job]
        local turned = it.kind == "on" and job ~= nil and it.value ~= not job.optional
        if turned then
            out[#out + 1] = { key = it.key, kind = it.kind, jobId = it.job, value = it.value,
                              text = Du.itemText(it, it.value), status = "applied", fixes = {},
                              remove = function()
                                  Du.applyItems({ { kind = it.kind, job = it.job, a = it.a, b = it.b } })
                              end }
        elseif isHand(it, it.value) then
            local status, reason, fixes = statusOf(it, byName, members)
            local cost = status == "applied" and Du.costs().byKey[it.key]
            if cost then
                status, reason = cost.level == "bad" and "costly" or "low", table.concat(cost.lines, " ")
            end
            local c = { key = it.key, kind = it.kind, jobId = it.job, a = it.a, b = it.b, value = it.value,
                        text = Du.itemText(it, it.value), status = status, reason = reason }
            -- A fight's giver set by hand goes back to auto's giver, and the
            -- fight still asks for the school.
            local back = it.kind == "resist" or nil
            c.remove = function()
                Du.applyItems({ { kind = it.kind, job = it.job, a = it.a, b = it.b, v = back } })
            end
            c.fixes = fixes and copy(fixes) or {}
            if status ~= "applied" and #c.fixes == 0 then
                c.fixes[1] = { text = "Back to auto", fn = c.remove }
            end
            if it.kind == "picks" then
                local plan = Du.shown(it.job)
                c.note = plan and plan.picked and plan.picked.note
            end
            out[#out + 1] = c
        end
    end
    return out
end

-- =============================================================
-- Gaps
-- =============================================================
-- What the raid wants and nobody gives, on the board the window shows, as
-- { jobId, buff, what, why, text }: `what` is the buff or the assignment
-- ("Power Word: Fortitude"), `why` the reason ("No priest here.") and
-- `text` both in one line ("No Power Word: Fortitude: no priest here.").
-- The raid-wide totems count one by one, since the totems job is never
-- empty while a shaman is here.
--
-- A talent buff isn't a gap while someone who could give it has a spec we
-- don't know. They may well have the talent, and we'd only cry wolf.
local function unknownTalent(options, members, never)
    for _, id in ipairs(options) do
        local b = D.BY_ID[id]
        if b.talent then
            for _, m in ipairs(members) do
                if m.online and m.class == b.class and m.spec == nil and not barred(never, m) then return true end
            end
        end
    end
    return false
end

-- The lowest level a buff of `options` that player `m`'s class gives is
-- learned at, when `m` is below it. nil when they have the level.
local function tooLow(options, m)
    local need
    for _, id in ipairs(options) do
        local b = D.BY_ID[id]
        local lv = b.class == m.class and Du.needsLevel(b)
        if lv and m.level and m.level < lv and (not need or lv < need) then need = lv end
    end
    return need
end

-- "No priest here is level 30 yet." when every player of `classes` here is
-- too low for `options`, else nil.
local function lowWhy(classes, members, options)
    local need, class = nil, nil
    for _, m in ipairs(members) do
        if m.online and classes[m.class] then
            local lv = tooLow(options, m)
            if not lv then return nil end
            if not need or lv < need then need, class = lv, m.class end
        end
    end
    return need and format("No %s here is level %d yet.", className(class):lower(), need) or nil
end
Du.lowWhy = lowWhy

-- Why nobody gives it, as a sentence. `can(m)` is whether `m` could give it.
-- `never` is who the job never goes to, and `options` the buffs it's of.
local function gapWhy(classes, members, can, never, options)
    local present, able, kept = false, false, {}
    for _, m in ipairs(members) do
        if m.online and classes[m.class] then
            present = true
            if can(m) then
                if barred(never, m) then
                    kept[#kept + 1] = m.name
                else
                    able = true
                end
            end
        end
    end
    if not present then
        local words = {}
        for class in pairs(classes) do words[#words + 1] = className(class):lower() end
        table.sort(words)
        return format("No %s here.", andList(words, "or"))
    end
    if able then return "Everyone who can give it is busy." end
    if #kept > 0 then
        table.sort(kept)
        return format("%s %s set to never do it.", andList(kept), #kept == 1 and "is" or "are")
    end
    return lowWhy(classes, members, options or {}) or "Nobody here has the talent for it."
end

-- The words that start a reason which isn't a player's name, lowered in
-- `text`.
local GAP_WORDS = { No = true, Nobody = true, Everyone = true, Every = true }

local function gap(t, jobId, what, why, buff)
    local lead = why:match("^(%a+)")
    local mid = GAP_WORDS[lead] and why:sub(1, 1):lower() .. why:sub(2) or why
    t[#t + 1] = { jobId = jobId, buff = buff, what = what, why = why, text = format("No %s: %s", what, mid) }
    return t[#t]
end

-- Why a buff of `options` is missing when the fight on now is the reason:
-- every player who could give it puts up a resistance in that slot instead,
-- like both paladins on resistance auras for Ragnaros. nil when someone
-- who could is free or busy with something else.
local function fightWhy(classes, members, options, never)
    local plan = Du.shown("resistances")
    if not (plan and plan.active and plan.fight) then return nil end
    local function heldBy(m)
        for _, a in ipairs(plan.list) do
            if a.giver.name == m.name then
                for _, id in ipairs(options) do
                    local b = D.BY_ID[id]
                    if Du.canGive(m, b) and ((b.family and a.buff.family == b.family)
                                            or (b.element and a.buff.element == b.element)) then
                        return a
                    end
                end
            end
        end
    end
    local held = {}
    for _, m in ipairs(members) do
        if m.online and classes[m.class] and not barred(never, m) then
            local can = false
            for _, id in ipairs(options) do can = can or Du.canGive(m, D.BY_ID[id]) end
            if can then
                local a = heldBy(m)
                if not a then return nil end
                held[#held + 1] = a
            end
        end
    end
    if #held == 0 then return nil end
    if #held == 1 then
        return format("%s puts up %s for %s.", held[1].giver.name, bname(held[1].buff), plan.fight)
    end
    local names = {}
    for _, a in ipairs(held) do names[#names + 1] = a.giver.name end
    table.sort(names)
    return format("%s put up resistances for %s.", andList(names), plan.fight)
end

-- Whether another job gives a buff that excludes one of `job`'s, so `job`
-- has nothing left to give: with a Feral druid's Leader of the Pack up,
-- nobody misses Moonkin Aura.
local function excludedUp(job)
    for _, id in ipairs(job.options) do
        local b = D.BY_ID[id]
        local ex = b.excludes and D.BY_ID[b.excludes]
        if ex and ex.job ~= job.id then
            local p = Du.shown(ex.job)
            if p and p.active then return true end
        end
    end
    return false
end

function Du.gaps()
    local members = Du.shownMembers()
    local t = {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.shown(job.id)
        local never = Du.never(job.id)
        if job.kind ~= "totem" and plan and not plan.active
           and (plan.code == "nobody" or plan.code == "absent")
           and not unknownTalent(job.options, members, never) and not excludedUp(job) then
            local classes = {}
            for _, id in ipairs(job.options) do classes[D.BY_ID[id].class] = true end
            local why = gapWhy(classes, members, function(m)
                for _, id in ipairs(job.options) do
                    if Du.canGive(m, D.BY_ID[id]) then return true end
                end
                return false
            end, never, job.options)
            if why == "Everyone who can give it is busy." then
                why = fightWhy(classes, members, job.options, never) or why
            end
            gap(t, job.id, Du.title(job), why).code = plan.code
        end
    end
    local tp = Du.shown("totems")
    if tp and tp.code ~= "off" then
        for _, id in ipairs({ "windfury", "strengthofearth", "graceofair" }) do
            local b = D.BY_ID[id]
            local placed = false
            for _, a in ipairs(tp.list) do
                if a.buff == b then placed = true end
            end
            if not placed and wanted(b, members) then
                local why = gapWhy({ SHAMAN = true }, members, function(m) return Du.canGive(m, b) end, nil, { id })
                if why == "Everyone who can give it is busy." then
                    why = fightWhy({ SHAMAN = true }, members, { id })
                          or format("Every shaman's %s totem is taken.", b.element)
                end
                gap(t, "totems", bname(b), why, id)
            end
        end
    end
    -- A gap an override causes says so, and which: "Sham Enh puts down no
    -- air totem." It's what to take back to fill it. A reason that already
    -- names the Nevers stays as it is.
    local byKey = Du.costs().byKey
    local keys = {}
    for k in pairs(byKey) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, g in ipairs(t) do
        for _, k in ipairs(keys) do
            local c = byKey[k]
            for id, level in pairs(c.ids) do
                if not g.cost and (id == g.buff or (not g.buff and D.BY_ID[id].job == g.jobId)) then
                    g.cost = level
                    if not g.why:find("set to never do it%.$") then
                        g.why = upperFirst(c.text) .. "."
                        g.text = format("No %s: %s", g.what, g.why)
                    end
                end
            end
        end
    end
    return t
end

-- =============================================================
-- Who an assignment covers
-- =============================================================
-- Orders Du.targets' list by the players' groups. It's made once, since the
-- HUD asks for every assignment's players twice a second.
local function byMember(x, y) return byGroup(x.m, y.m) end

-- The players assignment `a` puts its buff on, as a list of { m, b }: the
-- blessings by person, or everyone it reaches who wants it. An aura covers
-- its giver, and a debuff covers the target, which gives an empty list.
function Du.targets(a)
    local t = {}
    if a.job.scope == "target" then return t end
    -- A blessing backup: what the others give the classes it backs up.
    if a.spare then
        for _, x in ipairs(a.spare) do
            if x.m.online then t[#t + 1] = x end
        end
        table.sort(t, byMember)
        return t
    end
    -- An aura is the giver's to keep up, and what we watch is whether they
    -- have it.
    if a.buff and a.buff.aura then
        if a.giver.online then t[1] = { m = a.giver, b = a.buff } end
        return t
    end
    for _, m in ipairs(Du.shownMembers()) do
        if m.online then
            if a.bless then
                local id = a.bless[m.name]
                if id then t[#t + 1] = { m = m, b = D.BY_ID[id] } end
            elseif (not a.party or m.group == a.party) and Du.wants(m, a.buff)
                   and not (a.except and Du.wants(m, a.except)) then
                t[#t + 1] = { m = m, b = a.buff }
            end
        end
    end
    table.sort(t, byMember)
    return t
end

-- =============================================================
-- What one player gets
-- =============================================================
-- Everything player `m` wants on the board the window shows, sorted three
-- ways, for the You box on the Assignments page:
--   got   what reaches them, as { b, from, target }. `from` is the giver,
--         and `target` is set for a debuff on the target.
--   wont  what someone here could give them, but this setup doesn't, as
--         { b, why, level }. `level` is the override's cost ("bad" or
--         "low") when an override is why.
--   cant  what nobody here can give, as { b, why }
-- A debuff counts when it's one they gain from. One in place of another
-- that does the same (Recklessness for Faerie Fire) isn't missing.
--
-- Can't is only when nobody here has the class or the talent. Everything
-- else could change with the setup, even a third blessing with two
-- paladins here, since one of them could give it in place of another.

-- What a buff takes the place of: a giver's one of a family ("blessing"),
-- or a shaman's one totem of an element.
local SLOT_WORD = { blessing = "blessing", paladinAura = "aura", airTotem = "air totem", curse = "curse",
                    judgement = "judgement" }

local function slotOf(b)
    local fam = b.family and D.FAMILIES[b.family]
    if fam and fam.per == "giver" then return b.family, SLOT_WORD[b.family] or "buff" end
    if b.element then return "totem:" .. b.element, b.element .. " totem" end
end

-- Whether a debuff on the target does what `b` would: one of its family
-- when the target holds one of the family only, or one it clashes with.
local function covered(b, on)
    local fam = b.family and D.FAMILIES[b.family]
    for id in pairs(on) do
        local x = D.BY_ID[id]
        if x ~= b and ((fam and fam.per == "one" and x.family == b.family) or (b.clash and x.clash == b.clash)) then
            return true
        end
    end
    return false
end

-- The buffs `m` wants, in the page's order: their blessings by Blessing
-- Priority, then each job's.
local function wantList(m)
    local list, seen = {}, {}
    local function add(b)
        if b and not seen[b.id] then
            seen[b.id] = true
            list[#list + 1] = b
        end
    end
    for _, id in ipairs(Du.blessOrder(m)) do add(D.BY_ID[id]) end
    for _, job in ipairs(D.JOBS) do
        if job.kind ~= "blessing" and job.kind ~= "resist" then
            for _, id in ipairs(job.options) do
                local b = D.BY_ID[id]
                if not b.school and Du.wants(m, b, true) then add(b) end
            end
        end
    end
    return list
end

-- Where `b` comes in its job's options, to tell which of two that exclude
-- each other is the better.
local function place(b)
    for i, id in ipairs(D.JOB[b.job].options) do
        if id == b.id then return i end
    end
    return 99
end

-- Why nobody gives `b` to `m` though `able` could. `from` is who gives `m`
-- what, `on` who puts what on the target, `holds` what slot (slotOf) each
-- giver fills and `busy` the first thing each giver does.
local function wontWhy(m, b, able, members, from, on, holds, busy)
    local job = D.JOB[b.job]
    if not Du.enabled(job) then return "Turned off." end
    local loss = Du.costs().byLoss[m.name .. "\1" .. b.id]
    if loss then
        local why = upperFirst(andList(loss.texts)) .. "."
        if loss.instead then why = format("You get %s instead. %s", bname(D.BY_ID[loss.instead]), why) end
        return why, loss.level
    end
    local reach = {}
    for _, x in ipairs(able) do
        if not (job.scope == "party" or b.party) or x.group == m.group then reach[#reach + 1] = x end
    end
    if #reach == 0 then
        local by, parties = {}, {}
        for _, x in ipairs(able) do
            if not by[x.group] then
                by[x.group] = {}
                parties[#parties + 1] = x.group
            end
            table.insert(by[x.group], x.name)
        end
        table.sort(parties)
        local parts = {}
        for _, g in ipairs(parties) do parts[#parts + 1] = format("%s in group %d", andList(by[g]), g) end
        return format("No %s in your group. %s can.", className(b.class):lower(), andList(parts, "or"))
    end
    local never, free = Du.never(job.id), {}
    for _, x in ipairs(reach) do
        if not barred(never, x) then free[#free + 1] = x end
    end
    if #free == 0 then
        local names = {}
        for _, x in ipairs(reach) do names[#names + 1] = x.name end
        return format("%s %s set to never do it.", andList(names), #names == 1 and "is" or "are")
    end
    -- Each giver who could already fills the slot `b` needs.
    local slot, word = slotOf(b)
    if slot then
        local taken, mine = {}, true
        for _, x in ipairs(free) do
            local held
            if slot == "blessing" then
                for id, g in pairs(from) do
                    if g.name == x.name and D.BY_ID[id].family == "blessing" then held = D.BY_ID[id] end
                end
            else
                held = holds[x.name] and holds[x.name][slot]
            end
            if not held then
                taken = nil
                break
            end
            taken[#taken + 1] = bname(held)
            if not (from[held.id] or on[held.id]) then mine = false end
        end
        if taken then
            table.sort(taken)
            local lead = b.debuff and "The target gets" or mine and "You get" or "They put down"
            if not b.debuff and not mine and not b.element then lead = "They put up" end
            return format("One %s per %s. %s %s.", word, className(b.class):lower(), lead, andList(taken))
        end
    end
    local names = {}
    for _, x in ipairs(free) do
        if busy[x.name] then names[#names + 1] = format("%s on %s", x.name, bname(busy[x.name])) end
    end
    if #names == #free then return format("Everyone who could is busy: %s.", andList(names)) end
    local plan = Du.shown(job.id)
    return plan and plan.why or "Not in this setup."
end

-- Whether `from` (who gives a player what they want) has another of `b`'s
-- family, when that family is flex (Data.lua). A resistance aura for a
-- fight doesn't count, since it isn't what they want. It's what the fight
-- takes their aura for.
local function flexFrom(b, from)
    local fam = b.family and D.FAMILIES[b.family]
    if not (fam and fam.flex) then return false end
    for id in pairs(from) do
        local x = D.BY_ID[id]
        if id ~= b.id and x.family == b.family and not x.school then return true end
    end
    return false
end

function Du.player(m)
    local out = { got = {}, wont = {}, cant = {} }
    if not m then return out end
    local members = Du.shownMembers()
    for _, x in ipairs(members) do
        if x.name == m.name then m = x end
    end
    -- What reaches them and from whom, what's on the target, what slots
    -- each giver fills and the first thing each does.
    local from, on, holds, busy = {}, {}, {}, {}
    for _, job in ipairs(D.JOBS) do
        local plan = Du.shown(job.id)
        for _, a in ipairs(plan and plan.active and plan.list or {}) do
            local b
            -- A paladin's resistance aura for the fight reaches only their
            -- party, like their usual aura.
            local party = a.party or job.kind == "resist" and a.buff.family == "paladinAura" and a.giver.group or nil
            if a.bless then
                b = a.bless[m.name] and D.BY_ID[a.bless[m.name]]
            elseif a.buff and a.buff.debuff then
                on[a.buff.id] = a.giver
                b = Du.wants(m, a.buff) and a.buff
            elseif a.buff and (not party or party == m.group) and Du.wants(m, a.buff)
                   and not (a.except and Du.wants(m, a.except)) and (a.giver.online or not a.buff.aura) then
                b = a.buff
            end
            if b and not from[b.id] then from[b.id] = a.giver end
            if a.giver and a.buff then
                local slot = slotOf(a.buff)
                if slot then
                    holds[a.giver.name] = holds[a.giver.name] or {}
                    holds[a.giver.name][slot] = holds[a.giver.name][slot] or a.buff
                end
                busy[a.giver.name] = busy[a.giver.name] or a.buff
            end
        end
    end
    for _, b in ipairs(wantList(m)) do
        local ex = b.excludes and D.BY_ID[b.excludes]
        if from[b.id] then
            out.got[#out.got + 1] = { b = b, from = from[b.id], target = b.debuff or nil }
        elseif not Du.canTake(m, b) then
            out.cant[#out.cant + 1] = { b = b, why = format("You need level %d for it.", b.ranks[2] - Du.RANK_REACH) }
        elseif b.debuff and covered(b, on) then
            -- Another debuff does what it would.
        elseif ex and from[ex.id] and (ex.job ~= b.job or place(ex) < place(b)) then
            -- The better of two that exclude each other is up. Two in jobs
            -- of their own, like Leader of the Pack and Moonkin Aura, are as
            -- good as each other, so either one is enough.
        elseif flexFrom(b, from) then
            -- Another of a flex family they want is up, like Devotion Aura
            -- for a melee who'd take Retribution too.
        else
            local able, here = {}, false
            for _, x in ipairs(members) do
                if Du.canGive(x, b) then able[#able + 1] = x end
                if x.online and x.class == b.class then here = true end
            end
            if #able == 0 then
                local why = not here and format("No %s here.", className(b.class):lower())
                            or lowWhy({ [b.class] = true }, members, { b.id })
                            or "Nobody here is known to have the talent."
                out.cant[#out.cant + 1] = { b = b, why = why }
            else
                local why, level = wontWhy(m, b, able, members, from, on, holds, busy)
                out.wont[#out.wont + 1] = { b = b, why = why, level = level }
            end
        end
    end
    -- The fight's resistances that reach them. Nobody wants those but for
    -- the fight, so they aren't in wantList.
    local fight = Du.shown("resistances")
    for _, a in ipairs(fight and fight.active and fight.list or {}) do
        if from[a.buff.id] then out.got[#out.got + 1] = { b = a.buff, from = from[a.buff.id] } end
    end
    return out
end
