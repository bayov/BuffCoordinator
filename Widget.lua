-- A row of icons on the screen that anyone can read at a glance: Group buffs
-- (GroupBuffs.lua) and Target debuffs (TargetDebuffs.lua) are each one.
--
-- A widget is made from a spec, and does the rest the same way for both:
--   key       the start of its settings' names ("group" makes groupWidth,
--             groupPerRow and the rest, Options.lua's O.widget)
--   show      the name of its "Show ..." setting
--   name      what move mode's box calls it
--   frame     the name of its frame
--   db        where its spot is kept in our saved variables
--   home      { x, y } where it sits until it's dragged
--   cells()   what it shows now, a list of cells with `b` (the buff)
--   samples() made-up cells for Preview, and for move mode when it has
--             nothing real to show
--   wanted()  whether it has a reason to show beyond its settings, or nil
--   missing(c) whether cell `c` needs attention ("Only what's missing")
--   paint(f, c, now, glows)
--             paints icon `f` for cell `c`
--   tip(f)    its tooltip
--   click(c, shift)
--   fit(f)    anything more an icon needs after it's sized, or nil
--   painted(icons)
--             anything more the icons on the screen need after a paint,
--             or nil
--   clear(f)  undoes that for an icon that goes, or nil
--
-- Its look and place are the player's own, on the HUD tab. The font, the
-- border and the glow are the HUD's. The HUD tab draws it with made-up
-- cells in its preview pane (W.stage), and Preview in game does on the
-- screen (HUD.lua's preview). Move mode puts a box around it (W.MOVE), and shows
-- it with made-up cells when it has nothing to show, so it can be placed
-- solo. A setting of Never hides it in both.
--
-- It's plain frames, not secure buttons, so it can change in combat.

local _, NS = ...
local Tr, O, T = NS.Tracking, NS.Options, NS.Theme
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local Wd = {}
NS.Widget = Wd

local function previewing() return NS.HUD ~= nil and NS.HUD.previewing() end
local function moving() return NS.HUD ~= nil and NS.HUD.moving() end

-- How far up the countdown sits from an icon's middle so it clears a count
-- in a bottom corner `countSize` pixels tall, in screen pixels. Down instead
-- for a count in a top corner (`top`).
function Wd.timerLift(countSize, top)
    local lift = ceil(countSize / 2) + 1
    return top and -lift or lift
end

-- Puts icon `f`'s countdown in the middle, or clear of its count when it
-- has one. `top` says the count is in a top corner.
function Wd.placeTimer(f, hasCount, countSize, top)
    local y = hasCount and Wd.timerLift(countSize, top) or 0
    if f.timerY == y and f.timerSize == countSize then return end
    f.timerY, f.timerSize = y, countSize
    f.timer:ClearAllPoints()
    f.timer:SetPoint("CENTER", f, "CENTER", 0, y * T.pixel(f))
end

function Wd.new(spec)
    local W = { icons = {} }
    local icons = W.icons
    local key = spec.key
    -- What it draws into: the widget on the screen, or a preview pane's
    -- copy (W.stage). `live` is the one on the screen, which moves and
    -- hears clicks.
    local screen = { icons = icons, live = true }
    local holder
    local function opt(k) return O.get(key .. k) end
    -- Goes up with every settings change, so each icon fits itself again
    -- to a new font or border.
    local fitGen = 0
    local sampleStart = 0
    W.sampleStart = function() return sampleStart end

    -- Whether it shows now: its "Show ..." setting ("always", "group",
    -- "raid" or "never"), "Show in combat" and the spec's own reason. The
    -- mock raid's players aren't there.
    function W.wanted()
        local when = O.get(spec.show)
        if when == "never" then return false end
        if previewing() or moving() then return true end
        if NS.mock then return false end
        if when == "raid" and not NS.Roster.raid() then return false end
        if when == "group" and not NS.Roster.grouped() then return false end
        if InCombatLockdown() and not opt("Combat") then return false end
        if spec.wanted and not spec.wanted() then return false end
        return true
    end

    -- Whether it shows real cells, which need reading.
    function W.reading()
        return holder ~= nil and holder:IsShown() and not previewing()
    end

    -- =============================================================
    -- Where it sits
    -- =============================================================
    local function spot()
        local pos = NS.db[spec.db] or {}
        return pos.x or spec.home[1], pos.y or spec.home[2]
    end

    local function place()
        if not holder then return end
        local x, y = spot()
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end

    local function keep(x, y)
        NS.db[spec.db] = NS.db[spec.db] or {}
        NS.db[spec.db].x, NS.db[spec.db].y = NS.HUD.tidy(x), NS.HUD.tidy(y)
    end

    -- Moves it by `dx` and `dy` whole screen pixels from its top left
    -- corner, rounded to a pixel first, the way HUD.lua's nudge moves the
    -- HUD.
    local function nudge(dx, dy)
        local p = T.pixel(UIParent)
        local x, y = spot()
        local l, t = holder:GetLeft(), holder:GetTop()
        local cx, cy = holder:GetCenter()
        if l and t and cx and cy then
            local r = holder:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local ux, uy = UIParent:GetCenter()
            l, t = l * r, t * r
            x = cx * r - ux + (floor(l / p + 0.5) + dx) * p - l
            y = cy * r - uy + (floor(t / p + 0.5) + dy) * p - t
        else
            x, y = x + dx * p, y + dy * p
        end
        keep(x, y)
        place()
    end

    -- Keeps the spot a drag left it at, on a whole pixel.
    local function save()
        local x, y = holder:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not (x and ux) then return end
        local s = holder:GetEffectiveScale() / UIParent:GetEffectiveScale()
        keep(x * s - ux, y * s - uy)
        nudge(0, 0)
    end

    -- The move mode box goes around the icons shown.
    local function fitBox(box)
        box:ClearAllPoints()
        local l, r, t, b
        for _, f in ipairs(icons) do
            if f:IsShown() and f:GetLeft() then
                l, r = l and min(l, f:GetLeft()) or f:GetLeft(), r and max(r, f:GetRight()) or f:GetRight()
                t, b = t and max(t, f:GetTop()) or f:GetTop(), b and min(b, f:GetBottom()) or f:GetBottom()
            end
        end
        local hl, ht = holder:GetLeft(), holder:GetTop()
        if not (l and hl and ht) then
            box:SetAllPoints(holder)
            return
        end
        box:SetPoint("TOPLEFT", holder, "TOPLEFT", l - hl, t - ht)
        box:SetSize(r - l, t - b)
    end

    -- What HUD.lua's move mode adds to the shared movers (Shared/Movers.lua)
    -- for us. Set to Never, it isn't on show, and it has no box.
    W.MOVE = { key = spec.key, label = spec.name, frame = function() return holder end, get = spot,
               place = place, nudge = nudge, save = save, fit = fitBox,
               hidden = function() return not (holder and holder:IsShown()) end }

    -- =============================================================
    -- Icons
    -- =============================================================
    local function newIcon(view)
        local f = CreateFrame("Button", nil, view.holder)
        f.edge = f:CreateTexture(nil, "BACKGROUND")
        f.edge:SetColorTexture(0, 0, 0, 1)
        f.edge:SetAllPoints(f)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.over = CreateFrame("Frame", nil, f)
        f.over:SetAllPoints(f)
        f.over:SetFrameLevel(f:GetFrameLevel() + 4)
        f.timer = f.over:CreateFontString(nil, "OVERLAY")
        f.timer:SetPoint("CENTER", f, "CENTER", 0, 0)
        f.count = f.over:CreateFontString(nil, "OVERLAY")
        f.hl = f:CreateTexture(nil, "HIGHLIGHT")
        f.hl:SetColorTexture(1, 1, 1, 0.12)
        f:SetScript("OnEnter", function(self)
            W.hover = view.live
            if self.cell then spec.tip(self) end
        end)
        f:SetScript("OnLeave", function()
            W.hover = false
            GameTooltip:Hide()
        end)
        if not view.live then return f end
        f:RegisterForClicks("LeftButtonUp")
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self)
            if O.get("lock") then return end
            self.dragged = true
            holder:StartMoving()
        end)
        f:SetScript("OnDragStop", function()
            holder:StopMovingOrSizing()
            save()
        end)
        f:SetScript("OnClick", function(self)
            if self.dragged then
                self.dragged = nil
                return
            end
            if self.cell then spec.click(self.cell, _G.IsShiftKeyDown ~= nil and IsShiftKeyDown() and true or false) end
        end)
        return f
    end

    -- Sizes icon `f` to `w` by `h` screen pixels, with the HUD's border.
    local function fit(f, w, h)
        local p = T.pixel(f)
        local edge = O.get("border") and 1 or 0
        f:SetSize(w * p, h * p)
        f.edge:SetShown(edge > 0)
        f.icon:ClearAllPoints()
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", edge * p, -edge * p)
        f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -edge * p, edge * p)
        NS.HUD.crop(f.icon, w - 2 * edge, h - 2 * edge)
        f.hl:ClearAllPoints()
        f.hl:SetAllPoints(f.icon)
        NS.HUD.setFont(f.timer, opt("TimerSize"))
        NS.HUD.setFont(f.count, opt("CountSize"))
        f.count:ClearAllPoints()
        f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2 * p, 2 * p)
        f.count:SetJustifyH("RIGHT")
        f.timerY = nil
        f.w, f.h = w, h
        if spec.fit then spec.fit(f) end
    end

    -- Paints the count and the countdown of icon `f`: `count` in `color`,
    -- and the time left until `expires` in `tcolor`, when its setting is
    -- on. The countdown moves up clear of a count.
    function W.texts(f, count, color, expires, tcolor, now)
        f.count:SetText(count or "")
        f.count:SetTextColor(color[1], color[2], color[3], 1)
        local text = ""
        if opt("Timer") and expires and expires > 0 then text = NS.HUD.timeText(expires - now) end
        f.timer:SetText(text)
        NS.HUD.keepFresh(f.timer, text ~= "" and expires or nil, now)
        f.timer:SetTextColor(tcolor[1], tcolor[2], tcolor[3], 1)
        Wd.placeTimer(f, (count or "") ~= "", opt("CountSize"), false)
    end

    -- Whether a cell that needs attention glows here.
    function W.glows(glows) return glows and opt("Glow") end

    -- =============================================================
    -- Laying out
    -- =============================================================
    -- The icons go in rows of "Icons per row". The first row stays where
    -- the widget is placed, and more rows go below or above it. A row that
    -- isn't full sits left, in the middle or right of that spot.
    -- Returns the size of the whole in screen pixels, and how many rows it
    -- has.
    local function arrange(view, list)
        local icons = view.icons
        local w, h, gap = opt("Width"), opt("Height"), opt("Gap")
        local perRow, align, grow = opt("PerRow"), opt("Align"), opt("Grow")
        local p = T.pixel(view.holder)
        local cols = max(1, min(#list, perRow))
        local rows = max(1, ceil(#list / perRow))
        view.holder:SetSize(max(1, cols * w + (cols - 1) * gap) * p, h * p)
        for i = 1, #list do
            local f = icons[i] or newIcon(view)
            icons[i] = f
            if f.w ~= w or f.h ~= h or f.fitFor ~= fitGen then
                fit(f, w, h)
                f.fitFor = fitGen
            end
            local row, col = floor((i - 1) / perRow), (i - 1) % perRow
            local inRow = min(perRow, #list - row * perRow)
            local rowW = inRow * w + (inRow - 1) * gap
            local fullW = cols * w + (cols - 1) * gap
            local x = col * (w + gap)
            if align == "center" then
                x = x + (fullW - rowW) / 2
            elseif align == "right" then
                x = x + fullW - rowW
            end
            local y = row * (h + gap) * (grow == "up" and 1 or -1)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", view.holder, "TOPLEFT", floor(x + 0.5) * p, floor(y + 0.5) * p)
            f:Show()
        end
        for i = #list + 1, #icons do
            icons[i].cell = nil
            NS.HUD.glow(icons[i], nil)
            if spec.clear then spec.clear(icons[i]) end
            icons[i]:Hide()
        end
        return cols * w + (cols - 1) * gap, rows * h + (rows - 1) * gap, rows
    end

    -- Only what's missing, when that's on.
    local function shown(list)
        if not opt("MissingOnly") then return list end
        local t = {}
        for _, c in ipairs(list) do
            if spec.missing(c) then t[#t + 1] = c end
        end
        return t
    end

    -- The cells the icons show, in the order they showed last while the
    -- mouse is over them, so a click doesn't land on another one.
    local shownOrder = {}

    local function steady(list)
        if not W.hover then
            for k in pairs(shownOrder) do shownOrder[k] = nil end
            for i, c in ipairs(list) do shownOrder[c.b.id] = i end
            return list
        end
        local far = #list + 1000
        for i, c in ipairs(list) do c.order = i end
        table.sort(list, function(x, y)
            return (shownOrder[x.b.id] or far + x.order) < (shownOrder[y.b.id] or far + y.order)
        end)
        return list
    end

    local function paintAll()
        local list = previewing() and {} or spec.cells()
        -- Made up in Preview, and while we move it with nothing real.
        if previewing() or moving() and #list == 0 then list = spec.samples() end
        list = steady(shown(list))
        arrange(screen, list)
        local now = GetTime()
        local glows = previewing() and NS.HUD.previewGlows() or NS.HUD.glowsHere()
        for i, c in ipairs(list) do
            icons[i].cell = c
            spec.paint(icons[i], c, now, glows)
        end
        if spec.painted then spec.painted(icons) end
        holder:SetAlpha(InCombatLockdown() and opt("CombatAlpha") or opt("Alpha"))
    end

    function W.paint()
        if not holder then return end
        local show = W.wanted()
        if show ~= holder:IsShown() then
            if show then
                place()
                holder:Show()
                -- Shown now, so its buffs need reading.
                Tr.readSoon()
            else
                holder:Hide()
            end
        end
        if moving() then NS.HUD.fitMovers() end
        if not show then return end
        Tr.memoize(true)
        local ok, err = pcall(paintAll)
        Tr.memoize(false)
        if not ok then error(err, 0) end
        if moving() then NS.HUD.fitMovers() end
    end

    W.frame = function() return holder end
    W.place = function() if holder then place() end end

    -- A copy of it in `parent` that shows the made-up cells, for the HUD
    -- tab's preview pane. `stage.update()` draws it again from the
    -- settings and answers its width and height in `parent`'s units. Its
    -- countdowns tick while it shows.
    function W.stage(parent)
        local view = { icons = {}, live = false }
        view.holder = CreateFrame("Frame", nil, parent)
        local st = { frame = view.holder, view = view }
        function st.update()
            local list = shown(spec.samples())
            local w, h, rows = arrange(view, list)
            local now = GetTime()
            for i, c in ipairs(list) do
                view.icons[i].cell = c
                spec.paint(view.icons[i], c, now, NS.HUD.previewGlows())
            end
            local p = T.pixel(view.holder)
            -- Rows that grow up go above the first row, so the first row
            -- moves down to make room in the pane.
            st.lift = opt("Grow") == "up" and (rows - 1) * (opt("Height") + opt("Gap")) * p or 0
            view.holder:SetAlpha(opt("Alpha"))
            return w * p, h * p
        end
        -- Its cells for the pane's clicks (Settings.lua), which go to the
        -- icons' size, and the text on them, which goes to its own size.
        function st.targets()
            local t = {}
            for _, f in ipairs(view.icons) do t[#t + 1] = { f, key .. "Width" } end
            for _, f in ipairs(view.icons) do
                t[#t + 1] = { f.timer, key .. "TimerSize" }
                t[#t + 1] = { f.count, key .. "CountSize" }
            end
            return t
        end
        local tick = 0
        view.holder:SetScript("OnUpdate", function(_, elapsed)
            tick = tick + elapsed
            if tick < 0.5 then return end
            tick = 0
            local now = GetTime()
            for _, f in ipairs(view.icons) do
                if f:IsShown() and f.cell then spec.paint(f, f.cell, now, NS.HUD.previewGlows()) end
            end
        end)
        return st
    end

    -- =============================================================
    -- Events
    -- =============================================================
    local soonKey = spec.key .. "WidgetPaint"
    local function soon() NS.soon(soonKey, 0.1, W.paint) end
    NS.listen("login", function()
        holder = CreateFrame("Frame", spec.frame, UIParent)
        screen.holder = holder
        holder:SetMovable(true)
        holder:SetClampedToScreen(true)
        holder:SetSize(1, 1)
        holder:Hide()
        place()
        W.paint()
        C_Timer.NewTicker(0.5, W.paint)
    end)
    NS.listen("board", soon)
    NS.listen("roster", soon)
    NS.listen("tracking", soon)
    NS.listen("preview", function(on)
        if on then sampleStart = GetTime() end
        soon()
    end)
    NS.listen("moving", function(on)
        if on then sampleStart = GetTime() end
        W.paint()
    end)
    NS.listen("option", function(k)
        fitGen = fitGen + 1
        if k == nil and holder then place() end
        soon()
    end)
    NS.on("PLAYER_REGEN_DISABLED", W.paint)
    NS.on("PLAYER_REGEN_ENABLED", W.paint)
    return W
end

-- A made-up cell's countdown: `left` seconds, counting down from when the
-- preview started and starting over.
function Wd.loop(left, start, now)
    if not left then return 0 end
    return now + left - (now - start) % left
end

-- Says `text` in the group's chat, a line at a time.
function Wd.say(text)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    local R = NS.Roster
    local channel = R.raid() and "RAID" or R.grouped() and "PARTY" or nil
    if not (send and channel) then return end
    for _, line in ipairs(NS.Whisper.lines(text)) do pcall(send, line, channel) end
end

-- The givers of `assigns`, each once, as tooltip text: "From Mira, Fen.".
function Wd.fromLine(assigns)
    local givers, seen = {}, {}
    for _, a in ipairs(assigns) do
        if not seen[a.giver.name] then
            seen[a.giver.name] = true
            givers[#givers + 1] = NS.who(a.giver)
        end
    end
    if #givers == 0 then return nil end
    return "From " .. table.concat(givers, ", ") .. "."
end
