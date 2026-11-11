-- The PLAN row at the top of the Assignments page, and the picker it opens.
-- A plan is mostly the assignments set by hand, and it also keeps where each
-- player goes in the raid, so the raid pane previews it.
--
-- It's BayovCore's preset box (Modules/Presets.lua) for our plans, in the
-- same look and words. One row says which plan the raid uses:
--
--   PLAN  [Naxx main v]  25 players, auto in Naxxramas              [Save]
--
-- Its button opens the picker: a search box, Auto and Off at the top, the
-- plans in folders, and New, New folder and Import along the bottom. Each
-- plan has a menu (the ... under the mouse) to rename it in place,
-- duplicate it, move it to a folder, set it for an instance, invite its
-- missing players, export it or delete it. Asking before a delete happens
-- in its row. A plan dragged onto a folder (or onto a plan in it) moves
-- there. We copy rather than share, as Theme.lua does, because Buff
-- Coordinator is published for players who don't have BayovCore.
--
-- Which plan is in use depends on where we are:
--
--   - In a mock raid, it's the plan the mock raid was loaded from or saved
--     as (Pl.current). The mock raid is where we edit a plan, and Save on
--     the row keeps the edits. Picking another plan loads it.
--   - In a real group, it's the plan we applied (Pl.active), which gives the
--     players who join later their place. Picking a plan first shows what
--     applying it would do, in the pane's parties. Meanwhile the row says
--     "Not in use", with Use it and "Back to <the one in use>", like
--     BayovCore's "Edit without using it". Auto is the plan set for the
--     instance we're in (Pl.forHere), and Off stops following a plan.
--   - Solo, it's the plan we applied, as in a group, and it stays in use
--     when a raid forms. Picking one applies it at once, since there are no
--     parties to show first. Its players who aren't here show dimmed.
--
-- The menus are Theme's (T.menu).

local _, NS = ...
local R, M, Pl, G, T = NS.Roster, NS.Mock, NS.Plans, NS.Group, NS.Theme

local floor, max, min = math.floor, math.max, math.min
local format = string.format

local Pr = {}
NS.Profiles = Pr

local RED = { 1.00, 0.36, 0.33 }
local AMBER = { 0.95, 0.74, 0.32 }
local WHITE = { 1, 1, 1 }
local ROW_H = 26
local PAD = 10
local GAP = 6
-- How tall the box is, for the pane to keep room for it.
Pr.HEIGHT = PAD + ROW_H + PAD

-- Auto and Off, the choices that aren't plans. Tables, so no plan's name can
-- be mistaken for one.
local AUTO, OFF = { "auto" }, { "off" }
Pr.AUTO, Pr.OFF = AUTO, OFF

-- The picker, once it has been opened (Pr.openPicker).
local picker
-- Every PLAN row made (Pr.box).
local boxes = setmetatable({}, { __mode = "k" })

local function tip(owner, title, text)
    T.tip(owner, title, text and { text } or {})
end
local function untip() GameTooltip:Hide() end

-- A word in a colour, for the picker's tags.
local function tinted(word, c)
    c = c or T.ACCENT
    return format("|cff%02x%02x%02x%s|r", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5),
                  floor(c[3] * 255 + 0.5), word)
end

local function dim(text)
    return text and text ~= "" and ("|cff8c919a" .. text .. "|r") or nil
end

local function entry(spec, id)
    for _, p in ipairs(spec.list()) do
        if p.id == id then return p end
    end
end

local function folderOf(spec, id)
    return spec.folderOf and id ~= nil and spec.folderOf(id) or nil
end

local function choiceName(c)
    if c == AUTO then return "Auto" end
    if c == OFF then return "Off" end
end

-- =============================================================
-- The spec
-- =============================================================
-- The box and the picker take one table that says how plans are kept. It's
-- BayovCore's spec, less what plans don't have (bases and changes):
--
--   noun        what one is called: "plan"
--   list()      every plan, in order, as { id, name, info }. `info` is a few
--               dim words for the box, once it's picked
--   inUse()     the id in use now, or nil
--   pick()      the choice: an id, AUTO, OFF, or nil for none
--   setPick(c)  picks an id, AUTO or OFF
--   choices()   AUTO and OFF, when they're offered here
--   autoPick()  the id Auto would take now
--   shown()     the id the box shows, and show(id) to show another. show(nil)
--               goes back to the one in use
--   useIt(), useLabel(), useTip()   what "Use it" does and says
--   useInfo()   what the one in use comes to now, after its name
--   canNew(), newTip(), new(owner, done)   makes one and calls done(id)
--   rename(id, name), delete(id), duplicate(id)
--   folderOf(id), folderList(), setFolder(id, name), addFolder(name),
--   renameFolder(old, new), deleteFolder(name)
--   export(id)  a string and a title, to copy
--   import(text)  makes one from such a string: its id, or nil and why
--   more(root, id)  items of our own in a plan's menu
--   buttons     extra buttons for the right of the box:
--               { { label, shown(), click(self), tip(), main } }

-- =============================================================
-- The paste box, for Import and Export
-- =============================================================
local paste

local function pasteBox()
    if paste then return paste end
    local b = CreateFrame("Frame", "BuffCoordinatorPlanText", UIParent)
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    b:SetFrameLevel(40)
    b:SetSize(440, 200)
    b:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    b:EnableMouse(true)
    b.bg = T.fill(b, T.BG, 0.97)
    b.bg:SetAllPoints(b)
    T.border(b, WHITE, 0.2)
    b.title = T.text(b, 13, true, 1)
    b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 12, -12)
    b.hint = T.text(b, 12, false, T.A_DIM)
    b.hint:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -4)
    local well = CreateFrame("Frame", nil, b)
    well:SetPoint("TOPLEFT", b, "TOPLEFT", 12, -50)
    well:SetPoint("TOPRIGHT", b, "TOPRIGHT", -12, -50)
    well:SetHeight(90)
    well.bg = T.fill(well, T.INPUT, 0.9)
    well.bg:SetAllPoints(well)
    T.border(well, WHITE, 0.12)
    local sf = CreateFrame("ScrollFrame", nil, well)
    sf:SetPoint("TOPLEFT", well, "TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -6, 6)
    local edit = CreateFrame("EditBox", nil, sf)
    edit:SetMultiLine(true)
    edit:SetMaxLetters(0)
    edit:SetAutoFocus(false)
    edit:SetFont(T.FONT, 12, "")
    edit:SetTextColor(1, 1, 1, T.A_TEXT)
    edit:SetWidth(400)
    edit:SetScript("OnEscapePressed", function() b:Hide() end)
    sf:SetScrollChild(edit)
    well:EnableMouse(true)
    well:SetScript("OnMouseDown", function() edit:SetFocus() end)
    b.edit = edit
    b.status = T.text(b, 12, false, 1)
    b.status:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 12, 16)
    b.status:SetTextColor(RED[1], RED[2], RED[3], 1)
    b.ok = T.button(b, "Import", 80, 24, true)
    b.ok:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -12, 10)
    b.ok:SetScript("OnClick", function()
        local id, why = b.onAccept(b.edit:GetText() or "")
        if id then b:Hide() else b.status:SetText(why or "That isn't a plan.") end
    end)
    b.cancel = T.button(b, "Cancel", 80, 24)
    b.cancel:SetPoint("RIGHT", b.ok, "LEFT", -6, 0)
    b.cancel:SetScript("OnClick", function() b:Hide() end)
    table.insert(_G.UISpecialFrames, "BuffCoordinatorPlanText")
    paste = b
    return b
end

local function importPlan(spec, after)
    local b = pasteBox()
    b.title:SetText("Import a " .. spec.noun)
    b.hint:SetText("Paste what Export gave you.")
    b.edit:SetText("")
    b.status:SetText("")
    b.ok:Show()
    b.cancel:SetText("Cancel")
    b.onAccept = function(text)
        local id, why = spec.import(text)
        if id and after then after(id) end
        return id, why
    end
    b:Show()
    b.edit:SetFocus()
end

-- The same box shows an export, selected, to copy.
local function exportPlan(spec, id)
    local text, title = spec.export(id)
    if not text then return end
    -- The picker would sit over it.
    if picker then picker:Hide() end
    local b = pasteBox()
    b.title:SetText(title or id)
    b.hint:SetText("Press Ctrl+C to copy, then share it.")
    b.status:SetText("")
    b.ok:Hide()
    b.cancel:SetText("Close")
    b.edit:SetText(text)
    b:Show()
    b.edit:SetFocus()
    if b.edit.HighlightText then b.edit:HighlightText() end
end

-- =============================================================
-- The picker
-- =============================================================
-- One panel, under the button that opened it. It closes on a pick, on
-- Escape, and on a click anywhere but on it or a menu it opened.
local PICK_W, PICK_ROW, PICK_HEAD, PICK_MAX = 260, 20, 20, 280
local PICK_FONT, PICK_BTN = 12, 18

local SEARCH_H = 6 + 20 + 6

-- The picker's buttons, a size down from the window's.
local function fitButton(b)
    b:SetWidth(floor((b.label:GetStringWidth() or 40) + 16))
end

local function smallButton(parent, label, w, h)
    local b = T.button(parent, label, w or 60, h or PICK_BTN)
    b.label:SetFont(T.BOLD, 11, "")
    if not w then fitButton(b) end
    return b
end

-- A small "..." button at a row's right, shown under the mouse.
local function moreButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 16)
    b.label = T.text(b, 12, true, T.A_DIM)
    b.label:SetPoint("CENTER", b, "CENTER", 0, 3)
    b.label:SetText("...")
    b:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 1, 1, 1)
        self:GetParent().hl:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.label:SetTextColor(1, 1, 1, T.A_DIM)
        if not self:GetParent():IsMouseOver() then self:GetParent().hl:Hide() end
    end)
    return b
end

local function pickRow(f)
    local r = CreateFrame("Button", nil, f.scroll.child)
    r:SetHeight(PICK_ROW)
    r.hl = T.fill(r, WHITE, 0.06)
    r.hl:SetAllPoints(r)
    r.hl:Hide()
    r.sel = T.fill(r, T.ACCENT, 0.16, "BORDER")
    r.sel:SetAllPoints(r)
    r.drop = T.fill(r, T.ACCENT, 0.30, "BORDER")
    r.drop:SetAllPoints(r)
    r.drop:Hide()
    r.name = T.text(r, PICK_FONT, false, T.A_TEXT)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.tag = T.text(r, 9, true, 0.8)
    r.info = T.text(r, 10, false, T.A_DIM)
    r.info:SetJustifyH("RIGHT")
    if r.info.SetWordWrap then r.info:SetWordWrap(false) end
    r.more = moreButton(r)
    r.more:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnEnter", function(self)
        if not self.still then self.hl:Show() end
        if self.canMore then self.more:Show() end
    end)
    r:SetScript("OnLeave", function(self)
        if self.more:IsMouseOver() then return end
        self.hl:Hide()
        self.more:Hide()
    end)
    return r
end

-- The row asking before a delete, in place of the row it's for.
local function confirmRow(f)
    local c = CreateFrame("Frame", nil, f.scroll.child)
    c:SetHeight(PICK_ROW)
    c.bg = T.fill(c, RED, 0.14)
    c.bg:SetAllPoints(c)
    c.text = T.text(c, 11, true, 1)
    c.text:SetPoint("LEFT", c, "LEFT", 10, 0)
    if c.text.SetWordWrap then c.text:SetWordWrap(false) end
    c.yes = smallButton(c, "Delete", 50, 16)
    c.yes:SetPoint("RIGHT", c, "RIGHT", -4, 0)
    c.yes.label:SetTextColor(RED[1], RED[2], RED[3], 1)
    c.no = smallButton(c, "Cancel", 50, 16)
    c.no:SetPoint("RIGHT", c.yes, "LEFT", -4, 0)
    c.text:SetPoint("RIGHT", c.no, "LEFT", -6, 0)
    return c
end

local function buildPicker()
    local f = CreateFrame("Frame", "BuffCoordinatorPlanPicker", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(5)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f.bg = T.fill(f, { 0.07, 0.08, 0.10 }, 0.98)
    f.bg:SetAllPoints(f)
    T.border(f, WHITE, 0.18)
    f:Hide()

    f.search = T.edit(f, PICK_W - 12, 20)
    f.search:SetJustifyH("LEFT")
    f.search:SetFont(T.FONT, PICK_FONT, "")
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    f.hint = T.text(f.search, PICK_FONT, false, T.A_FAINT)
    f.hint:SetPoint("LEFT", f.search, "LEFT", 7, 0)
    f.hint:SetText("Search")
    f.search:SetScript("OnTextChanged", function(self)
        local q = (self:GetText() or ""):lower()
        f.hint:SetShown(q == "")
        if q ~= f.query then
            f.query = q
            f.paint()
        end
    end)
    f.search:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else f:Hide() end
        self:ClearFocus()
    end)

    f.scroll = T.scroll(f)
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -SEARCH_H)

    f.newBtn = smallButton(f, "+ New", 80)
    f.folderBtn = smallButton(f, "+ New folder")
    f.importBtn = smallButton(f, "Import")

    -- Renaming in place: one box, put over the row being renamed.
    f.edit = T.edit(f.scroll.child, 160, PICK_ROW - 2)
    f.edit:SetJustifyH("LEFT")
    f.edit:SetFont(T.FONT, PICK_FONT, "")
    if f.edit.SetTextInsets then f.edit:SetTextInsets(4, 4, 0, 0) end
    f.edit:Hide()
    local function finish(keep)
        local r = f.renaming
        if not r then return end
        f.renaming = nil
        f.edit:Hide()
        local text = (f.edit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if keep and text ~= "" and text ~= r.was then r.done(text) end
        f.paint()
    end
    f.edit:SetScript("OnEnterPressed", function() finish(true) end)
    f.edit:SetScript("OnEscapePressed", function() finish(false) end)
    f.edit.onFocusLost = function() finish(true) end
    f.finishRename = finish

    f.rows, f.confirm = {}, confirmRow(f)
    f.confirm:Hide()
    f.closed = {}

    table.insert(_G.UISpecialFrames, "BuffCoordinatorPlanPicker")
    f:SetScript("OnEvent", function()
        if f:IsMouseOver() or T.menuHasMouse() or (f.owner and f.owner:IsMouseOver())
           or (paste and paste:IsShown()) then
            return
        end
        f:Hide()
    end)
    f:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    f:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        finish(true)
        self.asking = nil
        self.search:ClearFocus()
        T.closeMenus()
    end)
    picker = f
    return f
end

-- What the picker lists, after the search: the plans out of folders, then
-- each folder with its plans. A folder is listed while searching only when
-- something in it matches.
local function groups(spec, query)
    local top, byFolder = {}, {}
    for _, p in ipairs(spec.list()) do
        if query == "" or p.name:lower():find(query, 1, true) then
            local fo = folderOf(spec, p.id)
            if fo then
                byFolder[fo] = byFolder[fo] or {}
                table.insert(byFolder[fo], p)
            else
                top[#top + 1] = p
            end
        end
    end
    local out = { { items = top } }
    for _, name in ipairs(spec.folderList()) do
        if query == "" or byFolder[name] then
            out[#out + 1] = { folder = name, items = byFolder[name] or {} }
        end
    end
    return out
end

local planMenu, folderMenu

local function startRename(f, row, was, done)
    f.renaming = { was = was, done = done }
    -- The box sits over the row, so the row's own text goes while we type.
    row.name:Hide()
    row.tag:Hide()
    row.info:Hide()
    row.more:Hide()
    f.edit:SetFrameLevel(row:GetFrameLevel() + 5)
    f.edit:ClearAllPoints()
    f.edit:SetPoint("LEFT", row.name, "LEFT", -5, 0)
    f.edit:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    f.edit:SetText(was)
    f.edit:Show()
    f.edit:SetFocus()
    if f.edit.HighlightText then f.edit:HighlightText() end
end

-- Lays the picker out, and starts a rename or a question when one was asked
-- for.
local function paintPicker()
    local f = picker
    local spec = f.spec
    local query = f.query or ""
    local shown, using, pick = spec.shown(), spec.inUse(), spec.pick()
    local autoHere = spec.autoPick()
    -- Picked through Auto, the blue row is Auto's, and the plan only says
    -- AUTO.
    local throughAuto = shown ~= nil and shown == using and pick == AUTO
    local closed = f.closed
    local w = max(PICK_W, floor((f.owner and f.owner:GetWidth() or 0) + 0.5))
    f:SetWidth(w)
    f.search:SetWidth(w - 12)
    local cw = w - 2
    f.scroll.child:SetWidth(cw - 6)
    for _, r in ipairs(f.rows) do r:Hide() end
    f.confirm:Hide()

    local n, y = 0, 0
    local renameRow
    local function row()
        n = n + 1
        local r = f.rows[n] or pickRow(f)
        f.rows[n] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", f.scroll.child, "TOPLEFT", 0, -y)
        r:SetWidth(cw - 6)
        r.hl:Hide()
        r.more:Hide()
        r.drop:Hide()
        r.still = nil
        r.name:Show()
        r.tag:Show()
        r.info:Show()
        r:SetAlpha(1)
        r:Show()
        return r
    end
    local function ask(text, onYes)
        local c = f.confirm
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", f.scroll.child, "TOPLEFT", 0, -y)
        c:SetWidth(cw - 6)
        c.text:SetText(text)
        c.yes:SetScript("OnClick", function()
            f.asking = nil
            onYes()
            f.paint()
        end)
        c.no:SetScript("OnClick", function()
            f.asking = nil
            f.paint()
        end)
        c:Show()
        y = y + PICK_ROW + 1
    end

    -- Auto and Off first, when they're offered. Picking one is what the
    -- raid uses from then on.
    local choices = spec.choices()
    if query == "" and #choices > 0 then
        for _, c in ipairs(choices) do
            local r = row()
            r.kind, r.folder, r.id = "choice", nil, c
            r.sel:SetShown(pick == c)
            r.name:ClearAllPoints()
            r.name:SetPoint("LEFT", r, "LEFT", 10, 0)
            r.name:SetFont(T.FONT, PICK_FONT, "")
            r.name:SetText(choiceName(c))
            r.name:SetTextColor(1, 1, 1, pick == c and 1 or T.A_TEXT)
            r.tag:SetText("")
            r.info:ClearAllPoints()
            r.info:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.info:SetPoint("LEFT", r.tag, "RIGHT", 8, 0)
            r.info:SetText(c == AUTO and (autoHere or "nothing set here") or "")
            r.canMore = false
            r:SetScript("OnClick", function()
                f:Hide()
                spec.setPick(c)
            end)
            r:SetScript("OnDragStart", nil)
            r:SetScript("OnDragStop", nil)
            y = y + PICK_ROW
        end
        y = y + 4
    end

    for _, g in ipairs(groups(spec, query)) do
        local empty = #g.items == 0
        local folded = g.folder and closed[g.folder] and query == "" and not empty
        if g.folder then
            local key = "folder:" .. g.folder
            if f.asking == key then
                ask(format("Delete the folder %s? Its plans stay.", g.folder), function()
                    spec.deleteFolder(g.folder)
                end)
            else
                local r = row()
                r.kind, r.folder, r.id = "folder", g.folder, nil
                r.still = empty
                r.sel:Hide()
                r.tag:SetText("")
                r.name:ClearAllPoints()
                r.name:SetPoint("LEFT", r, "LEFT", 10, 0)
                r.name:SetFont(T.BOLD, 10, "")
                r.name:SetText(empty and format("%s (empty)", g.folder:upper())
                               or format("%s %s (%d)", folded and "+" or "-", g.folder:upper(), #g.items))
                r.name:SetTextColor(1, 1, 1, T.A_DIM)
                r.info:SetText("")
                r.canMore = true
                r.more:SetScript("OnClick", function(self) folderMenu(self, f, r) end)
                r:SetScript("OnClick", function()
                    if empty then return end
                    closed[g.folder] = not closed[g.folder] or nil
                    f.paint()
                end)
                r:SetScript("OnDragStart", nil)
                r:SetScript("OnDragStop", nil)
                if f.renameFolder == g.folder then renameRow = r end
                y = y + PICK_HEAD
            end
        end
        if not folded then
            for _, p in ipairs(g.items) do
                local id = p.id
                if f.asking == id then
                    ask(format("Delete %s? This can't be undone.", p.name), function()
                        spec.delete(id)
                    end)
                else
                    local r = row()
                    r.kind, r.folder, r.id = "plan", g.folder, id
                    local on = id == shown and not throughAuto
                    r.sel:SetShown(on)
                    r.name:ClearAllPoints()
                    r.name:SetPoint("LEFT", r, "LEFT", g.folder and 20 or 10, 0)
                    r.name:SetFont(T.FONT, PICK_FONT, "")
                    r.name:SetText(p.name)
                    r.name:SetTextColor(1, 1, 1, on and 1 or T.A_TEXT)
                    r.tag:ClearAllPoints()
                    r.tag:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
                    -- The blue row is the one shown, which is the one in use
                    -- unless we're looking at another. Then the tag says
                    -- which. AUTO in green, so it reads apart from IN USE.
                    local tags = {}
                    if id == autoHere then tags[#tags + 1] = tinted("AUTO", T.COLOR.up) end
                    if id == using and id ~= shown then tags[#tags + 1] = tinted("IN USE") end
                    r.tag:SetText(table.concat(tags, "  "))
                    r.info:SetText("")
                    r.canMore = true
                    r.more:SetScript("OnClick", function(self) planMenu(self, f, p) end)
                    r:SetScript("OnClick", function()
                        f:Hide()
                        spec.setPick(id)
                    end)
                    r:SetScript("OnDragStart", function(self)
                        f.dragging = self
                        self:SetAlpha(0.5)
                        self:SetScript("OnUpdate", function()
                            for _, o in ipairs(f.rows) do
                                o.drop:SetShown(o:IsShown() and o ~= self and o.kind ~= "choice" and o:IsMouseOver())
                            end
                        end)
                    end)
                    r:SetScript("OnDragStop", function(self)
                        self:SetScript("OnUpdate", nil)
                        self:SetAlpha(1)
                        if f.dragging ~= self then return end
                        f.dragging = nil
                        for _, o in ipairs(f.rows) do
                            if o:IsShown() and o ~= self and o.kind ~= "choice" and o:IsMouseOver() then
                                if o.folder ~= folderOf(spec, id) then spec.setFolder(id, o.folder) end
                                break
                            end
                        end
                        f.paint()
                    end)
                    if f.renameId == id then renameRow = r end
                    y = y + PICK_ROW
                end
            end
        end
    end
    if n == 0 and not f.confirm:IsShown() then
        local r = row()
        r.kind, r.id, r.folder = "none", nil, nil
        r.sel:Hide()
        r.tag:SetText("")
        r.info:SetText("")
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", r, "LEFT", 10, 0)
        r.name:SetFont(T.FONT, PICK_FONT, "")
        r.name:SetText(query == "" and "No plans yet." or "Nothing matches.")
        r.name:SetTextColor(1, 1, 1, T.A_DIM)
        r.canMore = false
        r:SetScript("OnClick", nil)
        r:SetScript("OnDragStart", nil)
        y = y + PICK_ROW
    end

    local listH = min(PICK_MAX, max(PICK_ROW, y))
    f.scroll:SetSize(cw, listH)
    f.scroll.child:SetHeight(max(1, y))
    if f.scroll.update then f.scroll:update() end

    -- The buttons along the bottom.
    local by = SEARCH_H + listH + 6
    f.newBtn:SetText("+ New " .. spec.noun)
    fitButton(f.newBtn)
    f.newBtn:ClearAllPoints()
    f.newBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -by)
    f.newBtn:SetEnabled(spec.canNew())
    f.folderBtn:ClearAllPoints()
    f.folderBtn:SetPoint("LEFT", f.newBtn, "RIGHT", 4, 0)
    f.importBtn:ClearAllPoints()
    f.importBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -by)
    f:SetHeight(by + PICK_BTN + 6)

    if renameRow then
        local id, folder = f.renameId, f.renameFolder
        f.renameId, f.renameFolder = nil, nil
        if id then
            startRename(f, renameRow, id, function(name) spec.rename(id, name) end)
        else
            startRename(f, renameRow, folder, function(name) spec.renameFolder(folder, name) end)
        end
    end
end

-- A plan's menu, from its "...".
planMenu = function(owner, f, p)
    local spec, id = f.spec, p.id
    T.menu(owner, function(_, root)
        root:CreateTitle(p.name)
        root:CreateButton("Rename", function()
            f.renameId = id
            f.paint()
        end)
        root:CreateButton("Duplicate", function()
            local new = spec.duplicate(id)
            if new then f.renameId = new end
            f.paint()
        end)
        local into = root:CreateButton("Move to folder")
        into:CreateRadio("No folder", function() return folderOf(spec, id) == nil end,
                         function() spec.setFolder(id, nil) f.paint() end)
        for _, name in ipairs(spec.folderList()) do
            into:CreateRadio(name, function() return folderOf(spec, id) == name end,
                             function() spec.setFolder(id, name) f.paint() end)
        end
        spec.more(root, id)
        root:CreateButton("Export", function() exportPlan(spec, id) end)
        root:CreateDivider()
        root:CreateButton("Delete", function()
            f.asking = id
            f.paint()
        end)
    end)
end

folderMenu = function(owner, f, row)
    local name = row.folder
    T.menu(owner, function(_, root)
        root:CreateTitle(name)
        root:CreateButton("Rename", function()
            f.renameFolder = name
            f.paint()
        end)
        root:CreateButton("Delete folder", function()
            f.asking = "folder:" .. name
            f.paint()
        end)
    end)
end

-- Opens the picker under `owner`, or closes it when it's open there.
-- `opts.rename` starts renaming that plan, like after Save.
function Pr.openPicker(owner, spec, opts)
    local f = picker or buildPicker()
    if f:IsShown() and f.owner == owner and not (opts and opts.rename) then
        f:Hide()
        return
    end
    f:Hide()
    f.owner, f.spec, f.query, f.asking = owner, spec, "", nil
    f.renameId = opts and opts.rename or nil
    f.paint = paintPicker
    f.search:SetText("")
    f.hint:Show()
    -- A new plan may come from a menu of sizes, which a click on it would
    -- close the picker for. So it opens again to rename the new one.
    f.newBtn:SetScript("OnClick", function(self)
        local fo = folderOf(spec, spec.shown())
        spec.new(self, function(id)
            if fo then spec.setFolder(id, fo) end
            f.renameId = id
            if not f:IsShown() then f:Show() end
            f.paint()
        end)
    end)
    f.newBtn.tip = function(self) tip(self, "New " .. spec.noun, spec.newTip()) end
    f.folderBtn:SetScript("OnClick", function()
        local name, taken = "New folder", {}
        for _, x in ipairs(spec.folderList()) do taken[x:lower()] = true end
        for i = 2, 99 do
            if not taken[name:lower()] then break end
            name = format("New folder %d", i)
        end
        spec.addFolder(name)
        f.renameFolder = name
        f.paint()
    end)
    f.folderBtn.tip = function(self)
        tip(self, "New folder", "Drag a " .. spec.noun .. " onto it to put it there.")
    end
    f.importBtn:SetScript("OnClick", function()
        importPlan(spec, function()
            if f:IsShown() then f.paint() end
        end)
    end)
    f.importBtn.tip = function(self) tip(self, "Import", "Paste a " .. spec.noun .. " someone exported.") end
    -- It sits in the window's scale, under the button.
    local s, u = owner:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if s and u and u > 0 then f:SetScale(s / u) end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    f:Show()
    f.paint()
end

function Pr.picker() return picker end

-- A plan's "..." menu, as the picker opens it. The tests open it here.
function Pr.planMenu(owner, spec, id)
    local f = picker or buildPicker()
    f.spec, f.paint = spec, f.paint or paintPicker
    planMenu(owner, f, { id = id, name = id })
end

-- =============================================================
-- The box
-- =============================================================
local function rowLabel(box, text)
    local fs = T.text(box, 12, true, 0.9)
    fs:SetTextColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.9)
    fs:SetText(text)
    return fs
end

-- A button with a small down arrow at its right, for a choice from a list.
local function choiceButton(box)
    local b = T.button(box, "", 160, 24)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -22, 0)
    b.label:SetJustifyH("LEFT")
    if b.label.SetWordWrap then b.label:SetWordWrap(false) end
    b.arrow = T.chevron(b, 10)
    b.arrow:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    -- The label is cut at the button's edge, so its full width is the
    -- unbounded one where the game has it.
    function b:fit(text, lo, hi)
        self:SetText(text)
        local fs = self.label
        local tw = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
        self:SetWidth(max(lo, min(hi, floor((tw or 60) + 38))))
    end
    return b
end

-- A line of text that works as a link, like "Back to Naxx main".
local function link(box, onClick, onTip)
    local o = CreateFrame("Button", nil, box)
    o:SetHeight(20)
    o.label = T.text(o, 12, false, 1)
    o.label:SetPoint("RIGHT", o, "RIGHT", 0, 0)
    o.label:SetTextColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.8)
    o:SetScript("OnClick", onClick)
    o:SetScript("OnEnter", function(self)
        self.label:SetTextColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 1)
        if onTip then onTip(self) end
    end)
    o:SetScript("OnLeave", function(self)
        self.label:SetTextColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.8)
        untip()
    end)
    function o:SetText(text)
        self.label:SetText(text)
        self:SetWidth(floor((self.label:GetStringWidth() or 0) + 2))
    end
    return o
end

-- Undo and Redo, two square buttons with an arrow each beside the picker.
-- They take back or make again every change to the plan: an assignment, a
-- need, a spec, a move in the mock raid (Duties.lua keeps the steps).
local HIST = 24
local MEDIA = [[Interface\AddOns\BuffCoordinator\Media\]]

local function historyButton(box, glyph, word, can, text, run)
    local b = T.button(box, "", HIST, HIST)
    -- A disabled button gets no OnEnter unless asked, and its tooltip says
    -- there's nothing to undo.
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(14, 14)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon:SetTexture(MEDIA .. glyph)
    b:SetScript("OnClick", function()
        if not can() then return end
        run()
        NS.Config.refresh()
    end)
    b.tip = function(self)
        local what = (text() or ""):match("^%a+: (.+)$")
        if what then
            tip(self, word, what:sub(1, 1):upper() .. what:sub(2) .. ".")
        else
            tip(self, word, format("Nothing to %s.", word:lower()))
        end
    end
    -- Off, its border stays faint under the mouse too.
    function b:paint()
        local on = can()
        self.on = on
        self:SetEnabled(on)
        self.icon:SetVertexColor(1, 1, 1, on and 0.9 or 0.25)
    end
    return b
end

function Pr.box(parent, spec)
    spec = spec or Pr.spec
    local box = CreateFrame("Frame", nil, parent)
    box.bg = T.fill(box, T.INPUT, 0.6)
    box.bg:SetAllPoints(box)
    T.border(box, WHITE, 0.08)

    box.label = rowLabel(box, spec.noun:upper())
    box.pick = choiceButton(box)
    box.pick:SetScript("OnClick", function(self) Pr.openPicker(self, spec) end)
    box.pick.tip = function(self)
        tip(self, "Which " .. spec.noun .. " the raid uses", spec.pickTip())
    end
    local Du = NS.Duties
    box.undo = historyButton(box, "Undo", "Undo", Du.canUndo, Du.undoText, Du.undo)
    box.redo = historyButton(box, "Redo", "Redo", Du.canRedo, Du.redoText, Du.redo)
    box.chip = T.chip(box)
    box.useIt = T.button(box, "Use it", nil, 22, true)
    box.useIt:SetScript("OnClick", function() spec.useIt() end)
    box.useIt.tip = function(self) tip(self, self:GetText(), spec.useTip()) end
    box.back = link(box, function() spec.show(nil) end, function(self)
        tip(self, "Back to the one in use", "Keep the raid as it is.")
    end)
    box.info = T.text(box, 12, false, T.A_DIM)
    box.info:SetWordWrap(false)
    box.actions = {}
    for _, x in ipairs(spec.buttons or {}) do
        local b = T.button(box, x.label, nil, 22, x.main)
        b:SetScript("OnClick", function(self) x.click(self, box) end)
        b.tip = function(self) tip(self, x.label, x.tip()) end
        b.def = x
        box.actions[#box.actions + 1] = b
    end
    -- The picker belongs to the window, so it goes when the window does.
    box:SetScript("OnHide", function()
        if picker and picker:IsShown() and picker.owner == box.pick then picker:Hide() end
    end)

    -- Places the box at (x, y) of `root`, `w` wide, and answers the y under
    -- it. Pr.repaint places it again where it was.
    function box:place(root, x, y, w)
        self.at = { root, x, y, w }
        local inner = w - PAD * 2
        local labelW = (self.label:GetStringWidth() or 40) + 12
        local mid = PAD + ROW_H / 2
        self.label:ClearAllPoints()
        self.label:SetPoint("LEFT", self, "TOPLEFT", PAD, -mid)

        local id, using, pick = spec.shown(), spec.inUse(), spec.pick()
        local following = id == using
        local text
        if id == nil then
            text = pick == OFF and "Off" or "None"
        elseif following and pick == AUTO then
            -- What Auto took goes beside the button.
            text = "Auto"
        else
            local fo = folderOf(spec, id)
            text = (fo and dim(fo .. " /") .. " " or "") .. id
        end

        -- The buttons on the right, from the right edge.
        local rightW, prev = 0, nil
        for i = #self.actions, 1, -1 do
            local b = self.actions[i]
            local on = b.def.shown()
            b:SetShown(on)
            if on then
                b:ClearAllPoints()
                if prev then
                    b:SetPoint("RIGHT", prev, "LEFT", -GAP, 0)
                else
                    b:SetPoint("RIGHT", self, "TOPRIGHT", -PAD, -mid)
                end
                rightW = rightW + b:GetWidth() + GAP
                prev = b
            end
        end

        -- Looking at one we don't use: say so, and offer to use it or go
        -- back.
        local away = id ~= nil and not following
        self.chip:SetShown(away)
        self.useIt:SetShown(away)
        self.back:SetShown(away)
        local awayW = 0
        if away then
            self.chip:show("Not in use", AMBER)
            self.useIt:SetText(spec.useLabel())
            self.back:SetText("Back to " .. (choiceName(pick) or using or "None"))
            awayW = 8 + self.chip:GetWidth() + 6 + self.useIt:GetWidth() + 10 + self.back:GetWidth()
            -- A long name leaves the button too little room, so it goes.
            if inner - labelW - awayW - rightW - 10 < 80 then
                awayW = awayW - self.back:GetWidth()
                self.back:SetText("Back")
                awayW = awayW + self.back:GetWidth()
            end
        end

        -- The button gets what room is left, within limits.
        local histW = 6 + HIST + 2 + HIST
        local hi = max(80, min(240, inner - labelW - awayW - rightW - histW - 10))
        self.pick:fit(text, min(120, hi), hi)
        self.pick:ClearAllPoints()
        self.pick:SetPoint("LEFT", self, "TOPLEFT", PAD + labelW, -mid)
        self.undo:ClearAllPoints()
        self.undo:SetPoint("LEFT", self.pick, "RIGHT", 6, 0)
        self.redo:ClearAllPoints()
        self.redo:SetPoint("LEFT", self.undo, "RIGHT", 2, 0)
        self.undo:paint()
        self.redo:paint()
        local after = self.redo
        local leftW = labelW + self.pick:GetWidth() + histW
        if away then
            self.chip:ClearAllPoints()
            self.chip:SetPoint("LEFT", self.redo, "RIGHT", 8, 0)
            self.useIt:ClearAllPoints()
            self.useIt:SetPoint("LEFT", self.chip, "RIGHT", 6, 0)
            self.back:ClearAllPoints()
            self.back:SetPoint("LEFT", self.useIt, "RIGHT", 10, 0)
            after = self.back
            leftW = leftW + awayW
        end

        local p = id and entry(spec, id)
        local info = p and p.info or ""
        local now = following and spec.useInfo() or ""
        if now ~= "" then info = info .. (info ~= "" and "  \194\183  " or "") .. now end
        -- On Auto, the plan it took comes first, in the green of the AUTO
        -- tag in the picker.
        if following and pick == AUTO and id then
            info = tinted(id, T.COLOR.up) .. (info ~= "" and "  \194\183  " .. info or "")
        end
        self.info:SetText(info)
        local room = inner - leftW - 10 - rightW
        self.info:ClearAllPoints()
        self.info:SetPoint("LEFT", after, "RIGHT", 10, 0)
        self.info:SetWidth(max(0, room))
        self.info:SetShown(room > 40 and info ~= "")

        local h = Pr.HEIGHT
        self:SetHeight(h)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
        self:SetWidth(w)
        self:Show()
        -- An open picker shows what changed too.
        if picker and picker:IsShown() and picker.spec == spec and not picker.renaming then
            picker.paint()
        end
        return y + h
    end

    boxes[box] = true
    return box
end

-- Every box drawn again where it was, after a change the page didn't draw,
-- like a plan picked to preview in the raid pane.
function Pr.repaint()
    for box in pairs(boxes) do
        if box.at and box:IsShown() then box:place((table.unpack or unpack)(box.at)) end
    end
end

-- =============================================================
-- Plans as the spec
-- =============================================================
-- Runs `fn` now, or after a yes when the mock raid has changes no plan
-- has.
local function unsaved(fn)
    if M.on() and Pl.dirty() and #R.list() > 1 then
        T.confirm("The mock raid has unsaved changes. Continue anyway?", fn)
    else
        fn()
    end
end
Pr.unsaved = unsaved

-- Whether we're in a real group, where picking a plan previews it first.
local function grouped() return not NS.mock and R.real.grouped() end

local function pane() return NS.RaidPane end

-- The plan the pane previews, or nil.
local function previewing()
    local p = pane().proposal()
    return p and p.plan or nil
end

-- What it says in a size menu: "A party of 5", "A raid of 25".
local function sizeName(n) return n == 5 and "A party of 5" or format("A raid of %d", n) end
Pr.sizeName = sizeName

local spec = { noun = "plan" }
Pr.spec = spec

-- Each plan, with how many players it has and the instance Auto picks it
-- in, if any.
function spec.list()
    local t = {}
    local inst = Pl.instances()
    for _, name in ipairs(Pl.list()) do
        local plan = Pl.get(name)
        local n = #(plan.members or {}) + 1
        local info = format("%d %s", n, n == 1 and "player" or "players")
        for _, x in ipairs(inst) do
            if Pl.forInstance(x.id) == name then
                info = info .. ", auto in " .. (x.name or x.id)
                break
            end
        end
        t[#t + 1] = { id = name, name = name, info = info }
    end
    return t
end

function spec.inUse()
    if M.on() then return Pl.current() end
    return Pl.active()
end

function spec.pick()
    if M.on() then return Pl.current() end
    if not Pl.active() then return OFF end
    return Pl.activeAuto() and AUTO or Pl.active()
end

function spec.shown()
    if M.on() then return Pl.current() end
    if grouped() then return previewing() or Pl.active() end
    return Pl.active()
end

-- In a group, showing a plan previews it in the pane, and show(nil) puts
-- the parties back as they are.
function spec.show(id)
    if not grouped() then return end
    if id == nil then
        if previewing() then pane().cancelProposal() end
    else
        pane().previewPlan(id)
    end
end

function spec.setPick(c)
    if grouped() then
        if c == OFF then
            spec.show(nil)
            if Pl.active() then Pl.stop() end
        elseif c == AUTO then
            local name = Pl.forHere()
            if not name then
                NS.print("No plan is set for this instance.")
                return
            end
            pane().previewPlan(name, true)
        else
            pane().previewPlan(c)
        end
        return
    end
    if M.on() then
        if c == AUTO or c == OFF or c == nil then return end
        unsaved(function() Pl.load(c) end)
        return
    end
    -- Solo, a plan goes in use at once.
    if c == OFF then
        if Pl.active() then Pl.stop() end
    elseif c == AUTO then
        local name = Pl.forHere()
        if not name then
            NS.print("No plan is set for this instance.")
            return
        end
        Pl.apply(name, true)
    elseif c then
        Pl.apply(c)
    end
end

function spec.choices()
    if M.on() then return {} end
    return { AUTO, OFF }
end

function spec.autoPick() return Pl.forHere() end

function spec.useIt() pane().applyProposal() end
function spec.useLabel() return Pl.drafting() and "Put in draft" or "Use it" end
function spec.useTip()
    local name = spec.shown() or ""
    if Pl.drafting() then return format("Put plan %s in your draft, to send as a suggestion.", name) end
    return format("Apply plan %s to the raid.", name)
end

function spec.pickTip()
    if grouped() then
        return "Picking one shows what it changes first. Auto is the plan set for this instance."
    end
    if M.on() then return "Picking one loads it into the mock raid, where you change it." end
    return "Picking one puts it in use. Players not here show dimmed."
end

-- What the one in use comes to now: who of it isn't here, or that the mock
-- raid has changes it doesn't have yet.
function spec.useInfo()
    if not M.on() then
        local name = Pl.active()
        local n = name and #Pl.missing(name) or 0
        return n > 0 and format("%d %s", n, n == 1 and "isn't here" or "aren't here") or ""
    end
    if M.on() and Pl.dirty() and (Pl.current() or #R.list() > 1) then
        return T.hex(T.ACCENT) .. (Pl.current() and "edited" or "not saved") .. "|r"
    end
    return ""
end

function spec.canNew() return true end

function spec.newTip()
    if grouped() then return "The raid as it is now: its groups, specs and assignments. Type its name." end
    return "A mock raid of a size you pick, every assignment on auto. Type its name."
end

-- In a group, a new plan is the raid. Else it's a fresh mock raid of a size
-- we pick, saved at once so it has a name to type over.
function spec.new(owner, done)
    if grouped() then
        local inst = Pl.instance()
        local name = Pl.freeName(inst and inst.name or "Raid")
        if Pl.fromRaid(name) then done(name) end
        return
    end
    T.menu(owner, function(_, root)
        root:CreateTitle("How many is it for?")
        for _, n in ipairs(M.SIZES) do
            root:CreateButton(sizeName(n), function()
                unsaved(function()
                    if not Pl.new(n) then return end
                    local name = Pl.freeName("New plan")
                    if Pl.save(name) then done(name) end
                end)
            end)
        end
    end)
end

-- A preview of a plan follows it to its new name, and goes with it.
function spec.rename(id, name)
    if not Pl.rename(id, name) then
        if Pl.get(name) then NS.print("There's a plan called %s already.", name) end
        return
    end
    local p = pane().proposal()
    if p and p.plan == id then pane().previewPlan(name, p.auto) end
end

function spec.delete(id)
    if previewing() == id then pane().cancelProposal() end
    Pl.delete(id)
end

function spec.duplicate(id)
    local new = Pl.freeName(id .. " copy")
    return Pl.duplicate(id, new) and new or nil
end

spec.folderOf = Pl.folderOf
spec.folderList = Pl.folders
spec.setFolder = Pl.setFolder
spec.addFolder = Pl.addFolder
spec.renameFolder = Pl.renameFolder
spec.deleteFolder = Pl.deleteFolder

function spec.export(id) return Pl.export(id), "Plan " .. id end
function spec.import(text) return Pl.import(text) end

-- Ours in a plan's menu: the instances Auto picks it in, and inviting its
-- players who aren't here.
function spec.more(root, id)
    local sub = root:CreateButton("Set for instance")
    sub:CreateTitle("Auto picks it in")
    local list = Pl.instances()
    if #list == 0 then sub:CreateNote("Instances you zone into show here") end
    for _, inst in ipairs(list) do
        local iid = inst.id
        sub:CreateCheckbox((inst.name or iid) .. (inst.here and " " .. T.DIM .. "(here)|r" or ""),
                           function() return Pl.forInstance(iid) == id end,
                           function() Pl.useFor(iid, Pl.forInstance(iid) ~= id and id or nil) end)
    end
    if G.canInvite() then
        local n = #Pl.missing(id)
        if n > 0 then
            root:CreateButton(format("Invite %d missing", n), function() pane().inviteMissing(id) end)
        end
    end
end

-- Save keeps the mock raid's changes in its plan, or saves it as a new one
-- when it isn't one yet. Save as new keeps them in a copy, and the plan
-- stays as it was. A new one opens the picker to type its name.
local function saveNew(box, base)
    local name = Pl.freeName(base)
    if not Pl.save(name) then return end
    NS.print("Saved plan %s.", name)
    Pr.openPicker(box.pick, spec, { rename = name })
end

spec.buttons = {
    { label = "Save as new", main = false,
      shown = function() return M.on() and Pl.current() ~= nil and Pl.dirty() end,
      click = function(_, box) saveNew(box, Pl.current() .. " copy") end,
      tip = function() return "Keep the changes in a new plan. Type its name." end },
    { label = "Save", main = true,
      shown = function() return M.on() and Pl.dirty() and (Pl.current() ~= nil or #R.list() > 1) end,
      click = function(_, box)
          local name = Pl.current()
          if not name then return saveNew(box, "New plan") end
          if Pl.save(name) then NS.print("Saved plan %s.", name) end
      end,
      tip = function()
          local name = Pl.current()
          return name and format("Keep the changes in %s.", name) or "Keep the mock raid as a plan."
      end },
}

-- An open picker shows a change made anywhere, like a plan set for an
-- instance from its menu.
NS.listen("plans", function()
    if picker and picker:IsShown() and not picker.renaming then picker.paint() end
end)
