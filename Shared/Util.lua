-- Util -- small helpers both of our addons need: hidden values, copies,
-- names, other addons, a debounce and a few words.
--
-- This file is in bayovui/shared, so BayovCore and Buff Coordinator each load
-- their own copy of it (NS.Util). Each addon keeps its old names for these
-- (Buff Coordinator's NS.secret, BayovCore's NS.Shared.copy and the rest), so
-- the code that calls them didn't have to change.

local _, NS = ...
local C_Timer = NS.Profiler and select(2, NS.Profiler.scope("shared")) or C_Timer

local U = {}
NS.Util = U

-- =============================================================
-- Hidden values
-- =============================================================
-- Forever hides some values from addons in combat, like counts and names.
-- They come back as "secret" values that we may pass on to the game but
-- never read or compare, and comparing one is an error. We look the game's
-- test up on each call, so a client that doesn't have it (anniversary) only
-- ever says no.
function U.secret(v)
    local is = _G.issecretvalue
    return is ~= nil and is(v) == true
end

-- Whether `v` is there and we may read it.
function U.readable(v)
    return v ~= nil and not U.secret(v)
end

-- A deep copy of `v`, for saved tables we hand on or keep a before of.
function U.copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = U.copy(x) end
    return t
end

-- =============================================================
-- Names
-- =============================================================
-- A unit's name, without a realm: "Ginger Olle", or nil when the name is
-- hidden or unknown.
--
-- On Forever a player has a first and a last name, and UnitName answers them
-- as two values. So its second value is the last name, never the realm.
function U.unitName(unit)
    local first, last = UnitName(unit)
    if type(first) ~= "string" or U.secret(first) or first == "" then return nil end
    if type(last) == "string" and not U.secret(last) and last ~= "" then
        return first .. " " .. last
    end
    return first
end

-- =============================================================
-- Other addons
-- =============================================================
-- Whether addon `addon` is loaded.
function U.loaded(addon)
    local is = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    return is ~= nil and is(addon) and true or false
end

-- =============================================================
-- Later, once
-- =============================================================
-- Runs `fn` once, `delay` seconds after the last call with the same `key`.
-- Each call starts the wait again, and the `fn` of the last call is the one
-- that runs. Many events can come at once, like a UNIT_AURA for each of
-- twenty players, and we only need to look once after they stop.
--
-- Some events never stop for long, like UNIT_AURA in a raid fight. So we
-- never wait longer than SOON_MAX_WAITS times `delay` (and at least a second)
-- after the first call, or a window would never refresh in combat.
local SOON_MAX_WAITS = 4
local pending = {}
function U.soon(key, delay, fn)
    local now = GetTime()
    local p = pending[key]
    if not p then
        p = { first = now, gen = 0 }
        pending[key] = p
    end
    p.gen, p.fn = p.gen + 1, fn
    local gen = p.gen
    local latest = p.first + math.max(delay * SOON_MAX_WAITS, 1)
    C_Timer.After(math.max(0, math.min(delay, latest - now)), function()
        if pending[key] ~= p or p.gen ~= gen then return end
        pending[key] = nil
        p.fn()
    end)
end

-- =============================================================
-- Words
-- =============================================================
-- "a mage", "an orc".
function U.article(word)
    return (word:find("^[AEIOUaeiou]") and "an " or "a ") .. word
end

function U.upperFirst(s)
    return s:sub(1, 1):upper() .. s:sub(2)
end

-- "Bob", "Bob and Carl", "Bob, Carl and Dan". `word` joins the last two
-- when it isn't "and", like "or".
function U.andList(list, word)
    word = word or "and"
    if #list <= 2 then return table.concat(list, " " .. word .. " ") end
    return table.concat(list, ", ", 1, #list - 1) .. " " .. word .. " " .. list[#list]
end
