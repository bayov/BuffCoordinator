-- The Party buffs section of the Assignments page (Config.lua): who gives
-- each party the buffs that reach only the giver's party. A click goes to
-- where it's set. It draws with the page's own pieces, Config.lua's C.kit.

local _, NS = ...
local D, R, Du, Tr, T = NS.Data, NS.Roster, NS.Duties, NS.Tracking, NS.Theme
local C = NS.Config
local floor = math.floor
local min = math.min
local ceil = math.ceil
local format = string.format

local K = C.kit
local BLUE, GREY, DIM, hex, ROW_BG = K.BLUE, K.GREY, K.DIM, K.hex, K.ROW_BG
local CARD_H, CARD_MIN, CARD_GAP = K.CARD_H, K.CARD_MIN, K.CARD_GAP
local changedWhere = K.changedWhere
local colored, countOf, heading, makeCard, makeFlash = K.colored, K.countOf, K.heading, K.makeCard, K.makeFlash
local mark, pool, spellTip = K.mark, K.pool, K.spellTip
local pageWidth, reachesParty = K.pageWidth, K.reachesParty

-- =============================================================
-- Party buffs
-- =============================================================
-- The buffs that reach only the giver's party: a paladin's aura, a shaman's
-- totem of each element and the Imp's Blood Pact. Only the kinds someone
-- here gives show, and the ones that are missing.
--
-- A party gets a card for each, the same as the sections above it. A raid
-- gets a table like Blessings: a row for each kind of buff and a column for
-- each group, where a cell is the buff's icon and who gives it. A raid of
-- more than four groups that doesn't fit across goes in two blocks of four.
local PARTY_ROWS = {
    { label = "Paladin aura", job = "paladinAura" },
    { label = "Earth totem", element = "earth" },
    { label = "Water totem", element = "water" },
    { label = "Air totem", element = "air" },
    { label = "Blood Pact", job = "bloodpact" },
}
local LABEL_W, HEAD_H, ROW_H, ROW_GAP, COL_GAP = 104, 22, 30, 2, 3
local CELL_ICON = 22
-- A column narrower than this has no room for the count, and a raid's
-- groups that would be narrower go in two blocks.
local COL_MIN = 110

-- The buffs row `row` may be.
local function rowBuffs(row)
    local t = {}
    if row.job then
        for _, id in ipairs(D.JOB[row.job].options) do t[#t + 1] = D.BY_ID[id] end
    else
        for _, id in ipairs(D.JOB.totems.options) do
            local b = D.BY_ID[id]
            if b.party and b.element == row.element then t[#t + 1] = b end
        end
    end
    return t
end

-- The assignments of row `row` for group `g`.
--
-- While a fight is on, a paladin in the group may put up a resistance aura
-- in place of their usual one. That aura reaches only their party too, so
-- it shows in the Paladin aura row, after the usual auras.
local function rowIn(row, g)
    local t = {}
    local plan = Du.shown(row.job or "totems")
    for _, a in ipairs(plan and plan.active and plan.list or {}) do
        if a.party == g and (not row.element or a.buff.element == row.element) then t[#t + 1] = a end
    end
    if row.job == "paladinAura" then
        local fight = Du.shown("resistances")
        for _, a in ipairs(fight and fight.active and fight.list or {}) do
            if a.buff.family == "paladinAura" and a.giver.group == g then t[#t + 1] = a end
        end
    end
    return t
end

-- Who gives it: the first giver, and how many more when there are more.
local function giversOf(list)
    return colored(list[1].giver) .. (#list > 1 and format(" %s+%d|r", DIM, #list - 1) or "")
end

-- Whether the draft changed what group `g` gets in row `row`.
local function changedIn(row, g)
    local job = row.job and D.JOB[row.job] or D.JOB.totems
    return changedWhere(function(it)
        if it.job ~= job.id then return false end
        if it.kind == "totem" and it.b ~= row.element then return false end
        return reachesParty(it, g)
    end)
end

local function missingLine(gap)
    return T.line("Missing" .. (gap ~= "" and ": " .. gap or "") .. ".", "gap")
end

-- Where what row `row` shows is set, from the first of `list` that gives
-- it (C.whereSet). A resistance aura is set on Resistances.
local function placesFor(row, list)
    local a = list[1]
    local job = a and a.job or D.JOB[row.job or "totems"]
    return C.whereSet(job, a, not a and rowBuffs(row)[1] or nil)
end

-- The tooltip of what group `g` gets in row `row`: the game's spell
-- tooltip, then each giver and why. `gap` is why nobody gives it, and a
-- click goes to `places`.
local function tipFor(self, row, list, changed, gap, places)
    local lines = {}
    for _, x in ipairs(list) do
        lines[#lines + 1] = { format("%s: %s", NS.who(x.giver), NS.buffText(x.buff)), 1, 1, 1 }
        if x.why then lines[#lines + 1] = x.why end
        if x.note then lines[#lines + 1] = x.note end
    end
    if #list == 0 then lines[1] = gap and missingLine(gap) or "Nobody here gives it." end
    if changed then lines[#lines + 1] = T.line("Changed in the draft.", "changed") end
    if list[1] then C.causeLines(lines, { list[1].buff.id }) end
    spellTip(self, list[1] and list[1].buff or rowBuffs(row)[1], row.label, lines, { C.goHint(places) })
end

-- So the Missing list and an override can take us to what row `row` shows.
local function markRow(page, row, list, f, y)
    mark(page, row.job or "totems", f, y)
    for _, x in ipairs(list) do
        if row.element then mark(page, format("totem:%s:%s", x.giver.name, row.element), f, y) end
    end
end

-- The rows with something to show: any group gets it, or nobody gives it
-- and someone wants it.
local function partyRows(groups, gapWhy)
    local t = {}
    for _, row in ipairs(PARTY_ROWS) do
        local any = row.job and gapWhy[row.job] ~= nil
        for _, g in ipairs(groups) do
            any = any or #rowIn(row, g) > 0
        end
        if any then t[#t + 1] = row end
    end
    return t
end

-- =============================================================
-- A party: cards
-- =============================================================
-- Card `c` for what row `row` gives group `g`, as the cards above it look:
-- the buff's icon, its name, who gives it and how many have it. One nobody
-- gives says why, and is faded with a grey edge.
local function paintCard(page, c, y, row, g, gap)
    local list = rowIn(row, g)
    local a = list[1]
    local b = a and a.buff or rowBuffs(row)[1]
    c.partyCell = true
    c.icon:SetTexture(Tr.icon(b))
    c.icon:SetDesaturated(a == nil)
    c.icon:SetAlpha(a and 1 or 0.5)
    c.name:SetText(a and Tr.title(a.buff) or row.label)
    c.name:SetTextColor(1, 1, 1, a and 1 or T.A_DIM)
    local count, color = countOf(list)
    c.count:SetText(count or "")
    if color then c.count:SetTextColor(color[1], color[2], color[3], 1) end
    if a then
        c.who:SetText(giversOf(list))
    elseif gap then
        c.who:SetText(hex(T.COLOR.gap) .. "Missing" .. (gap ~= "" and ": " .. gap or "") .. "|r")
    else
        c.who:SetText(DIM .. "Nobody here gives it|r")
    end
    c.changed = changedIn(row, g)
    if c.changed then
        T.paint(c, BLUE, 0.9)
    elseif not a then
        T.paint(c, GREY, 0.9)
    else
        T.paint(c, { 1, 1, 1 }, 0.08)
    end
    c.places = placesFor(row, list)
    c.tipFn = function(self) tipFor(self, row, list, c.changed, gap, c.places) end
    markRow(page, row, list, c, y)
end

local function partyCards(page, y, rows, g, gapWhy)
    local width = pageWidth(page)
    local cols = math.max(1, floor((width + CARD_GAP) / (CARD_MIN + CARD_GAP)))
    local w = floor((width - (cols - 1) * CARD_GAP) / cols)
    for i, row in ipairs(rows) do
        local col, line = (i - 1) % cols, floor((i - 1) / cols)
        local cy = y + line * (CARD_H + CARD_GAP)
        local c = pool(page, "partyCard", makeCard)
        paintCard(page, c, cy, row, g, row.job and gapWhy[row.job])
        c:SetWidth(w)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", page.body, "TOPLEFT", col * (w + CARD_GAP), -cy)
    end
    return y + (floor((#rows - 1) / cols) + 1) * (CARD_H + CARD_GAP)
end

-- =============================================================
-- A raid: a table
-- =============================================================
-- A row's stripe across the table, with its name at the left. The name of
-- a row nobody gives is orange, and says why in its tooltip.
local function makeRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    r.bg = T.fill(r, { 1, 1, 1 }, ROW_BG)
    r.bg:SetAllPoints(r)
    r.hit = CreateFrame("Frame", nil, r)
    r.hit:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.hit:SetSize(LABEL_W, ROW_H)
    r.hit:EnableMouse(true)
    r.hit:SetScript("OnEnter", function(self) if r.tipFn then r.tipFn(self) end end)
    r.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.label = T.text(r, T.SIZE.label, true, 1)
    r.label:SetPoint("LEFT", r, "LEFT", 8, 0)
    r.label:SetWidth(LABEL_W - 12)
    r.label:SetWordWrap(false)
    return r
end

-- A cell: the buff's icon, who gives it, and how many have it at the
-- right. An empty one is a faint dash in the middle, as on Blessings. It has
-- no fill of its own, so the row's stripe shows through, and an edge only
-- when the draft changed it.
local function makeCell(parent)
    local c = CreateFrame("Button", nil, parent)
    c.partyCell = true
    c:SetHeight(ROW_H)
    T.border(c, { 1, 1, 1 }, 0)
    makeFlash(c)
    c.icon = T.icon(c, nil, CELL_ICON)
    c.icon:SetPoint("LEFT", c, "LEFT", 4, 0)
    c.count = T.text(c, T.SIZE.caption, true, 1)
    c.count:SetPoint("RIGHT", c, "RIGHT", -6, 0)
    c.count:SetJustifyH("RIGHT")
    c.text = T.text(c, T.SIZE.body, false)
    c.text:SetPoint("LEFT", c, "LEFT", CELL_ICON + 10, 0)
    c.text:SetPoint("RIGHT", c.count, "LEFT", -4, 0)
    c.text:SetWordWrap(false)
    c.dash = T.text(c, T.SIZE.body, false, T.A_OFF)
    c.dash:SetPoint("CENTER", c, "CENTER", 0, 0)
    c.dash:SetText("-")
    -- A click goes to where it's set (C.goTo).
    c:SetScript("OnEnter", function(self) if self.tipFn then self.tipFn(self) end end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetScript("OnClick", function(self) if self.places then C.goTo(self.places) end end)
    T.hoverEdge(c, function(self) return self.places ~= nil end)
    return c
end

-- Fills cell `c` at `y` with what row `row` gives group `g`, `w` wide.
local function paintCell(page, c, y, row, g, w, gap)
    local list = rowIn(row, g)
    local a = list[1]
    c.icon:SetTexture(a and Tr.icon(a.buff) or nil)
    c.icon:SetShown(a ~= nil)
    c.dash:SetShown(a == nil)
    local count, color = countOf(list)
    c.count:SetText(w >= COL_MIN and count or "")
    if color then c.count:SetTextColor(color[1], color[2], color[3], 1) end
    c.text:SetText(a and giversOf(list) or "")
    c:SetWidth(w)
    c.changed = changedIn(row, g)
    if c.changed then T.paint(c, BLUE, 0.9) else T.paint(c, { 1, 1, 1 }, 0) end
    c.places = placesFor(row, list)
    c.tipFn = function(self) tipFor(self, row, list, c.changed, gap, c.places) end
    markRow(page, row, list, c, y)
end

local function makeGroupHead(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(HEAD_H)
    f.text = T.text(f, T.SIZE.caption, true, T.A_DIM)
    f.text:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
    return f
end

local function raidTable(page, y, rows, groups, gapWhy)
    local width = pageWidth(page)
    local per = #groups
    local function colW(n) return floor((width - LABEL_W - (n - 1) * COL_GAP) / n) end
    if colW(per) < COL_MIN and per > 4 then per = ceil(per / 2) end
    local w = colW(per)
    for start = 1, #groups, per do
        local block = {}
        for i = start, min(#groups, start + per - 1) do block[#block + 1] = groups[i] end
        if start > 1 then y = y + 10 end
        for i, g in ipairs(block) do
            local h = pool(page, "groupHead", makeGroupHead)
            h.text:SetText(format("GROUP %d", g))
            h:SetWidth(w)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", page.body, "TOPLEFT", LABEL_W + (i - 1) * (w + COL_GAP), -y)
        end
        y = y + HEAD_H
        for _, row in ipairs(rows) do
            local gap = row.job and gapWhy[row.job]
            local r = pool(page, "partyRow", makeRow)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -y)
            r.label:SetText(gap and hex(T.COLOR.gap) .. row.label .. "|r" or row.label)
            r.tipFn = gap and function(self) T.tip(self, row.label, { missingLine(gap) }) end or nil
            for i, g in ipairs(block) do
                local c = pool(page, "partyCell", makeCell)
                paintCell(page, c, y, row, g, w, gap)
                c:SetFrameLevel(r:GetFrameLevel() + 2)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", page.body, "TOPLEFT", LABEL_W + (i - 1) * (w + COL_GAP), -y)
            end
            y = y + ROW_H + ROW_GAP
        end
    end
    return y - ROW_GAP + 4
end

function C.partySection(page, y, gapWhy)
    local seen, groups = {}, {}
    for _, m in ipairs(Du.shownMembers()) do
        if not seen[m.group] then
            seen[m.group] = true
            groups[#groups + 1] = m.group
        end
    end
    table.sort(groups)
    if #groups == 0 then return y end
    local rows = partyRows(groups, gapWhy)
    if #rows == 0 then return y end
    y = heading(page, "Party buffs", y)
    if not R.raid() then return partyCards(page, y, rows, groups[1], gapWhy) end
    return raidTable(page, y, rows, groups, gapWhy)
end
