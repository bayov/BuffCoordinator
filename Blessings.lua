-- The Blessings section of the Assignments page (Config.lua): what each
-- class gets. It draws with the page's own pieces, Config.lua's C.kit.

local _, NS = ...
local D, R, Du, T, Tr = NS.Data, NS.Roster, NS.Duties, NS.Theme, NS.Tracking
local C = NS.Config
local min = math.min
local format = string.format
local classWord = NS.classWord
local upperFirst = NS.upperFirst
local andList = NS.andList

local K = C.kit
local RED, DIM, ROW_BG = K.RED, K.DIM, K.ROW_BG
local CLASSES, colored = K.CLASSES, K.colored
local heading, pool = K.heading, K.pool
local cards, missingIn, shortBless = K.cards, K.missingIn, K.shortBless
local warningLines = K.warningLines
local spellTip = T.spellTip

-- =============================================================
-- Blessings
-- =============================================================
-- What each class gets, as a table: a row per paladin, by their spec's
-- icon and initials, and a column per class here, under its icon. Each cell
-- is the icon of the blessing that paladin gives the class. Smaller icons
-- after it are blessings they give one player of the class only. The last
-- row says what each class misses, in red, when anything is. What each
-- class wants is set on Needs, and which paladin gives what by hand in
-- Overrides, so a click on an icon goes there (C.goTo).
local LABEL_W, HEAD_H, ROW_H, ROW_GAP = 64, 30, 30, 2
local CLASS_ICON, BLESS_ICON, EXTRA_ICON, MISS_ICON = 22, 22, 15, 22
local COL_MIN, COL_MAX = 38, 64

-- An icon with a tooltip, the `i`th of `list` on `parent`.
local function tipIcon(list, i, parent, size)
    local b = list[i]
    if not b then
        b = CreateFrame("Button", nil, parent)
        b:SetSize(size, size)
        b.icon = T.icon(b, nil, size)
        b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b:SetScript("OnEnter", function(self) if self.tipFn then self.tipFn(self) end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self) if self.places then C.goTo(self.places) end end)
        T.hoverEdge(b, function(self) return self.places ~= nil end)
        list[i] = b
    end
    b:Show()
    return b
end

-- A paladin's row: the stripe across the table, and their spec's icon and
-- initials at its left, which name them in a tooltip. The last row is
-- Missing.
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
    r.icon = T.icon(r, nil, 20)
    r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
    r.label = T.text(r, T.SIZE.label, true, 1)
    r.label:SetPoint("LEFT", r, "LEFT", 32, 0)
    r.label:SetWordWrap(false)
    return r
end

-- A class's column: its icon on top, which has the class's tooltip, then a
-- cell per paladin and what the class misses at the bottom. Its frame takes
-- no mouse, so the rows under it keep theirs.
local function makeResult(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:EnableMouse(false)
    r.head = CreateFrame("Frame", nil, r)
    r.head:SetSize(CLASS_ICON, CLASS_ICON)
    r.head:SetPoint("TOP", r, "TOP", 0, -2)
    r.head:EnableMouse(true)
    r.head:SetScript("OnEnter", function(self) if r.tipFn then r.tipFn(self) end end)
    r.head:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.class = T.icon(r.head, nil, CLASS_ICON)
    r.class:SetPoint("TOPLEFT", r.head, "TOPLEFT", 0, 0)
    -- How many miss a blessing sits inside its icon's bottom right corner.
    -- The icon is a frame of its own and draws over the column's text, so
    -- the count is on a frame above the icons.
    r.over = CreateFrame("Frame", nil, r)
    r.over:SetAllPoints(r)
    r.miss = T.text(r.over, T.SIZE.label, true, 1)
    r.miss:SetJustifyH("RIGHT")
    r.cells, r.extras, r.misses, r.empties = {}, {}, {}, {}
    return r
end

-- The classes here, in class order.
local function classesHere()
    local has, list = {}, {}
    for _, m in ipairs(Du.shownMembers()) do has[m.class] = true end
    for _, c in ipairs(CLASSES) do
        if has[c] then list[#list + 1] = c end
    end
    return list
end

-- What class `class` gets from the paladins of `plan`, as parts: "Kings
-- (Pal Alpha)", then "Might on Grom (Pal Beta)" for a single blessing.
-- With `icon`, the blessings and players have their icons, for the tooltip.
local function resultParts(plan, class, icon)
    local parts, singles = {}, {}
    local function bless(id)
        local b = D.BY_ID[id]
        return icon and NS.buffText(b, shortBless(b)) or shortBless(b)
    end
    local function giver(m) return icon and NS.who(m) or colored(m) end
    for _, a in ipairs(plan.list) do
        local g = a.byClass and a.byClass[class]
        if g then parts[#parts + 1] = format("%s (%s)", bless(g), giver(a.giver)) end
        for name, id in pairs(a.bless or {}) do
            local m = R.byName(name)
            if m and m.class == class and id ~= g then
                singles[#singles + 1] = { key = shortBless(D.BY_ID[id]) .. name,
                                          text = format("%s on %s (%s)", bless(id), name, giver(a.giver)) }
            end
        end
    end
    table.sort(singles, function(x, y) return x.key < y.key end)
    for _, x in ipairs(singles) do parts[#parts + 1] = x.text end
    return parts
end

-- "1 misses Might", "3 miss Might" or "3 miss a blessing", or "".
local function missText(plan, class)
    local n = missingIn(plan, class)
    if n == 0 then return "" end
    local w = plan.warnings[class]
    local ids = {}
    for id in pairs(w.missing) do ids[#ids + 1] = id end
    local what = #ids == 1 and shortBless(D.BY_ID[ids[1]]) or "a blessing"
    return format("%d %s %s", n, n == 1 and "misses" or "miss", what)
end

-- Whether everyone who misses a blessing in class `class` only gets one
-- they rank lower in its place, for an override (Du.costs). That's orange,
-- not red.
local function missedForAssign(plan, class)
    local w = plan.warnings and plan.warnings[class]
    if not w then return false end
    local cost = Du.costs().byFamily.blessing or {}
    for _, people in pairs(w.missing) do
        for _, m in ipairs(people) do
            if cost[m.name] ~= "low" then return false end
        end
    end
    return true
end

-- The blessings paladin `a` (an assignment of `plan`) gives class `class`:
-- the one for the whole class, and the ones for one player each, as
-- { id, name }, by blessing then player.
-- What paladin assignment `a` gives class `class`: its blessing for the
-- class, and the ones it gives single players of it, one entry a blessing
-- as { id, names }.
local function givesTo(a, class)
    local g = a.byClass and a.byClass[class]
    local byId, singles = {}, {}
    for name, id in pairs(a.bless or {}) do
        local m = R.byName(name)
        if m and m.class == class and id ~= g then
            if not byId[id] then
                byId[id] = { id = id, names = {} }
                singles[#singles + 1] = byId[id]
            end
            table.insert(byId[id].names, name)
        end
    end
    for _, x in ipairs(singles) do table.sort(x.names) end
    table.sort(singles, function(x, y) return x.id < y.id end)
    return g, singles
end

-- Paladin `m`'s spec icon, or the class's when we don't know the spec.
local function specIcon(m)
    local spec = m.spec and D.SPECS[m.class] and D.SPECS[m.class][m.spec]
    return spec and spec.icon or T.classIcon(m.class)
end

-- The tooltip of class `class`'s column: what it gets from whom, what it
-- misses, and the order it wants.
local function classTip(self, plan, class, cost)
    local lines = {}
    local parts = resultParts(plan, class, true)
    for _, p in ipairs(parts) do lines[#lines + 1] = { p, 1, 1, 1 } end
    if #parts == 0 then lines[1] = "No blessings." end
    local w = plan.warnings and plan.warnings[class]
    if w then
        lines[#lines + 1] = " "
        for _, l in ipairs(warningLines(w)) do lines[#lines + 1] = T.line(l, cost and "low" or "bad") end
    end
    if cost then C.causeLines(lines, D.JOB.blessings.options) end
    local order = Du.blessOrderOf(class) or Du.baseOrder(class)
    local t = {}
    for i = 1, min(#order, #plan.list) do
        local b = D.BY_ID[order[i]]
        t[#t + 1] = NS.buffText(b, shortBless(b))
    end
    if #t > 0 then lines[#lines + 1] = format("They want %s, in that order.", andList(t)) end
    T.tip(self, NS.classText(class, "Blessings for " .. classWord(class)), lines)
end

-- The players of `class` with too low a rank of blessing `id` from assignment
-- `a`, on the icon's word and in its tooltip.
local function lowOf(a, class, id)
    local out = {}
    for _, t in ipairs(Tr.status(a).low or {}) do
        if t.b.id == id and t.m.class == class then out[#out + 1] = t end
    end
    return out
end

-- The tooltip lines of a blessing icon: `text`, then who has too low a rank.
local function withLow(text, low)
    local lines = { text }
    local line = Tr.lowLine(low)
    if line then lines[2] = T.line(line, "low") end
    return lines
end

-- Places icons of `size` across a cell `w` wide at `top` in column `r`,
-- centred: the class's blessing first, then the single ones while they fit.
local function placeCell(r, w, top, main, singles, a, class, counts)
    local room = math.floor((w - 4 - BLESS_ICON) / (EXTRA_ICON + 1))
    local n = math.min(#singles, math.max(0, room))
    local x = math.floor((w - BLESS_ICON - n * (EXTRA_ICON + 1)) / 2)
    if main then
        counts.c = counts.c + 1
        local c = tipIcon(r.cells, counts.c, r, BLESS_ICON)
        local b = D.BY_ID[main]
        c.icon:SetTexture(Tr.icon(b))
        c.id = main
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", r, "TOPLEFT", x, -(top + (ROW_H - BLESS_ICON) / 2))
        c.places = C.whereSet(D.JOB.blessings, a, b, class)
        local low = lowOf(a, class, main)
        T.downrank(c, #low > 0, nil, w - 2)
        c.tipFn = function(self)
            spellTip(self, b, nil, withLow(format("From %s to all %s.", NS.who(a.giver), classWord(class)), low),
                     { C.goHint(self.places) })
        end
    else
        counts.e = counts.e + 1
        local e = r.empties[counts.e]
        if not e then
            e = T.text(r, T.SIZE.body, false, T.A_OFF)
            e:SetText("-")
            r.empties[counts.e] = e
        end
        e:Show()
        e:ClearAllPoints()
        e:SetPoint("CENTER", r, "TOPLEFT", x + BLESS_ICON / 2, -(top + ROW_H / 2))
    end
    x = x + BLESS_ICON + 1
    for k = 1, n do
        local sgl = singles[k]
        counts.x = counts.x + 1
        local c = tipIcon(r.extras, counts.x, r, EXTRA_ICON)
        local b = D.BY_ID[sgl.id]
        c.icon:SetTexture(Tr.icon(b))
        c.id = sgl.id
        -- How many get it, over the icon's corner, when it's more than one.
        if not c.num then
            c.num = T.text(c, T.SIZE.caption, true, 1)
            c.num:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 3, -2)
            c.num:SetShadowOffset(1, -1)
        end
        c.num:SetText(#sgl.names > 1 and tostring(#sgl.names) or "")
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", r, "TOPLEFT", x, -(top + (ROW_H - EXTRA_ICON) / 2))
        c.places = C.whereSet(D.JOB.blessings, a, b, class)
        local low = lowOf(a, class, sgl.id)
        T.downrank(c, #low > 0, nil, EXTRA_ICON + 16)
        c.tipFn = function(self)
            local who = {}
            for i, name in ipairs(sgl.names) do
                local m = R.byName(name)
                who[i] = m and NS.who(m) or name
            end
            spellTip(self, b, nil, withLow(format("From %s to %s only.", NS.who(a.giver), andList(who)), low),
                     { C.goHint(self.places) })
        end
        x = x + EXTRA_ICON + 1
    end
end

local function blessResults(page, y, plan)
    local W = K.pageWidth(page)
    local classes = classesHere()
    local colW = math.max(COL_MIN, min(COL_MAX, math.floor((W - LABEL_W) / math.max(1, #classes))))
    local missAny = false
    for _, class in ipairs(classes) do missAny = missAny or missingIn(plan, class) > 0 end
    -- The rows: a stripe each, from under the class icons.
    local rowTop = function(i) return HEAD_H + (i - 1) * (ROW_H + ROW_GAP) end
    local nRows = #plan.list + (missAny and 1 or 0)
    for i = 1, nRows do
        local r = pool(page, "blessRow", makeRow)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -(y + rowTop(i)))
        r:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -(y + rowTop(i)))
        local a = plan.list[i]
        if a then
            local m = a.giver
            r.icon:SetTexture(specIcon(m))
            r.icon:Show()
            r.label:SetText(NS.classColored(NS.initials(m.name), m.class))
            r.palName = m.name
            r.tipFn = function(self)
                local spec = m.spec and Du.specName(m.class, m.spec)
                T.tip(self, NS.who(m), { (spec and spec .. " " or "") .. NS.className(m.class) })
            end
        else
            r.icon:Hide()
            r.label:SetText(T.hex(RED) .. "Missing|r")
            r.palName = nil
            r.tipFn = function(self) T.tip(self, "Missing", { "Who misses a blessing they want, by class." }) end
        end
    end
    local height = rowTop(nRows + 1) - ROW_GAP

    for k, class in ipairs(classes) do
        local r = pool(page, "result", makeResult)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", page.body, "TOPLEFT", LABEL_W + (k - 1) * colW, -y)
        r:SetSize(colW, height)
        local parts = resultParts(plan, class)
        r.class:SetTexture(T.classIcon(class))
        r.resultText = table.concat(parts, ", ")
        local cost = missedForAssign(plan, class)
        r.tipFn = function(self) classTip(self, plan, class, cost) end
        -- A cell per paladin: the class's blessing, then the single ones.
        local counts = { c = 0, x = 0, e = 0 }
        for i, a in ipairs(plan.list) do
            local main, singles = givesTo(a, class)
            placeCell(r, colW, rowTop(i), main, singles, a, class, counts)
        end
        for i = counts.c + 1, #r.cells do r.cells[i]:Hide() end
        for i = counts.x + 1, #r.extras do r.extras[i]:Hide() end
        for i = counts.e + 1, #r.empties do r.empties[i]:Hide() end
        -- What the class misses, on the last row: the first blessing's icon,
        -- faded, with how many miss one inside its bottom right corner.
        local mc = cost and T.COLOR.low or RED
        local w = plan.warnings and plan.warnings[class]
        local ids = {}
        for id in pairs(w and w.missing or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        local nm = 0
        local top = rowTop(#plan.list + 1)
        local count = missingIn(plan, class)
        if count > 0 and ids[1] then
            nm = 1
            local c = tipIcon(r.misses, 1, r, MISS_ICON)
            local b = D.BY_ID[ids[1]]
            c.id = ids[1]
            c.icon:SetTexture(Tr.icon(b))
            c.icon:SetDesaturated(true)
            c.icon:SetAlpha(0.7)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", r, "TOPLEFT", math.floor((colW - MISS_ICON) / 2), -(top + (ROW_H - MISS_ICON) / 2))
            c.places = C.whereSet(D.JOB.blessings, nil, b, class)
            c.tipFn = function(self)
                local lines = {}
                for _, id in ipairs(ids) do
                    local who = {}
                    for _, m in ipairs(w.missing[id]) do who[#who + 1] = NS.who(m) end
                    lines[#lines + 1] = T.line(format("%s missing for %s.", NS.buffText(D.BY_ID[id], shortBless(D.BY_ID[id])),
                                                      andList(who)), cost and "low" or "bad")
                end
                -- Why, as the Blessings card says it.
                local why, seen = {}, {}
                for _, id in ipairs(ids) do
                    for _, x in ipairs(C.missWhy(w, id)) do
                        if not seen[x] then
                            seen[x] = true
                            why[#why + 1] = x
                        end
                    end
                end
                for _, x in ipairs(why) do lines[#lines + 1] = upperFirst(x) .. "." end
                if cost then C.causeLines(lines, D.JOB.blessings.options) end
                if #why == 0 and not cost then
                    lines[#lines + 1] = "Every paladin gives them something else."
                end
                T.tip(self, NS.classText(class, format("%s miss %s", upperFirst(classWord(class)),
                                                        #ids == 1 and shortBless(b) or "blessings")), lines,
                      { C.goHint(self.places) })
            end
            r.over:SetFrameLevel(c:GetFrameLevel() + 1)
            r.miss:ClearAllPoints()
            r.miss:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
        end
        for i = nm + 1, #r.misses do r.misses[i]:Hide() end
        r.miss:SetText(nm > 0 and tostring(count) or "")
        r.miss:SetTextColor(mc[1], mc[2], mc[3], 1)
        r.missText = missText(plan, class)
    end
    return y + height
end

function C.blessSection(page, y, gapWhy, gapCost)
    local plan = Du.shown("blessings")
    local job = D.JOB.blessings
    local needed = plan and (plan.active or gapWhy.blessings)
    if not needed then return y end
    y = heading(page, "Blessings", y)
    local gap = not plan.active and gapWhy.blessings or nil
    y = cards(page, { { job = job, gap = gap, cost = gap and gapCost.blessings } }, y)
    if not plan.active then return y end
    return blessResults(page, y, plan) + 4
end
