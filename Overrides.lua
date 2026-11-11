-- The Overrides page of the assignments window (Config.lua): every
-- override as a card.
--
-- An override says what one giver does: Mira gives Fortitude, Thrall puts
-- down Windfury Totem, Pal Holy covers Kings for whoever needs it. A giver
-- can be a whole spec too, like Holy paladins, and a player's own override
-- wins over their spec's. A giver who isn't here shows dimmed. Auto
-- gives everyone what they want (Buffs by Spec and Blessing Priority) and
-- works around the overrides.
--
-- A card is a row of dropdowns, each changed on its own:
--   Blessings  the paladin, the blessing, who it's for (whoever needs it,
--              a class, a spec or a player) and Forced, which gives it to
--              all of them, wanted or not (Du.assigns).
--   The rest   the giver, what they give, and Never, which keeps them off
--              it even in auto (Du.giverCards). Several givers on a job one
--              player does go in order, the second when the first can't.
-- and a cross that puts it back to auto.
--
-- "Add override" adds an empty card at the end, and so does a player
-- dragged here from the raid pane, with them as its giver. The empty card
-- is only ours until it has a giver and what they do. Then it becomes a
-- real override and goes where its kind goes in the list.
--
-- A card that didn't go as set says why on a line of its own. It's red when
-- it can't be done, or when it leaves someone without a buff auto would
-- have given them, and orange when someone gets a buff they rank lower for
-- it (Du.constraints, from Du.costs). A Fix it button offers the fixes.
-- The cards on Assignments name the override behind what it costs them, and
-- the Overrides tab has a red dot while one goes wrong.

local _, NS = ...
local D, R, Du, T, Tr = NS.Data, NS.Roster, NS.Duties, NS.Theme, NS.Tracking

local format = string.format
local min, max, floor = math.min, math.max, math.floor
local upperFirst, classWord = NS.upperFirst, NS.classWord

local Ov = {}
NS.Overrides = Ov

local ICON = 20
-- A card is as wide as the page. Its row of dropdowns has the same gap
-- (PAD) round each one and between them, the cross's square too.
local ROW_H, PAD, CARD_GAP = 32, 4, 6
local PART_H = ROW_H - 2 * PAD
-- The box (Forced or Never), before the cross.
local BOX_W = 70
-- A card's dropdowns: the giver, then the blessing and who it's for, or
-- what the giver does. The giver's grows a little with the card.
local GIVER_X, BLESS_W = PAD, ICON + 22
local CLASSES = D.CLASSES
local PLACE = { "1st", "2nd", "3rd", "4th", "5th" }

-- The cards being filled in, ours only: { giver = name or nil }, in the
-- order they were added.
local fresh = {}
-- The override a filled-in card just became, to flash when it shows:
-- { giver = pick, job = job id }.
local landed

local function canChange() return NS.Config.canChange() end
local function redraw() NS.soon("configRefresh", 0.05, NS.Config.refresh) end

-- The class of `name`, here or remembered.
local function classOf(name)
    local m = R.known(name)
    return m and m.class or nil
end

local function colored(name) return NS.classColored(name, classOf(name)) end

local NOT_HERE = " " .. T.hex(T.COLOR.idle) .. "(not here)|r"

-- A giver (a pick) for a card or a menu: the player after their icon, or "A
-- warlock" or "An Affliction warlock" for an older pick of a class or spec.
local function giverLabel(pick)
    local kind, a, b = Du.splitPick(pick)
    if kind == "name" then return NS.who(a) end
    local words = upperFirst(Du.pickWords(pick, true))
    if kind == "spec" then return NS.specText(a, tonumber(b), words) end
    return NS.classText(a, words)
end

-- Who override target `t` is, for a card or a menu: "Whoever needs it" (or
-- "Everyone" when it's forced), or "Warriors", "Fury warriors" or "Grom"
-- after their icon.
local function targetLabel(t, force)
    local kind, a, b = Du.splitPick(t)
    if kind == "name" then return NS.who(a) end
    local words = upperFirst(Du.targetWords(t, force and t == "all"))
    if kind == "class" then return NS.classText(a, words) end
    if kind == "spec" then return NS.specText(a, tonumber(b), words) end
    return words
end

-- =============================================================
-- Menus
-- =============================================================
-- The players here by class, by name.
local function here()
    local by = {}
    for _, m in ipairs(Du.shownMembers()) do
        by[m.class] = by[m.class] or {}
        table.insert(by[m.class], m)
    end
    for _, list in pairs(by) do
        table.sort(list, function(a, b) return a.name < b.name end)
    end
    return by
end

-- The players of `classes` (a set) here, then the ones we remember, as
-- { name, m, away }.
local function people(classes)
    local list = {}
    local by = here()
    for _, class in ipairs(CLASSES) do
        for _, m in ipairs(classes[class] and by[class] or {}) do list[#list + 1] = { name = m.name, m = m } end
    end
    for _, p in ipairs(R.remembered(classes)) do list[#list + 1] = { name = p.name, m = p, away = true } end
    return list
end

local function personLabel(p)
    return NS.who(p.m or p.name) .. (p.away and NOT_HERE or "")
end

-- The names of `class` we know who aren't here, for completing a typed
-- name: the people we grouped with, and the players of every plan.
local function knownNames(class)
    local t, seen = {}, {}
    local function add(name, c)
        if type(name) == "string" and not seen[name] and c == class and not R.byName(name) then
            seen[name] = true
            t[#t + 1] = name
        end
    end
    for name, p in pairs(NS.db.people or {}) do
        if type(p) == "table" then add(name, p.class) end
    end
    for _, plan in ipairs(NS.Plans.list()) do
        for _, p in ipairs(NS.Plans.get(plan).members or {}) do add(p.name, p.class) end
    end
    table.sort(t)
    return t
end

-- =============================================================
-- Typing a name
-- =============================================================
-- "Type a name" in a card's dropdown turns the dropdown into a box to type
-- a player's name. A list under it offers the names that start with
-- what's typed: the players of the class here, the ones we know who
-- aren't, then the game's own (friends, guild, the people we played with
-- lately). Up and
-- Down pick one, Tab fills it in, and Enter takes the picked one or else
-- what's typed. Escape or a click elsewhere leaves the dropdown as it was.
local SUGGEST = 6
-- What's being typed for: { key (the card's), what (its part), class,
-- apply (runs with the name) }, and the box.
local typing, box

-- The game's names that start with `text`, when it can tell us. Newer
-- clients give a table of { name, priority }, older ones the names.
local function gameNames(text)
    local all = _G.AUTOCOMPLETE_LIST and _G.AUTOCOMPLETE_LIST.ALL
    if text == "" or not (_G.GetAutoCompleteResults and all) then return {} end
    local ok, res = pcall(function()
        return { _G.GetAutoCompleteResults(text, SUGGEST, #text, false, all.include, all.exclude) }
    end)
    if not ok then return {} end
    local t = {}
    for _, x in ipairs(type(res[1]) == "table" and res[1] or res) do
        local name = type(x) == "table" and x.name or x
        if type(name) == "string" then t[#t + 1] = name end
    end
    return t
end

-- The names to offer for `text` when typing a player of `class`.
local function suggestions(class, text)
    local t, seen, lower = {}, {}, text:lower()
    local function add(name)
        if #t < SUGGEST and not seen[name] and name:lower():sub(1, #lower) == lower then
            seen[name] = true
            t[#t + 1] = name
        end
    end
    for _, m in ipairs((here())[class] or {}) do add(m.name) end
    for _, name in ipairs(knownNames(class)) do add(name) end
    for _, name in ipairs(gameNames(text)) do add(name) end
    return t
end

local stopTyping

-- Takes `name` as typed. A name we didn't know keeps its class, for the
-- card to show.
local function takeName(name)
    name = (name or ""):match("^%s*(.-)%s*$"):gsub("%s+", " ")
    local t = typing
    stopTyping()
    if not t or name == "" then return end
    local p = NS.db.people[name]
    if not R.byName(name) and type(p) ~= "table" then NS.db.people[name] = { class = t.class } end
    t.apply(name)
end

local function nameBox()
    if box then return box end
    local e = T.edit(UIParent, 100, PART_H)
    e:SetJustifyH("LEFT")
    e:SetMaxLetters(40)
    e:Hide()
    e.hint = T.text(e, T.SIZE.body, false, T.A_DIM)
    e.hint:SetPoint("LEFT", e, "LEFT", 6, 0)
    e.list = CreateFrame("Frame", nil, e)
    e.list:SetFrameStrata("FULLSCREEN_DIALOG")
    e.list.bg = T.fill(e.list, { 0.07, 0.08, 0.10 }, 0.98)
    e.list.bg:SetAllPoints(e.list)
    T.border(e.list, { 1, 1, 1 }, 0.18)
    e.list:SetPoint("TOPLEFT", e, "BOTTOMLEFT", 0, -2)
    e.list:Hide()
    e.rows, e.names, e.sel = {}, {}, 0
    local ROW = 20
    -- The list as it is for what's typed now, with the picked name lit.
    function e.paint()
        local text = e:GetText() or ""
        e.hint:SetShown(text == "")
        e.names = suggestions(typing and typing.class, text:match("^%s*(.-)%s*$"))
        if e.sel > #e.names then e.sel = #e.names end
        local a = T.ACCENT
        for i, name in ipairs(e.names) do
            local r = e.rows[i]
            if not r then
                r = CreateFrame("Button", nil, e.list)
                r:SetHeight(ROW)
                r:SetPoint("TOPLEFT", e.list, "TOPLEFT", 1, -1 - (i - 1) * ROW)
                r:SetPoint("RIGHT", e.list, "RIGHT", -1, 0)
                r.sel = T.fill(r, a, 0.16, "BORDER")
                r.sel:SetAllPoints(r)
                r.hl = T.fill(r, { 1, 1, 1 }, 0.06)
                r.hl:SetAllPoints(r)
                r.hl:Hide()
                r.text = T.text(r, T.SIZE.body, false, T.A_TEXT)
                r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
                r:SetScript("OnEnter", function(self) self.hl:Show() end)
                r:SetScript("OnLeave", function(self) self.hl:Hide() end)
                r:SetScript("OnClick", function(self) takeName(self.name) end)
                e.rows[i] = r
            end
            r.name = name
            r.text:SetText(NS.who(name))
            r.sel:SetColorTexture(a[1], a[2], a[3], 0.16)
            r.sel:SetShown(i == e.sel)
            r:Show()
        end
        for i = #e.names + 1, #e.rows do e.rows[i]:Hide() end
        e.list:SetSize(max(e:GetWidth() or 0, 180), #e.names * ROW + 2)
        e.list:SetShown(#e.names > 0)
    end
    e:SetScript("OnTextChanged", function(self, user)
        if user then self.sel = 0 end
        self.paint()
    end)
    e:SetScript("OnArrowPressed", function(self, key)
        if key == "DOWN" then self.sel = min(self.sel + 1, #self.names) end
        if key == "UP" then self.sel = max(self.sel - 1, 0) end
        self.paint()
    end)
    e:SetScript("OnTabPressed", function(self)
        local name = self.names[max(self.sel, 1)]
        if name then
            self:SetText(name)
            self:SetCursorPosition(#name)
            self.sel = 1
            self.paint()
        end
    end)
    e:SetScript("OnEnterPressed", function(self) takeName(self.names[self.sel] or self:GetText()) end)
    e:SetScript("OnEscapePressed", function() stopTyping() end)
    -- A click on a name in the list takes the focus first, and the click
    -- still takes the name.
    e.onFocusLost = function()
        if typing and not e.list:IsMouseOver() then stopTyping() end
    end
    box = e
    return e
end

function stopTyping()
    typing = nil
    if not box then return end
    box:Hide()
    box:ClearFocus()
end

-- Puts the box over part `part` of a card.
local function placeBox(part)
    local e = nameBox()
    e:SetParent(part)
    e:ClearAllPoints()
    e:SetAllPoints(part)
    e:SetFrameLevel(part:GetFrameLevel() + 5)
end

-- Turns dropdown `owner` of a card into the box, to type a player of
-- `class`, and runs `fn(name)` with what's taken.
local function startTyping(owner, class, fn)
    local c = owner:GetParent()
    typing = { key = c.key, what = owner.what, class = class, apply = fn }
    placeBox(owner)
    box.hint:SetText(format("%s's name", NS.className(class)))
    box:SetText("")
    box.sel = 0
    box:Show()
    box:SetFocus()
    box.paint()
end

-- A menu entry that turns dropdown `owner` into the box, for a player of
-- `class`.
local function typeButton(menu, owner, class, fn, words)
    menu:CreateButton(words or "Type a name", function() startTyping(owner, class, fn) end)
end

-- Whether a player of spec pick `pick` ("spec:PALADIN:1") is here.
local function specHere(pick)
    local _, class, tree = Du.splitPick(pick)
    for _, m in ipairs(Du.shownMembers()) do
        if m.class == class and m.spec == tonumber(tree) then return true end
    end
    return false
end

-- Whether giver `pick` isn't here: the player, or every player of the spec.
local function giverAway(pick)
    local kind, a = Du.splitPick(pick)
    if kind == "name" then return R.byName(a) == nil end
    if kind == "spec" then return not specHere(pick) end
    return false
end

-- A whole spec as a giver in a menu: "Holy paladins".
local function specLabel(pick)
    local _, class, tree = Du.splitPick(pick)
    local text = NS.specText(class, tonumber(tree), upperFirst(Du.pickWords(pick, false)))
    return text .. (specHere(pick) and "" or NOT_HERE)
end

-- The radios for each spec of `class` as a giver, then a divider.
-- `checked(pick)` and `set(pick)` are the radio's.
local function specRadios(menu, class, checked, set, label)
    for tree = 1, 3 do
        local pick = format("spec:%s:%d", class, tree)
        menu:CreateRadio((label and label(pick)) or specLabel(pick), function() return checked(pick) end,
                         function() set(pick) end)
    end
    menu:CreateDivider()
end

-- Which paladin gives blessing override `x`. Another paladin's own
-- override for the same players gives way to it.
local function paladinMenu(owner, x)
    if not canChange() then return end
    T.menu(owner, function(_, root)
        root:CreateTitle("Paladin")
        specRadios(root, "PALADIN", function(pick) return pick == x.paladin end, function(pick)
            if pick == x.paladin then return end
            Du.moveAssign(x.paladin, x.target, pick, x.target)
            x.paladin = pick
        end, function(pick)
            local label = specLabel(pick)
            if pick ~= x.paladin and Du.assignOf(pick, x.target) then
                label = label .. " " .. T.DIM .. "(replaces theirs)|r"
            end
            return label
        end)
        for _, p in ipairs(people({ PALADIN = true })) do
            local label = personLabel(p)
            if p.name ~= x.paladin and Du.assignOf(p.name, x.target) then
                label = label .. " " .. T.DIM .. "(replaces theirs)|r"
            end
            root:CreateRadio(label, function() return p.name == x.paladin end, function()
                if p.name == x.paladin then return end
                Du.moveAssign(x.paladin, x.target, p.name, x.target)
                -- The menu stays open, so the card it's for follows the
                -- move, for the radios and for another pick.
                x.paladin = p.name
            end)
        end
        typeButton(root, owner, "PALADIN", function(name) Du.moveAssign(x.paladin, x.target, name, x.target) end)
    end)
end

local function blessingMenu(owner, x)
    if not canChange() then return end
    T.menu(owner, function(_, root)
        root:CreateTitle("Blessing")
        for _, id in ipairs(D.JOB.blessings.options) do
            root:CreateRadio(NS.buffText(D.BY_ID[id]), function() return Du.assignOf(x.paladin, x.target) == id end,
                             function() Du.setAssign(x.paladin, x.target, id) end)
        end
    end)
end

-- Who blessing override `x` is for: everyone, or a class here, one of its
-- specs or one of its players.
local function targetMenu(owner, x)
    if not canChange() then return end
    T.menu(owner, function(_, root)
        root:CreateTitle("For")
        local _, force = Du.assignOf(x.paladin, x.target)
        local function radio(menu, label, t)
            if t ~= x.target and Du.assignOf(x.paladin, t) then
                label = label .. " " .. T.DIM .. "(replaces it)|r"
            end
            menu:CreateRadio(label, function() return x.target == t end, function()
                if x.target == t then return end
                Du.moveAssign(x.paladin, x.target, x.paladin, t)
                -- The menu stays open, so another pick in it moves the
                -- override from this one, not from where it was before.
                x.target = t
            end)
        end
        radio(root, targetLabel("all", force), "all")
        local by = here()
        local kind, a = Du.splitPick(x.target)
        local away = x.target ~= "all" and not (kind == "name" and R.byName(a) or kind ~= "name" and by[a])
        if away then radio(root, targetLabel(x.target) .. NOT_HERE, x.target) end
        root:CreateDivider()
        for _, class in ipairs(CLASSES) do
            if by[class] then
                local mine = x.target == "class:" .. class or (kind == "spec" and a == class)
                             or (kind == "name" and classOf(a) == class)
                local sub = root:CreateButton(NS.classText(class, NS.classColored(upperFirst(classWord(class)), class))
                                              .. (mine and " " .. T.MARK or ""))
                radio(sub, NS.classText(class, "All " .. classWord(class)), "class:" .. class)
                for tree = 1, 3 do
                    local pick = format("spec:%s:%d", class, tree)
                    radio(sub, NS.specText(class, tree, Du.pickWords(pick, false)), pick)
                end
                sub:CreateDivider()
                for _, m in ipairs(by[class]) do radio(sub, NS.who(m), "name:" .. m.name) end
                typeButton(sub, owner, class, function(name)
                    Du.moveAssign(x.paladin, x.target, x.paladin, "name:" .. name)
                end)
            end
        end
    end)
end

-- The classes that give one of job `jobId`'s buffs, as a set.
local function classesOf(jobId)
    local t = {}
    for _, id in ipairs(D.JOB[jobId].options) do t[D.BY_ID[id].class] = true end
    return t
end

-- What a giver of class `class` gives on job `jobId` when they take over
-- `buffId`: the same buff when it's theirs, else their class's option.
local function buffFor(jobId, buffId, class)
    if buffId and D.BY_ID[buffId].class == class then return buffId end
    for _, id in ipairs(D.JOB[jobId].options) do
        if D.BY_ID[id].class == class then return id end
    end
    return buffId
end

-- Who gives card `x`: the players who can give its buffs, here first.
local function giverMenu(owner, x)
    if not canChange() or x.kind == "bless" then return end
    T.menu(owner, function(_, root)
        root:CreateTitle("Giver")
        local classes = classesOf(x.job)
        local present = false
        for _, class in ipairs(CLASSES) do
            if classes[class] then
                specRadios(root, class, function(pick) return x.giver == pick end, function(pick)
                    if x.giver == pick then return end
                    local buff = buffFor(x.job, x.buff, class)
                    Du.moveGiver(x, pick, x.job, buff)
                    x.giver, x.buff = pick, buff
                end)
                for tree = 1, 3 do
                    present = present or x.giver == format("spec:%s:%d", class, tree)
                end
            end
        end
        local list = people(classes)
        for _, p in ipairs(list) do
            local pick = "name:" .. p.name
            present = present or pick == x.giver
            root:CreateRadio(personLabel(p), function() return x.giver == pick end, function()
                if x.giver == pick then return end
                local buff = buffFor(x.job, x.buff, p.m.class)
                Du.moveGiver(x, pick, x.job, buff)
                -- The menu stays open, so the card it's for follows the
                -- move, for the radios and for another pick.
                x.giver, x.buff = pick, buff
            end)
        end
        if not present then
            root:CreateRadio(giverLabel(x.giver), function() return true end, function() end)
        end
        local n = 0
        for _ in pairs(classes) do n = n + 1 end
        for _, class in ipairs(CLASSES) do
            if classes[class] then
                typeButton(root, owner, class, function(name)
                    Du.moveGiver(x, "name:" .. name, x.job, buffFor(x.job, x.buff, class))
                end, n > 1 and format("Type a %s's name", NS.className(class):lower()) or nil)
            end
        end
    end)
end

-- What card `x`'s giver does: everything their class can give, by
-- section. A blessing becomes a paladin override for whoever needs it.
local function whatMenu(owner, x)
    if not canChange() or x.kind == "bless" then return end
    local kind, a = Du.splitPick(x.giver)
    local class = kind == "name" and classOf(a) or a
    if not class then return end
    T.menu(owner, function(_, root)
        -- A totem or an aura they're set to put up none of is about the
        -- element or the aura, not one buff of it.
        if x.never and (x.kind == "totem" or x.kind == "choice") then
            root:CreateTitle("Puts up no")
            local seen = {}
            for _, o in ipairs(Du.giverOptions(class)) do
                local job = D.JOB[o.job]
                local b = D.BY_ID[o.buff]
                local slot = job.kind == "totem" and b.element or job.kind == "choice" and o.job or nil
                if slot and not seen[slot] then
                    seen[slot] = true
                    local label = job.kind == "totem" and format("No %s totem", slot) or "No " .. Du.title(job):lower()
                    local mine = job.kind == "totem" and x.kind == "totem" and x.element == slot
                                 or x.kind == "choice" and x.job == o.job
                    root:CreateRadio(label, function() return mine end, function()
                        if not mine then Du.moveGiver(x, x.giver, o.job, o.buff) end
                    end)
                end
            end
            return
        end
        root:CreateTitle(x.never and "Never" or "Gives")
        local section
        for _, o in ipairs(Du.giverOptions(class)) do
            local job = D.JOB[o.job]
            if not (job.kind == "blessing" and (kind == "class" or x.never)) then
                if job.section ~= section then
                    section = job.section
                    root:CreateTitle(section)
                end
                root:CreateRadio(NS.buffText(D.BY_ID[o.buff]), function()
                    return x.job == o.job and x.buff == o.buff
                end, function()
                    if not (x.job == o.job and x.buff == o.buff) then Du.moveGiver(x, x.giver, o.job, o.buff) end
                end)
            end
        end
    end)
end


-- =============================================================
-- Filling in a new card
-- =============================================================
-- Who a new card is for: every class here or remembered, each with its
-- players.
local function freshGiverMenu(owner, f)
    if not canChange() then return end
    T.menu(owner, function(_, root)
        root:CreateTitle("Who")
        for _, class in ipairs(CLASSES) do
            local sub = root:CreateButton(NS.classText(class, NS.classColored(upperFirst(classWord(class)), class)))
            local function choose(pick)
                f.giver = pick
                redraw()
            end
            specRadios(sub, class, function(pick) return f.giver == pick end, choose)
            local list = people({ [class] = true })
            for _, p in ipairs(list) do
                sub:CreateRadio(personLabel(p), function() return f.giver == "name:" .. p.name end,
                                function() choose("name:" .. p.name) end)
            end
            typeButton(sub, owner, class, function(name) choose("name:" .. name) end)
        end
    end)
end

-- The new card is an override now, and leaves the ones being filled in.
local function land(f, jobId, set)
    for i, x in ipairs(fresh) do
        if x == f then table.remove(fresh, i) end
    end
    landed = { giver = f.giver, job = jobId }
    set()
    redraw()
end

-- What the new card's giver does: everything their class can give, by
-- section, and Never for keeping them off a job even in auto.
local function freshWhatMenu(owner, f)
    if not canChange() or not f.giver then return end
    local kind, a = Du.splitPick(f.giver)
    local class = kind == "name" and classOf(a) or a
    if not class then return end
    local name = Du.holderOf(f.giver)
    T.menu(owner, function(_, root)
        root:CreateTitle("Gives")
        local section
        for _, o in ipairs(Du.giverOptions(class)) do
            local job = D.JOB[o.job]
            if job.section ~= section then
                section = job.section
                root:CreateTitle(section)
            end
            root:CreateButton(NS.buffText(D.BY_ID[o.buff]), function()
                land(f, o.job, function() Du.addGiver(name, o.job, o.buff) end)
            end)
        end
        root:CreateDivider()
        local nv = root:CreateButton("Never")
        local seen = {}
        for _, o in ipairs(Du.giverOptions(class)) do
            local job = D.JOB[o.job]
            if job.kind ~= "blessing" and job.kind ~= "totem" and not seen[o.job] then
                seen[o.job] = true
                nv:CreateButton(Du.title(job), function()
                    land(f, o.job, function() Du.setNever(o.job, f.giver, true) end)
                end)
            end
        end
    end)
end

-- =============================================================
-- Cards
-- =============================================================
-- One of a card's dropdowns: a box that lights under the mouse.
local function newPart(c, what)
    local b = CreateFrame("Button", nil, c)
    b:SetHeight(PART_H)
    b.what = what
    b.bg = T.fill(b, { 1, 1, 1 }, 0.04)
    b.bg:SetAllPoints(b)
    T.border(b, { 1, 1, 1 }, 0.10)
    b:SetScript("OnEnter", function(self)
        if canChange() then self.bg:SetColorTexture(1, 1, 1, 0.10) end
        if c.tip then c.tip(self, self.what) end
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.04)
        GameTooltip:Hide()
    end)
    return b
end

local function place(part, c, x, w)
    part:ClearAllPoints()
    part:SetPoint("TOPLEFT", c, "TOPLEFT", x, -PAD)
    part:SetWidth(w)
end

-- The small down arrow at a dropdown's right, which says a click opens a
-- list. It shows only while we may change the card (Ov.draw).
local function arrow(b)
    b.arrow = T.chevron(b, 9)
    b.arrow:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    return b.arrow
end

-- A part with an icon and words after it.
local function iconPart(c, what)
    local b = newPart(c, what)
    b.icon = T.icon(b, nil, ICON - 2)
    b.icon:SetPoint("LEFT", b, "LEFT", 3, 0)
    b.text = T.text(b, T.SIZE.body, false, T.A_TEXT)
    b.text:SetPoint("LEFT", b, "LEFT", ICON + 6, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -20, 0)
    b.text:SetWordWrap(false)
    arrow(b)
    return b
end

local function newCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(ROW_H)
    -- A card: a soft background and border, and a stripe at its left when
    -- it didn't go as set.
    c.bg = T.fill(c, { 1, 1, 1 }, 0.05)
    c.bg:SetAllPoints(c)
    T.border(c, { 1, 1, 1 }, 0.12)
    c.stripe = T.fill(c, { 1, 1, 1 }, 1, "ARTWORK")
    c.stripe:SetWidth(3)
    c.stripe:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.stripe:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 0)
    c.stripe:Hide()
    NS.Config.kit.makeFlash(c)
    c.giver = iconPart(c, "giver")
    c.bless = newPart(c, "blessing")
    c.bless.icon = T.icon(c.bless, nil, ICON)
    c.bless.icon:SetPoint("LEFT", c.bless, "LEFT", 2, 0)
    arrow(c.bless)
    c.to = newPart(c, "target")
    c.to.text = T.text(c.to, T.SIZE.body, false, T.A_TEXT)
    c.to.text:SetPoint("LEFT", c.to, "LEFT", 6, 0)
    c.to.text:SetPoint("RIGHT", c.to, "RIGHT", -20, 0)
    arrow(c.to)
    c.to.text:SetWordWrap(false)
    c.what = iconPart(c, "what")
    c.remove = T.close(c, nil)
    c.remove:SetSize(PART_H, PART_H)
    c.remove:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -PAD)
    c.tick = newPart(c, "tick")
    c.tick.box = CreateFrame("Frame", nil, c.tick)
    c.tick.box:SetSize(12, 12)
    c.tick.box:SetPoint("LEFT", c.tick, "LEFT", 6, 0)
    c.tick.box.bg = T.fill(c.tick.box, { 0, 0, 0 }, 0.45)
    c.tick.box.bg:SetAllPoints(c.tick.box)
    T.border(c.tick.box, { 1, 1, 1 }, 0.35)
    c.tick.box.on = T.fill(c.tick.box, T.ACCENT, 1, "ARTWORK")
    c.tick.box.on:SetPoint("TOPLEFT", c.tick.box, "TOPLEFT", 3, -3)
    c.tick.box.on:SetPoint("BOTTOMRIGHT", c.tick.box, "BOTTOMRIGHT", -3, 3)
    c.tick.text = T.text(c.tick, T.SIZE.body, false, T.A_TEXT)
    c.tick.text:SetPoint("LEFT", c.tick.box, "RIGHT", 6, 0)
    -- Why it didn't go as set, under the dropdowns, and the fixes.
    c.why = T.text(c, T.SIZE.body, false, 1)
    c.why:SetPoint("TOPLEFT", c, "TOPLEFT", GIVER_X + 4, -(ROW_H - 2))
    c.why:SetWordWrap(true)
    c.why:SetJustifyH("LEFT")
    c.fix = T.button(c, "Fix it", nil, 18)
    c.fix:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -(ROW_H - 2))
    return c
end

-- Lays card `c` out `w` wide: a blessing override has the blessing and who
-- it's for where the rest have what the giver does.
local function layout(c, w)
    local edit = canChange()
    for _, part in ipairs({ c.giver, c.bless, c.to, c.what }) do part.arrow:SetShown(edit) end
    local giverW = max(140, min(220, floor(w * 0.25)))
    local blessX = GIVER_X + giverW + PAD
    local toX = blessX + BLESS_W + PAD
    local boxX = w - PAD - PART_H - PAD - BOX_W
    c:SetWidth(w)
    place(c.giver, c, GIVER_X, giverW)
    place(c.bless, c, blessX, BLESS_W)
    place(c.to, c, toX, boxX - PAD - toX)
    place(c.what, c, blessX, boxX - PAD - blessX)
    place(c.tick, c, boxX, BOX_W)
end

-- The fixes worth a button: "Back to auto" alone is what the cross does.
local function fixesOf(st)
    local t = {}
    for _, f in ipairs(st and st.status ~= "applied" and st.fixes or {}) do
        if f.text ~= "Back to auto" then t[#t + 1] = f end
    end
    return t
end

-- The colour of an override's stripe and tooltip lines, by its status.
local LEVEL = { blocked = "bad", costly = "bad", low = "low", idle = "idle", next = "idle" }

-- Shows the stripe at `c`'s left in its status's colour, or none while it
-- goes as set. What the draft changed is in its tooltip, not on the card.
local function edge(c, st)
    local level = st and LEVEL[st.status]
    local color = level and T.COLOR[level]
    c.stripe:SetShown(color ~= nil)
    if color then c.stripe:SetColorTexture(color[1], color[2], color[3], level == "idle" and 0.6 or 1) end
    c.stripeColor = color
    return level
end

-- The status lines of a card's tooltip.
local function statusLines(lines, st, changed, level)
    if changed then lines[#lines + 1] = T.line("Changed in the draft.", "changed") end
    if st and st.reason and st.status ~= "applied" then
        lines[#lines + 1] = T.line(st.reason, level or "idle")
    end
    -- Why the ones picked before them didn't take it: "Pri One is offline."
    if st and st.note then lines[#lines + 1] = T.line(st.note, "idle") end
end

local TIP_CLICK = { giver = "change the giver", blessing = "change the blessing", target = "change who it's for",
                    what = "change what they do", tick = "turn it on or off" }

-- A paladin's blessing override: { paladin, target, buff, force }.
local function paintAssign(c, x, st)
    local name = x.paladin
    local pick = Du.pickOf(name)
    local whole = Du.isSpecKey(name)
    local m = not whole and R.byName(name)
    local tree = whole and tonumber(name:match("(%d)$")) or (not whole and R.known(name) or {}).spec
    local spec = tree and D.SPECS.PALADIN[tree]
    local who = whole and upperFirst(Du.pickWords(pick, false)) or name
    c.x, c.new = x, nil
    c.key = Du.itemKey("assign", name, x.target)
    c.bless:Show()
    c.to:Show()
    c.what:Hide()
    c.tick:Show()
    c.giver.icon:SetTexture(spec and spec.icon or T.classIcon("PALADIN"))
    c.giver.text:SetText(whole and NS.classColored(who, "PALADIN") or colored(name))
    c.bless.icon:SetTexture(Tr.icon(D.BY_ID[x.buff]))
    c.to.text:SetText(targetLabel(x.target, x.force))
    c.tick.text:SetText("Forced")
    c.tick.box.on:SetShown(x.force)
    c.tick.text:SetAlpha(x.force and 1 or T.A_DIM)
    local away = giverAway(pick)
    c:SetAlpha(away and 0.55 or 1)
    -- A player it's for who isn't here dims too.
    local target = x.target:match("^name:(.+)$")
    local targetAway = not away and target ~= nil and R.byName(target) == nil
    c.to:SetAlpha(targetAway and 0.55 or 1)
    local changed = NS.Config.changedWhere(function(it)
        return it.kind == "assign" and it.a == name and it.b == x.target
    end)
    local level = edge(c, st)
    c.changed = changed
    local edit = canChange()
    c.remove:SetShown(edit)
    c.remove:SetScript("OnClick", function() Du.setAssign(name, x.target, nil) end)
    c.giver:SetScript("OnClick", function(self) paladinMenu(self, x) end)
    c.bless:SetScript("OnClick", function(self) blessingMenu(self, x) end)
    c.to:SetScript("OnClick", function(self) targetMenu(self, x) end)
    c.tick:SetScript("OnClick", function()
        if edit then Du.setAssignForce(name, x.target, not x.force) end
    end)
    c.tip = function(owner, what)
        local lines = { { format("%s %s.", who, Du.assignWords(x.buff, x.target, x.force, whole)), 1, 1, 1 } }
        if what == "tick" then
            lines = { x.force and { "On: everyone it's for gets it, wanted or not.", 1, 1, 1 }
                      or { "Off: only those who need it get it.", 1, 1, 1 },
                      "Who needs it is on the Needs page." }
        elseif not x.force then
            lines[#lines + 1] = "Only those who want it on the Needs page. Auto chooses for the rest."
        else
            lines[#lines + 1] = "Wanted or not. Auto chooses for everyone else."
        end
        if away then
            lines[#lines + 1] = T.line(whole and format("No %s here.", Du.pickWords(pick, false))
                                       or name .. " isn't here.", "idle")
        elseif targetAway then
            lines[#lines + 1] = T.line(target .. " isn't here.", "idle")
        end
        statusLines(lines, st, changed, level)
        local hints = NS.Config.hints(lines, { { "Click", TIP_CLICK[what] } })
        local title = what == "giver" and (whole and NS.classColored(who, "PALADIN") or NS.who(name)) or what == "blessing" and NS.buffText(D.BY_ID[x.buff])
                      or what == "tick" and "Forced" or "For " .. targetLabel(x.target, x.force)
        if what == "blessing" then
            T.spellTip(owner, D.BY_ID[x.buff], title, lines, hints)
        else
            T.tip(owner, title, lines, hints)
        end
    end
end

-- The status of a giver card. A one-giver job has one setting for all its
-- picks, and it's about the pick that gives it. The picks after it wait
-- their turn.
local function giverStatus(x, byKey)
    local st = byKey[x.key]
    if x.kind ~= "pick" or not st then return st end
    local plan = Du.shown(x.job)
    local giving, any = false, false
    for _, a in ipairs(plan and plan.list or {}) do
        if a.hand then
            any = true
            if Du.pickMatches(x.giver, a.giver) then giving = true end
        end
    end
    if giving or not any then return st end
    local name = x.giver:match("^name:(.+)$")
    if name and not R.byName(name) then
        return { status = "absent", reason = format("%s isn't here.", name) }
    end
    return { status = "next", reason = "Takes over when the ones before can't." }
end

-- What a giver card does, in words for the card: "Power Word:
-- Fortitude", "Windfury Totem", "No air totem", "Never Fortitude".
local function whatText(x)
    local b = x.buff and D.BY_ID[x.buff]
    local job = D.JOB[x.job]
    if x.kind == "bless" then
        local words = format("%s for %s", b and Tr.title(b) or "Nothing", classWord(x.class))
        return upperFirst(words)
    end
    if x.never then
        if x.kind == "totem" then return format("No %s totem", x.element) end
        if x.kind == "choice" then return "No " .. Du.title(job):lower() end
        return Du.title(job)
    end
    local text = b and Tr.title(b) or Du.title(job)
    if x.kind == "pick" and x.place and x.place > 1 then
        text = text .. " " .. T.DIM .. "(" .. (PLACE[x.place] or x.place .. "th") .. " choice)|r"
    end
    return text
end

-- What a giver card says in its tooltip: "Mira gives Fortitude.", "Carl
-- never does Fortitude, even in auto."
local function giverSentence(x)
    local who = x.giver:match("^name:(.+)$") or upperFirst(Du.pickWords(x.giver, true))
    local job = D.JOB[x.job]
    local b = x.buff and D.BY_ID[x.buff]
    if x.kind == "bless" then
        return format("%s gives %s %s, an older override.", who, classWord(x.class), b and Tr.title(b) or "nothing")
    end
    if x.never then
        if x.kind == "totem" then return format("%s puts down no %s totem.", who, x.element) end
        if x.kind == "choice" then return format("%s puts up no %s.", who, Du.title(job):lower()) end
        return format("%s never does %s, even in auto.", who, Du.title(job))
    end
    if x.kind == "totem" then return format("%s puts down %s.", who, Tr.title(b)) end
    if x.kind == "choice" then return format("%s puts up %s.", who, Tr.title(b)) end
    if x.place and x.place > 1 then
        return format("%s gives %s when the ones before can't.", who, b and Tr.title(b) or Du.title(job))
    end
    return format("%s gives %s.", who, b and Tr.title(b) or Du.title(job))
end

local function paintGiver(c, x, st)
    c.x, c.new, c.key = x, nil, x.key
    c.bless:Hide()
    c.to:Hide()
    c.what:Show()
    local legacy = x.kind == "bless"
    c.tick:SetShown(not legacy)
    local kind, a, b = Du.splitPick(x.giver)
    local m = kind == "name" and R.byName(a)
    local who = kind == "name" and R.known(a) or nil
    local spec = who and who.class and who.spec and D.SPECS[who.class] and D.SPECS[who.class][who.spec]
    if kind == "name" then
        c.giver.icon:SetTexture(spec and spec.icon or (who and who.class and T.classIcon(who.class)))
        c.giver.text:SetText(colored(a))
    else
        local s = kind == "spec" and D.SPECS[a] and D.SPECS[a][tonumber(b)]
        c.giver.icon:SetTexture(s and s.icon or T.classIcon(a))
        c.giver.text:SetText(NS.classColored(upperFirst(Du.pickWords(x.giver, true)), a))
    end
    local buff = x.buff and D.BY_ID[x.buff]
    c.what.icon:SetTexture(buff and Tr.icon(buff) or nil)
    c.what.icon:SetDesaturated(x.never and true or false)
    c.what.text:SetText(whatText(x))
    c.what.text:SetAlpha(x.never and T.A_DIM or 1)
    c.tick.text:SetText("Never")
    c.tick.box.on:SetShown(x.never and true or false)
    c.tick.text:SetAlpha(x.never and 1 or T.A_DIM)
    local away = giverAway(x.giver)
    c:SetAlpha(away and 0.55 or 1)
    local changed = NS.Config.changedWhere(function(it) return it.key == x.key end)
    local level = edge(c, st)
    c.changed = changed
    local edit = canChange()
    c.remove:SetShown(edit)
    c.remove:SetScript("OnClick", function() Du.removeGiver(x) end)
    c.giver:SetScript("OnClick", function(self) giverMenu(self, x) end)
    c.what:SetScript("OnClick", function(self) whatMenu(self, x) end)
    c.tick:SetScript("OnClick", function()
        if edit then Du.setGiverNever(x, not x.never) end
    end)
    c.tip = function(owner, what)
        local lines = { { giverSentence(x), 1, 1, 1 } }
        if what == "tick" then
            lines = { x.never and { "On: they never do it, even in auto.", 1, 1, 1 }
                      or { "Off: they give it.", 1, 1, 1 } }
        elseif legacy then
            lines[#lines + 1] = "An old kind of override. Remove it and add a new one."
        end
        if away then
            lines[#lines + 1] = T.line(kind == "spec" and format("No %s here.", Du.pickWords(x.giver, false))
                                       or a .. " isn't here.", "idle")
        end
        statusLines(lines, st, changed, level)
        local hints
        if not (legacy and what ~= "tick") then hints = NS.Config.hints(lines, { { "Click", TIP_CLICK[what] } }) end
        local title = what == "giver" and giverLabel(x.giver) or what == "tick" and "Never"
                      or (buff and NS.buffText(buff, whatText(x)) or whatText(x))
        if what == "what" and buff then
            T.spellTip(owner, buff, title, lines, hints)
        else
            T.tip(owner, title, lines, hints)
        end
    end
end


-- Puts why card `c` didn't go as set (status `st`) under its dropdowns, in
-- its colour, with a Fix it button when there are fixes. Returns the
-- card's height.
local function explain(c, st, w)
    local level = st and LEVEL[st.status]
    local text = st and st.status ~= "applied" and st.reason or nil
    if text and st.note then text = text .. " " .. st.note end
    local fixes = fixesOf(st)
    local edit = canChange() and #fixes > 0
    c.fix:SetShown(edit)
    c.fix:SetScript("OnClick", function(self)
        T.menu(self, function(_, root)
            root:CreateTitle("Fix it")
            for _, f in ipairs(fixes) do root:CreateButton(f.text, f.fn) end
        end)
    end)
    c.whyText = text
    if not text then
        c.why:Hide()
        c:SetHeight(ROW_H)
        return ROW_H
    end
    local color = T.COLOR[level or "idle"] or T.COLOR.idle
    c.why:SetText(text)
    c.why:SetTextColor(color[1], color[2], color[3], 1)
    c.why:SetWidth(w - GIVER_X - 4 - PAD - (edit and c.fix:GetWidth() + 8 or 0))
    c.why:Show()
    local h = ROW_H + max(13, c.why:GetStringHeight() or 13) + 6
    c:SetHeight(h)
    return h
end

-- A card being filled in: who it's for, then what they do.
local function paintFresh(c, f)
    c.x, c.new, c.key = nil, f, f
    c.bless:Hide()
    c.to:Hide()
    c.what:Show()
    c.tick:Hide()
    c:SetAlpha(1)
    local kind, a, b = Du.splitPick(f.giver)
    if kind == "spec" then
        local s = D.SPECS[a] and D.SPECS[a][tonumber(b)]
        c.giver.icon:SetTexture(s and s.icon or T.classIcon(a))
        c.giver.text:SetText(NS.classColored(upperFirst(Du.pickWords(f.giver, false)), a))
    else
        local class = a and classOf(a)
        c.giver.icon:SetTexture(class and T.classIcon(class) or nil)
        c.giver.text:SetText(a and colored(a) or T.hex(T.ACCENT) .. "Choose who|r")
    end
    c.what.icon:SetTexture(nil)
    c.what.icon:SetDesaturated(false)
    c.what.text:SetText(f.giver and T.hex(T.ACCENT) .. "Choose what they do|r" or T.DIM .. "What they do|r")
    c.what.text:SetAlpha(1)
    edge(c, nil)
    c.changed = false
    c.remove:SetShown(canChange())
    c.remove:SetScript("OnClick", function()
        for i, x in ipairs(fresh) do
            if x == f then table.remove(fresh, i) end
        end
        redraw()
    end)
    c.giver:SetScript("OnClick", function(self) freshGiverMenu(self, f) end)
    c.what:SetScript("OnClick", function(self) freshWhatMenu(self, f) end)
    c.tick:SetScript("OnClick", nil)
    c.tip = function(owner, what)
        local lines = { "A new override. Choose a player or a spec, then what they do." }
        local hints
        if what == "giver" or f.giver then
            hints = NS.Config.hints(lines, { { "Click", what == "giver" and "choose who" or "choose what they do" } })
        else
            lines[#lines + 1] = "Choose who first."
        end
        T.tip(owner, "New override", lines, hints)
    end
end

-- Every override, the paladins' first, then the rest in the page's order:
-- { assign = x } or { giver = x }.
local function items()
    local t = {}
    for _, x in ipairs(Du.assigns()) do t[#t + 1] = { assign = x } end
    for _, x in ipairs(Du.giverCards()) do t[#t + 1] = { giver = x } end
    return t
end

-- Whether override card `x` is the one a new card just became.
local function isLanded(item)
    if not landed then return false end
    local x = item.assign or item.giver
    local giver = item.assign and Du.pickOf(x.paladin) or x.giver
    local job = item.assign and "blessings" or x.job
    return giver == landed.giver and job == landed.job
end

-- Draws the section's cards on `page` from `y`, and returns the y under
-- them. `anchor` takes a player dropped from the raid pane.
function Ov.draw(page, y, anchor)
    local K = NS.Config.kit
    local status = {}
    for _, st in ipairs(Du.constraints()) do status[st.key] = st end
    local w = K.pageWidth(page)
    local list = items()
    local edit = canChange()
    local flashed
    for _, item in ipairs(list) do
        local c = K.pool(page, "override", newCard)
        layout(c, w)
        local st
        if item.assign then
            local x = item.assign
            st = status[Du.itemKey("assign", x.paladin, x.target)]
            paintAssign(c, x, st)
        else
            st = giverStatus(item.giver, status)
            paintGiver(c, item.giver, st)
        end
        local h = explain(c, st, w)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
        if not flashed and isLanded(item) then
            flashed = true
            K.mark(page, "landed", c, y)
        end
        if item.assign and not page.anchors.assign then K.mark(page, "assign", c, y) end
        -- Where a click on Assignments goes (C.whereSet): a paladin's first
        -- card, a job's first card and a player's on it, and a totem's.
        if item.assign then
            K.mark(page, "pal:" .. item.assign.paladin, c, y)
        else
            local x = item.giver
            K.mark(page, "job:" .. x.job, c, y)
            local name = type(x.giver) == "string" and x.giver:match("^name:(.+)$")
            if name then K.mark(page, format("job:%s:%s", x.job, name), c, y) end
            if x.kind == "totem" then K.mark(page, "ov:" .. x.key, c, y) end
        end
        y = y + h + CARD_GAP
    end
    if flashed then landed = nil end
    for _, f in ipairs(edit and fresh or {}) do
        local c = K.pool(page, "override", newCard)
        layout(c, w)
        paintFresh(c, f)
        explain(c, nil, w)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
        y = y + ROW_H + CARD_GAP
    end
    if #list == 0 and not (edit and #fresh > 0) then
        y = K.note(page, "None. Auto chooses who gives what.", y) + 4
    end
    if anchor then
        anchor.onDrop = function(m) Ov.add(m.name) end
    end
    -- A name being typed stays in its card's box, wherever the card is now.
    if typing then
        local part
        for _, c in ipairs(Ov.cards()) do
            if c.key == typing.key then part = typing.what == "target" and c.to or c.giver end
        end
        if part and edit then placeBox(part) else stopTyping() end
    end
    return y, flashed
end

-- Adds an empty card to fill in, with player `name` as its giver when given.
function Ov.add(name)
    if not canChange() then return end
    fresh[#fresh + 1] = { giver = name and "name:" .. name or nil }
    redraw()
end

-- The box a name is typed in, for the tests.
function Ov.nameBox() return nameBox() end

-- The override cards that show, for the tests.
function Ov.cards()
    local t = {}
    local page = NS.Config.page and NS.Config.page()
    local p = page and page.pools and page.pools.override
    for i = 1, p and p.used or 0 do
        if p[i]:IsShown() then t[#t + 1] = p[i] end
    end
    return t
end
