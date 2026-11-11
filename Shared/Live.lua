-- Live -- countdowns the game draws for us from values it hides.
--
-- On Forever the game hides most times left from addons in combat. We can't
-- read them, compare them or print them. But we can hand them to the game's
-- own widgets, which draw them, live and exact, in or out of combat. So a
-- countdown drawn this way is right even when our own read is minutes old.
--
-- These are the small helpers both addons use for that:
--
--   Live.formatter()          the countdown's text, the way our timeText
--                             writes it ("42", "5m", "1h")
--   Live.timeColors(...)      the countdown's colour by the seconds left
--   Live.auraText(button,...) a countdown on a button of the game's aura
--                             display (an AuraContainer)
--   Live.durationText(fs)     a countdown in font string `fs` from any
--                             duration object, like a totem's
--
-- Each of them gives nil (or false) when the game doesn't have what it
-- needs, and the caller keeps its own countdown then. Nothing here needs
-- BayovCore, so Buff Coordinator loads it too.

local _, NS = ...

local L = {}
NS.Live = L

local max = math.max

local function secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- The countdown's text. The engine fills it in from the time left.
--
-- It has no tenths of a second, so the last 3 seconds read "3", "2" and "1"
-- instead of "2.5". The breakpoints are EUI's AuraKit's, with minutes rounded
-- up like ours.
local format
function L.formatter()
    if format == nil then
        format = false
        local round = Enum and Enum.NumericRuleFormatRounding
        if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and round then
            local f = C_StringUtil.CreateNumericRuleFormatter()
            local ok = pcall(f.SetBreakpoints, f, {
                { threshold = 0, format = "%d", step = 1, rounding = round.Up },
                { threshold = 60, format = "%dm", step = 1, rounding = round.Up,
                  components = { { div = 60 } } },
                { threshold = 3600, format = "%dh", step = 1, rounding = round.Down,
                  components = { { div = 3600 } } },
            })
            if ok then format = f end
        end
    end
    return format or nil
end

-- The binding property for the time left. It is 0, so "or" can't pick the
-- default.
local function remaining()
    local property = Enum and Enum.DurationTextBindingProperty
                     and Enum.DurationTextBindingProperty.RemainingDuration
    if property == nil then property = 0 end
    return property
end

-- The countdown's colour by the seconds left: `red` from `late` seconds,
-- `orange` from `warn`, and `white` above both. A threshold of 0 is off.
-- Colours are { r, g, b }. The result is what the game's bindings take as
-- their text colour, or nil when the game has no colour curves.
function L.timeColors(warn, late, white, orange, red)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local curve = C_CurveUtil.CreateColorCurve()
    if Enum and Enum.LuaCurveType then curve:SetType(Enum.LuaCurveType.Step) end
    local function add(at, c) curve:AddPoint(at, CreateColor(c[1], c[2], c[3], 1)) end
    add(0, (late > 0 and red) or (warn > 0 and orange) or white)
    if late > 0 and warn > late then add(late, orange) end
    if max(late, warn) > 0 then add(max(late, warn), white) end
    return { curve = curve, property = remaining() }
end

-- Has `button`, a button of the game's aura display, draw its aura's
-- countdown in font string `fs`, coloured by `colors` (Live.timeColors).
-- The colours are fixed when we hand it over, so the caller does it again
-- when they change.
--
-- When the engine refuses the colours, we try without them, and then with
-- no options at all, as EUI's AuraKit does. It returns whether the engine
-- took it.
function L.auraText(button, fs, colors)
    if not (button and button.SetDurationText) then return false end
    local opts = { textFormatter = L.formatter(), textColor = colors }
    local ok = pcall(button.SetDurationText, button, fs, opts)
    if not ok and opts.textColor then
        opts.textColor = nil
        ok = pcall(button.SetDurationText, button, fs, opts)
    end
    if not ok then ok = pcall(button.SetDurationText, button, fs, {}) end
    return ok
end

-- A countdown in font string `fs` from a duration object (like
-- GetTotemDuration's). It has two calls:
--
--   text:set(duration, colors)  starts counting `duration` down, coloured
--                               by `colors` (Live.timeColors) or white.
--                               Returns whether the game took it.
--   text:stop()                 stops it and empties `fs`.
--
-- It's nil when the game has no duration text bindings.
function L.durationText(fs)
    local util = _G.C_DurationUtil
    if not (util and util.CreateDurationTextBinding) then return nil end
    local ok, binding = pcall(util.CreateDurationTextBinding)
    if not ok or not binding then return nil end
    local text = { on = false }

    function text:set(duration, colors)
        -- A hidden reference may not even be compared with nil, but the
        -- binding takes it.
        if not secret(duration) and duration == nil then
            self:stop()
            return false
        end
        local done = pcall(function()
            binding:SetEnabled(false)
            binding:SetFontString(fs)
            binding:SetTextFormat("{}", { { property = remaining(), formatter = L.formatter() } })
            binding:SetZeroDurationText("")
            binding:SetExpiredText("")
            if binding.SetUpdateInterval then binding:SetUpdateInterval(0) end
            if colors then binding:SetTextColorCurve(colors.curve, colors.property) end
            binding:SetDuration(duration)
            binding:SetEnabled(true)
        end)
        self.on = done
        if not done then self:stop() end
        return done
    end

    function text:stop()
        pcall(binding.SetEnabled, binding, false)
        self.on = false
        pcall(fs.SetText, fs, "")
    end

    return text
end

-- Our totem in slot `slot` as a duration object, or nil when the game has
-- none to give. The game knows the time left in combat when we can't.
function L.totemDuration(slot)
    local get = _G.GetTotemDuration
    if not get then return nil end
    local ok, duration = pcall(get, slot)
    if not ok then return nil end
    return duration
end
