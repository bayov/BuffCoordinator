-- The auto-buffer: each click puts the next missing buff on the next player.
--
-- A HUD icon is one of the game's secure action buttons. The game only lets
-- us change what such a button casts out of combat. So just before each
-- click (PreClick) we pick who is next and set the button to cast that buff
-- on them. The game casts it, and the next click picks the next player.
--
-- In combat we can't change the button, so an icon that walks through
-- players can't walk there. When combat starts we set it to one fixed macro
-- instead, which casts its buff on whoever we hold the mouse over, or on our
-- friendly target. After combat it walks again. An icon with one fixed
-- spell, like Sunder Armor on the target or Battle Shout, never changes, so
-- it keeps working in combat. Blessings only get a mouseover when everyone
-- gets the same one from us (B.onlyBlessing).
--
-- The auto-buff button (the Next buff button on screen) is named
-- BuffCoordinatorNext, so a key can press it (Bindings.xml).

local _, NS = ...
local D, Tr = NS.Data, NS.Tracking
local readable = NS.readable
local format = string.format

-- The target clause names @target. Without it, when we have no target, the
-- game checks the Interact key's soft target instead (a friendly NPC in
-- view), and the buff goes on that NPC.
local MOUSEOVER = "/cast [@mouseover,help,nodead][@target,help,nodead] %s"

local B = {}
NS.Buffer = B

-- Whether assignment `a` walks through players (a long buff), or casts one
-- fixed spell (a debuff on the target, a shout or a totem).
function B.walks(a)
    return a.bless ~= nil or a.spare ~= nil or (a.buff and a.buff.kind == "long")
end

local function inRange(spell, unit)
    local check = C_Spell and C_Spell.IsSpellInRange or _G.IsSpellInRange
    if not check then return true end
    local ok, yes = pcall(check, spell, unit)
    if not ok or not readable(yes) then return true end
    return yes ~= false and yes ~= 0
end

-- Why we can't buff player `m` with `spell` now: "offline", "dead", "out of
-- sight" or "out of range". nil when we can.
function B.why(m, spell)
    if not m.online then return "offline" end
    if m.dead then return "dead" end
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(m.unit)
    if readable(dead) and dead then return "dead" end
    local vis = UnitIsVisible and UnitIsVisible(m.unit)
    if readable(vis) and not vis then return "out of sight" end
    if not inRange(spell, m.unit) then return "out of range" end
    return nil
end

-- Whether we can buff player `m` now: alive, online, in sight and in range.
local function reachable(m, spell)
    return B.why(m, spell) == nil
end

local spellName = Tr.spellName

-- Whether we can cast `spell` now. A group version needs a reagent, and
-- without one the game says it isn't usable. When the client can't tell us,
-- we try.
local function usable(spell)
    local check = (C_Spell and C_Spell.IsSpellUsable) or _G.IsUsableSpell
    if not check then return true end
    local ok, yes = pcall(check, spell)
    if not ok or not readable(yes) then return true end
    return yes and true or false
end
B.usable = usable

-- The reagent each group version needs, by buff: { item ID, name when the
-- game hasn't loaded the item yet }.
local REAGENT = {
    fortitude = { 17029, "Sacred Candle" },
    spirit = { 17029, "Sacred Candle" },
    shadowprot = { 17029, "Sacred Candle" },
    motw = { 17026, "Wild Thornroot" },
    intellect = { 17020, "Arcane Powder" },
}

local function itemCount(id)
    local get = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    if not get then return nil end
    local ok, n = pcall(get, id)
    if ok and readable(n) then return tonumber(n) end
end

local function itemName(r)
    local get = (C_Item and C_Item.GetItemNameByID) or _G.GetItemInfo
    local ok, name = pcall(get or function() end, r[1])
    if ok and type(name) == "string" and not NS.secret(name) and name ~= "" then return name end
    return r[2]
end

-- "no Sacred Candle" when assignments `list` would use a group version (two
-- or more missing) and we have none of its reagent, or nil. Blessings have
-- no group version on Forever.
function B.reagentNote(list)
    for _, a in ipairs(list) do
        local b = a.buff
        local r = b and b.group and REAGENT[b.id]
        if r and B.walks(a) and #Tr.status(a).missing >= 2 and itemCount(r[1]) == 0 then
            return "no " .. itemName(r)
        end
    end
    return nil
end

local function subtext(id)
    local get = (C_Spell and C_Spell.GetSpellSubtext) or _G.GetSpellSubtext
    if not get then return nil end
    local ok, text = pcall(get, id)
    if ok and type(text) == "string" and not NS.secret(text) and text ~= "" then return text end
    return nil
end

-- Whether everyone in `missing` can take the group version of `b`, like
-- Prayer of Fortitude at level 48, which a level 30 player can't.
local function groupFits(b, missing)
    local lv = b.groupRanks and b.groupRanks[2]
    if not lv then return true end
    for _, t in ipairs(missing) do
        if t.m.level and lv > t.m.level + NS.Duties.RANK_REACH then return false end
    end
    return true
end

-- What a click casts to put `b` on player `m`, as (spell, rank). The spell
-- is its name when our best rank is one they can take, and the name with
-- the rank when they're too low for it, like "Power Word: Fortitude(Rank
-- 2)". The game won't put a rank on a player more than 10 levels below it.
-- `rank` is the rank we cast, or nil for a buff without ranks. nil when
-- they're too low for every rank.
function B.rankedSpell(b, m)
    local title = Tr.title(b)
    local top = Tr.ourRank(b)
    local i, spell = Tr.ourRank(b, m)
    if not i then return title, nil end
    if i == 0 then return nil end
    if i >= top then return title, i end
    local name = spellName(spell) or title
    return format("%s(%s)", name, subtext(spell) or "Rank " .. i), i
end

-- The next { m, b, spell, cast, rank } of assignments `list` that needs a
-- buff and that we can reach, or nil. Missing buffs come before ones about
-- to run out, or of a lower rank than ours. `spell` is the buff's name, and
-- `cast` what the click casts, with a rank in it for a low player
-- (B.rankedSpell).
function B.next(list)
    for _, pass in ipairs({ false, true }) do
        for _, a in ipairs(list) do
            if B.walks(a) and a.buff and a.buff.group and not pass then
                -- Two or more missing a long buff: its group version buffs
                -- the whole raid in one cast. It still wants a friendly
                -- target in range, so we aim it at the first one missing.
                local missing = Tr.status(a).missing
                local spell = #missing >= 2 and groupFits(a.buff, missing) and spellName(a.buff.group)
                if spell and usable(spell) then
                    for _, t in ipairs(missing) do
                        if reachable(t.m, spell) then
                            return { m = t.m, b = t.b, spell = spell, all = true }
                        end
                    end
                end
            end
            if B.walks(a) then
                for _, t in ipairs(Tr.status(a).missing) do
                    -- A backup paladin has one blessing for each player too.
                    local busy = a.spare and Tr.blessedByUs(t.m.name)
                    if (t.soon or false) == pass and not busy then
                        local spell = Tr.title(t.b)
                        local cast, rank = B.rankedSpell(t.b, t.m)
                        if cast and reachable(t.m, spell) then
                            return { m = t.m, b = t.b, spell = spell, cast = cast, rank = rank, low = t.low }
                        end
                    end
                end
            elseif a.buff and not a.buff.debuff and not pass then
                -- A shout or a totem: cast when anyone it's for is missing it.
                -- An aura: turn it on when it's off.
                local st = Tr.status(a)
                local spell, macro = B.castOf(a.buff)
                if #st.missing > 0 and spell then return { b = a.buff, spell = spell, macro = macro } end
            end
        end
    end
    return nil
end

-- What a click casts for buff `b`, as (spell, macro): its own spell, or for
-- an aura what turns it on. A form goes through a macro with "!", so a click
-- while we're in it doesn't take us out of it. Nil when nothing does.
function B.castOf(b)
    if b.cast == false then return nil end
    local spell = b.cast and spellName(b.cast) or Tr.title(b)
    if not spell then return nil end
    if b.form then return spell, "/cast !" .. spell end
    return spell
end

-- The blessing we give most of assignments `list`, Kings when none.
function B.mainBlessing(list)
    local n, best, most = {}, nil, 0
    local function add(id)
        n[id] = (n[id] or 0) + 1
        if n[id] > most or (n[id] == most and best and id < best) then best, most = id, n[id] end
    end
    for _, a in ipairs(list) do
        for _, id in pairs(a.bless or {}) do add(id) end
        for _, x in ipairs(a.spare or {}) do add(x.b.id) end
    end
    return best and D.BY_ID[best] or D.BY_ID.kings
end

-- A spell's name without the words every rank shares: "Fortitude" for
-- Power Word: Fortitude, "Kings" for Blessing of Kings.
function B.short(spell)
    if type(spell) ~= "string" then return spell end
    return (spell:gsub("^Power Word: ", ""):gsub("Blessing of ", ""))
end

-- The one blessing every player of the blessing assignments in `list` gets
-- from us, or nil when they get different ones (or there are none).
--
-- In combat a blessing icon casts one fixed blessing on our mouseover. When
-- we give Kings to some and Wisdom to others, any one blessing we pick would
-- put the wrong one on half of them. So then it casts nothing.
function B.onlyBlessing(list)
    local only
    local function add(id)
        if only and only ~= id then return false end
        only = id
        return true
    end
    for _, a in ipairs(list or {}) do
        for _, id in pairs(a.bless or {}) do
            if not add(id) then return nil end
        end
        for _, x in ipairs(a.spare or {}) do
            if not add(x.b.id) then return nil end
        end
    end
    return only and D.BY_ID[only] or nil
end

-- The spell walking assignments `list` cast in combat, on our mouseover:
-- the first one's that someone is missing, else the first one's. nil when
-- none walks. The second value is true when we left out blessings because
-- we give different ones (B.onlyBlessing).
function B.combatSpell(list)
    local first, blocked
    local only = B.onlyBlessing(list)
    for _, a in ipairs(list or {}) do
        if B.walks(a) then
            local b = a.buff
            if a.bless or a.spare then
                b = only
                if not only then blocked = true end
            end
            local spell = b and Tr.title(b)
            first = first or spell
            if spell and #Tr.status(a).missing > 0 then return spell, blocked end
        end
    end
    return first, blocked
end

-- What the next-buff key casts in combat when nothing of ours walks, like a
-- warrior with only Battle Shout or a shaman with only totems: the first
-- fixed buff of `list` that someone is missing, else the first one. As
-- (spell, macro), or nil.
function B.combatFixed(list)
    local first, firstMacro
    for _, a in ipairs(list or {}) do
        if not B.walks(a) and a.buff and not a.buff.debuff then
            local spell, macro = B.castOf(a.buff)
            if spell then
                if not first then first, firstMacro = spell, macro end
                if #Tr.status(a).missing > 0 then return spell, macro end
            end
        end
    end
    return first, firstMacro
end

local function set(button, spell, unit, macro)
    button:SetAttribute("type1", macro and "macro" or spell and "spell" or nil)
    button:SetAttribute("macrotext1", macro)
    button:SetAttribute("spell1", not macro and spell or nil)
    button:SetAttribute("unit1", unit)
end

function B.keyDown()
    return GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") or false
end

-- Points `button` at the next buff of `list`. Out of combat only, and not
-- while the button is set for combat (below).
--
-- `click` says a click is about to cast it. Only then do we note who we
-- aimed at (Tr.aim), so the cast that follows counts on them
-- (Tracking.lua). The HUD aims every icon on each layout too. Noting those
-- would credit a later cast to whoever the layout aimed at, like a Fortitude
-- on our mouseover in combat landing on someone else.
function B.aim(button, list, click)
    if (InCombatLockdown and InCombatLockdown()) or button.inCombat then return end
    local n = B.next(list)
    if not n then
        set(button, nil, nil)
        if click then Tr.aim = nil end
        return nil
    end
    set(button, n.cast or n.spell, n.m and n.m.unit or nil, n.macro)
    if click then
        Tr.aim = n.m and { name = n.m.name, b = n.b, all = n.all, at = GetTime() } or nil
    end
    return n
end

-- Sets `button` to cast its one fixed spell.
local function setFixed(button)
    local fixed = button.fixed
    local spell, macro = B.castOf(fixed)
    set(button, spell, fixed.debuff and "target" or nil, macro)
end

-- Sets up a button for `list`, called when the HUD lays it out (out of
-- combat). A fixed spell is set once, and a walking one is aimed before
-- every click.
--
-- A button already set for combat keeps that until combat ends, which sets
-- it up again. Combat can start while move mode is on, say, and a layout
-- that ran after our combat handler must not aim it at a player again.
function B.setup(button, list, fixed)
    button.list = list
    button.fixed = fixed
    if InCombatLockdown and InCombatLockdown() then return end
    if not button.inCombat then
        if fixed then
            setFixed(button)
        else
            B.aim(button, list)
        end
    end
    if not button.buffHooked then
        button.buffHooked = true
        -- The button hears both halves of a click, and the game casts on
        -- the one the "cast on key down" setting says, so we aim on that one.
        button:SetScript("PreClick", function(self, mouse, down)
            if mouse ~= "LeftButton" or self.fixed then return end
            if down ~= B.keyDown() then return end
            B.aim(self, self.list or {}, true)
        end)
    end
end

-- Combat starts: every walking button casts its buff on our mouseover. The
-- game still lets us change buttons as combat starts. A button with nothing
-- that walks, like the next-buff button of a warrior with only Battle
-- Shout, casts that buff instead, so the key still does something.
--
-- What we aimed at before combat no longer says who a cast lands on. A
-- press in combat casts on our mouseover or friendly target.
--
-- It runs before every other handler of the event (Core.lua), since the game
-- only lets us change the buttons until combat starts.
NS.on("PLAYER_REGEN_DISABLED", function()
    Tr.aim = nil
    if InCombatLockdown and InCombatLockdown() then return end
    for _, button in ipairs(B.buttons or {}) do
        if not button.fixed then
            local spell, blocked = B.combatSpell(button.list)
            local fixed, macro
            if not spell and not blocked then fixed, macro = B.combatFixed(button.list) end
            button.inCombat = true
            button.mouseover, button.blocked, button.combatFixed = spell, blocked and not spell, fixed
            if spell then
                set(button, nil, nil, MOUSEOVER:format(spell))
            elseif fixed then
                set(button, fixed, nil, macro)
            else
                set(button, nil, nil)
            end
        end
    end
end, true)

-- Combat ends: they walk again. A button the HUD gave a fixed spell in
-- combat gets that now.
NS.on("PLAYER_REGEN_ENABLED", function()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, button in ipairs(B.buttons or {}) do
        if button.inCombat then
            button.inCombat, button.mouseover, button.blocked, button.combatFixed = nil, nil, nil, nil
            if button.fixed then
                setFixed(button)
            else
                B.aim(button, button.list or {})
            end
        end
    end
end)
