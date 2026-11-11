-- The coverage strip: every assignment of the group at a glance, for the
-- leader and the players promoted to assistant.
--
-- One small icon per active assignment that buffs players, with how many
-- have its buff ("38/40"), in the missing glow colour when someone is
-- missing it, the running out one when it runs out soon, and green when all
-- is up. The one missing something longest comes first. Its
-- tooltip names the giver, who is missing the buff and for how long, and
-- what the giver's client said on the last ready check. A click, out of
-- combat, nudges the giver: a whisper with the missing names (Whisper.lua).
--
-- It shows in raids by default, since a party has few enough buffs to see
-- on the HUD. Until it's dragged it sits just above the HUD. While the mouse
-- is over it the icons keep their places, so a click doesn't land on a
-- different giver because the order changed under it.
--
-- Many raids make everyone an assistant, and then the strip would show for
-- all 40 players. So only a rank given by hand counts. A Right-click on a
-- tile hides the strip (the "Coverage strip" setting).
--
-- Every client says on a ready check what of theirs is due on the pull
-- (the "check" message, Sync.lua), and the tooltips show it.
--
-- Reading every assignment's buffs is many more reads than our own, so we
-- only do it while the strip shows (Tracking.lua), and a little less often.
-- The strip is plain frames, not secure buttons, so it can change in combat.

local _, NS = ...
local D, R, Du, Tr, B, S, O, T = NS.Data, NS.Roster, NS.Duties, NS.Tracking, NS.Buffer, NS.Sync,
                                 NS.Options, NS.Theme
local floor, max = math.floor, math.max
local format = string.format

local Cv = {}
NS.Coverage = Cv

local SIZE = 24
local GAP = 2
local PER_ROW = 12
local COUNT_SIZE = 10

local strip
local tiles = {}

-- Whether the strip is for us: the leader or a player promoted to assistant
-- in a real group, with the setting on for this kind of group ("raid",
-- "group" or "never"). The roster's rank is the one given by hand, which
-- "everyone is assistant" leaves alone.
function Cv.wanted()
    local when = O.get("coverage")
    if when == "never" or not when then return false end
    if when ~= "group" and not R.raid() then return false end
    local me = R.real.me()
    return not NS.mock and R.grouped() and me ~= nil and (me.rank or 0) >= 1 and true or false
end

-- Whether the strip shows, so every assignment's buffs need reading.
function Cv.reading()
    return strip ~= nil and strip:IsShown()
end

-- "2m10s", for how long something has been missing.
function Cv.duration(seconds)
    seconds = max(0, floor(seconds + 0.5))
    if seconds >= 3600 then return format("%dh%dm", floor(seconds / 3600), floor(seconds % 3600 / 60)) end
    if seconds >= 60 then return format("%dm%02ds", floor(seconds / 60), seconds % 60) end
    return format("%ds", seconds)
end

-- How many of status `st` are missing the buff, and how many have it
-- running out.
local function counts(st)
    local missing, soon = 0, 0
    for _, t in ipairs(st.missing) do
        if t.soon then soon = soon + 1 else missing = missing + 1 end
    end
    return missing, soon
end

-- One assignment's place on the strip, kept while the mouse is over it.
local function keyOf(a)
    return format("%s\1%s\1%s", a.job.id, a.giver.name, tostring(a.party or ""))
end

-- The strip's assignments: { a, st, b, missing, soon } for every active
-- assignment that puts a buff on players, the one missing something longest
-- first, then ones running out, then the rest in the board's order.
function Cv.entries()
    local list = {}
    local now = GetTime()
    for _, job in ipairs(D.JOBS) do
        local plan = Du.plan(job.id)
        if plan and plan.active and job.scope ~= "target" then
            for _, a in ipairs(plan.list) do
                local st = Tr.status(a)
                if not st.debuff and (st.want > 0 or #st.missing > 0) then
                    local b = (a.bless or a.spare) and B.mainBlessing({ a }) or a.buff
                    local missing, soon = counts(st)
                    local since = missing > 0 and (st.oldest or now) or nil
                    local rank = missing > 0 and 0 or soon > 0 and 1 or 2
                    list[#list + 1] = { a = a, st = st, b = b, since = since, rank = rank, order = #list,
                                        missing = missing, soon = soon, key = keyOf(a) }
                end
            end
        end
    end
    table.sort(list, function(x, y)
        if x.rank ~= y.rank then return x.rank < y.rank end
        if x.since and x.since ~= y.since then return x.since < y.since end
        return x.order < y.order
    end)
    return list
end

-- The order the strip showed last, by key, and whether the mouse is over it.
local shownAt = {}

function Cv.hovered()
    if Cv.hover then return true end
    return strip ~= nil and strip.IsMouseOver ~= nil and strip:IsMouseOver() and true or false
end

-- `list` in the order the strip showed last, with what's new at the end.
local function frozen(list)
    local far = #list + 1000
    for i, e in ipairs(list) do e.order = i end
    table.sort(list, function(x, y)
        local px, py = shownAt[x.key] or far + x.order, shownAt[y.key] or far + y.order
        return px < py
    end)
    return list
end

-- What a ready check said of giver `name`, as a line, or nil.
function Cv.checkLine(name)
    local c = S.checks[name]
    if not c then
        if R.byName(name) and not S.hasAddon(name) then return "No addon." end
        return nil
    end
    local parts = {}
    for id, n in pairs(c.due) do parts[#parts + 1] = format("%d %s", n, B.short(Tr.title(D.BY_ID[id]))) end
    if #parts == 0 then return "Ready check: all up." end
    table.sort(parts)
    return "Ready check: due " .. table.concat(parts, ", ") .. "."
end

-- =============================================================
-- Tiles
-- =============================================================
local function title(e)
    local a = e.a
    local what = a.bless and "Blessings" or B.short(Tr.title(e.b))
    return format("%s (%s)", what, a.giver.name)
end

local function tooltip(f)
    local e = f.entry
    if not e then return end
    local st = Tr.status(e.a)
    local lines = {}
    local missing, soon = {}, 0
    for _, t in ipairs(st.missing) do
        if t.low then
            -- The DOWNRANK line below says it.
        elseif t.soon then
            soon = soon + 1
        else
            missing[#missing + 1] = t
        end
    end
    local red, orange = O.color("glowColor"), O.color("warnColor")
    if #missing > 0 then
        local since = st.oldest and Cv.duration(GetTime() - st.oldest)
        lines[#lines + 1] = { format("%d missing for %s.", #missing, since or "a moment"), red[1], red[2], red[3] }
        for i, t in ipairs(missing) do
            if i > 12 then
                lines[#lines + 1] = format("and %d more", #missing - 12)
                break
            end
            lines[#lines + 1] = NS.who(t.m)
        end
    elseif st.want > 0 and st.have + st.unknown >= st.want then
        lines[#lines + 1] = T.line("Everyone has it.", "up")
    end
    if soon > 0 then
        lines[#lines + 1] = { format("%d running out.", soon), orange[1], orange[2], orange[3] }
    end
    local low = Tr.lowLines(st.low)
    for _, l in ipairs(low or {}) do lines[#lines + 1] = { l, orange[1], orange[2], orange[3] } end
    if st.unknown > 0 then lines[#lines + 1] = format("%d not seen yet.", st.unknown) end
    local check = Cv.checkLine(e.a.giver.name)
    if check then lines[#lines + 1] = check end
    local hints = {}
    if #missing > 0 and not e.a.giver.me then
        hints[1] = { "Click", format("whisper %s who's missing it", e.a.giver.name:match("^(%S+)") or e.a.giver.name) }
    end
    if not O.get("lock") then hints[#hints + 1] = { "Drag", "move" } end
    hints[#hints + 1] = { "Right-click", "hide the strip" }
    table.insert(lines, 1, format("From %s.", NS.who(e.a.giver)))
    T.spellTip(f, e.b, title(e), lines, hints)
end

local function savePosition()
    local x, y = strip:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local s = strip:GetEffectiveScale() / UIParent:GetEffectiveScale()
    NS.db.coverage = NS.db.coverage or {}
    NS.db.coverage.x, NS.db.coverage.y = floor((x * s - ux) + 0.5), floor((y * s - uy) + 0.5)
end

-- A click nudges the giver, out of combat.
local function nudge(f)
    local e = f.entry
    if not e or InCombatLockdown() then return end
    local sent, wait = NS.Whisper.nudge(e.a)
    local who = NS.classColored(e.a.giver.name, e.a.giver.class)
    if sent then
        NS.print("Whispered %s what's missing.", who)
    elseif wait then
        NS.print("You whispered %s a moment ago. Try again in %d s.", who, wait)
    end
end
Cv.nudge = nudge

-- A Right-click hides the strip, and says how to bring it back.
local function hide()
    O.set("coverage", "never")
    NS.print("The coverage strip is hidden. Turn it back on in Settings.")
end

local function newTile()
    local f = CreateFrame("Button", nil, strip)
    f:SetSize(SIZE, SIZE)
    f.icon = T.icon(f, nil, SIZE)
    f.icon:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.count = T.text(f, COUNT_SIZE, true)
    f.count:SetPoint("TOP", f, "BOTTOM", 0, -1)
    f.count:SetJustifyH("CENTER")
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        if O.get("lock") then return end
        f.dragged = true
        strip:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        strip:StopMovingOrSizing()
        savePosition()
    end)
    f:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            GameTooltip:Hide()
            return hide()
        end
        if self.dragged then
            self.dragged = nil
            return
        end
        nudge(self)
    end)
    f:SetScript("OnEnter", function(self)
        Cv.hover = true
        tooltip(self)
    end)
    f:SetScript("OnLeave", function()
        Cv.hover = false
        GameTooltip:Hide()
    end)
    return f
end

local function build()
    strip = CreateFrame("Frame", "BuffCoordinatorCoverage", UIParent)
    strip:SetMovable(true)
    strip:SetClampedToScreen(true)
    strip:SetSize(SIZE, SIZE)
    strip:Hide()
end

-- How far the strip sits from the HUD until it's dragged.
local NEAR_HUD = 12

-- Where the strip goes: where it was dragged to, else just above the HUD
-- (or under it, when the HUD's icons grow up).
local function place()
    local pos = NS.db.coverage or {}
    strip:ClearAllPoints()
    local hud = NS.HUD and NS.HUD.frame()
    if pos.x or not hud then
        strip:SetPoint("CENTER", UIParent, "CENTER", pos.x or 0, pos.y or 260)
    elseif O.get("grow") == "up" then
        -- The line under the auto-buff button goes under it then.
        strip:SetPoint("TOPLEFT", hud, "BOTTOMLEFT", 0, -NEAR_HUD - 3 * O.get("countSize"))
    else
        strip:SetPoint("BOTTOMLEFT", hud, "TOPLEFT", 0, NEAR_HUD)
    end
end

function Cv.paint()
    if not strip then return end
    local show = Cv.wanted()
    if show ~= strip:IsShown() then
        if show then place() end
        strip:SetShown(show)
        -- Shown now, so the others' buffs need reading.
        if show then Tr.readSoon() end
    end
    if not show then return end
    Tr.memoize(true)
    local ok, list = pcall(Cv.entries)
    Tr.memoize(false)
    if not ok then error(list, 0) end
    if Cv.hovered() then
        list = frozen(list)
    else
        for k in pairs(shownAt) do shownAt[k] = nil end
        for i, e in ipairs(list) do shownAt[e.key] = i end
    end
    local step = SIZE + GAP
    local rowH = SIZE + COUNT_SIZE + 2 * GAP
    for i, e in ipairs(list) do
        local f = tiles[i] or newTile()
        tiles[i] = f
        f.entry = e
        local tex = Tr.icon(e.b)
        if f.tex ~= tex then
            f.icon:SetTexture(tex)
            f.tex = tex
        end
        f.count:SetText(format("%d/%d", e.st.have, e.st.want))
        local c = e.missing > 0 and O.color("glowColor") or e.soon > 0 and O.color("warnColor") or T.COLOR.up
        f.count:SetTextColor(c[1], c[2], c[3], 1)
        f.icon:SetDesaturated(e.missing == 0 and e.soon == 0)
        T.downrank(f, e.st.low ~= nil and #e.st.low > 0, O.color("glowColor"), nil, nil, 1.2)
        local row, col = floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", strip, "TOPLEFT", col * step, -row * rowH)
        f:Show()
    end
    for i = #list + 1, #tiles do
        tiles[i].entry = nil
        tiles[i]:Hide()
    end
    local cols = math.min(max(1, #list), PER_ROW)
    strip:SetSize(cols * step, max(1, math.ceil(#list / PER_ROW)) * rowH)
end

Cv.tiles = tiles
Cv.frame = function() return strip end

-- =============================================================
-- Our own ready-check status
-- =============================================================
-- What of ours is due on the pull, as { [buff id] = how many }.
local function dueNow()
    local t = {}
    for _, d in ipairs(Tr.due()) do t[d.b.id] = #d.names end
    return t
end

local sentDue

local function sendCheck()
    if not Tr.pulling() or not R.grouped() or NS.mock then return end
    local due = dueNow()
    local sig = S.ser(due)
    if sig == sentDue then return end
    sentDue = sig
    S.sendCheck(due)
end

NS.listen("pullCheck", function()
    sentDue = nil
    if Tr.pulling() and #Du.mine() > 0 then NS.soon("checkSend", 2, sendCheck) end
end)
-- What's due changes as we buff, and the strips hear it.
NS.listen("tracking", function()
    if Tr.pulling() and sentDue ~= nil then NS.soon("checkSend", 3, sendCheck) end
end)

-- =============================================================
-- Events
-- =============================================================
NS.listen("login", function()
    build()
    place()
    Cv.paint()
    C_Timer.NewTicker(1, Cv.paint)
end)
NS.listen("board", function() NS.soon("coveragePaint", 0.2, Cv.paint) end)
NS.listen("roster", function() NS.soon("coveragePaint", 0.2, Cv.paint) end)
NS.listen("option", function(key)
    if key == nil or key == "coverage" then NS.soon("coveragePaint", 0.05, Cv.paint) end
    if (key == nil or key == "grow") and strip then place() end
end)

-- The setting was on or off before it said which groups. Off stays off, and
-- on is the new default, raids only.
NS.listen("loaded", function()
    local opts = NS.db and NS.db.opts
    if not opts then return end
    if opts.coverage == false then opts.coverage = "never" end
    if opts.coverage == true then opts.coverage = nil end
end)
NS.listen("checks", function() NS.soon("coveragePaint", 0.2, Cv.paint) end)
