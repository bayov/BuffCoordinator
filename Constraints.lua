-- The review panel: a suggestion (Suggest.lua), change by change, with a
-- tick on each. A change the leader made something else of since the
-- suggestion was made is marked, since applying it would undo theirs. "Open
-- as draft" puts the suggestion on the page as a draft instead, to change it
-- before applying it. Once the suggestion is applied, turned down or taken
-- back, the panel closes.
--
-- The overrides themselves are in the Assignments page's Overrides
-- (Overrides.lua).
--
-- It sits beside whatever opened it, in that frame's scale, above the
-- window, and closes with the window.

local _, NS = ...
local T = NS.Theme

local format = string.format
local max = math.max

local Co = {}
NS.Constraints = Co

local WIDTH, ROW, PAD = 300, 20, 10
local HEAD_H, FOOT_H = 30, 32
local MAX_H = 460

local panel
-- Whose suggestion the panel reviews.
local reviewing
-- The changes ticked in a review, by key.
local checked = {}

-- =============================================================
-- Sending
-- =============================================================
-- Sends our draft as a suggestion, after asking for a line for the leader
-- and assistants, which may stay empty.
function Co.send()
    T.ask("Send to the leader and assistants. Add a note if you like:",
          NS.draft and NS.draft.note or "", NS.Suggest.submit, { empty = true, accept = "Send" })
end

-- =============================================================
-- Rows
-- =============================================================
local function newRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW)
    r.hl = T.fill(r, { 1, 1, 1 }, 0.05)
    r.hl:SetAllPoints(r)
    r.hl:Hide()
    -- The tick box: a square with a 1 pixel edge, filled in the
    -- accent when ticked, like the menus' own.
    r.box = CreateFrame("Button", nil, r)
    r.box:SetSize(12, 12)
    r.box:SetPoint("LEFT", r, "LEFT", 3, 0)
    r.box.bg = T.fill(r.box, { 0, 0, 0 }, 0.45)
    r.box.bg:SetAllPoints(r.box)
    T.border(r.box, { 1, 1, 1 }, 0.35)
    r.box.on = T.fill(r.box, T.ACCENT, 1, "ARTWORK")
    r.box.on:SetPoint("TOPLEFT", r.box, "TOPLEFT", 3, -3)
    r.box.on:SetPoint("BOTTOMRIGHT", r.box, "BOTTOMRIGHT", -3, 3)
    r.label = T.text(r, T.SIZE.body, false, T.A_TEXT)
    r.label:SetPoint("LEFT", r, "LEFT", 20, 0)
    r.label:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.label:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        if self.tip then self.tip(self) end
    end)
    r:SetScript("OnLeave", function(self)
        self.hl:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return r
end

-- The panel's rows, made as they're needed and kept.
local function row(i)
    local r = panel.rows[i]
    if not r then
        r = newRow(panel.body)
        panel.rows[i] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -(i - 1) * ROW)
    r:SetPoint("RIGHT", panel.body, "RIGHT", -6, 0)
    r.tip = nil
    r:SetScript("OnClick", nil)
    r.box:SetScript("OnClick", nil)
    r:Show()
    return r
end

local function plain(r, text, alpha)
    r.box:Hide()
    r.label:SetText(text)
    r.label:SetTextColor(1, 1, 1, alpha or T.A_DIM)
end

-- =============================================================
-- Drawing
-- =============================================================
local function drawReview()
    local Su = NS.Suggest
    local p
    for _, x in ipairs(Su.pending()) do
        if x.from == reviewing then p = x end
    end
    if not p then
        -- Applied, turned down or taken back.
        reviewing = nil
        panel:Hide()
        return 0
    end
    panel.title:SetText(format("%s's suggestion", NS.classColored(p.from, p.class)))
    local i = 0
    local note = Su.note(p.from)
    if note then
        i = i + 1
        plain(row(i), format("\"%s\"", note), T.A_TEXT)
    end
    for _, l in ipairs(Su.lines(p.from)) do
        i = i + 1
        local r = row(i)
        r.box:Show()
        if checked[l.key] == nil then checked[l.key] = true end
        r.box.on:SetShown(checked[l.key])
        local function flip()
            checked[l.key] = not checked[l.key]
            r.box.on:SetShown(checked[l.key])
        end
        r.box:SetScript("OnClick", flip)
        r:SetScript("OnClick", flip)
        local text = NS.upperFirst(l.text)
        if l.since then text = text .. "  " .. T.hex("bad") .. "changed since|r" end
        r.label:SetText(text)
        r.label:SetTextColor(1, 1, 1, T.A_TEXT)
        r.tip = function(self)
            local lines = {}
            if l.since then
                local red = T.COLOR.bad
                lines[1] = { "You changed this since they suggested it. Applying undoes your change.",
                             red[1], red[2], red[3] }
            end
            T.tip(self, text, lines, { { "Click", "tick or untick it" } })
        end
    end
    local b1, b2, b3 = panel.buttons[1], panel.buttons[2], panel.buttons[3]
    b1:SetText("Turn down")
    b1:setAccent(false)
    b1:Show()
    b1:Enable()
    b1:SetScript("OnClick", function() Su.decline(p.from) end)
    b1.tip = nil
    -- The whole suggestion on the page as a draft, where we can change it
    -- before we apply it. The page has its own Apply then.
    b3:SetText("Open as draft")
    b3:setAccent(false)
    b3:Show()
    b3:Enable()
    b3:SetScript("OnClick", function()
        Su.review(p.from)
        panel:Hide()
    end)
    b3.tip = function(self)
        T.tip(self, "Open as draft", { "Open it as a draft to edit before applying." })
    end
    b2:SetText("Apply checked")
    b2:setAccent(true)
    b2:Show()
    b2:Enable()
    b2:SetScript("OnClick", function()
        local keep = {}
        for k, v in pairs(checked) do
            if v then keep[k] = true end
        end
        Su.applyChecked(p.from, keep)
    end)
    b2.tip = nil
    return i
end

local function draw()
    if not panel or not panel:IsShown() then return end
    local n = drawReview()
    for j = n + 1, #panel.rows do panel.rows[j]:Hide() end
    panel.body:SetHeight(max(ROW, n * ROW))
    panel:SetHeight(math.min(MAX_H, HEAD_H + n * ROW + FOOT_H + PAD * 2))
    panel.body:SetWidth(WIDTH - PAD * 2)
    panel.scroll:update()
    -- The buttons, right to left: the main one, then the others.
    local prev
    for _, j in ipairs({ 2, 3, 1 }) do
        local b = panel.buttons[j]
        b:ClearAllPoints()
        if prev then
            b:SetPoint("RIGHT", prev, "LEFT", -6, 0)
        else
            b:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD)
        end
        if b:IsShown() then prev = b end
    end
end

local function build()
    panel = CreateFrame("Frame", "BuffCoordinatorConstraints", UIParent)
    panel:SetSize(WIDTH, 200)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    T.popup(panel)
    table.insert(_G.UISpecialFrames, "BuffCoordinatorConstraints")
    panel.title = T.text(panel, T.SIZE.label, true, 1)
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -10)
    local close = T.close(panel, function() panel:Hide() end)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    local line = T.fill(panel, { 1, 1, 1 }, 0.07, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -HEAD_H + 2)
    line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -HEAD_H + 2)
    panel.scroll = T.scroll(panel)
    panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -HEAD_H - 4)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, FOOT_H + PAD)
    panel.body = panel.scroll.child
    T.scrollShadow(panel.scroll)
    panel.rows = {}
    panel.buttons = { T.button(panel, "", nil, 20), T.button(panel, "", nil, 20), T.button(panel, "", nil, 20) }
    panel:SetScript("OnShow", draw)
    T.windowSounds(panel, true)
end

local function place(anchor)
    panel:ClearAllPoints()
    if anchor and anchor.GetEffectiveScale then
        local s, u = anchor:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if s and u and u > 0 then panel:SetScale(s / u) end
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- Opens the panel on `name`'s suggestion, every change ticked, beside
-- `anchor` when given.
function Co.review(name, anchor)
    if not panel then build() end
    reviewing = name
    for k in pairs(checked) do checked[k] = nil end
    if anchor or not panel:IsShown() then place(anchor) end
    if panel:IsShown() then draw() else panel:Show() end
end

-- Closes the panel, as the window does when it closes.
function Co.hide()
    if panel then panel:Hide() end
end

-- Whether the panel is open, and the suggestion it reviews.
function Co.shown()
    if not panel or not panel:IsShown() then return false end
    return true, reviewing
end

local function redraw() NS.soon("constraintsDraw", 0.1, draw) end
NS.listen("board", redraw)
NS.listen("draft", redraw)
NS.listen("roster", redraw)
