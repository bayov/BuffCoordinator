-- Resistances, a page of the assignments window (Config.lua): a column per
-- school and a row per fight. It draws with the page's own pieces,
-- Config.lua's C.kit.

local _, NS = ...
local D, R, Du, Tr, T = NS.Data, NS.Roster, NS.Duties, NS.Tracking, NS.Theme
local C = NS.Config
local format = string.format

local K = C.kit
local BLUE, RED = K.BLUE, K.RED
local ROW_BG, ROW_HOVER, canChange, changedWhere = K.ROW_BG, K.ROW_HOVER, K.canChange, K.changedWhere
local colored, makeFlash, mark = K.colored, K.makeFlash, K.mark
local pool, spellTip = K.pool, K.spellTip

-- =============================================================
-- Resistances
-- =============================================================
-- A table like Needs: a column per school under its icon, and a row per
-- fight. A fight is set up once and turned on before the pull, and while
-- it's on each school it needs has a giver, who puts the resistance up in
-- place of something else of theirs.
--
-- A row has the box that turns the fight on (one at a time), its name
-- (a click renames it), a cell per school and what the fight costs the
-- raid, and a cross that deletes it. A school's cell is the resistance
-- that covers it when the fight needs it, and a click needs it or not.
-- Under it, who gives it, and a click there picks someone else. Add fight,
-- at the right of the page's line, adds one (C.newFight).
local LABEL_W, COL, CELL, BOX = 190, 60, 22, 12
local ROW_H, HEAD_H = 46, 26

-- Asks for a fight's name, the target's to begin with.
function C.newFight()
    local name = UnitExists("target") and UnitName("target")
    if type(name) ~= "string" or NS.secret(name) then name = "" end
    T.ask("Name the fight, like the boss:", name, Du.addFight)
end

-- Asks for a new name for fight `fight`.
local function renameFight(fight)
    T.ask("Rename the fight:", fight, function(name)
        name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
        if name ~= "" and name ~= fight and not Du.renameFight(fight, name) then
            NS.print("There's a fight called %s already.", name)
        end
    end)
end

local function sameResist(a, b)
    if type(a) == "table" and type(b) == "table" then return a.giver == b.giver and a.buff == b.buff end
    return a == b
end

local function schoolMenu(owner, school, fight)
    if not canChange() then return end
    T.menu(owner, function(_, root)
        root:CreateTitle(format("%s resistance in %s", school.title, fight))
        local function radio(label, value)
            root:CreateRadio(label, function() return sameResist(Du.resist(fight, school.id), value) end,
                             function() Du.setResist(fight, school.id, value) end)
        end
        radio("Not needed", nil)
        radio("Auto", true)
        local any = false
        for _, id in ipairs(school.sources) do
            local b = D.BY_ID[id]
            if b.kind ~= "long" then
                for _, m in ipairs(Du.shownMembers()) do
                    if Du.canGive(m, b) then
                        if not any then root:CreateDivider() end
                        any = true
                        radio(format("%s: %s", NS.who(m), NS.buffText(b)), { giver = m.name, buff = id })
                    end
                end
            end
        end
    end)
end

-- What a resistance takes the place of, in words.
local function insteadText(s)
    if s.instead then
        local a = s.instead
        local what = Tr.title(a.buff)
        if a.party and R.raid() then what = format("%s for group %d", what, a.party) end
        return format("instead of %s", what)
    end
    if s.b and s.b.class == "HUNTER" then return "instead of their own aspect" end
    if s.b and s.b.element == "fire" and s.m and s.m.specKey ~= "restoration" then
        return "instead of their own fire totem"
    end
    return "costs nothing"
end

-- What fight `plan` costs the raid, in words.
local function lossText(plan)
    if not plan or not plan.lost then return "" end
    local parts = {}
    for _, l in ipairs(plan.lost) do
        local what = NS.iconText(Tr.icon(l.b), Tr.title(l.b), 12)
        if l.party and R.raid() then what = format("%s (group %d)", what, l.party) end
        parts[#parts + 1] = what
    end
    local own = {}
    for _, a in ipairs(plan.own or {}) do own[#own + 1] = colored(a.giver) end
    local text = #parts > 0 and format("Loses %s.", table.concat(parts, ", "))
                 or (next(plan.schools or {}) and T.hex("up") .. "Costs nothing.|r" or "")
    if #own > 0 then text = text .. format(" %s lose a little damage.", table.concat(own, ", ")) end
    return text
end

-- =============================================================
-- The table
-- =============================================================
-- The school icons over the columns.
local function makeHead(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(HEAD_H)
    f.label = T.text(f, T.SIZE.caption + 1, true, T.A_DIM)
    f.label:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 6)
    f.label:SetText("FIGHT")
    f.cost = T.text(f, T.SIZE.caption + 1, true, T.A_DIM)
    f.cost:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LABEL_W + #D.SCHOOLS * COL + 8, 6)
    f.cost:SetText("COST")
    f.schools = {}
    for i, school in ipairs(D.SCHOOLS) do
        local b = CreateFrame("Frame", nil, f)
        b:SetSize(CELL, CELL)
        b:SetPoint("BOTTOM", f, "BOTTOMLEFT", LABEL_W + (i - 0.5) * COL, 2)
        b:EnableMouse(true)
        b.icon = T.icon(b, school.icon, CELL)
        b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b:SetScript("OnEnter", function(self)
            local list = {}
            for _, id in ipairs(school.sources) do list[#list + 1] = Tr.title(D.BY_ID[id]) end
            T.tip(self, school.title .. " resistance", { format("From %s.", table.concat(list, " or ")) })
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.schools[i] = b
    end
    f.line = T.fill(f, { 1, 1, 1 }, 0.1, "ARTWORK")
    f.line:SetHeight(1)
    f.line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, -3)
    f.line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, -3)
    return f
end

-- A fight's row. The edge is blue when the draft changed the fight, and a
-- green strip at the left says it's on.
local function makeFightRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    r:EnableMouse(true)
    r.bg = T.fill(r, { 1, 1, 1 }, ROW_BG)
    r.bg:SetAllPoints(r)
    T.border(r, { 1, 1, 1 }, 0)
    makeFlash(r)
    r.strip = T.fill(r, T.COLOR.up, 1, "ARTWORK")
    r.strip:SetWidth(2)
    r.strip:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.strip:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    -- The on or off box, as on Needs.
    r.on = CreateFrame("Button", nil, r)
    r.on:SetSize(BOX + 6, BOX + 6)
    r.on:SetPoint("LEFT", r, "LEFT", 7, 0)
    r.on.box = CreateFrame("Frame", nil, r.on)
    r.on.box:SetSize(BOX, BOX)
    r.on.box:SetPoint("CENTER", r.on, "CENTER", 0, 0)
    r.on.box.bg = T.fill(r.on.box, { 0, 0, 0 }, 0.45)
    r.on.box.bg:SetAllPoints(r.on.box)
    T.border(r.on.box, { 1, 1, 1 }, 0.35)
    r.on.box.fill = T.fill(r.on.box, T.COLOR.up, 1, "ARTWORK")
    r.on.box.fill:SetPoint("TOPLEFT", r.on.box, "TOPLEFT", 3, -3)
    r.on.box.fill:SetPoint("BOTTOMRIGHT", r.on.box, "BOTTOMRIGHT", -3, 3)
    r.on:SetScript("OnEnter", function(self) if self.tip then self.tip(self) end end)
    r.on:SetScript("OnLeave", function() GameTooltip:Hide() end)
    T.hoverEdge(r.on, canChange)
    -- The name, which a click renames, and On now or Off under it.
    r.title = CreateFrame("Button", nil, r)
    r.title:SetPoint("TOPLEFT", r, "TOPLEFT", BOX + 20, -7)
    r.title:SetSize(LABEL_W - BOX - 28, 16)
    r.name = T.text(r.title, T.SIZE.label, true, 1)
    r.name:SetPoint("LEFT", r.title, "LEFT", 0, 0)
    r.name:SetPoint("RIGHT", r.title, "RIGHT", 0, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.title:SetScript("OnEnter", function(self)
        if canChange() then r.name:SetTextColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 1) end
        if self.tip then self.tip(self) end
    end)
    r.title:SetScript("OnLeave", function()
        r.name:SetTextColor(1, 1, 1, r.isOn and 1 or T.A_TEXT)
        GameTooltip:Hide()
    end)
    r.state = T.text(r, T.SIZE.caption, true, T.A_DIM)
    r.state:SetPoint("TOPLEFT", r, "TOPLEFT", BOX + 20, -26)
    r.cost = T.text(r, T.SIZE.body, false, T.A_DIM)
    r.cost:SetPoint("LEFT", r, "LEFT", LABEL_W + #D.SCHOOLS * COL + 8, 0)
    r.cost:SetPoint("RIGHT", r, "RIGHT", -30, 0)
    r.cost:SetJustifyH("LEFT")
    r.cost:SetWordWrap(true)
    r.del = T.close(r, nil)
    r.del:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.del:HookScript("OnEnter", function(self) T.tip(self, "Delete fight") end)
    r.del:HookScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, ROW_HOVER)
        if self.tipFn then self.tipFn(self) end
    end)
    r:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, ROW_BG)
        GameTooltip:Hide()
    end)
    return r
end

-- A school's cell: the resistance's icon, and who gives it on a chip
-- under it.
local function makeCell(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(CELL, CELL)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c.icon = T.icon(c, nil, CELL)
    c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.ring = CreateFrame("Frame", nil, c)
    c.ring:SetPoint("TOPLEFT", c, "TOPLEFT", -2, 2)
    c.ring:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 2, -2)
    T.border(c.ring, RED, 1)
    c:SetScript("OnEnter", function(self) if self.tipFn then self.tipFn(self) end end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    T.hoverEdge(c, canChange)
    c.chip = CreateFrame("Button", nil, c)
    c.chip:SetSize(COL - 10, 14)
    c.chip:SetPoint("TOP", c, "BOTTOM", 0, -3)
    -- What flashes when a click on Assignments comes here: the icon and
    -- who gives it under it, as wide as the chip.
    c.area = CreateFrame("Frame", nil, c)
    c.area:SetPoint("TOPLEFT", c.chip, "TOPLEFT", 0, CELL + 6)
    c.area:SetPoint("BOTTOMRIGHT", c.chip, "BOTTOMRIGHT", 0, -3)
    makeFlash(c.area)
    c.chip.text = T.text(c.chip, T.SIZE.caption, true, 1)
    c.chip.text:SetPoint("CENTER", c.chip, "CENTER", -5, 0)
    c.chip.arrow = T.chevron(c.chip, 8)
    c.chip.arrow:SetPoint("LEFT", c.chip.text, "RIGHT", 2, 0)
    -- Gold under who gives it while it's set by hand.
    c.chip.mark = T.fill(c.chip, T.COLOR.hand, 1, "ARTWORK")
    c.chip.mark:SetHeight(1)
    c.chip.mark:SetPoint("BOTTOMLEFT", c.chip.text, "BOTTOMLEFT", 0, -2)
    c.chip.mark:SetPoint("BOTTOMRIGHT", c.chip.arrow, "BOTTOMRIGHT", 0, -2)
    c.chip:SetScript("OnEnter", function(self)
        if canChange() then self.arrow:SetVertexColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 1) end
        if self.tipFn then self.tipFn(self) end
    end)
    c.chip:SetScript("OnLeave", function(self)
        self.arrow:SetVertexColor(1, 1, 1, 0.6)
        GameTooltip:Hide()
    end)
    return c
end

-- Fills cell `c` for `school` in `fight`, whose board is `plan`.
local function paintCell(c, school, fight, plan)
    local want = Du.resist(fight, school.id)
    local s = want and plan and plan.schools and plan.schools[school.id]
    local hand = type(want) == "table"
    local changed = changedWhere(function(it)
        return it.kind == "resist" and it.a == fight and it.b == school.id
    end)
    local title = school.title .. " resistance"
    c.titleText = title
    c.icon:SetTexture(s and Tr.icon(s.b) or school.icon)
    c.icon:SetDesaturated(not want)
    c.icon:SetAlpha(want and 1 or 0.25)
    c.ring:SetShown(want ~= nil and not s)
    local edit = canChange()
    c:SetScript("OnClick", function(_, button)
        if not edit then return end
        if button == "RightButton" then
            if hand then Du.setResist(fight, school.id, true) end
        else
            Du.setResist(fight, school.id, not want and true or nil)
        end
    end)
    local function sources()
        local list = {}
        for _, id in ipairs(school.sources) do list[#list + 1] = Tr.title(D.BY_ID[id]) end
        return format("Only one of %s counts.", table.concat(list, " or "))
    end
    c.tipFn = function(self)
        local lines = { { want and "Needed." or "Not needed.", 1, 1, 1 } }
        if want and not s then lines[#lines + 1] = T.line("Nobody here can give it.", "bad") end
        if changed then lines[#lines + 1] = T.line("Changed in the draft.", "changed") end
        lines[#lines + 1] = sources()
        local list = { { "Click", want and "not needed" or "need it" } }
        if hand then list[#list + 1] = { "Right-click", "back to auto" } end
        spellTip(self, s and s.b or D.BY_ID[school.sources[1]], title, lines, C.hints(lines, list))
    end
    -- Who gives it.
    local chip = c.chip
    chip:SetShown(want ~= nil)
    if want then
        local text
        if s and s.m then
            text = NS.classColored(NS.initials(s.m.name), s.m.class)
        elseif s then
            text = "Buff"
        else
            text = T.hex("bad") .. "None|r"
        end
        chip.text:SetText(text)
        chip.arrow:SetShown(edit)
        if changed then chip.mark:SetColorTexture(BLUE[1], BLUE[2], BLUE[3], 1) end
        if hand and not changed then
            local g = T.COLOR.hand
            chip.mark:SetColorTexture(g[1], g[2], g[3], 1)
        end
        chip.mark:SetShown(hand or changed)
        chip:SetScript("OnClick", function(self) schoolMenu(self, school, fight) end)
        chip.tipFn = function(self)
            local lines = {}
            if s and s.m then
                lines[1] = { format("%s, %s.", NS.who(s.m), insteadText(s)), 1, 1, 1 }
            elseif s then
                lines[1] = { "From the priests' long buff, at no cost.", 1, 1, 1 }
            else
                lines[1] = T.line("Nobody here can give it.", "bad")
            end
            if hand then lines[#lines + 1] = T.line("Override.", "hand") end
            T.tip(self, title, lines, C.hints(lines, { { "Click", "choose who gives it" } }))
        end
    end
end

function C.resistSection(page, y)
    local fights = Du.fights()
    if #fights == 0 then
        return C.kit.note(page, "No fights yet. Add one for each boss that needs a resistance, like Ragnaros and fire.", y) + 4
    end
    local head = pool(page, "resistHead", makeHead)
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
    head:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -y)
    y = y + HEAD_H + 8
    local edit = canChange()
    local current = Du.fight()
    for _, fight in ipairs(fights) do
        local plan = Du.preview(fight)
        local on = current == fight
        local r = pool(page, "fightRow", makeFightRow)
        r.fight, r.isOn = fight, on
        r.name:SetText(fight)
        r.name:SetTextColor(1, 1, 1, on and 1 or T.A_TEXT)
        r.state:SetText(on and T.hex("up") .. "On now|r" or "Off")
        r.strip:SetShown(on)
        r.on.box.fill:SetShown(on)
        r.cost:SetText(lossText(plan))
        r.changed = changedWhere(function(it)
            return (it.kind == "fight" and it.a == fight) or (it.kind == "fighton" and (it.v == fight or it.w == fight))
        end)
        if r.changed then T.paint(r, BLUE, 0.9) else T.paint(r, { 1, 1, 1 }, 0) end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", -8, -y)
        mark(page, "resistances", r, y)
        r.on:SetScript("OnClick", function()
            if edit then Du.setFight(not on and fight or nil) end
        end)
        r.on.tip = function(self)
            local lines = { { on and "On now." or "Off. Turn it on before the pull.", 1, 1, 1 } }
            if not on and current then lines[2] = format("%s goes off, since one fight is on at a time.", current) end
            T.tip(self, fight, lines, C.hints(lines, { { "Click", on and "turn it off" or "turn it on" } }))
        end
        r.title:SetScript("OnClick", function() if edit then renameFight(fight) end end)
        r.title.tip = function(self)
            local lines = {}
            if r.changed then lines[1] = T.line("Changed in the draft.", "changed") end
            T.tip(self, fight, lines, edit and C.hints(lines, { { "Click", "rename it" } }) or nil)
        end
        r.del:SetShown(edit)
        r.del:SetScript("OnClick", function()
            T.confirm(format("Delete the fight %s?", fight), function() Du.removeFight(fight) end)
        end)
        r.tipFn = function(self)
            local lines = { on and "On now." or "Off. Turn it on before the pull." }
            local cost = lossText(plan)
            if cost ~= "" then lines[#lines + 1] = cost end
            if r.changed then lines[#lines + 1] = T.line("Changed in the draft.", "changed") end
            T.tip(self, fight, lines)
        end
        for i, school in ipairs(D.SCHOOLS) do
            local c = pool(page, "resistCell", makeCell)
            paintCell(c, school, fight, plan)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", r, "TOPLEFT", LABEL_W + (i - 0.5) * COL - CELL / 2, -5)
            c:SetFrameLevel(r:GetFrameLevel() + 2)
            mark(page, format("resist:%s:%s", fight, school.id), c.area, y)
        end
        y = y + ROW_H + 4
    end
    return y
end
