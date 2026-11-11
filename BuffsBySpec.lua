-- Buffs by Spec, the Needs page (Config.lua): what each spec wants. A
-- column per spec under its icon, and a column for each player with needs
-- of their own after them. The filter over it (Config.lua's C.specFilter)
-- shows three classes at a time: their specs and their players. "Per
-- Player" shows only the players, and "All" every column.
--
-- The blessings come first, each column's in order, most wanted at the top
-- (Priority.lua's Pr.column). Then a row per other buff under the page's
-- headings. A cell shows the buff's icon, lit when the spec or player wants
-- it and faded when not. A click turns it on or off (Du.setWant), and a gold
-- line under it says it's an override. Auto gives a buff only to those who
-- want it, and puts up the aura a party wants most, so this is what auto
-- aims for. A change here never makes an override warn, since auto aims for
-- the new wants as well.
--
-- Hovering a row or a cell shows the spell's tooltip, then how the buff
-- works with the others (Bs.rules): what it doesn't stack with and which
-- comes first, like Sunder Armor over Expose Armor or Windfury Totem over
-- Flametongue.
--
-- A right-click on a column's icon puts the whole column back to auto,
-- blessings too. "Add player override" (Bs.addMenu, beside the filter)
-- adds a column for one player, who starts as their spec does. A player's
-- column has their initials over the icon, and a click on it takes it away.
--
-- The box at the left of a row turns its assignment on or off (Du.
-- setEnabled). One turned off gets nobody, and its row is faded. A row of an
-- assignment with several buffs, like Sunder Armor and Expose Armor, turns
-- them all on or off together, and its tooltip says so.
--
-- Config.lua draws it into a frame of the page (Bs.draw), scaled down to fit
-- when the page is narrower than the grid. The row of icons over the
-- columns stays in sight at the top while the page scrolls down.

local _, NS = ...
local D, R, Du, T, Tr = NS.Data, NS.Roster, NS.Duties, NS.Theme, NS.Tracking

local format = string.format
local min = math.min

local Bs = {}
NS.BuffsBySpec = Bs

local CLASSES = D.CLASSES
-- A cell is as big as the spec icons over it and the blessings, and a
-- row as tall as a blessing's place. The icon in a row's name is smaller.
local ICON = 20
local CELL, LABEL_ICON = ICON, 16
-- The on or off box, the buff's name at the left of its row, then the
-- columns, an icon wide each. Each class's three are a little apart from
-- the next class's, and the players more.
local BOX = 12
local LABEL_W = 176
local COL = ICON + 4
local CLASS_GAP, PLAYER_GAP = 6, 12
local ROW, SECTION_H = ICON + 4, 20
-- The spec icons over the columns. A player's has their initials over it,
-- which take PLAYER_TOP more.
local TOP = ICON + 8
local PLAYER_TOP = 14

-- The frame of the page we draw in, from the last Bs.draw.
local panel
-- Players given a column this session, before they have a want of their
-- own. A column that shows stays until its X takes it away, even when a
-- change makes it like their spec again, so it doesn't vanish under the
-- mouse.
local added = {}

local function canChange() return NS.Config.canChange() end

-- The buffs and debuffs a row each, by section in the page's order: every
-- one that isn't a blessing or a fight's resistance.
local function rows()
    local by, seen = {}, {}
    for _, job in ipairs(D.JOBS) do
        if job.kind ~= "blessing" and job.kind ~= "resist" then
            for _, id in ipairs(job.options) do
                local b = D.BY_ID[id]
                local section = NS.Config.headingOf(job.section)
                if not seen[id] and not b.school then
                    seen[id] = true
                    by[section] = by[section] or {}
                    table.insert(by[section], b)
                end
            end
        end
    end
    local t, seen = {}, {}
    for _, s in ipairs(D.SECTIONS) do
        local h = NS.Config.headingOf(s)
        if by[h] and not seen[h] then
            seen[h] = true
            t[#t + 1] = { section = h, buffs = by[h] }
        end
    end
    return t
end

-- Whether filter `f` (C.specFilter) shows a column of `class`, a player's
-- when `player`.
local function shows(f, class, player)
    if f == "all" then return true end
    if f == "players" then return player end
    return NS.Config.filterShows(f, class)
end

-- The columns: { key, tex, name, class, tree, m }, the specs by class, then
-- the players here with wants of their own or added this session. Only
-- those filter `f` shows, when given.
local function columns(f)
    f = f or "all"
    local t = {}
    for _, class in ipairs(CLASSES) do
        for tree = 1, 3 do
            local spec = D.SPECS[class] and D.SPECS[class][tree]
            local name = format("%s %s", NS.Config.specName(class, tree), NS.className(class))
            if shows(f, class, false) then
                t[#t + 1] = { key = class .. ":" .. tree, tex = spec and spec.icon or T.classIcon(class),
                              name = NS.classColored(name, class), class = class, tree = tree }
            end
        end
    end
    local keys = Du.wantKeys()
    local orders = NS.Priority.playerOrders()
    local players, here = {}, {}
    for _, m in ipairs(R.list()) do
        here[m.name] = true
        if keys["name:" .. m.name] or orders[m.name] or added[m.name] then players[#players + 1] = m end
    end
    -- A player who left keeps their column while they have wants of their
    -- own, so they can still be seen and put back to auto.
    for key in pairs(keys) do
        local name = key:match("^name:(.+)$")
        if name and not here[name] then
            local p = R.known(name) or {}
            players[#players + 1] = { name = name, class = p.class or "", spec = p.spec, gone = true }
        end
    end
    table.sort(players, function(a, b)
        if a.class ~= b.class then return a.class < b.class end
        return a.name < b.name
    end)
    for _, m in ipairs(players) do
        local spec = m.spec and D.SPECS[m.class] and D.SPECS[m.class][m.spec]
        local name = NS.classColored(m.name, m.class)
        if m.gone then name = name .. " " .. T.DIM .. "(not here)|r" end
        local tex = spec and spec.icon or m.class ~= "" and T.classIcon(m.class)
                    or [[Interface\Icons\INV_Misc_QuestionMark]]
        if shows(f, m.class, true) then
            t[#t + 1] = { key = "name:" .. m.name, tex = tex,
                          name = name, class = m.class, m = m }
            if not m.gone then added[m.name] = true end
        end
    end
    return t
end

-- Whether column `col` wants `b`, and whether it's its own override.
local function wantOf(col, b)
    local own = Du.wantOf(col.key, b)
    if col.m then return Du.wants(col.m, b), own ~= nil end
    return Du.specWants(col.class, col.tree, b), own ~= nil
end

-- =============================================================
-- How a buff works with the others
-- =============================================================
-- The tooltips of a row and its cells say in a few short lines how far the
-- buff reaches, what it doesn't stack with and which wins, and what it
-- needs. The grid already shows who wants it. It's all read from the data,
-- so it stays true when the data changes.

-- Who an `unwanted` tag rules out, in a player's words.
local UNWANTED = { tank = "Will not be cast on tanks" }

-- Whether debuffs `a` and `b` don't stack: one of a family that's only one
-- at a time, or two that clash.
local function clashes(a, b)
    local fam = a.family and D.FAMILIES[a.family]
    return (fam and fam.per == "one" and a.family == b.family) or (a.clash ~= nil and a.clash == b.clash)
end

-- Where `id` is in `job`'s options, 0 when it isn't.
local function placeIn(job, id)
    for i, x in ipairs(job and job.options or {}) do
        if x == id then return i end
    end
    return 0
end

-- The lines for buff or debuff `b`: how far it reaches in white, how it
-- stacks, then what it needs in grey.
function Bs.rules(b)
    local t = {}
    local job = D.JOB[b.job]
    local at = placeIn(job, b.id)
    if not b.debuff then
        local party = b.party or (job and job.scope == "party")
        t[#t + 1] = { party and "Group-wide" or "Raid-wide", 1, 1, 1 }
    end
    -- A flex family like the paladin auras: a player with any aura they
    -- want isn't missing one, and auto gives each party its favourite.
    local fam = b.family and D.FAMILIES[b.family]
    if fam and fam.flex then
        t[#t + 1] = "Any wanted aura counts"
        t[#t + 1] = "Auto picks the group's top choice"
    end
    local function versus(x, lost)
        if placeIn(job, x.id) > at then
            t[#t + 1] = format("Overrides %s", Tr.title(x))
        else
            t[#t + 1] = T.line(format(lost or "Overridden by %s", Tr.title(x)), "low")
        end
    end
    if b.debuff and job and job.kind == "single" then
        for _, id in ipairs(job.options) do
            local x = D.BY_ID[id]
            if x ~= b and clashes(b, x) then versus(x) end
        end
    end
    local ex = b.excludes and D.BY_ID[b.excludes]
    if ex then
        -- Flametongue still goes to those who don't take Windfury, so it
        -- isn't overridden outright.
        versus(ex, "Will not be suggested when %s is available")
    end
    for _, tag in ipairs(b.debuff and {} or b.unwanted or {}) do
        if UNWANTED[tag] then t[#t + 1] = UNWANTED[tag] end
    end
    -- Forever's one curse per warlock on a target, which isn't the game's
    -- old rule.
    if b.family == "curse" then t[#t + 1] = "One curse per warlock" end
    local function need(text) t[#t + 1] = T.line(text, "idle") end
    if b.talent then need(format("Needs the %s talent", NS.Config.specName(b.class, b.talent))) end
    local lv = Du.needsLevel(b)
    if lv then need(format("Needs %s level %d+", NS.className(b.class), lv)) end
    if b.optional then need(job.optional and "Off by default" or "Only when set by hand") end
    return t
end

-- Every want of `key` back to auto, and its blessing order, as one step.
local function clearColumn(key, name)
    Du.batch(format("set %s's buffs back to auto", name), function()
        for _, s in ipairs(rows()) do
            for _, b in ipairs(s.buffs) do
                if Du.wantOf(key, b) ~= nil then Du.setWant(key, b.id, nil) end
            end
        end
        NS.Priority.clear(key)
    end)
end

-- =============================================================
-- Drawing
-- =============================================================
local function pooled(list, i, make)
    local f = list[i]
    if not f then
        f = make()
        list[i] = f
    end
    f:Show()
    return f
end

local function newHead()
    local h = CreateFrame("Button", nil, panel.head)
    h:SetFrameLevel(panel.head:GetFrameLevel() + 1)
    h:SetSize(ICON, ICON)
    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    h.icon = T.icon(h, nil, ICON)
    h.icon:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    -- Gold under the icon while the column has an override, blue when the
    -- draft changed it.
    h.mark = T.fill(h, T.COLOR.hand, 1, "ARTWORK")
    h.mark:SetHeight(2)
    h.mark:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2)
    h.mark:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", 0, -2)
    -- Under the mouse, a player's icon fades to grey and a red cross fades
    -- in over it, since a click takes their override away. The column under
    -- it fades to half, the part that goes with it. `fade` goes from 0 to 1
    -- and back a part of the way each frame. `under` is the column's frames,
    -- each with the alpha it has when nothing fades.
    h.grey = T.icon(h, nil, ICON)
    h.grey:SetDrawLayer("ARTWORK", 1)
    h.grey:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    h.grey:SetDesaturated(true)
    h.cross = {}
    for i, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local t = T.fill(h, T.COLOR.bad, 1, "OVERLAY", 7)
        t:SetSize(ICON, 2)
        t:SetPoint("CENTER", h, "CENTER", 0, 0)
        t:SetRotation(angle)
        h.cross[i] = t
    end
    h.fade, h.want, h.under = 0, 0, {}
    local function paintFade()
        h.grey:SetAlpha(h.fade)
        for _, t in ipairs(h.cross) do t:SetAlpha(h.fade) end
        for f, a in pairs(h.under) do f:SetAlpha(a * (1 - 0.5 * h.fade)) end
    end
    h.paintFade = paintFade
    local function step(self, elapsed)
        local d = self.want - self.fade
        local k = math.min(1, (elapsed or 0) * 10)
        self.fade = math.abs(d) < 0.02 and self.want or self.fade + d * k
        paintFade()
        if self.fade == self.want then self:SetScript("OnUpdate", nil) end
    end
    local function fadeTo(v)
        h.want = v
        h:SetScript("OnUpdate", step)
    end
    h:SetScript("OnEnter", function(self)
        if self.removable then fadeTo(1) end
        if self.tip then self.tip(self) end
    end)
    h:SetScript("OnLeave", function()
        fadeTo(0)
        GameTooltip:Hide()
    end)
    -- A spec's icon with an override goes back to auto on a right-click,
    -- and its edge lights to say so.
    T.hoverEdge(h, function(self) return self.canBack end)
    -- A player's initials over their icon.
    h.initials = T.text(h, T.SIZE.caption, true, 1)
    h.initials:SetPoint("BOTTOM", h, "TOP", 0, 3)
    paintFade()
    return h
end


local function newLabel()
    local f = CreateFrame("Frame", nil, panel.body)
    f:SetSize(LABEL_W, ROW)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local b = D.BY_ID[self.id]
        if b then T.spellTip(self, b, nil, Bs.rules(b)) end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The on or off box.
    f.on = CreateFrame("Button", nil, f)
    f.on:SetSize(BOX + 4, BOX + 4)
    f.on:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.on.box = CreateFrame("Frame", nil, f.on)
    f.on.box:SetSize(BOX, BOX)
    f.on.box:SetPoint("CENTER", f.on, "CENTER", 0, 0)
    f.on.box.bg = T.fill(f.on.box, { 0, 0, 0 }, 0.45)
    f.on.box.bg:SetAllPoints(f.on.box)
    T.border(f.on.box, { 1, 1, 1 }, 0.35)
    f.on.box.fill = T.fill(f.on.box, T.ACCENT, 1, "ARTWORK")
    f.on.box.fill:SetPoint("TOPLEFT", f.on.box, "TOPLEFT", 3, -3)
    f.on.box.fill:SetPoint("BOTTOMRIGHT", f.on.box, "BOTTOMRIGHT", -3, 3)
    f.on:SetScript("OnEnter", function(self) if self.tip then self.tip(self) end end)
    f.on:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.icon = T.icon(f, nil, LABEL_ICON)
    f.icon:SetPoint("LEFT", f, "LEFT", BOX + 8, 0)
    f.text = T.text(f, T.SIZE.body, false, T.A_TEXT)
    f.text:SetPoint("LEFT", f, "LEFT", BOX + 8 + LABEL_ICON + 6, 0)
    f.text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    f.text:SetWordWrap(false)
    NS.Config.kit.makeFlash(f)
    return f
end

local function newSection()
    local f = CreateFrame("Frame", nil, panel.body)
    f:SetHeight(SECTION_H)
    NS.Config.kit.makeFlash(f)
    f.label = T.text(f, T.SIZE.caption + 1, true, T.A_DIM)
    f.label:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 4)
    f.line = T.fill(f, { 1, 1, 1 }, 0.07, "ARTWORK")
    f.line:SetHeight(1)
    f.line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    return f
end

local function newCell()
    local c = CreateFrame("Button", nil, panel.body)
    c:SetSize(CELL, CELL)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c.icon = T.icon(c, nil, CELL)
    c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.mark = T.fill(c, T.COLOR.hand, 1, "ARTWORK")
    c.mark:SetHeight(2)
    c.mark:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -1)
    c.mark:SetPoint("TOPRIGHT", c, "BOTTOMRIGHT", 0, -1)
    c:SetScript("OnEnter", function(self) if self.tip then self.tip(self) end end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    T.hoverEdge(c, canChange)
    return c
end

-- Whether the draft changed what `key` wants of `id`, or of anything when
-- `id` is nil.
local function changedIn(key, id)
    return NS.Config.changedWhere(function(it)
        return it.kind == "want" and it.a == key and (id == nil or it.b == id)
    end)
end

local function paintCell(c, col, b)
    local on, own = wantOf(col, b)
    local changed = changedIn(col.key, b.id)
    c.col, c.id, c.on, c.own, c.changed = col, b.id, on, own, changed
    c.icon:SetTexture(Tr.icon(b))
    c.icon:SetDesaturated(not on)
    c.icon:SetAlpha(on and 1 or 0.25)
    local mark = changed and T.COLOR.changed or T.COLOR.hand
    c.mark:SetColorTexture(mark[1], mark[2], mark[3], 1)
    c.mark:SetShown(own or changed)
    local edit = canChange()
    c:SetScript("OnClick", function(_, button)
        if not edit then return end
        if button == "RightButton" then
            if own then Du.setWant(col.key, b.id, nil) end
        else
            Du.setWant(col.key, b.id, not on)
        end
    end)
    c.tip = function(self)
        local lines = { { format("%s for %s.", on and "Wanted" or "Not wanted", col.name), 1, 1, 1 } }
        if own then lines[#lines + 1] = T.line("Override.", "hand") end
        if changed then lines[#lines + 1] = T.line("Changed in the draft.", "changed") end
        local rules = Bs.rules(b)
        if #rules > 0 then lines[#lines + 1] = " " end
        for _, l in ipairs(rules) do lines[#lines + 1] = l end
        local list = { { "Click", "turn it on or off" } }
        if own then list[#list + 1] = { "Right-click", "back to auto" } end
        T.spellTip(self, b, nil, lines, NS.Config.hints(lines, list))
    end
end

-- A player who set their own blessing order on their You page has a column
-- too. Its mark under the icon is green, not gold, while that's all that's
-- set for them, so it's plain the player chose it and not the leader.
local function paintHead(h, col)
    local wants = false
    for _, s in ipairs(rows()) do
        for _, b in ipairs(s.buffs) do wants = wants or Du.wantOf(col.key, b) ~= nil end
    end
    local order, classOrder = NS.Priority.own(col.key)
    local own = wants or order or classOrder ~= nil
    local selfSet = order and col.m ~= nil and Du.selfOrder(col.m.name)
    local byLeader = wants or (order and not selfSet) or classOrder ~= nil
    local changed = changedIn(col.key) or NS.Priority.changed(col.key)
    h.col, h.changed = col, changed
    h.icon:SetTexture(col.tex)
    h.grey:SetTexture(col.tex)
    local mark = changed and T.COLOR.changed or (selfSet and not byLeader) and T.COLOR.up or T.COLOR.hand
    h.mark:SetColorTexture(mark[1], mark[2], mark[3], 1)
    h.mark:SetShown(own or changed)
    local edit = canChange()
    local function back()
        if not edit then return end
        if col.m then added[col.m.name] = nil end
        if own then clearColumn(col.key, col.m and col.m.name or col.name) elseif col.m then NS.Config.refresh() end
    end
    -- A player's column goes on either click, a spec's on a right-click.
    h:SetScript("OnClick", function(_, button)
        if col.m or button == "RightButton" then back() end
    end)
    h.removable = col.m ~= nil and edit
    h.canBack = own and edit and not col.m
    if not h.removable and h.want ~= 0 then
        h.want, h.fade = 0, 0
        h.paintFade()
    end
    h.initials:SetShown(col.m ~= nil)
    if col.m then h.initials:SetText(NS.classColored(NS.initials(col.m.name), col.m.class)) end
    local gone = col.m ~= nil and col.m.gone
    h.icon:SetAlpha(gone and 0.5 or 1)
    h.initials:SetAlpha(gone and 0.5 or 1)
    h.tip = function(self)
        local lines = {}
        if col.m then
            if byLeader then lines[#lines + 1] = T.line("Player override.", "hand") end
            if selfSet then
                lines[#lines + 1] = T.line(format("%s set their own blessings.", col.m.name), "up")
            end
            if gone then lines[#lines + 1] = T.line(col.m.name .. " isn't here.", "idle") end
        elseif own then
            lines[1] = T.line("Override.", "hand")
        end
        if changed then lines[#lines + 1] = T.line("Changed in the draft.", "changed") end
        local hints
        if col.m and edit then
            lines[#lines + 1] = format("%s goes back to what their spec needs.", NS.who(col.m))
            hints = NS.Config.hints(lines, { { "Click", "remove override" } })
        elseif own then
            hints = NS.Config.hints(lines, { { "Right-click", "back to auto" } })
        end
        T.tip(self, NS.iconText(col.tex, col.name), lines, hints)
    end
end

-- The buffs of job `job` in words: "Sunder Armor and Expose Armor".
local function buffsOf(job)
    local t = {}
    for _, id in ipairs(job.options) do t[#t + 1] = Tr.title(D.BY_ID[id]) end
    return NS.andList(t)
end

-- Row label `l`'s box, for the assignment of buff `b`.
local function paintOn(l, b)
    local job = D.JOB[b.job]
    local on = Du.enabled(job)
    l.isOn = on
    l.on.box.fill:SetShown(on)
    l.text:SetAlpha(on and 1 or T.A_DIM)
    l.icon:SetDesaturated(not on)
    local edit = canChange()
    l.on:SetScript("OnClick", function()
        if edit then Du.setEnabled(job, not Du.enabled(job)) end
    end)
    l.on.tip = function(self)
        local lines = { { on and "On." or "Off. Nobody is put on it.", 1, 1, 1 } }
        if #job.options > 1 then lines[#lines + 1] = format("Turns %s together.", buffsOf(job)) end
        T.tip(self, Du.title(job), lines, NS.Config.hints(lines, { { "Click", on and "turn it off" or "turn it on" } }))
    end
end

-- Keeps the row of icons at the top of the page's view while the page
-- scrolls past it, and back over the grid when the grid's top is in sight.
-- It never goes below the grid's last row.
local function stick(holder)
    local view = holder.view
    local hs, vs = holder:GetEffectiveScale(), view and view:GetEffectiveScale()
    local top, vtop = holder:GetTop(), view and view:GetTop()
    local push = 0
    if top and vtop and hs and hs > 0 then
        push = math.max(0, (top * hs - vtop * vs) / hs)
        push = min(push, math.max(0, (holder.gridH or 0) - (holder.top or TOP)))
    end
    if push == holder.push then return end
    holder.push = push
    holder.head:ClearAllPoints()
    holder.head:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -push)
    holder.head.under:SetShown(push > 0)
    holder.head.bg:SetShown(push > 0)
end

-- Draws the grid in `holder`, a frame of the page, `width` wide at most.
-- `view` is the page's scroll frame, for the row of icons to stay in.
-- Returns its height on the page.
function Bs.draw(holder, width, view)
    panel = holder
    if not holder.heads then
        holder.body = CreateFrame("Frame", nil, holder)
        -- The row of icons sits over the cells, on the panel's colour, so
        -- the rows pass under it when it stays at the top.
        holder.head = CreateFrame("Frame", nil, holder)
        holder.head:SetFrameLevel(holder.body:GetFrameLevel() + 20)
        holder.head.bg = T.fill(holder.head, T.BG, 1, "BACKGROUND")
        holder.head.bg:SetAllPoints(holder.head)
        holder.head.under = T.fill(holder.head, { 1, 1, 1 }, 0.1, "ARTWORK")
        holder.head.under:SetHeight(1)
        holder.head.under:SetPoint("BOTTOMLEFT", holder.head, "BOTTOMLEFT", 0, 0)
        holder.head.under:SetPoint("BOTTOMRIGHT", holder.head, "BOTTOMRIGHT", 0, 0)
        holder.head:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        holder.heads, holder.labels, holder.sections, holder.cells = {}, {}, {}, {}
        holder:SetScript("OnUpdate", stick)
    end
    holder.view = view
    local cols = columns(NS.Config.specFilter())
    -- Where each column sits, from the left of the cells.
    local xs, x, prev = {}, 0, nil
    for i, col in ipairs(cols) do
        if prev and (col.m and not prev.m) then
            x = x + PLAYER_GAP
        elseif prev and col.class ~= prev.class then
            x = x + CLASS_GAP
        end
        xs[i] = x
        x = x + COL
        prev = col
    end
    local w = LABEL_W + x
    -- Room over the icons for the players' initials.
    local top = TOP
    for _, col in ipairs(cols) do
        if col.m then top = TOP + PLAYER_TOP end
    end
    holder.body:ClearAllPoints()
    holder.body:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -top)
    for i, col in ipairs(cols) do
        local h = pooled(panel.heads, i, newHead)
        h.under = {}
        paintHead(h, col)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", panel.head, "TOPLEFT", LABEL_W + xs[i], -(top - TOP) - 4)
    end
    for j = #cols + 1, #panel.heads do panel.heads[j]:Hide() end
    local y, nl, ns, nc = 0, 0, 0, 0
    local function section(text)
        ns = ns + 1
        local sec = pooled(panel.sections, ns, newSection)
        sec.label:SetText(text:upper())
        sec:ClearAllPoints()
        sec:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -y)
        sec:SetWidth(w)
        y = y + SECTION_H + 2
    end
    -- Where C.focus goes, from the top of the grid.
    panel.marks = {}
    -- The blessings, each column's in order, with how to read them at the
    -- left.
    section("Blessings")
    panel.marks.order = { frame = panel.sections[ns], y = top + y - SECTION_H - 2 }
    if not panel.blessHint then
        local f = CreateFrame("Frame", nil, panel.body)
        f:SetSize(LABEL_W - 16, 10)
        f.text = T.text(f, T.SIZE.body, false, T.A_DIM)
        f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.text:SetWidth(LABEL_W - 16)
        f.text:SetWordWrap(true)
        f.text:SetJustifyH("LEFT")
        f.text:SetText("Top is wanted most. With one paladin a spec gets its top blessing, with two its top two. Drag to reorder, click to turn one off.")
        panel.blessHint = f
    end
    panel.blessHint:ClearAllPoints()
    panel.blessHint:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -(y + 2))
    -- A player who isn't here shows dimmed, their column too.
    local function dim(col) return col.m and col.m.gone and 0.5 or 1 end
    for i, col in ipairs(cols) do
        local c = NS.Priority.column(panel.body, i, col.key, col.name)
        panel.heads[i].under[c] = dim(col)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", panel.body, "TOPLEFT", LABEL_W + xs[i], -y)
    end
    NS.Priority.hideFrom(panel.body, #cols + 1)
    y = y + math.max(NS.Priority.PLACES * NS.Priority.COL, (panel.blessHint.text:GetStringHeight() or 0) + 6) + 4
    for _, s in ipairs(rows()) do
        section(s.section)
        for _, b in ipairs(s.buffs) do
            nl = nl + 1
            local l = pooled(panel.labels, nl, newLabel)
            l.icon:SetTexture(Tr.icon(b))
            l.text:SetText(Tr.title(b))
            l.id = b.id
            paintOn(l, b)
            if b.job and not panel.marks["onoff:" .. b.job] then
                panel.marks["onoff:" .. b.job] = { frame = l, y = top + y }
            end
            panel.marks["buff:" .. b.id] = panel.marks["buff:" .. b.id] or { frame = l, y = top + y }
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -y)
            for i, col in ipairs(cols) do
                nc = nc + 1
                local c = pooled(panel.cells, nc, newCell)
                paintCell(c, col, b)
                c:SetAlpha((l.isOn and 1 or 0.4) * dim(col))
                panel.heads[i].under[c] = (l.isOn and 1 or 0.4) * dim(col)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", panel.body, "TOPLEFT", LABEL_W + xs[i] + (ICON - CELL) / 2,
                           -(y + (ROW - CELL) / 2))
            end
            y = y + ROW
        end
        y = y + 4
    end
    -- A redraw under the mouse keeps the column faded.
    for i = 1, #cols do panel.heads[i].paintFade() end
    for j = nl + 1, #panel.labels do panel.labels[j]:Hide() end
    for j = ns + 1, #panel.sections do panel.sections[j]:Hide() end
    for j = nc + 1, #panel.cells do panel.cells[j]:Hide() end
    panel.head:SetSize(w, top)
    panel.body:SetSize(w, y)
    local scale = min(1, width / w)
    holder:SetScale(scale)
    holder:SetSize(w, top + y)
    holder.gridH, holder.top, holder.push = top + y, top, nil
    stick(holder)
    return (top + y) * scale, scale
end

-- The players here without a column, by class, to give one.
function Bs.addMenu(owner)
    if not canChange() then return end
    T.menu(owner, function(_, root)
        root:CreateTitle("Add player override")
        local keys, orders, any = Du.wantKeys(), NS.Priority.playerOrders(), false
        for _, class in ipairs(CLASSES) do
            local list = {}
            for _, m in ipairs(R.list()) do
                if m.class == class and not keys["name:" .. m.name] and not orders[m.name] and not added[m.name] then
                    list[#list + 1] = m
                end
            end
            if #list > 0 then
                table.sort(list, function(a, b) return a.name < b.name end)
                local sub = root:CreateButton(NS.classText(class, NS.classColored(NS.className(class), class)))
                for _, m in ipairs(list) do
                    sub:CreateButton(NS.who(m), function()
                        added[m.name] = true
                        NS.Config.showPlayer(m.class)
                    end)
                end
                any = true
            end
        end
        if not any then root:CreateNote("Nobody else is here.") end
    end)
end

-- Where the last drawing put the Blessings section, each job's first row
-- and each buff's row, for C.focus and C.goTo: { [key] = { frame, y } }.
function Bs.marks() return panel and panel.marks or {} end

-- Whether a player has a column, for the filter's Overrides.
function Bs.hasPlayers() return #columns("players") > 0 end

-- Whether a spec or player of `class` has needs set by hand, for the
-- filter's gold dot.
function Bs.marked(class)
    if NS.Priority.marked(class) then return true end
    for key in pairs(Du.wantKeys()) do
        local name = key:match("^name:(.+)$")
        local m = name and (R.byName(name) or NS.db.people[name])
        if key:match("^(%u+):") == class or type(m) == "table" and m.class == class then return true end
    end
    return false
end

-- Opens the window on Needs.
function Bs.open() NS.Config.open("needs") end

function Bs.shown() return NS.Config.shown() and NS.Config.current() == "needs" end

-- The cells that show, for the tests.
function Bs.cells()
    local t = {}
    for _, c in ipairs(panel and panel.cells or {}) do
        if c:IsVisible() then t[#t + 1] = c end
    end
    return t
end

-- The row labels that show, for the tests.
function Bs.labels()
    local t = {}
    for _, l in ipairs(panel and panel.labels or {}) do
        if l:IsVisible() then t[#t + 1] = l end
    end
    return t
end

-- The column heads that show, for the tests.
function Bs.heads()
    local t = {}
    for _, h in ipairs(panel and panel.heads or {}) do
        if h:IsVisible() then t[#t + 1] = h end
    end
    return t
end
