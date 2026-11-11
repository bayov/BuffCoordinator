-- Options -- everything that ACTS on a declaration table, and not one option.
--
-- BayovRotation/Options.lua opens by counting twenty-nine defaults written
-- twice and replacing them with one row that four consumers read. This file is
-- the same argument one level up. Reading a row -- parse the text, clamp it,
-- store a default as an absence, print what a key is for, generate a console
-- verb per key, hand Panel.lua an adapter -- is not a fact about the rotation,
-- and this addon has modules of its own that each wanted all of it.
--
-- So a consumer keeps its declarations, which are the part that is about it,
-- and this owns the machinery. BayovCore publishes `Options.new` as
-- `_G.BayovCore.options` beside `register` (its own Options.lua), because
-- those two are the pair another addon needs: a namespaced store and a place
-- in the console, then a way to put settings in both.
--
-- This file is in bayovui/shared, so BayovCore and Buff Coordinator each load
-- their own copy of it. It prints through Options.printer and colours with
-- Options.C, which BayovCore points at its console's (Core.printer and
-- Core.C). Buff Coordinator has no console verbs, so it leaves them as the
-- plain ones below. Options.COMMAND is the slash command a listing names.
--
-- ---------------------------------------------------------------------
-- WHAT A ROW IS
--
--   default   what the option is when nobody has set it, or a function that
--             answers it (Buff Coordinator's icon font, which depends on
--             whether EllesmereUI is loaded). A value equal to it
--             is stored as an ABSENCE rather than written down, so a default
--             corrected in source reaches a character who never touched that
--             key. A file full of values identical to the defaults is a file
--             that pins them.
--   kind      number | bool | enum
--   min max   for a number. Guard rails against a typo, not a claim about what
--             is sensible: they reject a value that would break the consumer
--             outright and stay wide everywhere else. That is why the panel
--             draws an edit box and not a slider.
--   values    for an enum: a list, or a function that answers one (Buff
--             Coordinator's fonts, which come from LibSharedMedia).
--   group     orders the console listing and names the panel's page. NOT a
--             namespace -- keys are flat, because `/bayov enemy ttl.tau 3` is
--             a worse thing to type than `/bayov enemy ttlTau 3` and the
--             grouping is only ever read.
--   name      what the settings page heads the row with. The KEY stays the
--             identity everywhere else, and the page shows it too, spelled as
--             the command that sets it.
--   desc      one sentence, printed by the console and hovered on the page.
--   order     where the row goes inside its group, lowest first. Rows
--             without one come after, alphabetical by key. A group is
--             alphabetical when no row has one.
--   section   a heading inside the group's page. The page draws it above the
--             first row of each section, so rows of one section go next to
--             each other in `order`.
--   sub       a sub-tab inside the group's page. The page draws a selector of
--             its subs above the rows and shows the rows of one at a time,
--             like each Raid Buffs widget's own settings. `subTitles` on the
--             consumer names them.
--   inherit   another key this row follows while nobody has set it, instead
--             of a `default` of its own. The icon width of Raid Buffs' "Our
--             long buffs" is the icon width for all of them until we give it
--             its own. Any value set is its own and is stored, even one equal
--             to the value it follows, so it stays put when that one changes.
--             A reset makes it follow again. A row with both has a default of
--             its own, and `inherit` does nothing.
--   home      a function that answers the table this key's value is kept
--             in, instead of `opts`. Supplies' bank alt is one of our
--             characters, and the game only mails within a realm and
--             faction. So it keeps one bank alt per realm and faction, and
--             a Horde character never sees the Alliance pick.
--
-- The rest is only how the settings page draws a row. The console reads none
-- of it, and none of it changes what a value may be.
--
--   labels    for an enum, what the page calls each value, like
--             { OUTLINE = "Thin" }. The value stays what the console takes.
--   swatches  for an enum, a colour per value, drawn in its segment.
--   icons     for an enum, a texture per value, drawn in its segment.
--   unit      for a number, a word after the edit box ("px", "s", "%"), so
--             the name doesn't have to carry it.
--   slide     for a number whose whole range is worth trying, like an
--             opacity: a slider beside the edit box. `step` is its step.
--   needs     another key this row only matters with. While that key is off
--             the row is greyed and its tooltip says why. A string is a bool
--             key that must be on, a table is { key = value } that must all
--             hold, and a function answers (met, why) for anything else.
--   master    on a bool: every other row of its section (and sub) needs it,
--             unless that row names its own `needs`. `master = "page"`
--             holds over the whole page (or sub) instead, as well as any
--             row's own `needs`.
--   drop      on an enum: always a dropdown, even when its values would fit
--             as segments. For a list that changes, like our characters.
--   advanced  folds the row away under "Advanced" at the end of its page,
--             for what hardly anyone changes.
--   pos       on an X key, the Y key it pairs with. The page draws one
--             position row with Move and Reset for the pair, and the two
--             numbers go under Advanced.
--
-- ---------------------------------------------------------------------
-- WHAT A CONSUMER SUPPLIES
--
--   name      its /bayov verb, which is also its key in the store
--   decls     the table above
--   groups    the order the console lists groups in
--   titles    what the panel's sidebar calls each group
--   subTitles what the page's sub-tab selector calls each sub
--   sectionTitles, sectionNotes
--             what the page heads a section with when it isn't the
--             section's own name, and a dim line under the heading
--   store     a function that answers the table holding `opts`, read on
--             every access, for a consumer whose store isn't there yet when
--             it declares (Buff Coordinator's NS.db). Without it, `bind`.
--   clamp     numbers past min or max are moved inside them rather than
--             refused. Buff Coordinator's sliders write that way, so a drag
--             past the end still lands on it.
--   apply     called after a set that took, with (key, value). What "the
--             consumer now reads this" means is its own business: the rotation
--             rebuilds its engine, the enemy module re-reads its upvalues and
--             restarts a ticker.
--   refuse    a sentence when a set must not happen at all, nil when it may.
--             The rotation refuses in combat, because a rebuild there costs it
--             the live GCD reading and the immunity mirror. A module that
--             applies a change by assigning a few upvalues throws nothing away
--             and so refuses nothing -- and the difference belongs to the
--             consumer rather than being a rule this file makes for everyone.
--   visible   whether a row is this CHARACTER'S at all, nil when every row is.
--             Not the same question as `refuse`: a refused set is one that
--             cannot happen now, an invisible row is one that was never on
--             offer here. BayovRotation declares one table holding every spec
--             it ships -- a shaman's rotation options and a paladin's -- and
--             answers no to the ones belonging to another class, so neither
--             the console listing nor the settings page offers a setting that
--             would do nothing. An invisible row keeps whatever a character
--             stored under it: this hides a row, it does not delete one.
--
-- Nothing here prints except the console verbs, and they print through the
-- module's own printer, so a line from an option set is indistinguishable from
-- any other line that module writes.

local ADDON, NS = ...
local format = string.format

local Options = {}
NS.Options = Options

-- The printer and the colours the console verbs print with, until the addon
-- points them at its own. Options.printer(name) answers (out, detail), two
-- functions that take a format string and its values.
local function plain(name)
    local function say(fmt, ...) print(name .. ": " .. format(fmt, ...)) end
    return say, say
end
local function same(s) return s end
Options.printer = plain
Options.C = { cmd = same, num = same, dim = same, name = same }
Options.COMMAND = "/" .. ADDON:lower()

-- Sorts a group's keys the way the console and the settings page list them:
-- by `order`, then by key.
function Options.sortKeys(keys, decls)
    table.sort(keys, function(a, b)
        local oa, ob = decls[a].order or math.huge, decls[b].order or math.huge
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    return keys
end

-- One options object, bound to one module's sub-table of the store.
--
-- Every function it answers with is a plain closure rather than a method, so
-- `adapter.get = o.get` is a reference that works. Panel.lua takes exactly
-- that shape and has no idea any of this exists.
function Options.new(spec)
    local decls = spec.decls
    assert(type(decls) == "table", "Options.new: a decls table is required")
    assert(type(spec.name) == "string",
           "Options.new: a module name is required")

    local own, detail = Options.printer(spec.name)
    local out = spec.out or own
    local C = Options.C
    local bound   -- the module's sub-table, set by bind

    -- The table holding `opts`, or nil while there's none yet.
    local function S()
        if spec.store then return spec.store() end
        return bound
    end

    local o = {
        decls = decls,
        groups = spec.groups or {},
        groupTitles = spec.titles or {},
        subTitles = spec.subTitles or {},
        sectionTitles = spec.sectionTitles or {},
        sectionNotes = spec.sectionNotes or {},
    }

    -- =========================================================
    -- Reading and writing
    -- =========================================================
    -- `store.opts` is where every value lives, so a module's other keys -- the
    -- immunity log's mobs, the swing ring's sessions -- are never something a
    -- key collision could reach.
    function o.bind(s)
        bound = s
        if bound and type(bound.opts) ~= "table" then bound.opts = {} end
        return bound
    end

    -- The table `key`'s value is kept in: its own `home`, or `opts`. nil
    -- while there's none yet.
    local function where(key)
        local decl = decls[key]
        if decl and decl.home then return decl.home() end
        local s = S()
        return s and s.opts
    end

    -- What's stored under `key`, or nil.
    local function stored(key)
        local t = where(key)
        return t and t[key]
    end

    -- What a key is while nobody has set it: its default, or the value of
    -- the key it follows.
    function o.default(key)
        local decl = decls[key]
        if not decl then return nil end
        if decl.default == nil and decl.inherit then return o.get(decl.inherit) end
        if type(decl.default) == "function" then return decl.default() end
        return decl.default
    end

    -- An enum's values, from a function when it has one.
    function o.values(key)
        local decl = decls[key]
        local v = decl and decl.values
        if type(v) == "function" then return v() end
        return v or {}
    end

    function o.get(key)
        local decl = decls[key]
        if not decl then return nil end
        local v = stored(key)
        if v == nil then return o.default(key) end
        return v
    end

    -- Whether a key is one that follows another while unset.
    local function follower(key)
        local decl = decls[key]
        return decl ~= nil and decl.default == nil and decl.inherit ~= nil
    end
    o.follower = follower

    -- Whether a key follows another one right now, rather than having a
    -- value of its own.
    function o.inherits(key)
        return follower(key) and stored(key) == nil
    end

    -- Whether this row is on offer to this character. Asked in four places --
    -- the resolved table, the generated verbs, the console listing and the
    -- panel -- rather than being applied to `decls` once, because `decls` is
    -- the identity every closure and the adapter hold, and a consumer whose
    -- answer changes (a respec, a class module loading late) would be handing
    -- out a table that no longer matches the one they are looking at.
    function o.visible(key)
        local decl = decls[key]
        if not decl then return false end
        if not spec.visible then return true end
        return spec.visible(key, decl) and true or false
    end

    -- Every option, resolved, as one flat table for a consumer to close over.
    -- Invisible rows are absent rather than defaulted: a consumer that closes
    -- over this is the thing the row was for, and one that is not this
    -- character's has nothing to configure.
    --
    -- `all` includes them anyway, and it is not a hole in the rule above --
    -- it is the rule read exactly. Visibility is about what may be READ AND
    -- SET by whoever is logged in, which is a different question from what an
    -- engine needs in order to run at all. BayovRotation asks for it when it
    -- loads another class's rotation to demonstrate: the character may not
    -- touch one of those numbers, and the engine still cannot start without
    -- every one of them.
    function o.resolved(all)
        local t = {}
        for key in pairs(decls) do
            if all or o.visible(key) then t[key] = o.get(key) end
        end
        return t
    end

    -- A number inside the key's range: (n), or (nil, why) when it's past an
    -- end and the consumer doesn't clamp.
    local function inRange(key, decl, n)
        if spec.clamp then
            if decl.min and n < decl.min then n = decl.min end
            if decl.max and n > decl.max then n = decl.max end
            return n
        end
        if decl.min and n < decl.min then
            return nil, format("%s is at least %s", key, tostring(decl.min))
        end
        if decl.max and n > decl.max then
            return nil, format("%s is at most %s", key, tostring(decl.max))
        end
        return n
    end

    -- (value) or (nil, why). The caller prints `why` and changes nothing.
    function o.parse(key, text)
        local decl = decls[key]
        if not decl then return nil, format("no option %q", key) end

        if decl.kind == "bool" then
            local t = text:lower()
            if t == "on" or t == "true" or t == "1" or t == "yes" then
                return true
            end
            if t == "off" or t == "false" or t == "0" or t == "no" then
                return false
            end
            return nil, format("%s is on or off", key)
        end

        if decl.kind == "enum" then
            -- Typed in any case, and stored as the declaration spells it.
            local t = text:lower()
            local values = o.values(key)
            for _, v in ipairs(values) do
                if v:lower() == t then return v end
            end
            return nil, format("%s is one of %s", key,
                               table.concat(values, ", "))
        end

        local n = tonumber(text)
        if not n then return nil, format("%s is a number", key) end
        return inRange(key, decl, n)
    end

    -- Writes only. Applying is `commit`'s job, because whether a write may
    -- happen at all is a decision about the consumer rather than about
    -- storage.
    function o.set(key, value)
        local t = where(key)
        if not t then return end
        if value == o.default(key) and not follower(key) then
            t[key] = nil
        else
            t[key] = value
        end
    end

    function o.reset(key)
        if key then
            local t = where(key)
            if t then t[key] = nil end
            return
        end
        local s = S()
        if not (s and s.opts) then return end
        for k, decl in pairs(decls) do
            if decl.home and o.visible(k) then
                local t = decl.home()
                if t then t[k] = nil end
            end
        end
        -- "Every option" means every option you can see. Without a visibility
        -- hook that is the whole table, and clearing it wholesale also drops
        -- keys no declaration claims any more, which is worth keeping. With
        -- one, a shaman pressing Reset All must not silently wipe what a
        -- paladin on the same account had set.
        if not spec.visible then s.opts = {} return end
        for k in pairs(decls) do
            if o.visible(k) then s.opts[k] = nil end
        end
    end

    -- Clears stored values that change nothing, and answers how many.
    --
    -- A value equal to its default still pins the option. When we later move
    -- that default in the source, like after /sync adopts a value from the
    -- game, this account keeps the old one. A key no declaration has any more
    -- does nothing at all. Both are what bayovui/build/prune.py clears from
    -- outside the game.
    function o.prune()
        local s = S()
        if not (s and s.opts) then return 0 end
        local n = 0
        for k, v in pairs(s.opts) do
            if not decls[k] or (v == o.default(k) and not follower(k)) then
                s.opts[k] = nil
                n = n + 1
            end
        end
        return n
    end

    function o.format(key)
        local v = o.get(key)
        if type(v) == "boolean" then return v and "on" or "off" end
        if type(v) == "number" then
            return (v == math.floor(v)) and tostring(math.floor(v))
                                        or format("%.2f", v)
        end
        return tostring(v)
    end

    -- A stored value equal to the default counts as the default. It changes
    -- nothing, so we don't mark it as changed. It only waits for o.prune.
    function o.isDefault(key)
        local v = stored(key)
        if v == nil then return true end
        if follower(key) then return false end
        return decls[key] ~= nil and v == o.default(key)
    end

    -- =========================================================
    -- The one write path
    -- =========================================================
    -- Named, and the reason it exists as a function is the options panel. Two
    -- ways to set an option is two chances to skip the guard, parse a value
    -- differently, or forget to apply it -- and the panel is exactly the
    -- consumer that would never notice it had, because it has no output of its
    -- own to be wrong in. Both callers come through here.
    --
    -- (true) or (false, why). Nothing is printed: the console prints, and the
    -- panel prints only failures, which is not a decision this should make for
    -- it.
    local function refuse()
        if not spec.refuse then return nil end
        return spec.refuse()
    end

    function o.commit(key, text)
        local v, why = o.parse(key, text)
        if v == nil then return false, why end
        local no = refuse()
        if no then return false, no end
        o.set(key, v)
        if spec.apply then spec.apply(key, v) end
        return true
    end

    -- The write path for a value that's already typed, like a slider's number
    -- or a toggle's flip, rather than text. It checks it as `commit` checks
    -- text: a number goes through the range, a bool is a bool, and an enum
    -- must be one of its values.
    --
    -- (true, changed) or (false, why). Unlike `commit`, it applies only when
    -- the value changed, so a slider dragged onto the value it had redraws
    -- nothing.
    function o.write(key, value)
        local decl = decls[key]
        if not decl then return false, format("no option %q", key) end
        if decl.kind == "number" then
            local n = tonumber(value)
            if not n then return false, format("%s is a number", key) end
            local why
            value, why = inRange(key, decl, n)
            if value == nil then return false, why end
        elseif decl.kind == "bool" then
            value = value and true or false
        elseif decl.kind == "enum" then
            local found = false
            for _, v in ipairs(o.values(key)) do found = found or v == value end
            if not found then return false, format("%s is one of %s", key, table.concat(o.values(key), ", ")) end
        end
        local no = refuse()
        if no then return false, no end
        local before = stored(key)
        o.set(key, value)
        if stored(key) == before then return true, false end
        if spec.apply then spec.apply(key, o.get(key)) end
        return true, true
    end

    -- nil `key` resets every option, which is what the console's bare `reset`
    -- means.
    function o.commitReset(key)
        local no = refuse()
        if no then return false, no end
        o.reset(key)
        if spec.apply then spec.apply(key, key and o.get(key) or nil) end
        return true
    end

    -- =========================================================
    -- The console
    -- =========================================================
    -- The key leads, because the key is what you just typed and what you will
    -- type again. The settings page leads with the name for the opposite
    -- reason. Both print both, so neither is a screen you cannot get from.
    function o.describe(key)
        local decl = decls[key]
        local follows = decl.default == nil and decl.inherit
        out("%s = %s%s%s", C.cmd(key), C.num(o.format(key)),
            o.isDefault(key) and " " .. C.dim(follows and ("(same as " .. follows .. ")")
                                                      or "(default)") or "",
            decl.name and "  " .. C.name(decl.name) or "")
        if follows then
            detail("      %s unless set here, now %s", C.cmd(follows),
                   C.num(tostring(o.default(key))))
        elseif decl.kind == "enum" then
            local values = {}
            for i, v in ipairs(o.values(key)) do values[i] = C.num(v) end
            detail("      one of: %s", table.concat(values, ", "))
        elseif decl.kind == "number" and (decl.min or decl.max) then
            detail("      %s to %s, default %s", C.num(tostring(decl.min)),
                   C.num(tostring(decl.max)), C.num(tostring(o.default(key))))
        else
            detail("      default %s", C.num(tostring(o.default(key))))
        end
        detail("      %s", decl.desc)
    end

    -- One verb per option key, generated, plus `list` and `reset`. The
    -- alternative is a fallback hook in Core.lua's dispatcher, and a table of
    -- names it can see is worth more than one it cannot -- `/bayov enemy` with
    -- a typo names the option it thinks you meant, which a catch-all cannot
    -- do.
    --
    -- `extra` is the module's own verbs, and a collision with a key is an
    -- error rather than a silent winner: both spellings would be typed by
    -- somebody expecting the other one.
    function o.commands(extra)
        local cmds = {}

        for key in pairs(decls) do
            cmds[key] = function(rest)
                -- The one place visibility is enforced on a write, because the
                -- console is the only way to reach a row the panel did not
                -- draw. Said with the same sentence a misspelling gets: from
                -- where you are standing a setting that belongs to another
                -- class is not a setting that exists.
                if not o.visible(key) then
                    return out("no option %s", C.name(format("%q", key)))
                end
                rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if rest == "" or rest == "help" then return o.describe(key) end
                if rest == "reset" or rest == "default" then
                    local okay, why = o.commitReset(key)
                    if not okay then return out("%s", why) end
                    return out("%s reset to %s", C.cmd(key), C.num(o.format(key)))
                end
                local okay, why = o.commit(key, rest)
                if not okay then return out("%s", why) end
                out("%s = %s", C.cmd(key), C.num(o.format(key)))
            end
        end

        cmds.list = function(rest)
            local only = rest and rest:match("^(%S+)") or nil
            local seen = {}
            local function page(group)
                local keys = {}
                for key, decl in pairs(decls) do
                    if decl.group == group and not seen[key]
                       and o.visible(key) then
                        keys[#keys + 1] = key
                        seen[key] = true
                    end
                end
                Options.sortKeys(keys, decls)
                if #keys == 0 then return end
                detail("  %s", C.name(group))
                for _, key in ipairs(keys) do
                    detail("      %-18s %s%s", key, C.num(o.format(key)),
                           o.isDefault(key) and "" or " " .. C.cmd("*"))
                end
            end

            for _, group in ipairs(o.groups) do
                if not only or only == group then page(group) end
            end
            -- Anything whose group is not in the ordered list is still
            -- printed. A new group name is a typo away from an option that
            -- exists everywhere except the listing built to show every option.
            local rest2 = {}
            for key, decl in pairs(decls) do
                if not seen[key] then rest2[decl.group or "other"] = true end
            end
            local names = {}
            for g in pairs(rest2) do names[#names + 1] = g end
            table.sort(names)
            for _, g in ipairs(names) do
                if not only or only == g then page(g) end
            end

            out("%s marks a value that is not the default. %s says what one is for.",
                C.cmd("*"), C.cmd(format("%s %s <key>", Options.COMMAND, spec.name)))
        end

        cmds.reset = function()
            local okay, why = o.commitReset(nil)
            if not okay then return out("%s", why) end
            out("every option back to its default")
        end

        for verb, fn in pairs(extra or {}) do
            assert(not decls[verb],
                   "Options: " .. spec.name .. " verb " .. verb
                   .. " is also an option key")
            cmds[verb] = fn
        end
        return cmds
    end

    -- =========================================================
    -- The settings page
    -- =========================================================
    -- Panel.lua generates the whole page from `decls`, so this is only the
    -- plumbing: how to read a value, how to write one, and when writing is
    -- refused. No option is named here, which is the point -- a new row in a
    -- declaration table appears on the page without anything else changing.
    --
    -- A module that wants pages of its own hangs them off `extras` after this
    -- comes back.
    o.adapter = {
        decls  = decls,
        groups = o.groups,
        groupTitles = o.groupTitles,
        subTitles = o.subTitles,
        sectionTitles = o.sectionTitles,
        sectionNotes = o.sectionNotes,

        get       = o.get,
        values    = o.values,
        default   = o.default,
        inherits  = o.inherits,
        follower  = o.follower,
        format    = o.format,
        isDefault = o.isDefault,
        prune     = o.prune,

        -- Asked per row rather than applied to `decls`, for the reason
        -- `o.visible` gives. Absent from an adapter whose consumer declared no
        -- hook, so a panel that never asks is a panel drawing every row.
        visible   = spec.visible and o.visible or nil,

        -- The console's own write path, verbatim, and the one for a value
        -- that's typed already.
        commit = o.commit,
        write  = o.write,
        reset  = o.commitReset,

        -- Asked before a control is touched rather than after, so the page
        -- greys out instead of refusing a click. Same condition, same
        -- sentence.
        locked = function()
            local why = refuse()
            if why then return true, why end
            return false
        end,
    }

    return o
end

-- One page for the settings of several modules, like Inventory, which shows
-- the Inventory Manager's and the bag patch's.
--
-- Each module keeps its own declarations and its own saved settings, so no
-- key moves and nothing stored changes. The joined adapter hands each key to
-- the module that declared it. The tabs are the first module's, then the
-- others'. Two modules may not declare the same key, because then a row
-- couldn't say whose it is.
--
-- `extras`, `edits` and `editLines` are read when they're asked for rather
-- than copied now, because a module may hang them off its adapter after this
-- runs.
function Options.join(...)
    local parts = { ... }
    local owner, decls, groups = {}, {}, {}
    local groupTitles, subTitles, sectionTitles, sectionNotes = {}, {}, {}, {}
    for _, a in ipairs(parts) do
        for key, decl in pairs(a.decls) do
            assert(not owner[key], "Options.join: two modules declare " .. key)
            owner[key], decls[key] = a, decl
        end
        for _, g in ipairs(a.groups or {}) do groups[#groups + 1] = g end
        for k, v in pairs(a.groupTitles or {}) do groupTitles[k] = v end
        for k, v in pairs(a.subTitles or {}) do subTitles[k] = v end
        for k, v in pairs(a.sectionTitles or {}) do sectionTitles[k] = v end
        for k, v in pairs(a.sectionNotes or {}) do sectionNotes[k] = v end
    end

    local function byKey(name)
        return function(key, ...)
            local a = owner[key]
            if not (a and a[name]) then return nil end
            return a[name](key, ...)
        end
    end

    local joined = {
        decls = decls, groups = groups, groupTitles = groupTitles, subTitles = subTitles,
        sectionTitles = sectionTitles, sectionNotes = sectionNotes,
        get = byKey("get"), default = byKey("default"), inherits = byKey("inherits"),
        values = byKey("values"), write = byKey("write"),
        follower = byKey("follower"), format = byKey("format"),
        isDefault = byKey("isDefault"), commit = byKey("commit"), reset = byKey("reset"),
        prune = function() for _, a in ipairs(parts) do a.prune() end end,
        locked = function()
            for _, a in ipairs(parts) do
                local on, why = a.locked()
                if on then return true, why end
            end
            return false
        end,
    }
    local anyVisible = false
    for _, a in ipairs(parts) do anyVisible = anyVisible or a.visible ~= nil end
    if anyVisible then
        joined.visible = function(key)
            local a = owner[key]
            if not a then return false end
            return not a.visible or a.visible(key)
        end
    end

    return setmetatable(joined, { __index = function(_, k)
        if k == "extras" then
            local all = {}
            for _, a in ipairs(parts) do
                for _, e in ipairs(a.extras or {}) do all[#all + 1] = e end
            end
            return all
        elseif k == "edits" then
            return function()
                local n = 0
                for _, a in ipairs(parts) do
                    if a.edits then n = n + (a.edits() or 0) end
                end
                return n
            end
        elseif k == "editLines" then
            return function()
                local lines = {}
                for _, a in ipairs(parts) do
                    for _, l in ipairs(a.editLines and a.editLines() or {}) do
                        lines[#lines + 1] = l
                    end
                end
                return lines
            end
        end
    end })
end

return Options
