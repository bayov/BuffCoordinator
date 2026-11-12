-- SettingsPage -- a page of settings drawn from an options adapter.
--
-- Every row is drawn from the declarations (Shared/Options.lua), so a setting
-- added tomorrow shows up here, or a test fails. BayovCore's config window
-- (Panel.lua) draws every module's settings with it, and Buff Coordinator's
-- Settings and HUD tabs (Settings.lua) draw theirs.
--
-- THE SHAPE. A tab per option group in a strip along the top, then the rows of
-- the tab on show in a scroll, in one column or two, whichever fits the width.
-- Rows go under a heading per section, with the section's note under it when
-- the adapter has one (`sectionNotes`, and `sectionTitles` for a heading that
-- isn't the section's name).
--
-- A declaration with `sub` goes on a sub-tab of its group's page. The page
-- then starts with a selector of its subs, named by the adapter's
-- `subTitles`, and shows the rows of one sub at a time. With `subTabs` in the
-- opts, the subs are tabs in the strip instead, for a page that has only the
-- one group. A jump to a setting (a click in a preview, a search result)
-- opens its sub too.
--
-- A declaration with `inherit` follows another setting until it's set
-- (Options.lua). Its row has an "All" or "Own" chip where the revert button
-- goes, rather than the changed mark and the revert button: "All" while it
-- follows (its value dimmed), "Own" while it has a value of its own. A click
-- on the chip switches.
--
-- An adapter may carry `visible(key)`, and a row it says no to isn't drawn or
-- counted. An adapter's `extras` are pages of a module's own: a list of
-- { name, title, build, refresh, layout }, or with `under` or `over` a group,
-- drawn under or over that group's rows. An extra page may draw ordinary
-- settings with `page:optionRow(page, key)`.
--
-- NO POLICY IN HERE. Every write goes through `adapter.commit(key, text)`,
-- which is the console's own path: parse, refuse when the module says no,
-- store, apply. So a page can't validate differently from the console.
--
-- SLIDERS ONLY WHERE THE RANGE IS THE POINT. A number's min and max are
-- usually guard rails against a typo, not the range worth exploring. So
-- every number is an edit box, and a declaration with `slide` adds a slider
-- beside it, for a value like an opacity, whose whole range is worth trying.
--
-- HOW A ROW LOOKS is the declaration's too (Options.lua's header): names for
-- a choice's values, a swatch or icon per value, a unit after a number, a
-- row greyed while the setting it `needs` is off, the rows hardly anyone
-- changes folded away under Advanced, and an X and Y drawn as one position
-- row with Move and Reset.
--
-- SP.new(parent, adapter, opts) builds a page into `parent`. The opts:
--
--   name          the frame's global name, or nil
--   cmd           the command that sets an option, like "/bayov raidbuffs",
--                 for the tooltips, or nil when there's no console
--   out           a printer, for the sentence when a write is refused
--   featId        the feature the page is for, which the Move button of a
--                 position row moves (Movers.lua)
--   only          a set of the groups to draw, or nil for every group
--   defaultGroup  the group of a declaration with none, "other" by default
--   subTabs       the subs as tabs in the strip, rather than a selector
--   sub, onSub    the sub to start on, and what hears when another is shown
--
-- The page doesn't select a tab or fill its rows by itself. The caller does
-- that, after it has hooked onSelect, onRefresh and the rest.
--
-- SP.SIZE holds every size, BayovCore's. An addon with a smaller window, like
-- Buff Coordinator, changes them after this file loads. They're read each
-- time a row is made or laid out.
--
-- This file is in bayovui/shared, so BayovCore and Buff Coordinator each load
-- their own copy of it.

local _, NS = ...
local CreateFrame = NS.Profiler and NS.Profiler.scope("config") or CreateFrame

local SP = {}
NS.SettingsPage = SP

local format = string.format
local max, min, floor = math.max, math.min, math.floor

local T = NS.Theme

SP.SIZE = {
    ROW = 34,
    TAB = 30,
    SUB = 26,         -- a button in a page's sub-tab selector
    EDIT = 76,
    REVERT = 20,
    OWN = 44,         -- the "All" / "Own" chip of a row that follows another
    SLIDE = 120,      -- the slider beside a number's edit box (`slide`)
    FOLD = 28,        -- the "Advanced" fold at the end of a page
    -- A choice wider than this, or with more values than ENUM_SEGS, is a
    -- dropdown rather than a run of segments.
    ENUM_MAX = 400,
    ENUM_SEGS = 6,
    SEG = 56,         -- the narrowest a choice's segment is
    DROP_MIN = 130,
    DROP_MAX = 240,
    CTRL = 22,        -- the height of a row's control
    BUTTON = 64,      -- a position row's Move and Reset
    POS_EDIT = 60,
    SCROLL = 14,
    GUTTER = 12,
    INSET = 12,       -- a row's label and control sit this far inside it
    FALLBACK = 700,   -- until the game has given the frame a size
    -- What one column has to hold: a readable label, a control and the
    -- revert button. Two columns only when two of these fit, because two
    -- columns of names cut off halfway are worse than one column of readable
    -- ones.
    MIN_LABEL = 132,
    FOLD_FONT = 12,
    MARK_FONT = 15,
    WARN_FONT = 13,
}
local Z = SP.SIZE

local function minCol()
    return Z.INSET + Z.MIN_LABEL + 8 + Z.REVERT + 6 + Z.EDIT + Z.INSET
end

-- Keys in their `order`, then alphabetical, the order the console lists
-- them in (Options.sortKeys).
local function sortKeys(keys, decls)
    table.sort(keys, function(a, b)
        local oa, ob = decls[a].order or math.huge, decls[b].order or math.huge
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    return keys
end

local WHITE = { 1, 1, 1 }
local BLUE  = { 0.5, 0.84, 1.0 }
local GREY  = { 0.5, 0.5, 0.5 }

-- The default of `key`, which may be a function's answer, like a font that
-- depends on another addon being loaded.
local function defaultOf(a, key, decl)
    local v = a and a.default and a.default(key)
    if v == nil then v = decl.default end
    return v
end

-- The values of choice `key`, which may come from a function, like the fonts
-- LibSharedMedia knows.
local function valuesOf(a, key, decl)
    local v = a and a.values and a.values(key)
    if type(v) ~= "table" then v = decl.values end
    if type(v) == "function" then v = v() end
    return v or {}
end

-- =============================================================
-- Tooltip
-- =============================================================
-- The name, the command that sets it, the range and default, then what it
-- does. The same lines the console prints for `<command> <key>`, so the
-- window teaches the console. Without a console there's no command, and a
-- choice's values go by their names only.
local function rowTooltip(self)
    local decl, key = self.decl, self.optKey
    if not decl or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(decl.name or key, T.GOLD[1], T.GOLD[2], T.GOLD[3])
    if self.cmd then
        GameTooltip:AddLine(self.cmd, BLUE[1], BLUE[2], BLUE[3])
    end
    local a = self.panel and self.panel.adapter
    if decl.default == nil and decl.inherit and a then
        local from = a.decls[decl.inherit] or {}
        local where = from.sub and a.subTitles and a.subTitles[from.sub]
        GameTooltip:AddLine(format("the same as %s%s unless set here, now %s",
                                   from.name or decl.inherit,
                                   where and (" in " .. where) or "",
                                   a.format(decl.inherit)),
                            GREY[1], GREY[2], GREY[3], true)
    elseif decl.kind == "enum" then
        local names = {}
        for i, v in ipairs(valuesOf(a, key, decl)) do
            local l = decl.labels and decl.labels[v]
            if not self.cmd then
                names[i] = l or tostring(v)
            else
                names[i] = (l and l ~= v) and format("%s (%s)", l, v) or v
            end
        end
        GameTooltip:AddLine("one of: " .. table.concat(names, ", "),
                            GREY[1], GREY[2], GREY[3], true)
    elseif decl.kind == "number" and (decl.min or decl.max) then
        GameTooltip:AddLine(format("%s to %s, default %s",
                                   tostring(decl.min), tostring(decl.max),
                                   tostring(defaultOf(a, key, decl))),
                            GREY[1], GREY[2], GREY[3])
    else
        GameTooltip:AddLine("default " .. tostring(defaultOf(a, key, decl)),
                            GREY[1], GREY[2], GREY[3])
    end
    GameTooltip:AddLine(decl.desc, WHITE[1], WHITE[2], WHITE[3], true)
    if self.unmet then
        GameTooltip:AddLine(self.unmet, T.ORANGE[1], T.ORANGE[2], T.ORANGE[3], true)
    end
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function simpleTip(owner, title, text)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 1, 1)
    if text then GameTooltip:AddLine(text, GREY[1], GREY[2], GREY[3], true) end
    GameTooltip:Show()
end
SP.simpleTip, SP.hideTooltip = simpleTip, hideTooltip

-- =============================================================
-- One row
-- =============================================================
-- A row holds its control, and `apply` is the only thing that moves the
-- control. It is driven by what the store says, never by what the control said
-- a moment ago. So a refused write puts the control back for free: the write
-- doesn't land, the refresh shows what storage still says.
--
-- `full` is whether the row needs a whole line. A choice is a run of segments
-- as wide as its values, so it can't share a line with another row.
local function newRow(parent, panel, key, decl)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(Z.ROW)
    row.optKey, row.decl, row.panel = key, decl, panel
    -- Set by the layout for a choice of segments, from whether they fit a
    -- column.
    row.full = false

    -- The command that sets this option, for the tooltip.
    if panel.cmd then row.cmd = panel.cmd .. " " .. key end

    row.bg = T.fill(row, WHITE, 0.03)
    row.bg:SetAllPoints(row)
    row.hl = T.fill(row, WHITE, 0.05, "BORDER")
    row.hl:SetAllPoints(row)
    row.hl:Hide()

    row.label = T.text(row, T.SIZE.label, false, T.A_TEXT)
    row.label:SetPoint("LEFT", row, "LEFT", Z.INSET, 0)
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    -- Kept apart from what is drawn, which grows a `*` when the value isn't
    -- the default.
    row.labelText = decl.name or key
    row.name = row.labelText
    row.label:SetText(row.labelText)

    -- The whole row is the tooltip's hit area, not just the control. The
    -- parts of the preview it changes light up too.
    local function lightPreview(on)
        local band = panel.band and panel.band()
        if band then band.highlight(key, on) end
    end
    local function enter() row.hl:Show() rowTooltip(row) lightPreview(true) end
    local function leave() row.hl:Hide() hideTooltip() lightPreview(false) end
    row:EnableMouse(true)
    row:SetScript("OnEnter", enter)
    row:SetScript("OnLeave", leave)

    -- Shown only when the value isn't the default. A reset button on every
    -- row would be forty buttons saying nothing.
    if decl.default == nil and decl.inherit then
        -- The "All" / "Own" chip of a row that follows another.
        local a = panel.adapter
        local own = T.segment(row, "All", Z.OWN, Z.CTRL - 2)
        own:SetScript("OnClick", function()
            if a.inherits(key) then
                panel:commit(key, a.format(key))
            else
                panel:reset(key)
            end
        end)
        own:SetScript("OnEnter", function(self)
            row.hl:Show()
            local from = a.decls[decl.inherit] or {}
            local where = from.sub and a.subTitles and a.subTitles[from.sub]
            local shared = format("%s%s", from.name or decl.inherit,
                                  where and (" in " .. where) or "")
            if a.inherits(key) then
                simpleTip(self, "Follows " .. (where or "the shared setting"),
                          format("This uses %s, now %s. Click to keep it as its own, or type"
                                 .. " a value%s.", shared, a.format(decl.inherit),
                                 row.slider and " or move the slider" or ""))
            else
                simpleTip(self, "Its own value",
                          format("Click to follow %s again, now %s.", shared,
                                 a.format(decl.inherit)))
            end
        end)
        own:SetScript("OnLeave", leave)
        row.own, row.revert, row.revW = own, own, Z.OWN
    else
        row.revert = T.revert(row, function() panel:reset(key) end, function(self)
            row.hl:Show()
            simpleTip(self, "Back to the default",
                      "The default is " .. tostring(defaultOf(panel.adapter, key, decl)) .. ".")
        end, leave)
        row.revert:SetSize(Z.REVERT, Z.REVERT)
        row.revW = Z.REVERT
    end

    if decl.kind == "bool" then
        local check = T.toggle(row)
        check:SetScript("OnClick", function(self)
            -- The adapter parses text, so we hand it text. One parser, and
            -- "on"/"off" is what the console takes.
            panel:commit(key, self:GetChecked() and "on" or "off")
        end)
        check:SetScript("OnEnter", enter)
        check:SetScript("OnLeave", leave)
        row.control = check
        row.ctrlW = floor((check:GetWidth() or 36) + 0.5)
        row.apply = function(self, value, enabled)
            check:show(value, enabled)
        end

    elseif decl.kind == "enum" then
        -- A segment per value rather than a dropdown, when they fit. The
        -- enums here are mostly short by nature, and three visible choices
        -- say what the choices are, which a closed dropdown doesn't. A long
        -- one, like six motions, is a dropdown.
        local labels = decl.labels or {}
        local swatches = decl.swatches or {}
        local icons = decl.icons or {}
        local values = valuesOf(panel.adapter, key, decl)
        local buttons, total = {}, 0
        for _, v in ipairs(values) do
            -- As wide as its text, with room on both sides.
            local b = T.segment(row, labels[v] or v, Z.SEG, Z.CTRL)
            local extra = 0
            if swatches[v] then
                local sw = T.fill(b, swatches[v], 1, "ARTWORK")
                sw:SetSize(10, 10)
                sw:SetPoint("LEFT", b, "LEFT", 9, 0)
                b.swatch, extra = sw, 16
            elseif icons[v] then
                local ic = T.icon(b, icons[v], 14)
                ic:SetPoint("LEFT", b, "LEFT", 8, 0)
                b.icon, extra = ic, 18
            end
            if extra > 0 then
                b.label:ClearAllPoints()
                b.label:SetPoint("LEFT", b, "LEFT", 8 + extra, 0)
            end
            local tw = (b.label:GetStringWidth() or 0)
            local w = max(extra > 0 and 34 or Z.SEG, floor(tw + 28 + extra + 0.5))
            if (labels[v] or v) == "" then w = 30 end
            b:SetWidth(w)
            b:SetScript("OnClick", function() panel:commit(key, v) end)
            b:SetScript("OnEnter", enter)
            b:SetScript("OnLeave", leave)
            buttons[#buttons + 1] = { value = v, frame = b, w = w }
            total = total + w + 2
        end

        if decl.drop or total - 2 > Z.ENUM_MAX or #values > Z.ENUM_SEGS then
            for _, b in ipairs(buttons) do b.frame:Hide() end
            local items, widest = {}, 0
            for i, v in ipairs(values) do
                items[i] = { value = v, label = labels[v] or v, swatch = swatches[v] }
                local fs = buttons[i].frame.label
                widest = max(widest, fs:GetStringWidth() or 0)
            end
            local ddW = min(Z.DROP_MAX, max(Z.DROP_MIN, floor(widest + 48)))
            local dd = T.dropdown(row, ddW, Z.CTRL)
            dd:setItems(items)
            dd.onPick = function(v) panel:commit(key, v) end
            dd:SetScript("OnEnter", enter)
            dd:SetScript("OnLeave", leave)
            row.control = dd
            row.ctrlW = ddW
            row.apply = function(self, value, enabled)
                dd:show(value, enabled)
            end
        else
            row.control = buttons[1] and buttons[1].frame
            row.buttons = buttons
            row.ctrlW = total - 2
            -- Whether it shares a line is up to the layout: a short choice
            -- fits a column like any row, a long one takes the whole line.
            row.wide = true
            row.apply = function(self, value, enabled)
                for _, b in ipairs(buttons) do
                    -- The chosen one is DISABLED. Pressing the mode you are
                    -- already in still rebuilds the rotation's engine, and
                    -- mid-pull that costs the live GCD reading.
                    local chosen = (b.value == value)
                    if chosen then b.frame:Disable()
                    elseif enabled then b.frame:Enable()
                    else b.frame:Disable() end
                    b.frame:show(chosen, enabled)
                    local a = enabled and 1 or 0.4
                    if b.frame.swatch then b.frame.swatch:SetAlpha(a) end
                    if b.frame.icon then b.frame.icon:SetAlpha(a) end
                end
            end
        end

    else
        local edit = T.edit(row, Z.EDIT, Z.CTRL)
        edit:SetMaxLetters(12)
        edit:SetScript("OnEnterPressed", function(self)
            panel:commit(key, self:GetText() or "")
            self:ClearFocus()
        end)
        edit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            panel:refresh()
        end)
        -- Losing focus REVERTS rather than commits. A half-typed number that
        -- applies because you clicked elsewhere is how a settings page
        -- silently changes something you were only looking at.
        edit.onFocusLost = function() panel:refresh() end
        edit:SetScript("OnEnter", enter)
        edit:SetScript("OnLeave", leave)
        row.control = edit
        row.ctrlW = Z.EDIT

        -- The unit after the box, so the name doesn't carry it.
        if decl.unit then
            row.unit = T.text(row, T.SIZE.body, false, T.A_DIM)
            row.unit:SetText(decl.unit)
            row.unitW = max(14, floor((row.unit:GetStringWidth() or 14) + 0.5))
            row.ctrlW = row.ctrlW + 5 + row.unitW
        end

        -- A slider beside it, for a value whose range is worth trying. It
        -- moves the number in the box as it's dragged and writes once, when
        -- it's let go, so a drag is one write rather than fifty.
        if decl.slide and decl.min and decl.max then
            local step = decl.step or ((decl.max - decl.min) <= 2 and 0.05 or 1)
            local r = T.range(row, Z.SLIDE, decl.min, decl.max, step)
            r.onChange = function(v)
                edit:SetText(((v == floor(v)) and tostring(floor(v))) or format("%.2f", v))
            end
            r.onCommit = function(v) panel:commit(key, tostring(v)) end
            r:HookScript("OnEnter", enter)
            r:HookScript("OnLeave", leave)
            row.slider = r
            row.ctrlW = row.ctrlW + Z.SLIDE + 10
        end

        row.apply = function(self, value, enabled)
            T.setText(edit, panel.adapter.format(key))
            if enabled then edit:Enable() else edit:Disable() end
            edit:SetTextColor(1, 1, 1, enabled and T.A_TEXT or T.A_OFF)
            if self.slider then
                if not self.slider.dragging and type(value) == "number" then
                    self.slider:SetValue(value)
                end
                self.slider:EnableMouse(enabled)
                self.slider:SetAlpha(enabled and 1 or 0.35)
            end
            if self.unit then
                self.unit:SetTextColor(1, 1, 1, enabled and T.A_DIM or T.A_OFF)
            end
        end
    end

    -- Laid out again whenever the width changes. The control sits at the
    -- right edge and the revert button just left of it, so the controls in a
    -- column line up whatever the labels do.
    function row:place(w)
        self:SetWidth(w)
        local ctrlX = w - Z.INSET - self.ctrlW
        self.label:SetWidth(max(40, ctrlX - 6 - self.revW - 8 - Z.INSET))
        if self.buttons then
            local x = ctrlX
            for _, b in ipairs(self.buttons) do
                b.frame:ClearAllPoints()
                b.frame:SetPoint("LEFT", self, "LEFT", x, 0)
                x = x + b.w + 2
            end
        else
            local x = ctrlX
            if self.slider then
                self.slider:ClearAllPoints()
                self.slider:SetPoint("LEFT", self, "LEFT", x, 0)
                x = x + Z.SLIDE + 10
            end
            self.control:ClearAllPoints()
            self.control:SetPoint("LEFT", self, "LEFT", x, 0)
            if self.unit then
                self.unit:ClearAllPoints()
                self.unit:SetPoint("LEFT", self, "LEFT", x + Z.EDIT + 5, 0)
            end
        end
        self.revert:ClearAllPoints()
        self.revert:SetPoint("LEFT", self, "LEFT", ctrlX - 6 - self.revW, 0)
    end

    return row
end

-- =============================================================
-- A position row
-- =============================================================
-- An X and a Y drawn as one row: a box for each number, a Move button that
-- puts our HUD in its moving mode (Movers.lua), and a Reset that puts both
-- back. The boxes behave like a number row's: Enter writes, and Escape or a
-- click elsewhere puts the number back.
--
-- A declaration with `noMove` has no Move button. BayovRotation's display
-- isn't in Movers, because you drag the display itself.
local function newPosRow(parent, panel, xKey, yKey, decl)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(Z.ROW)
    row.isPos, row.xKey, row.yKey, row.decl = true, xKey, yKey, decl
    row.bg = T.fill(row, WHITE, 0.03)
    row.bg:SetAllPoints(row)
    row.label = T.text(row, T.SIZE.label, false, T.A_TEXT)
    row.label:SetPoint("LEFT", row, "LEFT", Z.INSET, 0)
    row.label:SetText(decl.posName or "Position")
    local function box(key, letter)
        local edit = T.edit(row, Z.POS_EDIT, Z.CTRL)
        edit:SetMaxLetters(12)
        edit:SetScript("OnEnterPressed", function(self)
            panel:commit(key, self:GetText() or "")
            self:ClearFocus()
        end)
        edit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            panel:refresh()
        end)
        edit.onFocusLost = function() panel:refresh() end
        edit.letter = T.text(row, T.SIZE.body, false, T.A_DIM)
        edit.letter:SetText(letter)
        edit.letter:SetPoint("RIGHT", edit, "LEFT", -5, 0)
        return edit
    end
    row.x, row.y = box(xKey, "X"), box(yKey, "Y")

    -- It moves only this feature, and picks this row's part for the arrow
    -- keys. A feature with nothing in Movers moves the whole HUD.
    row.move = T.button(row, "Move", Z.BUTTON, Z.CTRL)
    row.move:SetScript("OnClick", function()
        local M = NS.Movers
        if not M then return end
        local id = panel.featId
        if id and M.has and M.has(id) and M.moveOnly then
            if M.movingOnly() == id then M.stop() else M.moveOnly(id, xKey) end
        else
            M.start()
        end
    end)
    row.move.tip = function(b)
        simpleTip(b, "Move", "Shows it where it goes on your screen. Drag it, or use the arrow keys"
            .. " to move it a pixel at a time (Shift for ten). Enter or Escape when you're done."
            .. (panel.moveAll and (" " .. panel.moveAll) or ""))
    end
    row.reset = T.button(row, "Reset", Z.BUTTON, Z.CTRL)
    row.reset:SetScript("OnClick", function()
        panel.adapter.reset(xKey)
        panel:reset(yKey)
    end)
    row.reset.tip = function(b) simpleTip(b, "Reset", "Back to where it starts.") end
    row.ctrlW = 14 + Z.POS_EDIT + 10 + 14 + Z.POS_EDIT + 12 + Z.BUTTON
    if decl.noMove then row.move:Hide() else row.ctrlW = row.ctrlW + Z.BUTTON + 6 end

    row:EnableMouse(true)
    local function lightPreview(on)
        local band = panel.band and panel.band()
        if band then band.highlight(xKey, on) end
    end
    local function enter()
        simpleTip(row, row.label:GetText(), panel.cmd
                  and format("%s and %s.", panel.cmd .. " " .. xKey, panel.cmd .. " " .. yKey))
        lightPreview(true)
    end
    local function leave()
        hideTooltip()
        lightPreview(false)
    end
    row:SetScript("OnEnter", enter)
    row:SetScript("OnLeave", leave)
    for _, e in ipairs({ row.x, row.y }) do
        e:SetScript("OnEnter", enter)
        e:SetScript("OnLeave", leave)
    end

    function row:fill(enabled)
        local a = panel.adapter
        T.setText(self.x, a.format(xKey))
        T.setText(self.y, a.format(yKey))
        for _, e in ipairs({ self.x, self.y }) do
            e:SetEnabled(enabled)
            e:SetAlpha(enabled and 1 or 0.4)
        end
        local moved = not (a.isDefault(xKey) and a.isDefault(yKey))
        self.label:SetText((decl.posName or "Position") .. (moved and panel.marks and (" " .. T.MARK) or ""))
        self.label:SetTextColor(1, 1, 1, enabled and T.A_TEXT or T.A_FAINT)
        local M = NS.Movers
        self.move:SetText(M and M.movingOnly and M.movingOnly() == panel.featId and "Done" or "Move")
        if enabled then self.move:Enable() else self.move:Disable() end
        if enabled and moved then self.reset:Enable() else self.reset:Disable() end
    end

    function row:place(w)
        self:SetWidth(w)
        self.reset:ClearAllPoints()
        self.reset:SetPoint("RIGHT", self, "RIGHT", -Z.INSET, 0)
        self.move:ClearAllPoints()
        self.move:SetPoint("RIGHT", self.reset, "LEFT", -6, 0)
        self.y:ClearAllPoints()
        self.y:SetPoint("RIGHT", decl.noMove and self.reset or self.move, "LEFT", -12, 0)
        self.x:ClearAllPoints()
        self.x:SetPoint("RIGHT", self.y.letter, "LEFT", -10, 0)
    end
    return row
end

-- =============================================================
-- The Advanced fold
-- =============================================================
-- A line at the end of a page (or a sub) that opens the rows hardly anyone
-- changes. It counts them, and says when one of them is changed, so a fold
-- never hides a change.
local function newFold(parent, page, sub, onToggle)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(Z.FOLD)
    f.isFold, f.sub = true, sub
    f.label = T.text(f, Z.FOLD_FONT, true, T.A_DIM)
    f.label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.line = T.fill(f, WHITE, 0.07, "ARTWORK")
    f.line:SetHeight(1)
    f.line:SetPoint("LEFT", f.label, "RIGHT", 10, 0)
    f.line:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.count, f.changed = 0, false
    function f:paint(over)
        local open = page.foldOpen and page.foldOpen[sub or "_"]
        self.label:SetText(format("%s ADVANCED (%d)%s", open and "-" or "+",
                                  self.count, self.changed and (" " .. T.MARK) or ""))
        self.label:SetTextColor(1, 1, 1, over and 1 or T.A_DIM)
    end
    f:SetScript("OnEnter", function(self) self:paint(true) end)
    f:SetScript("OnLeave", function(self) self:paint(false) end)
    f:SetScript("OnClick", function(self)
        page.foldOpen = page.foldOpen or {}
        local k = sub or "_"
        page.foldOpen[k] = not page.foldOpen[k]
        self:paint(true)
        onToggle()
    end)
    return f
end

-- Whether the setting a row `needs` holds, and the sentence for when it
-- doesn't. A string is a bool key that must be on, a table holds keys and the
-- values they must have, and a function decides for itself.
local function needsMet(a, needs)
    if needs == nil then return true end
    if type(needs) == "function" then
        local ok, met, why = pcall(needs)
        if not ok then return true end
        return met and true or false, why
    end
    if type(needs) == "string" then needs = { [needs] = true } end
    for k, want in pairs(needs) do
        if a.get(k) ~= want then
            local d = a.decls[k] or {}
            local name = d.name or k
            if want == true then return false, format("Needs %s on.", name) end
            if want == false then return false, format("Needs %s off.", name) end
            local l = d.labels and d.labels[want] or tostring(want)
            return false, format("Needs %s set to %s.", name, l)
        end
    end
    return true
end
SP.needsMet = needsMet

-- =============================================================
-- A tab in a feature's strip
-- =============================================================
-- The word, and an accent underline under the one on show, the way EUI's
-- tabs look. They go left to right in the order they are made, because
-- BayovRotation's pages arrive after the generated ones.
local function newTab(panel, name, title)
    local b = CreateFrame("Button", nil, panel.strip)
    b:SetHeight(Z.TAB)
    b.label = T.text(b, T.SIZE.tab, true, T.A_DIM)
    b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
    -- `name` stays the identity (what `/bayov <mod> list <group>` takes), and
    -- the title is only ever read.
    b.label:SetText(title or name)

    b.selected = T.fill(b, T.ACCENT, 1, "ARTWORK")
    b.selected:SetHeight(2)
    b.selected:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, 0)
    b.selected:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 0)
    b.selected:Hide()

    b.mark = T.text(b, Z.MARK_FONT, true, 1)
    b.mark:SetPoint("LEFT", b.label, "RIGHT", 2, 2)
    b.mark:SetText(T.MARK)
    b.mark:Hide()

    local w = floor((b.label:GetStringWidth() or 40) + 30)
    b:SetWidth(w)
    -- mt:wrapTabs places it, since where it goes depends on the width.
    panel.tabs[#panel.tabs + 1] = b

    function b:light(on)
        self.on = on
        self.selected:SetShown(on)
        self.label:SetTextColor(1, 1, 1, on and 1 or T.A_DIM)
    end
    b:SetScript("OnEnter", function(self)
        if not self.on then self.label:SetTextColor(1, 1, 1, 0.85) end
    end)
    b:SetScript("OnLeave", function(self)
        self.label:SetTextColor(1, 1, 1, self.on and 1 or T.A_DIM)
    end)
    b:SetScript("OnClick", function() panel:select(name) end)
    return b
end

-- =============================================================
-- A module's settings
-- =============================================================
local mt = {}
mt.__index = mt
-- For a stand-in that holds a page's adapter before the page is built, like
-- BayovCore's (Panel.add), so it can count what changed.
SP.mt = mt

-- A row for an option an extra page draws itself, positioned by whoever
-- asked for it. It goes into `self.rows`, which mt:refresh walks, so it is
-- filled, greyed and marked like every generated row. It doesn't go into
-- `page.rows`, which mt:layout arranges into columns, because an extra page
-- lays itself out. Hidden on arrival: the page decides where it goes.
function mt:optionRow(page, key)
    local decl = self.adapter.decls[key]
    if not decl then return nil end
    local row = newRow(page.frame, self, key, decl)
    row.needs = decl.needs
    row:Hide()
    self.rows[#self.rows + 1] = row
    page.owned = page.owned or {}
    page.owned[#page.owned + 1] = row
    return row
end

function mt:select(name)
    self.current = name
    self.aboutShown = nil
    for _, page in ipairs(self.pages) do
        local on = (page.name == name)
        page.frame:SetShown(on)
        page.tab:light(on)
        -- A page whose subs are tabs in the strip shows them only while
        -- it's on show.
        for _, b in ipairs(page.subTabs or {}) do b:SetShown(on) end
    end
    if self.aboutView then
        self.aboutView:Hide()
        self.aboutTab:light(false)
    end
    self.scroll:Show()
    self:layout()
    if self.scroll.setScroll then self.scroll:setScroll(0) end
    if self.onSelect then self.onSelect() end
end

-- Puts sub `sub` on show on `page`, and tells `onSub` when that's a change.
function mt:setSub(page, sub)
    if page.sub == sub then return end
    page.sub = sub
    if self.onSub then self.onSub(sub, page.name) end
end

-- Shows sub `sub` of page `name`, the page on show when it's nil.
function mt:selectSub(sub, name)
    for _, page in ipairs(self.pages) do
        if page.name == (name or self.current) and page.subOf and page.subOf[sub] then
            self:setSub(page, sub)
            if page.name ~= self.current then return self:select(page.name) end
            self:layout()
            if self.scroll.setScroll then self.scroll:setScroll(0) end
            if self.onSelect then self.onSelect() end
            return
        end
    end
end

-- The sub on show on the page on show, or nil.
function mt:currentSub()
    for _, page in ipairs(self.pages) do
        if page.name == self.current then return page.sub end
    end
end

-- How tall the tab strip is, one Z.TAB for each line of tabs.
function mt:tabsH()
    return self.stripH or Z.TAB
end

-- Moves the settings down by `extra`, for a preview band under the tabs.
function mt:setTop(extra)
    self.topExtra = extra
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -(self:tabsH() + 12 + (extra or 0)))
    self.scroll:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
end

-- Places the tabs in lines as wide as the window.
--
-- A module with many tabs, like Upgrades, has more than fit beside each other
-- in a narrow window, so the ones that don't fit go on a new line under the
-- others. The first line also leaves room at its right end for the head
-- buttons and the combat line. When the number of lines changes, everything
-- under the tabs moves down or up with them.
function mt:wrapTabs()
    local w = self.frame:GetWidth() or 0
    if w < 200 then w = Z.FALLBACK end
    local reserve = 0
    for _, b in ipairs(self.heads) do reserve = reserve + b:GetWidth() + 6 end
    if self.warning:IsShown() then
        reserve = reserve + (self.warning:GetStringWidth() or 0) + 12
    end
    local x, line = 0, 0
    for _, b in ipairs(self.tabs) do
        if b:IsShown() then
            local room = w - (line == 0 and reserve or 0)
            if x > 0 and x + b:GetWidth() > room then x, line = 0, line + 1 end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.strip, "TOPLEFT", x, -line * Z.TAB)
            x = x + b:GetWidth() + 2
        end
    end
    local h = (line + 1) * Z.TAB
    if h == self.stripH then return end
    self.stripH = h
    self.strip:SetHeight(h)
    self:setTop(self.topExtra)
    if self.onTabLines then self.onTabLines() end
end

-- A module's own button at the top right, on every tab, like Supplies'
-- window toggle or Consumes' Move icons. Each one added goes left of the one
-- before, and the combat line moves left of them all.
function mt:headButton(b)
    local last = self.heads[#self.heads]
    b:SetParent(self.frame)
    b:ClearAllPoints()
    if last then
        b:SetPoint("RIGHT", last, "LEFT", -6, 0)
    else
        b:SetPoint("RIGHT", self.strip, "TOPRIGHT", 0, -Z.TAB / 2)
    end
    self.heads[#self.heads + 1] = b
    self.warning:ClearAllPoints()
    self.warning:SetPoint("RIGHT", b, "LEFT", -12, 0)
end

-- The About tab, which the feature's page adds after the settings tabs. Its
-- view takes the place of the settings while it is on show.
function mt:addAbout(view)
    self.aboutView = view
    self.aboutTab = newTab(self, "about", "About")
    self.aboutTab:SetScript("OnClick", function() self:showAbout() end)
end

function mt:showAbout()
    for _, page in ipairs(self.pages) do page.tab:light(false) end
    self.aboutTab:light(true)
    self.scroll:Hide()
    self.aboutView:Show()
    self.aboutShown = true
    if self.onSelect then self.onSelect() end
end

-- The settings this character has changed, in the order the page shows them.
--
-- Listed by setting rather than by row, so a setting with two rows (an extra
-- page can draw one with mt:optionRow) still counts once.
--
-- A setting with no row counts too, last. Supplies draws its `role` as a chip
-- rather than a row. And a page not built yet (Panel.add) has no rows at all,
-- so it counts the same settings the built page would.
function mt:changedKeys()
    local a, keys, seen = self.adapter, {}, {}
    local function add(key)
        if not seen[key] and (not a.visible or a.visible(key))
           and not a.isDefault(key) then
            keys[#keys + 1] = key
        end
        seen[key] = true
    end
    for _, row in ipairs(self.rows or {}) do add(row.optKey) end
    -- An X and Y have no rows of their own. Their position row holds both.
    for _, page in ipairs(self.pages or {}) do
        for _, pr in ipairs(page.posRows or {}) do
            add(pr.xKey)
            add(pr.yKey)
        end
    end
    local rest = {}
    for key in pairs(a.decls) do
        if not seen[key] then rest[#rest + 1] = key end
    end
    sortKeys(rest, a.decls)
    for _, key in ipairs(rest) do add(key) end
    return keys
end

local NONE = {}

-- Whether `key` counts as a changed setting.
local function isChanged(a, key)
    return (not a.visible or a.visible(key)) and not a.isDefault(key)
end

-- A row's or position row's key that no declaration has counts once too.
-- Only a page that draws rows of its own can have one, so `seen` is rarely
-- made. Answers `seen` and 1 when the key counts.
local function extraKey(a, seen, key)
    if key == nil or a.decls[key] ~= nil or (seen and seen[key]) then return seen, 0 end
    seen = seen or {}
    seen[key] = true
    return seen, isChanged(a, key) and 1 or 0
end

-- How many settings this character has changed. The sidebar marks a feature
-- that has any, and the Overview counts them.
--
-- A module whose changes aren't all settings counts the rest with `edits()`
-- on its adapter. Supplies does, so a changed count on one supply marks the
-- whole feature in the sidebar.
--
-- It counts the same settings as mt:changedKeys, without making and sorting
-- that list. The sidebar's marks and the Overview ask every module for this
-- on each refresh, and building every module's sorted list each time was most
-- of the garbage of opening the config window.
function mt:changed()
    local a, n = self.adapter, 0
    for key in pairs(a.decls) do
        if isChanged(a, key) then n = n + 1 end
    end
    local seen, d
    for _, row in ipairs(self.rows or NONE) do
        seen, d = extraKey(a, seen, row.optKey)
        n = n + d
    end
    for _, page in ipairs(self.pages or NONE) do
        for _, pr in ipairs(page.posRows or NONE) do
            seen, d = extraKey(a, seen, pr.xKey)
            n = n + d
            seen, d = extraKey(a, seen, pr.yKey)
            n = n + d
        end
    end
    if a.edits then
        local ok, more = pcall(a.edits)
        if ok and type(more) == "number" then n = n + more end
    end
    return n
end

-- What this character changed, a line each, for the Overview's tooltip. A
-- setting says its value and its default. The rest comes from the module's
-- `editLines()`, like "Mana Potion: keep 15".
function mt:changedLines()
    local a, lines = self.adapter, {}
    for _, key in ipairs(self:changedKeys()) do
        local decl = a.decls[key] or {}
        local def = decl.default
        if type(def) == "boolean" then def = def and "on" or "off" end
        local where = decl.sub and a.subTitles and a.subTitles[decl.sub]
        local name = (where and (where .. ": ") or "") .. (decl.name or key)
        if def == nil and decl.inherit then
            lines[#lines + 1] = format("%s: %s (its own, the shared one is %s)", name,
                                       a.format(key), a.format(decl.inherit))
        else
            lines[#lines + 1] = format("%s: %s (default %s)", name, a.format(key),
                                       tostring(def))
        end
    end
    if a.editLines then
        local ok, more = pcall(a.editLines)
        if ok and type(more) == "table" then
            for _, line in ipairs(more) do lines[#lines + 1] = line end
        end
    end
    return lines
end

-- Everything that depends on the width, which the game only knows once the
-- window is on screen.
function mt:layout()
    self:wrapTabs()
    -- The width we laid out at, so OnSizeChanged can tell a new one.
    self.laidW = self.frame:GetWidth()
    local frameW = self.frame:GetWidth() or 0
    if frameW < 200 then frameW = Z.FALLBACK end
    local paneW = frameW - Z.SCROLL
    if paneW < minCol() then paneW = minCol() end
    self.paneW = paneW

    -- Two columns when two readable ones fit. Decided by width rather than by
    -- how many options there are, because what has to fit is a label beside
    -- its control.
    local cols = (paneW >= minCol() * 2 + Z.GUTTER) and 2 or 1
    local colW = floor((paneW - (cols - 1) * Z.GUTTER) / cols)
    self.cols, self.colW = cols, colW

    self.content:SetWidth(paneW)

    for _, page in ipairs(self.pages) do
        if page.name == self.current then
            local col, y, line = 0, 0, 0
            -- The subs as tabs in the strip (`subTabs`).
            for _, b in ipairs(page.subTabs or {}) do
                b:light(b.sub == page.sub)
                b.mark:SetShown((self.marks and page.subTouched and page.subTouched[b.sub]) and true or false)
            end
            -- The sub-tab selector, in lines as wide as the page.
            local bar = page.subBar
            if bar then
                local x, by = 0, 0
                for _, b in ipairs(bar.buttons) do
                    if x > 0 and x + b:GetWidth() > paneW then x, by = 0, by + Z.SUB + 4 end
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -by)
                    x = x + b:GetWidth() + 4
                    b.label:SetText(b.title .. (self.marks and page.subTouched and page.subTouched[b.sub]
                                                and (" " .. T.MARK) or ""))
                    b:show(b.sub == page.sub, true)
                end
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, 0)
                bar:SetSize(paneW, by + Z.SUB)
                y = by + Z.SUB + 14
            end
            -- What the module draws above the rows (`over`).
            if page.layoutTop then
                y = page.layoutTop(self, page.frame, y, paneW) or y
            end
            for _, row in ipairs(page.rows) do
                local hidden = row.sub ~= nil and row.sub ~= page.sub
                -- A folded row is on show only while its fold is open.
                if not hidden and row.adv then
                    hidden = not (page.foldOpen and page.foldOpen[row.sub or "_"])
                end
                row:SetShown(not hidden)
                if row.wide then
                    -- A choice of segments shares a line when it fits a
                    -- column beside its name.
                    row.full = cols == 1 or (Z.INSET + Z.MIN_LABEL + 8 + row.revW + 6
                                             + row.ctrlW + Z.INSET > colW)
                end
                if hidden then
                    -- Not on show: another sub's row, or a folded one.
                elseif row.isFold then
                    if col > 0 then col, y = 0, y + Z.ROW + 2 end
                    y = y + 10
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, -y)
                    row:SetWidth(paneW)
                    row:paint(false)
                    y, line = y + Z.FOLD + 6, 0
                elseif row.isHead then
                    -- A section heading closes an open line and takes the
                    -- whole width. The first one sits at the top, and later
                    -- ones get some space from the rows above them.
                    if col > 0 then col, y = 0, y + Z.ROW + 2 end
                    if y > 0 then y = y + 8 end
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, -y)
                    row:SetWidth(paneW)
                    y, line = y + row:GetHeight() + 4, 0
                elseif row.isNote then
                    -- A section's note, under its heading.
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 0, -y)
                    y, line = y + row:place(paneW) + 6, 0
                else
                    -- A full-width row closes an open line first rather than
                    -- leaving a hole beside itself.
                    if row.full and col > 0 then
                        col, y, line = 0, y + Z.ROW + 2, line + 1
                    end
                    local w = row.full and paneW or colW
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", page.frame, "TOPLEFT",
                                 col * (colW + Z.GUTTER), -y)
                    row:place(w)
                    -- Alternate lines are a shade lighter, as in EUI, so the
                    -- eye can follow a row across to its control.
                    row.bg:SetColorTexture(1, 1, 1,
                                           line % 2 == 0 and 0.035 or 0.015)
                    if row.full then
                        col, y, line = 0, y + Z.ROW + 2, line + 1
                    else
                        col = col + 1
                        if col >= cols then
                            col, y, line = 0, y + Z.ROW + 2, line + 1
                        end
                    end
                end
            end
            if col > 0 then y = y + Z.ROW + 2 end

            if page.layout then
                y = page.layout(self, page.frame, y, paneW) or y
            end

            page.frame:SetSize(paneW, max(y, 10))
            self.content:SetHeight(max(y, 10))
        end
    end
    if self.scroll.update then self.scroll:update() end
end

function mt:refresh()
    local a = self.adapter
    local locked, why = a.locked()
    local enabled = not locked

    -- A row for a key this character doesn't have is left as it was built:
    -- hidden, never filled and not counted.
    local function shown(key)
        return not a.visible or a.visible(key)
    end

    for _, row in ipairs(self.rows) do
        local key = row.optKey
        -- A row whose `needs` doesn't hold is greyed like a locked one, and
        -- its tooltip says what it needs.
        local met, why = needsMet(a, row.needs)
        row.unmet = (not met) and (why or "Needs another setting on.") or nil
        local enabled = enabled and met
        if shown(key) and row.own then
            -- No changed mark: the chip says whether it has its own value.
            local following = a.inherits(key)
            row.apply(row, a.get(key), enabled)
            row.label:SetText(row.labelText)
            row.label:SetTextColor(1, 1, 1, enabled and T.A_TEXT or T.A_FAINT)
            row.own.label:SetText(following and "All" or "Own")
            row.own:show(not following, enabled)
            if enabled then row.own:Enable() else row.own:Disable() end
            if following and row.decl.kind == "number" and row.control.SetTextColor then
                row.control:SetTextColor(1, 1, 1, enabled and T.A_DIM or T.A_OFF)
            end
        elseif shown(key) then
            local isDefault = a.isDefault(key)
            row.apply(row, a.get(key), enabled)
            row.label:SetText(row.labelText
                              .. ((isDefault or not self.marks) and "" or " " .. T.MARK))
            row.label:SetTextColor(1, 1, 1, enabled and T.A_TEXT or T.A_FAINT)
            if isDefault or locked then row.revert:Hide()
            else row.revert:Show() end
        end
    end

    -- The position rows and the folds, which hold no setting of their own.
    for _, page in ipairs(self.pages) do
        for _, pr in ipairs(page.posRows or {}) do
            pr:fill(enabled and (needsMet(a, pr.needs)))
        end
        for _, fold in ipairs(page.folds or {}) do
            fold.changed = false
            for _, row in ipairs(page.rows) do
                if self.marks and row.fold == fold and row.optKey and shown(row.optKey)
                   and not a.isDefault(row.optKey) then
                    fold.changed = true
                end
            end
            fold:paint(false)
        end
    end

    -- A tab with something changed on it is marked, rows an extra page drew
    -- itself included, so a change is findable without opening every tab.
    for _, page in ipairs(self.pages) do
        local touched = false
        if page.subTouched then page.subTouched = {} end
        for _, row in ipairs(page.rows) do
            if row.optKey and shown(row.optKey)
               and not a.isDefault(row.optKey) then
                touched = true
                if row.sub and page.subTouched then page.subTouched[row.sub] = true end
            end
        end
        for _, row in ipairs(page.owned or {}) do
            if shown(row.optKey) and not a.isDefault(row.optKey) then
                touched = true
            end
        end
        -- An extra page's own changes, like the supplies on Supplies' list.
        if page.edits then
            local ok, more = pcall(page.edits)
            if ok and more then touched = true end
        end
        page.tab.mark:SetShown(touched and self.marks)
    end

    -- Said in words as well as greyed out, because a page of grey controls
    -- with no sentence looks broken.
    if locked then
        self.warning:SetText(why or "")
        self.warning:Show()
    else
        self.warning:Hide()
    end

    for _, page in ipairs(self.pages) do
        if page.refresh then page.refresh(self, enabled) end
    end
    self:layout()
    if self.onRefresh then self.onRefresh(self) end
end

function mt:commit(key, text)
    self.lastKey = key
    local ok, why = self.adapter.commit(key, text)
    if not ok and why and self.out then self.out("%s", why) end
    -- Every time. A refused write must put the control back, and an accepted
    -- one may have been stored as an absence.
    self:refresh()
end

function mt:reset(key)
    self.lastKey = key
    local ok, why = self.adapter.reset(key)
    if not ok and why and self.out then self.out("%s", why) end
    self:refresh()
end

-- Shows the row for a setting: its tab and sub, scrolled to it, and a flash.
-- A row an extra page drew itself is found as well. Answers the row, or nil
-- when the page has none for `key`.
function mt:jump(key)
    for _, page in ipairs(self.pages) do
        local found
        for _, row in ipairs(page.rows) do
            if row.optKey == key and not row.isHead then found = row end
        end
        for _, row in ipairs(page.owned or {}) do
            if row.optKey == key then found = row end
        end
        -- An X or Y shows its position row rather than the number under
        -- Advanced.
        if page.posOf and page.posOf[key] then found = page.posOf[key] end
        if found then
            if found.sub then self:setSub(page, found.sub) end
            if found.adv then
                page.foldOpen = page.foldOpen or {}
                page.foldOpen[found.sub or "_"] = true
            end
            self:select(page.name)
            local top, rowTop = self.content:GetTop(), found:GetTop()
            if top and rowTop and self.scroll.setScroll then
                self.scroll:setScroll(max(0, top - rowTop - 20))
            end
            T.flash(found)
            return found
        end
    end
end

-- A section's note, a dim line or two under its heading. `place(w)` sets
-- its width and answers how tall it came out.
local function newNote(parent, text)
    local n = CreateFrame("Frame", nil, parent)
    n.isNote = true
    n.text = T.text(n, T.SIZE.body, false, T.A_DIM)
    n.text:SetPoint("TOPLEFT", n, "TOPLEFT", 0, 0)
    n.text:SetJustifyH("LEFT")
    if n.text.SetWordWrap then n.text:SetWordWrap(true) end
    n.text:SetText(text)
    function n:place(w)
        self:SetWidth(w)
        self.text:SetWidth(w)
        local h = max(13, floor((self.text:GetStringHeight() or 13) + 0.5))
        self:SetHeight(h)
        return h
    end
    return n
end

-- Builds the page for `adapter` into `parent` (the header says what `opts`
-- holds).
function SP.new(parent, adapter, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", opts.name, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    frame:Hide()

    local self = setmetatable({
        adapter = adapter,
        frame = frame,
        featId = opts.featId,
        rows = {},
        pages = {},
        titles = adapter.groupTitles or {},
        cmd = opts.cmd,
        out = opts.out,
        moveAll = opts.moveAll,
        onSub = opts.onSub,
        -- The gold mark on a changed setting, and on its tab and sub. A page
        -- for players we ship to can leave it off (`marks = false`).
        marks = opts.marks ~= false,
        tabs = {},
        heads = {},
    }, mt)
    local only = opts.only
    local defaultGroup = opts.defaultGroup or "other"
    local function groupOf(decl) return decl.group or defaultGroup end
    local function wanted(group) return not only or only[group] end

    self.strip = CreateFrame("Frame", nil, frame)
    self.strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    self.strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    self.strip:SetHeight(Z.TAB)
    local rule = T.fill(frame, WHITE, 0.07, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", self.strip, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("TOPRIGHT", self.strip, "BOTTOMRIGHT", 0, 0)

    -- The combat line, at the right end of the first line of tabs.
    self.warning = T.text(frame, Z.WARN_FONT, true, 1)
    self.warning:SetPoint("RIGHT", self.strip, "TOPRIGHT", 0, -Z.TAB / 2)
    self.warning:SetTextColor(T.WARN[1], T.WARN[2], T.WARN[3], 1)
    self.warning:Hide()

    local scroll = T.scroll(frame)
    T.scrollShadow(scroll)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(Z.TAB + 12))
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    self.scroll = scroll
    self.content = scroll.child
    -- The rows follow the window's width as it is resized.
    --
    -- Only a new width lays them out again. The height changes too, on every
    -- change of tab whose preview is taller or shorter, and when the window is
    -- made taller. Nothing in a layout reads the height, and the scroll frame
    -- fits itself to it. On 2026-11-12 this fired 135 times in one session,
    -- and each layout of Upgrades cost up to 6 ms and 160 KB.
    frame:SetScript("OnSizeChanged", function()
        if frame:IsShown() and frame:GetWidth() ~= self.laidW then self:layout() end
    end)

    -- ------------------------------------------------------------------
    -- The tabs, in the console's order: the module's group list, then any
    -- group it didn't list. Keys inside a group go in their `order`, then
    -- alphabetical, the order `/bayov <mod> list` prints.
    -- ------------------------------------------------------------------
    -- Claimed keys first, so a claimed key gets no row here and a group with
    -- nothing left gets no tab.
    local seen = {}
    for key, decl in pairs(adapter.decls) do
        if decl.page or not wanted(groupOf(decl)) then seen[key] = true end
    end

    local function shown(key)
        return not adapter.visible or adapter.visible(key)
    end

    -- An extra page goes where `groups` names it, among the generated ones,
    -- so a module's own page can come first. One that `groups` doesn't name
    -- comes after them all. An extra with `under = <group>` gets no tab of
    -- its own: it draws under that group's rows, like a Reset button after
    -- a position.
    local extras, under, over = {}, {}, {}
    for _, ex in ipairs(adapter.extras or {}) do
        if ex.under then under[ex.under] = ex
        elseif ex.over then over[ex.over] = ex
        else extras[ex.name] = ex end
    end

    local function addExtra(ex)
        if ex.added then return end
        ex.added = true
        local pageFrame = CreateFrame("Frame", nil, self.content)
        pageFrame:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)
        pageFrame:Hide()
        local page = { name = ex.name, frame = pageFrame, rows = {},
                       layout = ex.layout, refresh = ex.refresh, edits = ex.edits }
        self.pages[#self.pages + 1] = page
        page.tab = newTab(self, page.name, ex.title or self.titles[page.name])
        if ex.build then ex.build(self, pageFrame, page) end
    end

    local function addPage(group)
        local keys = {}
        for key, decl in pairs(adapter.decls) do
            if groupOf(decl) == group and not seen[key] and shown(key) then
                keys[#keys + 1] = key
            end
        end
        sortKeys(keys, adapter.decls)
        if #keys == 0 then
            -- Nothing generated to draw under: what was to go under it is
            -- a page of its own.
            local ex = under[group] or over[group]
            if ex then
                ex.name = ex.name or group
                addExtra(ex)
            end
            return
        end

        local pageFrame = CreateFrame("Frame", nil, self.content)
        pageFrame:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)
        pageFrame:Hide()

        local page = { name = group, frame = pageFrame, rows = {}, posOf = {} }
        self.pages[#self.pages + 1] = page
        page.tab = newTab(self, group, self.titles[group])

        -- The Y half of a position, which the X half's row draws.
        local posY = {}
        for _, key in ipairs(keys) do
            local d = adapter.decls[key]
            if d.pos and adapter.decls[d.pos] then posY[d.pos] = key end
        end

        -- The master switch of each section, by its section and sub, and of
        -- the whole page (or sub) for one with `master = "page"`.
        local masters, pageMasters = {}, {}
        for _, key in ipairs(keys) do
            local d = adapter.decls[key]
            if d.master == "page" then
                pageMasters[d.sub or ""] = key
            elseif d.master then
                masters[(d.section or "") .. "\1" .. (d.sub or "")] = key
            end
        end

        local relayout = function() self:layout() end
        local adv, advSubs = {}, {}
        local function addRow(key, decl, row)
            row = row or newRow(pageFrame, self, key, decl)
            row.sub = decl.sub
            row.needs = decl.needs
            if row.needs == nil and not decl.master then
                local m = masters[(decl.section or "") .. "\1" .. (decl.sub or "")]
                if m and m ~= key then row.needs = m end
            end
            -- A page's master holds over every row of the page, a section's
            -- master included.
            local pm = pageMasters[decl.sub or ""]
            if pm and pm ~= key then
                if row.needs == nil then
                    row.needs = pm
                elseif type(row.needs) == "string" and row.needs ~= pm then
                    row.needs = { [row.needs] = true, [pm] = true }
                elseif type(row.needs) == "table" and row.needs[pm] == nil then
                    local t = { [pm] = true }
                    for k, v in pairs(row.needs) do t[k] = v end
                    row.needs = t
                end
            end
            if not row.isPos then self.rows[#self.rows + 1] = row end
            return row
        end

        local section, sub
        for _, key in ipairs(keys) do
            seen[key] = true
            local decl = adapter.decls[key]
            if decl.sub then
                page.subs = page.subs or {}
                page.subOf = page.subOf or {}
                if not page.subOf[decl.sub] then
                    page.subOf[decl.sub] = true
                    page.subs[#page.subs + 1] = decl.sub
                end
            end
            if posY[key] then
                -- A Y, which its X's position row draws.
            elseif decl.advanced then
                -- Folded away at the end of the page (or its sub), in order.
                local k = decl.sub or "_"
                if not adv[k] then adv[k] = {} advSubs[#advSubs + 1] = decl.sub or false end
                adv[k][#adv[k] + 1] = key
            end
            if not decl.advanced and not posY[key] then
                -- Each sub starts its sections again.
                if decl.sub ~= sub then section = nil end
                -- A heading above the first row of each section. It goes into
                -- `page.rows` so the layout places it, but not into
                -- `self.rows`, because it has no option to fill or mark.
                local name = decl.section
                if name and name ~= section then
                    local titles = adapter.sectionTitles or {}
                    local h = T.heading(pageFrame, titles[name] or name)
                    h.isHead = true
                    h.sub = decl.sub
                    page.rows[#page.rows + 1] = h
                    -- And the section's note under it, when it has one.
                    local text = (adapter.sectionNotes or {})[name]
                    if text then
                        local n = newNote(pageFrame, text)
                        n.sub = decl.sub
                        page.rows[#page.rows + 1] = n
                    end
                end
                section, sub = name, decl.sub
                if decl.pos and adapter.decls[decl.pos] then
                    -- An X with its Y: one position row with both numbers.
                    local pr = addRow(key, decl, newPosRow(pageFrame, self, key, decl.pos, decl))
                    page.rows[#page.rows + 1] = pr
                    page.posOf[key], page.posOf[decl.pos] = pr, pr
                    page.posRows = page.posRows or {}
                    page.posRows[#page.posRows + 1] = pr
                    seen[decl.pos] = true
                else
                    page.rows[#page.rows + 1] = addRow(key, decl)
                end
            end
        end

        -- The folds, one per sub that has rows to fold, then their rows.
        for _, sb in ipairs(advSubs) do
            local list, done = adv[sb or "_"], {}
            local fold = newFold(pageFrame, page, sb or nil, relayout)
            page.rows[#page.rows + 1] = fold
            page.folds = page.folds or {}
            page.folds[#page.folds + 1] = fold
            for _, key in ipairs(list) do
                if not done[key] then
                    done[key] = true
                    seen[key] = true
                    local row = addRow(key, adapter.decls[key])
                    row.adv, row.fold = true, fold
                    row.sub = sb or nil
                    page.rows[#page.rows + 1] = row
                    fold.count = fold.count + 1
                end
            end
        end

        -- The sub-tab selector, a button per sub in the order they come. With
        -- `subTabs` they're tabs in the strip instead, and the page's own
        -- tab makes way for them.
        if page.subs then
            page.sub = (opts.sub and page.subOf[opts.sub]) and opts.sub or page.subs[1]
            page.subTouched = {}
        end
        if page.subs and opts.subTabs then
            page.subTabs = {}
            page.tab:Hide()
            for _, sb in ipairs(page.subs) do
                local b = newTab(self, group, (adapter.subTitles or {})[sb] or sb)
                b.sub, b.subTab = sb, sb
                b:SetScript("OnClick", function() self:selectSub(sb, group) end)
                page.subTabs[#page.subTabs + 1] = b
            end
        elseif page.subs then
            local bar = CreateFrame("Frame", nil, pageFrame)
            bar.buttons = {}
            page.subBar = bar
            for _, sb in ipairs(page.subs) do
                local title = (adapter.subTitles or {})[sb] or sb
                local b = T.segment(bar, title, Z.SEG, Z.SUB)
                -- Room for the mark a sub with changes gets.
                b:SetWidth(max(Z.SEG, floor((b.label:GetStringWidth() or 0) + 40 + 0.5)))
                b.title, b.sub = title, sb
                b:SetScript("OnClick", function() self:selectSub(sb, group) end)
                bar.buttons[#bar.buttons + 1] = b
            end
        end

        -- What the module draws under the rows, and above them.
        local ex = under[group]
        if ex then
            page.layout, page.refresh, page.edits = ex.layout, ex.refresh, ex.edits
            if ex.build then ex.build(self, pageFrame, page) end
        end
        local top = over[group]
        if top then
            page.layoutTop = top.layout
            local r, e = page.refresh, page.edits
            page.refresh = (r and top.refresh) and function(...) r(...) top.refresh(...) end
                           or r or top.refresh
            page.edits = (e and top.edits) and function() return e() or top.edits() end
                         or e or top.edits
            if top.build then top.build(self, pageFrame, page) end
        end
    end

    for _, group in ipairs(adapter.groups or {}) do
        if not wanted(group) then
            -- Another page draws it.
        elseif extras[group] then addExtra(extras[group]) else addPage(group) end
    end
    -- A group missing from the ordered list still gets a tab. A new group
    -- name is a typo away from a setting that is everywhere except here.
    local rest = {}
    for key, decl in pairs(adapter.decls) do
        if not seen[key] then rest[groupOf(decl)] = true end
    end
    local restNames = {}
    for g in pairs(rest) do restNames[#restNames + 1] = g end
    table.sort(restNames)
    for _, g in ipairs(restNames) do addPage(g) end

    -- The module's own pages that `groups` didn't place, after the generated
    -- ones. `build` makes the frames once, `refresh` fills them after every
    -- write, and `layout` places them whenever the width changes.
    for _, ex in ipairs(adapter.extras or {}) do
        if not (ex.under or ex.over) and wanted(ex.name) then addExtra(ex) end
    end
    for _, ex in ipairs(adapter.extras or {}) do ex.added = nil end
    return self
end
