-- The Settings and HUD pages of the assignments window.
--
-- Both are drawn by the settings page BayovCore's config window uses
-- (Shared/SettingsPage.lua), from our settings in Options.lua: a row per
-- setting under its section's heading and the section's note, in one column
-- or two, whichever fits. A row's tooltip says its range or choices and its
-- default. A number is a box to type in, with a slider beside it for the
-- HUD's sizes and opacity. A choice is a row of segments, with a swatch for
-- a colour, or a dropdown when it has many values. A setting that isn't its
-- default has a gold dot after its name and a button to put it back.
--
-- The icons' sizes and opacity are on All three, and each of the three has
-- its own row for them too, like BayovCore's Raid Buffs. That row has an
-- "All" or "Own" chip where the button to put it back goes. "All" while it
-- goes by All three's (its value dimmed), "Own" while it has a value of its
-- own. A click on the chip switches, and so does typing a value.
--
-- The HUD page has a tab for each of the three (Yours for your assignments,
-- Group for Group buffs, Debuffs for Target debuffs) and one for the settings
-- they share (All three). Under the tabs is a preview band, BayovCore's
-- (Shared/PreviewBand.lua), that draws the tab's one (or all three) with
-- made-up buffs over a darkened picture of Darkshire. A click on a part of
-- the example goes to its setting, and the mouse over a row lights the parts
-- it changes.
--
-- The buttons sit at the right of the window's tab strip: "Reset all" on
-- Settings, and on HUD Preview in game, which puts made-up buffs on the
-- screen so each change shows there as it's made (HUD.lua's preview), Move,
-- which puts a box around each of the three (HUD.lua's move mode), and its
-- own Reset all. Reset all asks first.

local _, NS = ...
local O, T, C = NS.Options, NS.Theme, NS.Config
local SP, PB = NS.SettingsPage, NS.PreviewBand

local max, floor = math.max, math.floor

local S = {}
NS.Settings = S

-- Our window is smaller than BayovCore's and holds more, so its rows and
-- controls are too.
do
    local z = SP.SIZE
    z.ROW, z.TAB, z.SUB, z.CTRL = 26, 24, 20, 20
    z.EDIT, z.REVERT, z.OWN, z.SLIDE = 52, 16, 40, 84
    z.FOLD, z.SEG, z.DROP_MIN, z.DROP_MAX = 22, 40, 110, 180
    z.ENUM_MAX, z.BUTTON, z.POS_EDIT = 300, 56, 50
    z.GUTTER, z.INSET, z.MIN_LABEL = 16, 8, 104
    z.FOLD_FONT, z.MARK_FONT, z.WARN_FONT = 10, 13, 11
    local b = PB.SIZE
    b.PAD, b.BAR, b.BAR_LINE2, b.CTRL, b.FOLD_FONT = 12, 26, 22, 20, 10
end

-- The picture behind the example, BayovCore's: a 16:9 screenshot of
-- Darkshire in Duskwood, under a veil this dark so the icons stand out.
local ART = { file = [[Interface\AddOns\BuffCoordinator\Media\Darkshire.png]], aspect = 16 / 9 }
local ART_DIM = 0.6
-- How much room the band leaves for the settings under it.
local SETTINGS_ROOM = 110
-- The least the example is tall, so a short one still sits in the middle of
-- some picture.
local STAGE_MIN = 60

-- The sections by tab ("settings" or "hud"), the page each is on, and the
-- HUD page's band.
local sections, pages = {}, {}
local band

-- =============================================================
-- The examples
-- =============================================================
-- The space between the three in the All three example.
local ALL_GAP = 14

-- An example of all three at once, one under the other in the middle, for
-- the All three tab. Each is its own copy of the stage its tab shows.
-- `update()` answers the width and height of the whole stack, like theirs.
local function allStage(parent)
    local frame = CreateFrame("Frame", nil, parent)
    local parts = {
        NS.HUD.stage(frame),
        NS.GroupBuffs.stage(frame),
        NS.TargetDebuffs.stage(frame),
    }
    local st = { frame = frame, parts = parts }
    function st.targets()
        local t = {}
        for _, part in ipairs(parts) do
            for _, one in ipairs(part.targets()) do t[#t + 1] = one end
        end
        return t
    end
    function st.update()
        local sizes, width, height = {}, 0, 0
        for i, part in ipairs(parts) do
            part.frame:SetScale(1)
            local w, h = part.update()
            sizes[i] = { w, h }
            width = max(width, w)
            height = height + h + (i > 1 and ALL_GAP or 0)
        end
        local y = 0
        for i, part in ipairs(parts) do
            local w, h = sizes[i][1], sizes[i][2]
            part.frame:ClearAllPoints()
            part.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", (width - w) / 2 + (part.ox or 0),
                                -(y + (part.oy or part.lift or 0)))
            part.frame:Show()
            y = y + h + ALL_GAP
        end
        frame:SetSize(max(1, width), max(1, height))
        return width, height
    end
    return st
end

-- The example each tab of the HUD page shows.
local STAGES = {
    hud = function(parent) return NS.HUD.stage(parent) end,
    group = function(parent) return NS.GroupBuffs.stage(parent) end,
    debuff = function(parent) return NS.TargetDebuffs.stage(parent) end,
    all = allStage,
}

-- The tab on show on the HUD page.
local function currentSub()
    local sec = sections.hud
    return sec and sec:currentSub() or NS.db.window.hudPane or "hud"
end

-- Whether `region` shows inside stage frame `top`: it and every frame up to
-- it are shown. A countdown on a hidden icon is still shown itself.
local function shownIn(region, top)
    while region and region ~= top do
        if not region:IsShown() then return false end
        region = region:GetParent()
    end
    return true
end

-- The tooltip of a part of the example: its own, when it has one, with a
-- line under it that says where a click goes, or else the setting's.
local function hitTip(b, region, key, d, label)
    local hint = { { "Click", "go to " .. (d and d.name or tostring(key)) } }
    local enter = region:IsObjectType("Frame") and region:GetScript("OnEnter")
    if enter then enter(region) end
    local tip = _G.GameTooltip
    if enter and tip and tip:IsShown() then
        tip:AddLine(" ")
        T.tipHints(tip, hint)
        T.tipDone(tip)
    else
        T.tip(b, label or (d and d.name) or tostring(key), { d and d.desc }, hint)
    end
end

local function hitLeave(_, region)
    local leave = region:IsObjectType("Frame") and region:GetScript("OnLeave")
    if leave then leave(region) end
end

-- The HUD page's example: the stage of the tab on show, in the middle of the
-- band. Each stage names its parts with `st.targets()`, a list of { region,
-- key, label }, where `key` is the setting a click goes to and `label` the
-- tooltip's title for a part with no tooltip of its own. On All three, a
-- part that goes by All three's setting goes to that one.
local stages = {}
local function preview(stage, ctx)
    local pv = {}
    -- The click targets by stage, so a stage's go when another shows.
    local hitsOf = {}

    local function aim(key, st)
        if not st.targets then return end
        local list = hitsOf[key] or {}
        hitsOf[key] = list
        for _, t in ipairs(st.targets()) do
            local region = t[1]
            if region then
                local b = region.bbcHit
                if not b then
                    local entry = {}
                    b = ctx.hit(region, function() return entry.key end, function() return entry.title end)
                    b.entry = entry
                    region.bbcHit = b
                    list[#list + 1] = b
                end
                local k = t[2]
                if key == "all" and O.shared(k) then k = O.DECLS[k].inherit end
                b.entry.key, b.entry.title = k, t[3]
                b.key, b.title = k, t[3]
                local text = not region:IsObjectType("Frame") and region.GetText and (region:GetText() or "")
                b:SetShown(shownIn(region, st.frame) and text ~= "")
            end
        end
    end

    function pv:update(width)
        local key = currentSub()
        for k, st in pairs(stages) do
            st.frame:SetShown(k == key)
            if k ~= key then
                for _, b in ipairs(hitsOf[k] or {}) do b:Hide() end
            end
        end
        local st = stages[key]
        if not st then
            st = (STAGES[key] or STAGES.hud)(stage)
            stages[key] = st
        end
        st.frame:Show()
        st.frame:SetScale(1)
        local w, h = st.update()
        local ox, oy = st.ox or 0, st.oy or st.lift or 0
        local tall = max(STAGE_MIN, h + oy)
        st.frame:ClearAllPoints()
        st.frame:SetPoint("TOPLEFT", stage, "TOPLEFT", max(0, (width - w) / 2) + ox,
                          -((tall - h - oy) / 2 + oy))
        aim(key, st)
        return tall, max(width, w)
    end
    return pv
end

-- The HUD page's examples, by tab, for the tests.
function S.stages() return stages end
-- A tab's settings section, for the tests.
function S.section(tab) return sections[tab] end

-- =============================================================
-- Going to a setting
-- =============================================================
-- Opens the tab with setting `key`, scrolls to its row and flashes it.
function S.goTo(key)
    local tab = O.tabOf(key) or "settings"
    if not C.shown() or C.current() ~= tab then C.open(tab) end
    local sec = sections[tab]
    if sec and sec:jump(key) and pages[tab] then
        pages[tab].flashKey = key
    end
end

-- =============================================================
-- The pages
-- =============================================================
local function declCount()
    local n = 0
    for _ in pairs(O.DECLS) do n = n + 1 end
    return n
end

-- The band over the HUD page's settings, made with its page.
local function makeBand(sec)
    local b = PB.new(sec.frame, preview, {
        decls = O.DECLS,
        jump = S.goTo,
        tab = currentSub,
        onHeight = function(h) sec:setTop(h + 10) end,
        room = function()
            local h = sec.frame:GetHeight() or 0
            if h <= 0 then return nil end
            return h - sec:tabsH() - 12 - SETTINGS_ROOM
        end,
        folded = function() return NS.db.window.previewFolded == true end,
        setFolded = function(on) NS.db.window.previewFolded = on or nil end,
        art = function() return ART, ART_DIM end,
        hitTip = hitTip,
        hitLeave = hitLeave,
    })
    if not b then return nil end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", sec.frame, "TOPLEFT", 0, -(sec:tabsH() + 12))
    b:SetPoint("TOPRIGHT", sec.frame, "TOPRIGHT", -8, -(sec:tabsH() + 12))
    sec.band = function() return b end
    sec.onSelect = function() if b:IsVisible() then b.update() end end
    sec.onRefresh = function(self)
        if b:IsVisible() then
            b.update()
            if self.lastKey then b.pulse(self.lastKey) end
        end
        self.lastKey = nil
    end
    return b
end

-- Builds the page for tab `tab` into `page`, where the window's scroll was.
local function build(page, tab)
    local old = sections[tab]
    if old then old.frame:Hide() end
    if tab == "hud" then
        if band then band:Hide() end
        stages = {}
    end
    page.scroll:Hide()
    local host = page.host
    if not host then
        host = CreateFrame("Frame", nil, page.frame)
        host:SetPoint("TOPLEFT", page.scroll, "TOPLEFT", 0, 0)
        host:SetPoint("BOTTOMRIGHT", page.scroll, "BOTTOMRIGHT", 0, 0)
        page.host = host
    end
    local sec = SP.new(host, O.adapter, {
        only = { [tab] = true },
        defaultGroup = "settings",
        subTabs = true,
        sub = tab == "hud" and NS.db.window.hudPane or nil,
        onSub = function(sub) if tab == "hud" then NS.db.window.hudPane = sub end end,
        out = NS.print,
        -- The gold marks on changed settings are for BayovCore. Players we
        -- ship to don't need them.
        marks = false,
    })
    sec.decls = declCount()
    sections[tab] = sec
    local first = sec.pages[1]
    if tab ~= "hud" then
        -- One tab is no choice to make, so the strip says who the settings
        -- are for instead.
        if first then first.tab:Hide() end
        local note = T.text(sec.strip, T.SIZE.body, false, T.A_DIM)
        note:SetPoint("LEFT", sec.strip, "LEFT", 0, 0)
        note:SetText("These only affect you, except the ones under When you're Assignments Leader.")
    else
        band = makeBand(sec)
    end
    sec.frame:Show()
    if first then sec:select(first.name) end
    return sec
end

-- Preview in game and Move, at the right of the HUD page's own strip of
-- tabs, since they're about the HUD alone. Made once, and their words
-- follow what's on each time the page is drawn.
local function hudButtons(sec)
    if not sec then return end
    local HUD = NS.HUD
    local on, moving = HUD.previewing(), HUD.moving()
    local b = sec.hudButtons
    if not b then
        local preview = T.button(sec.strip, "", nil, T.CONTROL.button.h)
        preview:SetScript("OnClick", function() HUD.preview(not HUD.previewing()) end)
        preview.tip = function(self)
            local now = HUD.previewing()
            T.tip(self, now and "Stop Preview" or "Preview in game",
                  { now and "Back to your real buffs." or "Made-up buffs on your screen, on all three." })
        end
        local move = T.button(sec.strip, "", nil, T.CONTROL.button.h)
        move:SetScript("OnClick", function()
            if HUD.moving() then HUD.stopMoving() else HUD.startMoving() end
        end)
        move.tip = function(self)
            local now = HUD.moving()
            T.tip(self, now and "Stop Move" or "Move",
                  { now and "Stop moving them." or "Move all three. Drag a box, or use the arrow keys." },
                  { { NS.SLASH .. " move", "turns it on or off" } })
        end
        move:SetPoint("RIGHT", sec.strip, "RIGHT", 0, 0)
        preview:SetPoint("RIGHT", move, "LEFT", -6, 0)
        b = { preview = preview, move = move }
        sec.hudButtons = b
    end
    b.preview:SetText(on and "Stop Preview" or "Preview in game")
    b.preview:setAccent(true)
    b.move:SetText(moving and "Stop Move" or "Move")
end

-- The buttons at the right of the window's tab strip.
local function buttons(page, tab)
    if tab ~= "hud" then
        C.headButtons(page, nil, { { "Reset all", function()
            T.confirm("Set every setting back to its default?", function() O.resetAll("settings") end)
        end, tip = function(self)
            T.tip(self, "Reset all", { "Set every setting on this tab back to its default." })
        end } })
        return
    end
    C.headButtons(page, nil, { { "Reset all", function()
        T.confirm("Set every HUD setting back to its default?", function() O.resetAll("hud") end)
    end, tip = function(self)
        T.tip(self, "Reset all", { "Set every HUD setting back to its default." })
    end } })
    hudButtons(sections.hud)
end

-- Draws the Settings page, or with `tab` "hud" the HUD page. The page is
-- built the first time, and again when a setting was added since (only a
-- test does that).
function S.draw(page, tab)
    tab = tab or "settings"
    pages[tab] = page
    local sec = sections[tab]
    if not sec or sec.decls ~= declCount() then sec = build(page, tab) end
    -- The tab the window was asked to show, when that changed elsewhere.
    local want = tab == "hud" and NS.db.window.hudPane
    if want and want ~= sec:currentSub() then sec:selectSub(want) end
    buttons(page, tab)
    sec:refresh()
end
