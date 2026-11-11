-- Buff Coordinator: who puts up which raid buff and debuff.
--
-- Each assignment is a job, like Fortitude or Sunder Armor, and who does it.
-- Every assignment starts out "auto": we pick the best class, spec or
-- players for it by rules (Duties.lua). The raid leader and the assistants
-- can set someone else on it by hand.
--
-- The HUD (HUD.lua) has one icon per assignment of ours, and each icon is a
-- button that buffs the next person missing that buff. The assignments window
-- (Config.lua) is where assignments are set, with a raid pane beside them
-- (RaidPane.lua) and a page for our own settings (Settings.lua).
--
-- Everyone with the addon follows the board of one player, who "runs the
-- board" (Sync.lua). Players without rank can send the leader and the
-- assistants suggestions (Suggest.lua), and players without the addon get
-- whispers (Whisper.lua).
--
-- This file holds what every other file needs: the saved variables, our
-- printer, events and signals, the words we build sentences from, the slash
-- commands, and the public API other addons read.

local ADDON, NS = ...
local format = string.format

NS.name = ADDON
NS.title = "Buff Coordinator"

-- Our name as it shows, the way BayovCORE shows its own: one word, "Buff" in
-- white and "Coordinator" in the blue of our accent. And our logo, the B on
-- a blue hexagon that BayovCore wears too, drawn by bayovui/build/logo.py.
NS.BRAND = "Buff|cff4db8ffCoordinator|r"
NS.LOGO = [[Interface\AddOns\BuffCoordinator\Media\Logo]]

-- The public API, for other addons (BayovCore's Raid Buffs reads the
-- assignments from it).
local API = {}
_G.BuffCoordinator = API
NS.API = API

-- =============================================================
-- Shared helpers
-- =============================================================
-- Hidden values, copies and other addons are Shared/Util.lua's. Our old
-- names for them stay, since half the addon calls them.
local U = NS.Util
NS.secret, NS.readable, NS.copy, NS.loaded = U.secret, U.readable, U.copy, U.loaded

-- =============================================================
-- Printing
-- =============================================================
-- Every line we print starts with our logo and our name.
local PREFIX = "|T" .. NS.LOGO .. ":0|t " .. NS.BRAND .. ": "

function NS.print(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or fmt
    print(PREFIX .. text)
end

-- A player's name in their class colour, for a printed line.
function NS.classColored(name, class)
    local c = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    if not c then return name end
    return format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end

-- "E.D." for Elowen Duskwhisper: the first letters of the first and last
-- names.
function NS.initials(name)
    local first, last = name:match("^(%S+).-(%S+)$")
    if not first then return name:sub(1, 1):upper() .. "." end
    return (first:sub(1, 1) .. "." .. last:sub(1, 1) .. "."):upper()
end

-- Text with an icon before it, for a menu entry or a tooltip line. An icon
-- from Interface\Icons has a border, which we crop as T.icon does.
function NS.iconText(tex, text, size)
    if not tex then return text end
    size = size or 14
    return format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t %s", tex, size, size, text)
end

-- A player for a menu or a tooltip: their spec's icon, or their class's
-- when we don't know the spec, then their name in their class colour.
-- `m` is a member or a name, and `text` stands in for the name if given.
function NS.who(m, text)
    local name = type(m) == "table" and m.name or m
    local x = type(m) == "table" and m or NS.Roster.known(name) or {}
    local class = x.class
    local spec = class and x.spec and NS.Data.SPECS[class] and NS.Data.SPECS[class][x.spec]
    local tex = spec and spec.icon or class and NS.Theme.classIcon(class)
    return NS.iconText(tex, NS.classColored(text or name, class))
end

-- A buff with its icon: "[icon] Blessing of Kings", or `text` after it.
function NS.buffText(b, text)
    if not b then return text end
    return NS.iconText(NS.Tracking.icon(b), text or NS.Tracking.title(b))
end

-- A class or a spec with its icon, before `text`.
function NS.classText(class, text)
    return NS.iconText(NS.Theme.classIcon(class), text)
end

function NS.specText(class, tree, text)
    local s = NS.Data.SPECS[class] and NS.Data.SPECS[class][tree]
    return NS.iconText(s and s.icon or NS.Theme.classIcon(class), text)
end

-- =============================================================
-- Saved variables
-- =============================================================
-- BuffCoordinatorDB is account-wide, so the assignments a raid team set up
-- last week are there on every character.
--
--   opts      our settings (Options.lua), a default stored as an absence
--   duty      what's set by hand, by job (Duties.lua)
--   people    everyone we grouped with: { class, spec, seen }
--   specs     specs set by hand, by player name
--   plans     the saved plans by name (Plans.lua)
--   planFor   the plan for each instance, by instance ID (Plans.lua)
--   instances the instances we zoned into last, newest first (Plans.lua)
--   planFolders  the folders plans sort into, in order (Plans.lua)
--   planFolder   the folder of each plan, by plan name (Plans.lua)
--   pins      the players of the real raid the leader keeps in their party
--             (Arrange.lua)
--   coverage  where the coverage strip sits (Coverage.lua)
--   kept      the buffs we read, kept over a /reload (Tracking.lua)
--   remote    the board of whoever else runs it, kept over a /reload
--             (Sync.lua): { duty, specs, host, closed, at }
--   hud       where the HUD sits
--   window    where the assignments window sits, its size and whether it
--             was resized (sized), which page it shows (page), whether the
--             raid pane is folded (raidFolded), Not needed is open
--             (idleOpen), and which class Needs shows (specFilter, or
--             "players" or "all"). Saves from before have needsTab, from
--             when Needs had tabs, youShut, autoOpen, autoTab and
--             overridesShut, from when You, Auto and Overrides were parts
--             of one page that folded away, blessEdit, from the blessing table, assign, from the Paladin
--             Overrides window, overrides, priority and buffsBySpec, where
--             the Overrides, Blessing Priority and Buffs by Spec windows
--             were left, offOpen, from the Turned off fold, buffPriority and
--             wantedBuffs, the Buffs by Spec window's old names, and getAll,
--             from when You get hid the raid-wide buffs.
--   mock      the mock raid (Mock.lua): made-up players and its own
--             assignments. Saves from before called it planner or sandbox.
--   minimap   where our minimap button sits on the minimap's edge and whether it hides (LibDBIcon's minimapPos and hide)
--   hints     the one-time lines we printed: on the first login (login) and
--             the first time we joined a group (group)
--   whispers  what we last whispered each player without the addon, and who
--             we introduced the addon to, kept over a /reload while we run
--             the board (Whisper.lua): { said, introduced, at }
--
-- `version` 2 is All three's icon sizes (Options.lua's O.shareSame).
local DB_VERSION = 2

local function fresh(t, k)
    if type(t[k]) ~= "table" then t[k] = {} end
    return t[k]
end

function NS.loadDB()
    local db = _G.BuffCoordinatorDB
    if type(db) ~= "table" then db = {} end
    _G.BuffCoordinatorDB = db
    local version = db.version or DB_VERSION
    db.version = DB_VERSION
    fresh(db, "opts")
    if version < 2 then NS.Options.shareSame(db.opts) end
    -- The HUD's Scale setting is gone. It only moved the icons around, since
    -- the HUD's position scales with it, and Icon width and height size them.
    db.opts.hudScale = nil
    -- Forever has no Greater Blessings, so their setting is gone.
    db.opts.useGreater = nil
    -- "Hide when solo" became "Show the HUD": Always, In groups or Never.
    -- Hiding when solo was the default, so only an "off" was ever stored,
    -- and that is Always.
    if db.opts.hideSolo == false and db.opts.showHud == nil then db.opts.showHud = "always" end
    db.opts.hideSolo = nil
    fresh(db, "duty")
    -- Settings of jobs that are gone, like the air totems and Mana Spring
    -- before the totems became one job.
    for id in pairs(db.duty) do
        if not NS.Data.JOB[id] then db.duty[id] = nil end
    end
    fresh(db, "people")
    fresh(db, "specs")
    -- The talent buffs we saw each player give. Nothing reads them since the
    -- board stopped going by what only our own client saw.
    db.gives = nil
    fresh(db, "hud")
    fresh(db, "window")
    -- The blessing table, the Paladin Overrides window and the Overrides
    -- window are the Overrides page now. Blessing Priority and Buffs by Spec
    -- are tabs of Needs, where what's turned off is turned on again.
    db.window.blessEdit, db.window.assign, db.window.overrides, db.window.offOpen = nil, nil, nil, nil
    db.window.priority, db.window.buffsBySpec = nil, nil
    db.window.buffPriority, db.window.wantedBuffs, db.window.getAll = nil, nil, nil
    -- You, Auto and Overrides were parts of the Assignments page that folded
    -- away. They're pages of their own now, Auto is Needs, and its tabs are
    -- one page and Resistances.
    db.window.youShut, db.window.autoOpen, db.window.autoTab, db.window.overridesShut = nil, nil, nil, nil
    db.window.needsTab = nil
    fresh(db, "minimap")
    fresh(db, "hints")
    NS.db = db
    return db
end

-- The assignments and hand-set specs the group goes by, as { duty, specs }.
--
-- When we run the board (Sync.lua), or while we're solo, that's our own saved
-- ones. When someone else runs it, it's their copy, which Sync.lua keeps in
-- NS.remote, so our own setup is still there for the next group we lead.
-- In a mock raid (Mock.lua) it's the mock's own. What we send and
-- take from the group always goes by the group's (NS.groupState).
function NS.groupState()
    return NS.remote or NS.db
end

function NS.state()
    if NS.mock then return NS.db.mock end
    return NS.groupState()
end

-- The state the window shows and edits.
--
-- A player who can't change the assignments may draft a suggestion
-- (Suggest.lua). Their window then shows and edits `NS.draft`. Everything else (the board,
-- the HUD, the whispers and what we send) still goes by the group's state,
-- so the work that does runs inside `NS.asGroup`.
local grouping = 0

function NS.edited()
    if NS.draft and grouping == 0 then return NS.draft end
    return NS.state()
end

local function leaveGroup(ok, ...)
    grouping = grouping - 1
    if not ok then error((...), 0) end
    return ...
end

-- Runs `fn(...)` reading the group's state even while we draft.
function NS.asGroup(fn, ...)
    grouping = grouping + 1
    return leaveGroup(pcall(fn, ...))
end

-- The state an edit goes into: the group's when we may change it, a draft
-- when we may only suggest, or nil when the assignments are locked for us.
function NS.writable()
    if NS.Suggest then return NS.Suggest.target() end
    return NS.state()
end

-- =============================================================
-- Events
-- =============================================================
local frame = CreateFrame("Frame")
local handlers = {}

-- Runs `fn(event, ...)` on `event`. Several files may listen to one event.
-- Registering an event the client doesn't have is an error, and we listen
-- to a few that only some clients have (TRAIT_CONFIG_UPDATED), so we try.
--
-- Handlers run in the order they were added, which is the .toc's order of
-- the files. `first` puts `fn` before the others, for a handler that has to
-- run before anything else can go wrong (Buffer.lua's combat swap).
function NS.on(event, fn, first)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(list, first and 1 or #list + 1, fn)
end

-- An error in one handler goes to the game's error handler, and the
-- handlers after it still run. Otherwise a bug in Tracking.lua's combat
-- handler would leave Buffer.lua's buttons aimed at players all fight.
frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, event, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Our own signals between files, like "board" when the board changed.
local signals = {}

function NS.listen(signal, fn)
    signals[signal] = signals[signal] or {}
    table.insert(signals[signal], fn)
end

function NS.signal(signal, ...)
    for _, fn in ipairs(signals[signal] or {}) do fn(...) end
end

-- Runs `fn` once, `delay` seconds after the last call with the same `key`
-- (Shared/Util.lua).
NS.soon = NS.Util.soon

-- =============================================================
-- Start
-- =============================================================
NS.on("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    NS.loadDB()
    NS.signal("loaded")
end)

NS.on("PLAYER_LOGIN", function()
    NS.signal("login")
end)

-- =============================================================
-- Words
-- =============================================================
-- "a mage", "Bob and Carl" and the first letter in capitals are
-- Shared/Util.lua's.
NS.article, NS.upperFirst, NS.andList = NS.Util.article, NS.Util.upperFirst, NS.Util.andList

-- A class's name as the game shows it: "Warrior".
function NS.className(class)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    return (names and names[class]) or (class:sub(1, 1) .. class:sub(2):lower())
end

-- A class as a word for its players, in the middle of a sentence: "warriors".
function NS.classWord(class)
    return NS.className(class):lower() .. "s"
end

-- A member's rank as a word: "leader", "assistant", or nil for neither.
function NS.rankWord(m)
    if m.rank == 2 then return "leader" end
    if m.rank == 1 then return "assistant" end
    return nil
end

-- What our words mean, in the words a player sees. /bbc help prints the
-- ones marked `help`, and the window's legend shows them all, so the two
-- always say the same thing. What the colours mean is Theme.lua's T.LEGEND,
-- which the legend shows under these.
NS.GLOSSARY = {
    { word = "Assignment", text = "Who puts up a buff or debuff, like Fortitude or Sunder Armor." },
    { word = "Auto", help = true,
      text = "The addon picks who does what, so everyone gets what they want most." },
    { word = "Needs", text = "What each spec or player wants, blessings in order. Set on the Needs page. Auto aims for it, and a change there never warns." },
    { word = "Override", help = true,
      text = "What a player is set to give, by hand. Auto works around it, and warns when it costs someone a buff." },
    { word = "Assignments Leader",
      text = "The player everyone's assignments come from. The leader if they have the addon, else an assistant, else the first player with it." },
    { word = "Draft", help = true,
      text = "Without rank, your changes stay in a draft only you see. Send it to the leader and assistants as a suggestion." },
    { word = "Suggestion", text = "A draft you sent to the leader and assistants." },
    { word = "Backup", text = "A player who steps in when a buff has been missing for a while." },
}

-- =============================================================
-- Slash commands
-- =============================================================
local commands = {}

-- Adds `/bbc <word>`. `fn(rest)` gets the rest of the line.
function NS.command(word, help, fn)
    commands[#commands + 1] = { word = word, help = help, fn = fn }
end

local function slash(line)
    local word, rest = (line or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = word:lower()
    if word == "" then
        if NS.Config then NS.Config.toggle() end
        return
    end
    if word == "help" then return NS.help() end
    for _, c in ipairs(commands) do
        if c.word == word then return c.fn(rest) end
    end
    NS.print("Unknown command '%s'.", word)
    NS.help()
end

-- Prints the commands, and what the words in the window mean.
function NS.help()
    NS.print("Commands:")
    print(format("  %s - open or close the window", NS.SLASH))
    for _, c in ipairs(commands) do print(format("  %s %s - %s", NS.SLASH, c.word, c.help)) end
    print(format("  %s help - this list", NS.SLASH))
    for _, g in ipairs(NS.GLOSSARY) do
        if g.help then print(format("  %s: %s", g.word, g.text)) end
    end
end

-- The command we tell players to type. It's /bc once login gives it to us
-- (below), and /bbc while BayovCore or another addon has /bc.
NS.SLASH = "/bbc"

_G.SLASH_BUFFCOORDINATOR1 = "/bbc"
_G.SLASH_BUFFCOORDINATOR2 = "/buffco"
_G.SLASH_BUFFCOORDINATOR3 = "/buffcoordinator"
_G.SlashCmdList.BUFFCOORDINATOR = slash

-- /bc as well, for players without BayovCore, whose /bc opens its own
-- window. BayovCore adds its /bc at login only when no other addon has it,
-- so we wait for login too and take it only when BayovCore isn't loaded and
-- nobody else has it.

local function taken(cmd)
    for key, value in pairs(_G) do
        if type(key) == "string" and type(value) == "string" and key:find("^SLASH_")
           and value:lower() == cmd then
            return true
        end
    end
    return false
end

NS.listen("login", function()
    if NS.loaded("BayovCore") or taken("/bc") then return end
    _G.SLASH_BUFFCOORDINATORBC1 = "/bc"
    _G.SlashCmdList.BUFFCOORDINATORBC = slash
    NS.SLASH = "/bc"
end)

-- =============================================================
-- First run
-- =============================================================
-- A new player sees nothing of us while solo: the HUD waits for a group.
-- So we say once that we're here and how to open us, and once more the
-- first time they join a group, when the HUD shows up.
local WELCOME_AFTER = 5

local function groupHint()
    local hints = NS.db and NS.db.hints
    -- The welcome goes first, a few seconds after login.
    if not hints or not hints.login or hints.group then return end
    if not (NS.Roster and NS.Roster.real.grouped()) then return end
    hints.group = true
    NS.print("Your assignments in this group show on the HUD. %s shows everyone's.", NS.SLASH)
end

NS.listen("login", function()
    local hints = NS.db.hints
    C_Timer.After(WELCOME_AFTER, function()
        if not hints.login then
            hints.login = true
            NS.print("Buff Coordinator is installed. Type %s or click the minimap button.", NS.SLASH)
        end
        groupHint()
    end)
end)

NS.on("GROUP_ROSTER_UPDATE", groupHint)
