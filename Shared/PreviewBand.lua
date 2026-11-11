-- PreviewBand -- a live example of what a feature draws, in a band above
-- its settings, the way EUI's Nameplates and Unit Frames pages show one.
--
-- BayovCore's config window (Panel.lua) has one on each feature page that has
-- a `preview`, and Buff Coordinator's HUD tab has one for its icons. The band
-- shows a piece of the game world behind the example, darkened so the
-- example stands out. It doesn't scroll with the settings.
--
--   PB.new(parent, build, opts) -> band, or nil
--
-- `build(stage, ctx) -> pv` builds the example once into `stage`, which is at
-- the game's own pixel scale, so the example is the size it is on screen.
-- `pv:update(width)` draws it again from the current settings and answers
-- its height, and its width when that's more than it was given. Then the band
-- scrolls sideways. When the example is taller than the room it has, we draw
-- it smaller, so some settings still show under it. Then `width` is wider
-- than the band in the stage's own pixels, so an example that wraps to fit
-- can go side by side again.
--
-- `ctx.hit(region, key)` makes a part of the example clickable: a click goes
-- to that setting (`opts.jump`). `ctx.hit(region, key, label, text)` names it
-- on hover by `label` rather than the setting, with `text` under it, like
-- what state a made-up icon is in. Each of `key`, `label` and `text` may be a
-- function, asked on each hover or click, for a part that shows something
-- else after a change. A broken preview reports its error and stays empty,
-- and the page works without it. `ctx.tab()` is the tab on show
-- (`opts.tab`), for a preview that draws a different part on each tab.
--
-- A preview can offer scenes: states of the example to try that are hard to
-- reach in game, like a raid where everyone is missing a buff. They are chips
-- in the band's bar, from `pv.scenes` (a list, or a function that answers
-- one, asked again on every update):
--
--   { key = "group", label = "Group", tip = "...", default = "raid",
--     choices = { { "solo", "Solo" }, { "party", "Party" }, { "raid", "Raid" } } }
--   { key = "play", toggle = true, label = "Animate", default = true }
--   { key = "replay", action = true, label = "Replay" }
--
-- `ctx.scene(key)` reads one (a choice's value, or a toggle's true or false).
-- A change calls `pv:scene(key, value)` when the preview has it, then
-- `pv:update` again. An action only calls `pv:scene(key, true)`. A scene
-- lasts as long as the window does.
--
-- A preview can animate. Its frames are under `stage`, which hides while the
-- band is folded or its page isn't on show, so an OnUpdate on them stops
-- then too. `ctx.relayout()` runs `pv:update` again, for an animation that
-- changes the example's size.
--
-- Each part a `ctx.hit` made lights up while the mouse is over its setting's
-- row (`band.highlight`), and pulses once when that setting changes
-- (`band.pulse`), so the two point at each other.
--
-- The band's bar has a fold, the scene chips, and for a feature with a
-- `demo` (Movers.lua): Show in game, Show all HUD and Move. While the feature
-- is on the game screen or being moved, the band folds to its bar by itself,
-- so the settings get the room, and it opens again when that ends.
--
-- The opts:
--
--   decls          the settings' declarations, for the names on hover
--   jump(key)      shows the row for a setting
--   onHeight(h)    hears when the band's height changed
--   tab()          the tab on show, for ctx.tab
--   room()         the tallest the band may be, or nil for no limit
--   feat           the feature, for ctx.feat
--   featId         its id in Movers, for Move
--   demo           its demo function (Movers.demo), or nil
--   movable        whether Movers can move it alone
--   allDemos()     every feature's demo, for Show all HUD
--   moveAll        a line on how to move every widget at once, or nil
--   folded()       whether the player folded it by hand
--   setFolded(on)  keeps that
--   art()          the picture behind it and how dark the veil is: a
--                  { file, aspect, coords } and a number, or nil for none
--   hitTip(b, region, key, decl, label, text)
--                  draws the tooltip of a part, in place of the setting's
--                  name and "Click to edit it below."
--   hitLeave(b, region)
--                  hears when the mouse leaves a part
--   report(err)    hears an error, the game's error handler when not given
--
-- PB.SIZE holds the sizes, which an addon may change after this loads.
--
-- This file is in bayovui/shared, so BayovCore and Buff Coordinator each load
-- their own copy of it.

local _, NS = ...
local CreateFrame = NS.Profiler and NS.Profiler.scope("config") or CreateFrame

local PB = {}
NS.PreviewBand = PB

local max, floor = math.max, math.floor

local T = NS.Theme

PB.SIZE = {
    PAD = 14,
    -- The bar along the band's top. Scenes that don't fit beside the
    -- buttons get a second line of their own.
    BAR = 34,
    BAR_LINE2 = 28,
    CHIP_GAP = 4,
    CTRL = 22,
    FOLD_FONT = 12,
}
local Z = PB.SIZE
-- The smallest we draw an example to fit a short window. Smaller than this it
-- gets hard to read, so the band cuts off its bottom instead.
local MIN_FIT = 0.5
-- How long the band's size holds still before we draw the example for it.
local SETTLE = 0.1

local WHITE = { 1, 1, 1 }
local GREY = { 0.5, 0.5, 0.5 }
-- The band's own colour, under the picture.
local BG = { 0.04, 0.045, 0.055 }

local function simpleTip(owner, title, text)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 1, 1)
    if text then GameTooltip:AddLine(text, GREY[1], GREY[2], GREY[3], true) end
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

-- Every band made so far, so a change of picture reaches them all.
local bands = setmetatable({}, { __mode = "v" })

function PB.restyleAll()
    for _, band in pairs(bands) do band.restyle() end
end

function PB.new(parent, build, opts)
    if type(build) ~= "function" then return nil end
    opts = opts or {}
    local jump, onHeight, room = opts.jump or function() end, opts.onHeight, opts.room
    local function report(err)
        if opts.report then return opts.report(err) end
        local handler = _G.geterrorhandler and _G.geterrorhandler()
        if handler then return handler(err) end
    end

    local band = CreateFrame("Frame", nil, parent)
    if band.SetClipsChildren then band:SetClipsChildren(true) end
    band.bg = T.fill(band, T.PREVIEW or BG, 1, "BACKGROUND")
    band.bg:SetAllPoints(band)
    band.art = band:CreateTexture(nil, "BACKGROUND", nil, 1)
    band.art:SetAllPoints(band)
    band.veil = T.fill(band, { 0, 0, 0 }, 0, "BACKGROUND", 2)
    band.veil:SetAllPoints(band)
    T.border(band, WHITE, 0.06)
    bands[#bands + 1] = band
    band.scroll = T.hscroll(band, band)
    band.stage = band.scroll.child

    local decls = opts.decls or {}
    local ctx = { feat = opts.feat, tab = opts.tab }

    local function ask(v)
        if type(v) == "function" then return v() end
        return v
    end

    -- How high a part's target goes: above the part, and for text or a
    -- texture on a frame, above that frame's own target too, so the mouse
    -- on a countdown goes to the countdown.
    local function levelOf(region)
        if region.GetFrameLevel then return region:GetFrameLevel() + 5 end
        local p = region.GetParent and region:GetParent()
        return ((p and p.GetFrameLevel and p:GetFrameLevel()) or 1) + 6
    end

    -- A click target over a part of the example. On hover it shows an accent
    -- outline and the setting's name.
    local hits = {}
    function ctx.hit(region, key, label, text)
        local b = CreateFrame("Button", nil, band.stage)
        b:SetAllPoints(region)
        b:SetFrameLevel(levelOf(region))
        b.region, b.hitKey = region, key
        T.border(b, T.ACCENT, 0)
        b.glow = T.fill(b, T.ACCENT, 0, "OVERLAY")
        b.glow:SetAllPoints(b)
        b:SetScript("OnEnter", function(self)
            T.paint(self, T.ACCENT, 0.9)
            local k = ask(key)
            local d = decls[k]
            local body = ask(text)
            if opts.hitTip then
                opts.hitTip(self, region, k, d, ask(label), body)
            else
                simpleTip(self, ask(label) or (d and d.name) or k,
                          (body and (body .. "\n\n") or "") .. "Click to edit it below.")
            end
        end)
        b:SetScript("OnLeave", function(self)
            T.paint(self, T.ACCENT, 0)
            if opts.hitLeave then opts.hitLeave(self, region) end
            hideTooltip()
        end)
        b:SetScript("OnClick", function() jump(ask(key)) end)
        -- The target isn't the part's child, so it follows the part's
        -- showing and hiding itself. A preview that shows one part per tab
        -- hides the others, and their targets mustn't stay over the band.
        if region.HookScript and region.IsShown then
            region:HookScript("OnShow", function() b:Show() end)
            region:HookScript("OnHide", function() b:Hide() end)
            b:SetShown(region:IsShown())
        end
        hits[#hits + 1] = { b = b, key = key }
        return b
    end

    -- The scenes chosen so far, by key.
    local scenes = {}
    local pv
    local function sceneList()
        local list = pv and pv.scenes
        if type(list) == "function" then
            local ok, l = pcall(list, pv, ctx)
            list = ok and l or nil
        end
        return type(list) == "table" and list or {}
    end
    function ctx.scene(k)
        if scenes[k] ~= nil then return scenes[k] end
        for _, sc in ipairs(sceneList()) do
            if sc.key == k then
                if sc.default ~= nil then return sc.default end
                if sc.choices and sc.choices[1] then return sc.choices[1][1] end
                return false
            end
        end
        return nil
    end
    function ctx.relayout() if band:IsVisible() then band.update() end end

    local ok
    ok, pv = pcall(build, band.stage, ctx)
    if not ok or type(pv) ~= "table" or type(pv.update) ~= "function" then
        if not ok then report(pv) end
        band:Hide()
        return nil
    end

    -- The parts of the example that belong to setting `k`, lit while the
    -- mouse is over its row.
    function band.highlight(k, on)
        if not k then return end
        for _, h in ipairs(hits) do
            if h.b:IsShown() and ask(h.key) == k then
                T.paint(h.b, T.ACCENT, on and 0.9 or 0)
            end
        end
    end

    -- A short flash of those parts, after their setting changed.
    function band.pulse(k)
        if not k then return end
        local start = GetTime()
        for _, h in ipairs(hits) do
            local b = h.b
            if b:IsVisible() and ask(h.key) == k then
                b:SetScript("OnUpdate", function(self)
                    local t = (GetTime() - start) / 0.8
                    if t >= 1 then
                        self.glow:SetAlpha(0)
                        T.paint(self, T.ACCENT, self:IsMouseOver() and 0.9 or 0)
                        self:SetScript("OnUpdate", nil)
                        return
                    end
                    self.glow:SetColorTexture(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.3)
                    self.glow:SetAlpha(1 - t)
                    T.paint(self, T.ACCENT, 0.9 * (1 - t))
                end)
            end
        end
    end

    -- ---------------------------------------------------------
    -- The bar
    -- ---------------------------------------------------------
    local bar = CreateFrame("Frame", nil, band)
    bar:SetPoint("TOPLEFT", band, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, 0)
    bar:SetHeight(Z.BAR)
    bar:SetFrameLevel(band.scroll:GetFrameLevel() + 20)
    band.bar = bar

    local featId = opts.featId
    local demo = opts.demo
    if type(demo) ~= "function" or not NS.Movers then demo = nil end
    local movable = opts.movable and NS.Movers ~= nil

    -- Whether we move this feature by itself now.
    local function movingThis()
        local M = NS.Movers
        return featId ~= nil and M ~= nil and M.movingOnly ~= nil and M.movingOnly() == featId
    end
    -- Whether our whole HUD is on the game screen now.
    local function demoingAll()
        local M = NS.Movers
        return demo ~= nil and M.demoingAll()
    end

    -- While the feature is on the game screen or being moved by itself.
    local function busy()
        return (demo ~= nil and NS.Movers.demoing(demo)) or movingThis()
    end

    -- A click on the fold while the band folded itself opens it until the
    -- demo ends, without changing what's kept.
    local override
    local function byHand()
        return opts.folded ~= nil and opts.folded() == true
    end
    local function folded()
        if override ~= nil then return override end
        return byHand() or busy()
    end

    local fold = CreateFrame("Button", nil, bar)
    fold:SetHeight(Z.CTRL)
    fold.label = T.text(fold, Z.FOLD_FONT, true, T.A_DIM)
    fold.label:SetPoint("LEFT", fold, "LEFT", 0, 0)
    fold:SetPoint("LEFT", bar, "TOPLEFT", Z.PAD - 2, -Z.BAR / 2)
    local function paintFold(over)
        fold.label:SetText((folded() and "+" or "-") .. " PREVIEW")
        fold.label:SetTextColor(1, 1, 1, over and 1 or T.A_DIM)
        fold:SetWidth(floor((fold.label:GetStringWidth() or 60) + 4))
    end
    fold:SetScript("OnEnter", function(self)
        paintFold(true)
        simpleTip(self, folded() and "Show the preview" or "Hide the preview",
                  "Hidden, the settings get its room. It stays hidden on this page until"
                  .. " you show it again.")
    end)
    fold:SetScript("OnLeave", function() paintFold(false) hideTooltip() end)
    fold:SetScript("OnClick", function()
        if busy() then
            override = not folded()
        else
            if opts.setFolded then opts.setFolded(not byHand()) end
            override = nil
        end
        band.update()
        paintFold(true)
    end)

    -- What's going on, in place of the example while the band is folded.
    local note = T.text(bar, T.SIZE.body, false, T.A_DIM)
    note:SetPoint("LEFT", fold, "RIGHT", 14, 0)
    if note.SetWordWrap then note:SetWordWrap(false) end

    local buttons = {}
    local function barButton(tip)
        local b = T.button(bar, "", 100, Z.CTRL)
        b.tip = tip
        buttons[#buttons + 1] = b
        return b
    end
    local function setLabel(b, text)
        b:SetText(text)
        b:SetWidth(floor((b.label:GetStringWidth() or 60) + 24))
    end

    local allBtn, showBtn, moveBtn
    if demo then
        allBtn = barButton(function(self)
            simpleTip(self, "Show all HUD", "Every feature's demo on your game screen at once,"
                .. " with this one outlined, so you see it beside the rest of the HUD.")
        end)
        allBtn:SetScript("OnClick", function()
            local M = NS.Movers
            if M.demoingAll() then
                M.stopDemo()
            else
                M.demoAll(opts.allDemos and opts.allDemos() or { demo }, featId)
            end
        end)
        showBtn = barButton(function(self)
            simpleTip(self, "Show in game", "Shows it on your game screen, where it really goes,"
                .. " with made-up content that changes. This window fades while the mouse is"
                .. " off it.")
        end)
        showBtn:SetScript("OnClick", function()
            local M = NS.Movers
            if M.demoing(demo) and not M.demoingAll() then M.stopDemo() else M.demo(demo) end
        end)
    end
    if movable then
        moveBtn = barButton(function(self)
            simpleTip(self, "Move", "Drag it on your screen, or click it and use the arrow keys"
                .. " to move it a pixel at a time (Shift for ten). Enter or Escape when you're"
                .. " done." .. (opts.moveAll and (" " .. opts.moveAll) or ""))
        end)
        moveBtn:SetScript("OnClick", function()
            local M = NS.Movers
            if movingThis() then M.stop() else M.moveOnly(featId) end
        end)
    end

    -- The scene chips, made as they're first needed, and kept by index.
    local chips = {}
    local function chip(i)
        local c = chips[i]
        if c then return c end
        c = T.segment(bar, "", 40, Z.CTRL)
        c:SetScript("OnEnter", function(self)
            if self.tipText then simpleTip(self, self.tipTitle, self.tipText) end
        end)
        c:SetScript("OnLeave", hideTooltip)
        c:SetScript("OnClick", function(self) if self.run then self.run() end end)
        chips[i] = c
        return c
    end
    local function setScene(sc, v)
        if sc.action then
            if pv.scene then pcall(pv.scene, pv, sc.key, true) end
            return
        end
        scenes[sc.key] = v
        if pv.scene then
            local okS, err = pcall(pv.scene, pv, sc.key, v)
            if not okS then report(err) end
        end
        band.update()
    end

    -- Lays the bar out across `bw` and answers its height.
    local function layoutBar(bw)
        local isFolded = folded()
        paintFold(fold:IsMouseOver())
        local mine = demo and NS.Movers.demoing(demo)
        local everything = demoingAll()
        if allBtn then setLabel(allBtn, everything and "Stop all" or "Show all HUD") end
        if showBtn then
            setLabel(showBtn, (mine and not everything) and "Stop" or "Show in game")
        end
        if moveBtn then setLabel(moveBtn, movingThis() and "Done" or "Move") end

        -- The buttons from the right edge in.
        local x = bw - 8
        for _, b in ipairs(buttons) do
            x = x - b:GetWidth()
            b:ClearAllPoints()
            b:SetPoint("LEFT", bar, "TOPLEFT", x, -Z.BAR / 2)
            x = x - 6
        end
        local right = x - 8

        local text = ""
        if movingThis() then
            text = "Drag it on your screen, or use the arrow keys for a pixel (Shift for ten)."
        elseif everything and mine then
            text = "Our whole HUD is on your game screen, this one outlined."
        elseif mine then
            text = "On your game screen now. This window fades while the mouse is off it."
        end
        note:SetText(isFolded and text or "")
        note:SetWidth(max(1, right - (Z.PAD + fold:GetWidth() + 14)))

        -- The chips, after the fold when they fit, else on a line of their
        -- own. They go while the band is folded, since they change only the
        -- example.
        local list = isFolded and {} or sceneList()
        local n, widths, total = 0, {}, 0
        for _, sc in ipairs(list) do
            for _, ch in ipairs(sc.choices or { { true, sc.label or sc.key } }) do
                n = n + 1
                local c = chip(n)
                c.label:SetText(ch[2])
                local w = floor((c.label:GetStringWidth() or 30) + 18)
                c:SetWidth(w)
                widths[n] = w
                total = total + w + Z.CHIP_GAP
            end
            total = total + 8
        end
        for i = n + 1, #chips do chips[i]:Hide() end
        if n == 0 then return Z.BAR end

        local startX = Z.PAD + fold:GetWidth() + 14
        local second = startX + total > right
        local cx, cy = second and Z.PAD or startX, second and -(Z.BAR - 4 + Z.BAR_LINE2 / 2)
                                                            or -Z.BAR / 2
        local i = 0
        for _, sc in ipairs(list) do
            local now = ctx.scene(sc.key)
            for _, ch in ipairs(sc.choices or { { true, sc.label or sc.key } }) do
                i = i + 1
                local c = chip(i)
                local value = ch[1]
                c:ClearAllPoints()
                c:SetPoint("LEFT", bar, "TOPLEFT", cx, cy)
                cx = cx + widths[i] + Z.CHIP_GAP
                if sc.action then
                    c:show(false, true)
                    c.run = function() setScene(sc, true) end
                elseif sc.toggle then
                    c:show(now == true, true)
                    c.run = function() setScene(sc, not (ctx.scene(sc.key) == true)) end
                else
                    c:show(now == value, true)
                    c.run = function() setScene(sc, value) end
                end
                c.tipTitle = sc.label or ch[2]
                c.tipText = sc.tip
                c:Show()
            end
            cx = cx + 8
        end
        return second and (Z.BAR + Z.BAR_LINE2 - 4) or Z.BAR
    end

    -- The band folds by itself while its feature shows in game or moves, so
    -- it hears when that starts and ends.
    if (demo or movable) and NS.Movers and NS.Movers.onDemo then
        NS.Movers.onDemo(function()
            override = nil
            if band:IsVisible() then band.update() end
        end)
    end

    -- The art cut to the band's shape, from its middle, so it isn't stretched.
    local function fitArt(bw, bh)
        local art = band.artDef
        if not art or bw <= 0 or bh <= 0 then return end
        local l, r, t, b = unpack(art.coords or { 0, 1, 0, 1 })
        local want = bw / bh
        local aspect = art.aspect or 4 / 3
        if want > aspect then
            local keep = (b - t) * aspect / want
            local mid = (t + b) / 2
            t, b = mid - keep / 2, mid + keep / 2
        else
            local keep = (r - l) * want / aspect
            local mid = (l + r) / 2
            l, r = mid - keep / 2, mid + keep / 2
        end
        band.art:SetTexCoord(l, r, t, b)
    end

    function band.restyle()
        local art, dim = nil, 0
        if opts.art then art, dim = opts.art() end
        band.artDef = art
        if art then
            band.art:SetTexture(art.file)
            band.art:Show()
            band.veil:SetColorTexture(0, 0, 0, dim or 0.6)
            band.veil:Show()
            fitArt(band:GetWidth() or 0, band:GetHeight() or 0)
        else
            band.art:Hide()
            band.veil:Hide()
        end
    end
    band.restyle()

    local height = 0
    function band.update()
        local bw = band:GetWidth() or 0
        local barH = layoutBar(bw)
        bar:SetHeight(barH)
        local bh
        if folded() then
            band.scroll:Hide()
            band.scroll.track:Hide()
            bh = barH
        else
            band.scroll:Show()
            local parentScale = band:GetEffectiveScale() or 1
            local s = (_G.UIParent:GetEffectiveScale() or 1) / parentScale
            if s <= 0 then s = 1 end
            local w = (bw - 2 * Z.PAD) / s
            if w < 100 then w = 600 end
            local top = barH + 4

            -- Draws the example at `f` of its size, across the whole band.
            local function draw(f)
                local okU, h, cw = pcall(pv.update, pv, w / f)
                if not okU then report(h) end
                return (okU and tonumber(h)) or 40, (okU and tonumber(cw)) or w / f, okU
            end
            local f = 1
            local h, cw, okU = draw(1)

            -- When it's taller than the room, like Farm's detailed widget
            -- under its small one in a short window, we draw it smaller. At
            -- the size where its height just fits it is drawn wider too, and
            -- an example that went under the other part to fit the band can
            -- go beside it again and come out shorter. So we look for the
            -- biggest size that fits between that one and the full size.
            local cap = room and room()
            local fitH = cap and (cap - top - Z.PAD) / s
            if okU and fitH and h > fitH then
                local lo, hi = max(MIN_FIT, fitH / h), 1
                for _ = 1, 5 do
                    local mid = (lo + hi) / 2
                    if draw(mid) * mid <= fitH then lo = mid else hi = mid end
                end
                f = lo
                h, cw = draw(f)
            end

            local sf = s * f
            band.scroll:SetScale(sf)
            band.scroll:ClearAllPoints()
            band.scroll:SetPoint("TOPLEFT", band, "TOPLEFT", Z.PAD / sf, -top / sf)
            band.scroll:SetSize(w / f, h)
            band.stage:SetSize(max(w / f, cw), h)
            band.scroll:update()
            bh = floor(h * sf + top + Z.PAD + 0.5)
            -- Even at the smallest size it didn't fit, so the band cuts off
            -- the bottom of it.
            if cap and bh > cap then bh = max(floor(cap), top + Z.PAD + 40) end
        end
        fitArt(bw, bh)
        if bh ~= height then
            height = bh
            band:SetHeight(bh)
            if onHeight then onHeight(bh) end
        end
        return bh
    end
    -- While the window is being resized, the band's size changes every
    -- frame. Drawing the example again each time made a big one, like Raid
    -- Buffs' four widgets, disappear until the drag ended. So we draw it once
    -- the size has held still for a moment, and until then it keeps its last
    -- drawing.
    local settle = CreateFrame("Frame", nil, band)
    local changedAt
    function band.later()
        changedAt = GetTime()
        settle:SetScript("OnUpdate", function(self)
            if GetTime() - changedAt < SETTLE then return end
            self:SetScript("OnUpdate", nil)
            if band:IsVisible() then band.update() end
        end)
    end
    band:SetScript("OnSizeChanged", function()
        if band:IsVisible() then band.later() end
    end)
    return band
end
