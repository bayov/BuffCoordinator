-- The buffs the group gives, the debuffs it puts on the target, which specs
-- want which, and the duties (jobs) they make.
--
-- This is the list we maintain by hand. BayovCore's Raid Buffs reads it too,
-- through BuffCoordinator.data, so a buff that's wrong here is fixed here for
-- both.
--
-- SPECS. Each class has its three talent trees in the order of the old talent
-- tabs. A spec is a role, an icon and a set of tags, and the tags are what the buffs
-- and debuffs below ask for. A rogue has no "mana" tag, so we never put
-- Arcane Intellect on one. `key` is the spec's name in FojjiCore's spec
-- messages ("FJSPEC"), which is one way we learn other players' specs.
--
--   melee     hits in melee, so wants Battle Shout, Strength of Earth, Might
--   ranged    shoots, like a hunter
--   physical  deals physical damage, melee or ranged (Trueshot, Faerie Fire)
--   caster    deals spell damage
--   healer    heals
--   tank      tanks, so wants Thorns, and Demoralizing Shout on the target
--   mana      uses mana, so wants Intellect and Wisdom
--   spirit    gets enough from spirit to want Divine Spirit
--   imbue     puts Windfury Weapon on itself (Enhancement), so doesn't want
--             the Windfury Totem
--   fire, frost, shadow, arcane, nature, holy
--             the schools it deals damage in, for the debuffs that raise one
--
-- BUFFS. Each one is something a player puts on another:
--
--   id        our key for it
--   name      what we call it, and how we find it on a unit. The game's name
--             of the first spell in `spells` wins when the game knows it.
--   class     the class that gives it
--   kind      "long" for 10 minutes and more (Fortitude, blessings), "short"
--             for shouts, totems and auras
--   spells    every spell ID that puts it on a unit, each rank and the group
--             version
--   names     more spell IDs whose names count, like the group version's
--   wants     the tags of the specs that want it. "all" is everyone.
--   unwanted  tags that rule a spec out even so, like "imbue" for the Windfury Totem
--   party     only reaches the giver's own party, like Mana Spring or an aura
--   talent    the giver needs a talent for it: their spec is that tree
--   deep      the talent is at the bottom of its tree, so only that spec
--             has it, and a player of another spec set to give it is an
--             error
--   family    buffs that one giver gives one of at a time, like blessings
--   group     for a long buff, its group version (Prayer of Fortitude). On
--             Forever it reaches every raid member within 100 yards of the
--             caster, so one cast buffs the whole raid.
--   optional  its duty is off unless turned on
--   aura      an aura: nobody casts it on anyone. The giver only keeps it up
--             (talented, in a form, or turned on), so its duty is whether the
--             giver has it.
--   cast      for an aura, the spell ID that turns it on, when that isn't the
--             aura itself (Moonkin Form), or false when nothing does (Leader
--             of the Pack comes with Cat and Bear Form)
--   form      the cast is a form, which a second cast would leave
--   how       for an aura nothing casts, how the giver keeps it up
--   ask       how we name it in a whisper, when the name alone is odd
--   tip       the spell whose game tooltip its icons show, when it isn't the
--             cast or the first of `spells`: Leader of the Pack's talent,
--             since the aura's own spell has no text, and the Imp's Blood
--             Pact, not Summon Imp
--   school    a resistance buff's school (fire, frost, nature, shadow). Two of
--             the same school don't stack, and they're only up for a fight
--             that needs them (the Resistances duty).
--   duration  how many seconds it lasts, from the client's spell data
--             (SpellMisc and SpellDuration). For a totem, how long the totem
--             stands. We count a buff we cast as up for this long until we
--             read it on a player (Tracking.lua). An aura that stays up has
--             none.
--   camp      for a blessing, the campfire feature whose buff can take its
--             place, as the text of Camp Benefits names it (Tracking.lua).
--             source: wago Spell 1229741 1.60.1.70685
--
-- DEBUFFS go on the target. `benefits` is the tags of the specs that gain
-- from it, and it is wanted when someone in the group has one. `stacks` is how
-- many it stacks to. `duration` is as for buffs, at the top rank. `clash`
-- names debuffs of different classes that don't stack with each other, like
-- Faerie Fire and Curse of Recklessness.

local _, NS = ...

local D = {}
NS.Data = D
NS.API.data = D

-- Every class, in the order the windows list them, and each one's place in
-- it to sort by.
D.CLASSES = { "WARRIOR", "ROGUE", "PALADIN", "DRUID", "SHAMAN", "HUNTER", "MAGE", "WARLOCK", "PRIEST" }
D.CLASS_RANK = {}
for i, c in ipairs(D.CLASSES) do D.CLASS_RANK[c] = i end

-- =============================================================
-- Specs
-- =============================================================
D.SPECS = {
    WARRIOR = {
        { key = "arms", role = "melee", tags = { "melee", "physical" },
          icon = [[Interface\Icons\Ability_Warrior_SavageBlow]] },
        { key = "fury", role = "melee", tags = { "melee", "physical" },
          icon = [[Interface\Icons\Ability_Warrior_InnerRage]] },
        { key = "protection", role = "tank", tags = { "tank", "melee", "physical" },
          icon = [[Interface\Icons\Ability_Warrior_DefensiveStance]] },
    },
    PALADIN = {
        { key = "holy", role = "healer", tags = { "healer", "mana" },
          icon = [[Interface\Icons\Spell_Holy_HolyBolt]] },
        { key = "protection", role = "tank", tags = { "tank", "melee", "physical", "mana", "holy" },
          icon = [[Interface\Icons\Spell_Holy_DevotionAura]] },
        { key = "retribution", role = "melee", tags = { "melee", "physical", "mana", "holy" },
          icon = [[Interface\Icons\Spell_Holy_AuraOfLight]] },
    },
    HUNTER = {
        { key = "beastmastery", role = "ranged", tags = { "ranged", "physical", "mana" },
          icon = [[Interface\Icons\Ability_Hunter_BeastTaming]] },
        { key = "marksmanship", role = "ranged", tags = { "ranged", "physical", "mana" },
          icon = [[Interface\Icons\Ability_Marksmanship]] },
        -- Forever rebuilt Survival as a melee tree around Mongoose Bite.
        { key = "survival", role = "melee", tags = { "melee", "physical", "mana" },
          icon = [[Interface\Icons\Ability_Hunter_SwiftStrike]] },
    },
    ROGUE = {
        { key = "assassination", role = "melee", tags = { "melee", "physical" },
          icon = [[Interface\Icons\Ability_Rogue_Eviscerate]] },
        { key = "combat", role = "melee", tags = { "melee", "physical" },
          icon = [[Interface\Icons\Ability_BackStab]] },
        { key = "subtlety", role = "melee", tags = { "melee", "physical" },
          icon = [[Interface\Icons\Ability_Stealth]] },
    },
    PRIEST = {
        { key = "discipline", role = "healer", tags = { "healer", "mana" },
          icon = [[Interface\Icons\Spell_Holy_WordFortitude]] },
        { key = "holy", role = "healer", tags = { "healer", "mana" },
          icon = [[Interface\Icons\Spell_Holy_HolyBolt]] },
        { key = "shadow", role = "caster", tags = { "caster", "mana", "shadow" },
          icon = [[Interface\Icons\Spell_Shadow_ShadowWordPain]] },
    },
    SHAMAN = {
        { key = "elemental", role = "caster", tags = { "caster", "mana", "nature", "fire" },
          icon = [[Interface\Icons\Spell_Nature_Lightning]] },
        { key = "enhancement", icon = [[Interface\Icons\Spell_Nature_LightningShield]], role = "melee",
          tags = { "melee", "physical", "mana", "nature", "imbue" } },
        { key = "restoration", role = "healer", tags = { "healer", "mana" },
          icon = [[Interface\Icons\Spell_Nature_MagicImmunity]] },
    },
    MAGE = {
        { key = "arcane", role = "caster", tags = { "caster", "mana", "arcane" },
          icon = [[Interface\Icons\Spell_Holy_MagicalSentry]] },
        { key = "fire", role = "caster", tags = { "caster", "mana", "fire" },
          icon = [[Interface\Icons\Spell_Fire_FireBolt02]] },
        { key = "frost", role = "caster", tags = { "caster", "mana", "frost" },
          icon = [[Interface\Icons\Spell_Frost_FrostBolt02]] },
    },
    WARLOCK = {
        { key = "affliction", role = "caster", tags = { "caster", "mana", "shadow" },
          icon = [[Interface\Icons\Spell_Shadow_DeathCoil]] },
        { key = "demonology", role = "caster", tags = { "caster", "mana", "shadow" },
          icon = [[Interface\Icons\Spell_Shadow_Metamorphosis]] },
        { key = "destruction", role = "caster", tags = { "caster", "mana", "shadow", "fire" },
          icon = [[Interface\Icons\Spell_Shadow_RainOfFire]] },
    },
    DRUID = {
        { key = "balance", role = "caster", tags = { "caster", "mana", "arcane", "nature" },
          icon = [[Interface\Icons\Spell_Nature_StarFall]] },
        -- Every shapeshift costs mana, so a feral wants it too.
        { key = "feralcombat", role = "melee", tags = { "melee", "physical", "mana" },
          icon = [[Interface\Icons\Ability_Racial_BearForm]] },
        { key = "restoration", role = "healer", tags = { "healer", "mana" },
          icon = [[Interface\Icons\Spell_Nature_HealingTouch]] },
    },
}

-- A player whose spec we don't know gets only these tags: the ones every spec
-- of their class has. Then we never ask for a buff they might not want. The
-- role the raid leader gave them (tank, healer, damage) picks a spec when it
-- says enough, like a druid tank being Feral.
D.ROLE_SPEC = {
    WARRIOR = { TANK = 3 },
    PALADIN = { TANK = 2, HEALER = 1 },
    PRIEST = { HEALER = 2, DAMAGER = 3 },
    SHAMAN = { HEALER = 3 },
    DRUID = { TANK = 2, HEALER = 3 },
}

-- =============================================================
-- Families
-- =============================================================
-- A paladin gives one blessing to each class and keeps one aura up, and a
-- warlock keeps one curse on the target. So with two paladins a warrior gets
-- two blessings, and we want the two they like best that the paladins can
-- give. A player who already has another one they want is fine with it, so
-- we don't ask a paladin to swap Might for Kings.
--
--   per     "giver" means one each per giver in reach, "one" means only one
--           of the family at all (Sunder Armor and Expose Armor don't stack)
--   order   for buffs, the order each role likes them in. A buff a role
--           doesn't list, it doesn't want. `unknown` is for a player whose
--           role we don't know, and holds only what every role wants.
--           Debuffs are ordered by how many in the group gain from each.
--   strict  the first in the data's order that someone in the group gives
--           always wins, even over another of the family that's up
--   flex    any one of the family a player wants is enough, so they miss
--           none while they have one. A paladin aura is up to each raid:
--           Retribution for damage or Devotion for defense are both fine
--           on melee, only Concentration there is a miss.
D.FAMILIES = {
    blessing = { per = "giver", order = {
        tank = { "kings", "might" },
        melee = { "kings", "might" },
        ranged = { "kings", "wisdom", "might" },
        caster = { "kings", "wisdom" },
        healer = { "kings", "wisdom" },
        unknown = { "kings" },
    } },
    paladinAura = { per = "giver", flex = true, order = {
        tank = { "devotion", "retribution" },
        melee = { "devotion", "retribution" },
        ranged = { "devotion", "retribution" },
        caster = { "devotion", "concentration" },
        healer = { "concentration", "devotion" },
        unknown = { "devotion" },
    } },
    -- The Windfury Totem comes first for melee, so a lone shaman's air totem
    -- is Windfury and we only ask for Grace of Air from a second one. Since
    -- client 70425 the two stack and both are raid-wide. An Enhancement
    -- shaman doesn't want the totem, since their own Windfury Weapon takes
    -- its place, but a lone shaman's totem is still Windfury for the others.
    airTotem = { per = "giver", order = {
        tank = { "windfury", "graceofair" },
        melee = { "windfury", "graceofair" },
    } },
    -- Warriors sunder whenever there's one, and a rogue's Expose only when
    -- there isn't, even when it's up.
    armor = { per = "one", strict = true },
    apDown = { per = "one" },
    curse = { per = "giver" },
    judgement = { per = "giver" },
}

-- =============================================================
-- Blessings by spec
-- =============================================================
-- The blessings each spec wants, most wanted first. With one paladin a
-- player gets the first, with two the first two, and so on. Kings is first
-- for everyone. Then Might for physical damage, and Wisdom for mana: casters,
-- healers and hunters, whose Might wouldn't count for shots. A Survival
-- hunter fights in melee on Forever, so Might comes before Wisdom. The leader can
-- change it for a class, a spec or one player (Duties.lua).
--
-- `class` is for a player whose spec we don't know: what most of the
-- class's specs want.
D.BLESSING_ORDER = {
    WARRIOR = { class = { "kings", "might" },
                { "kings", "might" }, { "kings", "might" },
                { "kings", "might" } },
    ROGUE = { class = { "kings", "might" } },
    HUNTER = { class = { "kings", "wisdom", "might" },
               { "kings", "wisdom", "might" }, { "kings", "wisdom", "might" },
               { "kings", "might", "wisdom" } },
    MAGE = { class = { "kings", "wisdom" } },
    WARLOCK = { class = { "kings", "wisdom" } },
    PRIEST = { class = { "kings", "wisdom" } },
    PALADIN = { class = { "kings", "wisdom", "might" },
                { "kings", "wisdom" }, { "kings", "wisdom", "might" },
                { "kings", "might", "wisdom" } },
    SHAMAN = { class = { "kings", "wisdom", "might" },
               { "kings", "wisdom" }, { "kings", "might", "wisdom" },
               { "kings", "wisdom" } },
    DRUID = { class = { "kings", "wisdom" },
              { "kings", "wisdom" }, { "kings", "might" },
              { "kings", "wisdom" } },
}

-- =============================================================
-- Buffs
-- =============================================================
-- The IDs of Fortitude, Mark of the Wild, Divine Spirit, Thorns, the
-- blessings, Arcane Intellect and Battle Shout are the ones EllesmereUI found
-- on the Forever client (EllesmereUI_BuffPresets.lua), which has some that
-- vanilla doesn't. The rest are vanilla's, and we learn more from what we
-- read on players.
-- The durations are the client's.
-- source: EllesmereUI_BuffPresets.lua and vanilla spell data 1.60.1.70755
D.BUFFS = {
    -- Long buffs
    { id = "fortitude", name = "Power Word: Fortitude", class = "PRIEST", kind = "long",
      icon = [[Interface\Icons\Spell_Holy_WordFortitude]],
      spells = { 1243, 1244, 1245, 2791, 10937, 10938, 10939, 10940, 13864, 23947, 23948,
                 21562, 21564, 450086 }, names = { 21562 }, group = 21562, wants = { "all" },
      duration = 3600 },
    { id = "motw", name = "Mark of the Wild", class = "DRUID", kind = "long",
      icon = [[Interface\Icons\Spell_Nature_Regeneration]],
      spells = { 1126, 5232, 5234, 5286, 5287, 6756, 8907, 8908, 9884, 9885, 16878, 24752,
                 364163, 1291335, 1310503, 21849, 21850 }, names = { 21849 }, group = 21849,
      wants = { "all" }, duration = 3600 },
    { id = "intellect", name = "Arcane Intellect", class = "MAGE", kind = "long",
      icon = [[Interface\Icons\Spell_Holy_MagicalSentry]],
      spells = { 1459, 1460, 1461, 10156, 10157, 13326, 16876, 364161, 23028 },
      names = { 23028 }, group = 23028, wants = { "mana" }, duration = 3600 },
    -- Baseline at level 30 on Forever, no longer a Discipline talent. Every
    -- mana user wants it: Prayer of Spirit buffs the whole raid in one cast,
    -- and Spirit refills the mana between casts (a feral's shifts, a
    -- hunter's shots), and while casting for a mage in Mage Armor.
    { id = "spirit", name = "Divine Spirit", class = "PRIEST", kind = "long",
      icon = [[Interface\Icons\Spell_Holy_DivineSpirit]],
      spells = { 14752, 14818, 14819, 16875, 27841, 27681 }, names = { 27681 }, group = 27681,
      wants = { "mana" }, duration = 3600 },
    { id = "shadowprot", name = "Shadow Protection", class = "PRIEST", kind = "long",
      icon = [[Interface\Icons\Spell_Shadow_AntiShadow]], optional = true,
      spells = { 976, 10957, 10958, 27683 }, names = { 27683 }, group = 27683, wants = { "all" },
      duration = 600 },
    { id = "thorns", name = "Thorns", class = "DRUID", kind = "long",
      icon = [[Interface\Icons\Spell_Nature_Thorns]],
      spells = { 467, 782, 1075, 8914, 9756, 9910, 15438, 16877, 21335, 21337, 22128, 22351,
                 22696, 25640, 25777, 438294, 438326, 1213813, 1213816, 1213834, 1236308,
                 1291338, 1312955 }, wants = { "tank" }, duration = 600 },

    -- The blessings. Forever has no Greater Blessings: a blessing lasts an
    -- hour and goes on one player. 1213408 is the Forever client's own
    -- copy of Kings.
    { id = "kings", name = "Blessing of Kings", class = "PALADIN", kind = "long",
      family = "blessing", icon = [[Interface\Icons\Spell_Magic_MageArmor]],
      spells = { 20217, 1213408 }, wants = { "all" }, duration = 3600, camp = "Fish Bowl" },
    { id = "might", name = "Blessing of Might", class = "PALADIN", kind = "long",
      family = "blessing", icon = [[Interface\Icons\Spell_Holy_FistOfJustice]],
      spells = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 },
      wants = { "melee" }, duration = 3600, camp = "Lodestone" },
    { id = "wisdom", name = "Blessing of Wisdom", class = "PALADIN", kind = "long",
      family = "blessing", icon = [[Interface\Icons\Spell_Holy_SealOfWisdom]],
      spells = { 19742, 19850, 19852, 19853, 19854, 25290 },
      wants = { "mana" }, duration = 3600, camp = "Mana Well" },
    -- The 2026-10-30 hotfix took Salvation, Mass Salvation and Blessing of
    -- Light away from paladins, though the client still lists them, and the
    -- 2026-11-02 development notes made it final. The tanks' own threat went
    -- up in Salvation's place (Bear Form, Defensive Stance, Righteous Fury),
    -- so nothing here stands in for it.
    -- Blessing of Sanctuary isn't in WoW Forever.

    -- Short buffs. Since client 70425 Battle Shout, the buff totems, Trueshot
    -- Aura, Leader of the Pack and Moonkin Aura reach the whole raid (the
    -- 2026-10-16 dev notes). The ones marked `party` still reach only the
    -- giver's party (the client's data: a party area aura). Sanctity Aura is
    -- gone.
    { id = "battleshout", name = "Battle Shout", class = "WARRIOR", kind = "short",
      icon = [[Interface\Icons\Ability_Warrior_BattleShout]],
      spells = { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 9128, 24438, 25101, 26043,
                 26099, 27578 }, wants = { "melee" }, duration = 180 },
    -- The totems, each of an `element`. A shaman puts down one of each, so
    -- they share them out like paladins do blessings (Duties.lua). `cast` is
    -- the spell that puts the totem down, when the buff on players has a
    -- name of its own. The IDs past the first rank are vanilla's, and we
    -- find the buff by name anyway. Windfury and Flametongue Totem never
    -- both apply on one player, even from two shamans (`excludes`). So with
    -- Windfury down, Flametongue only helps the players who don't take
    -- Windfury: an Enhancement shaman, whose own Windfury Weapon is in its
    -- place.
    { id = "strengthofearth", name = "Strength of Earth", class = "SHAMAN", kind = "short",
      element = "earth", cast = 8075, icon = [[Interface\Icons\Spell_Nature_EarthBindTotem]],
      spells = { 8076, 8162, 8163, 10441, 25362 }, names = { 8075 }, wants = { "melee" },
      duration = 300,
      ask = "Strength of Earth Totem" },
    { id = "stoneskin", name = "Stoneskin", class = "SHAMAN", kind = "short", party = true,
      element = "earth", cast = 8071, icon = [[Interface\Icons\Spell_Nature_StoneSkinTotem]],
      spells = { 8072, 8156, 8157, 10403, 10404, 10405 }, names = { 8071 }, wants = { "all" },
      duration = 300,
      ask = "Stoneskin Totem" },
    { id = "flametongue", name = "Flametongue Totem", class = "SHAMAN", kind = "short",
      element = "fire", excludes = "windfury", icon = [[Interface\Icons\Spell_Nature_GuardianWard]],
      spells = { 8227, 8249, 10526, 16387 }, wants = { "melee" }, duration = 300 },
    { id = "manaspring", name = "Mana Spring", class = "SHAMAN", kind = "short", party = true,
      element = "water", cast = 5675, icon = [[Interface\Icons\Spell_Nature_ManaRegenTotem]],
      spells = { 5677, 10491, 10493, 10494 }, names = { 5675 }, wants = { "mana" }, duration = 300,
      ask = "Mana Spring Totem" },
    { id = "healingstream", name = "Healing Stream", class = "SHAMAN", kind = "short", party = true,
      element = "water", cast = 5394, icon = [[Interface\Icons\INV_Spear_04]],
      spells = { 5672, 6371, 6372, 10460, 10461 }, names = { 5394 }, wants = { "all" }, duration = 300,
      ask = "Healing Stream Totem" },
    { id = "windfury", name = "Windfury Totem", class = "SHAMAN", kind = "short",
      element = "air", excludes = "flametongue", icon = [[Interface\Icons\Spell_Nature_Windfury]],
      spells = { 8512, 10613, 10614 }, wants = { "melee" }, duration = 300, unwanted = { "imbue" } },
    -- Agility is attack power and crit for melee and hunters alike.
    { id = "graceofair", name = "Grace of Air", class = "SHAMAN", kind = "short",
      element = "air", cast = 8835, icon = [[Interface\Icons\Spell_Nature_InvisibilityTotem]],
      spells = { 8836, 10626, 25360 }, names = { 8835 }, wants = { "physical" }, duration = 300,
      ask = "Grace of Air Totem" },
    { id = "windwall", name = "Windwall", class = "SHAMAN", kind = "short", party = true,
      element = "air", cast = 15107, icon = [[Interface\Icons\Spell_Nature_EarthBind]],
      spells = { 15108, 15109, 15110 }, names = { 15107 }, wants = { "all" }, duration = 300,
      ask = "Windwall Totem" },
    -- Forever's Trueshot Aura is ranged attack power only, so melee gain
    -- nothing from it (forever-sim's hunter notes).
    { id = "trueshot", name = "Trueshot Aura", class = "HUNTER", kind = "short", aura = true,
      talent = 2, deep = true, icon = [[Interface\Icons\Ability_TrueShot]],
      spells = { 1299346, 1299348, 19506, 20905, 20906 }, wants = { "ranged" }, duration = 1800 },
    -- Since the 2026-10-30 hotfix Leader of the Pack and Moonkin Aura are both
    -- 3% crit with everything, and one player only ever has one of the two
    -- (forever-sim's druid notes). So everyone wants them, and either is
    -- enough.
    { id = "leaderofthepack", name = "Leader of the Pack", class = "DRUID", kind = "short",
      talent = 2, deep = true, icon = [[Interface\Icons\Spell_Nature_UnyeildingStamina]],
      aura = true, cast = false, how = "It's up while you're in Cat Form or Bear Form.",
      spells = { 24932, 17007 }, tip = 17007, wants = { "all" }, excludes = "moonkin" },
    { id = "moonkin", name = "Moonkin Aura", class = "DRUID", kind = "short",
      talent = 1, deep = true, icon = [[Interface\Icons\Spell_Nature_MoonGlow]],
      aura = true, cast = 24858, form = true,
      spells = { 24907 }, wants = { "all" }, excludes = "leaderofthepack" },
    -- The Imp's. Summoning it is what turns it on.
    { id = "bloodpact", name = "Blood Pact", class = "WARLOCK", kind = "short", party = true,
      aura = true, cast = 688, icon = [[Interface\Icons\Spell_Shadow_BloodBoil]], optional = true,
      spells = { 6307, 7804, 7805, 11766, 11767 }, tip = 11767, wants = { "all" },
      ask = "your Imp's Blood Pact" },
    { id = "devotion", name = "Devotion Aura", class = "PALADIN", kind = "short", party = true,
      family = "paladinAura", aura = true, icon = [[Interface\Icons\Spell_Holy_DevotionAura]],
      spells = { 465, 10290, 643, 10291, 1032, 10292, 10293 }, wants = { "all" } },
    { id = "retribution", name = "Retribution Aura", class = "PALADIN", kind = "short",
      party = true, family = "paladinAura", aura = true, icon = [[Interface\Icons\Spell_Holy_AuraOfLight]],
      spells = { 7294, 10298, 10299, 10300, 10301 }, wants = { "tank", "melee", "ranged" } },
    { id = "concentration", name = "Concentration Aura", class = "PALADIN", kind = "short",
      party = true, family = "paladinAura", aura = true,
      icon = [[Interface\Icons\Spell_Holy_MindSooth]],
      spells = { 19746 }, wants = { "caster", "healer" } },

    -- Resistances, each raid-wide. Only one buff of a school counts: Fire
    -- Resistance Aura or Fire Resistance Totem, never both. Each takes the
    -- place of something its giver would put up otherwise (the paladin's
    -- aura, a totem of the shaman's, the hunter's own aspect), so they're
    -- only up for a fight that needs them. Shadow Protection is the priests'
    -- long buff, and counts as the shadow one.
    { id = "fireresaura", name = "Fire Resistance Aura", class = "PALADIN", kind = "short",
      family = "paladinAura", aura = true, school = "fire",
      icon = [[Interface\Icons\Spell_Fire_SealOfFire]], spells = { 19891, 19899, 19900 },
      wants = { "all" } },
    { id = "frostresaura", name = "Frost Resistance Aura", class = "PALADIN", kind = "short",
      family = "paladinAura", aura = true, school = "frost",
      icon = [[Interface\Icons\Spell_Frost_WizardMark]], spells = { 19888, 19897, 19898 },
      wants = { "all" } },
    { id = "shadowresaura", name = "Shadow Resistance Aura", class = "PALADIN", kind = "short",
      family = "paladinAura", aura = true, school = "shadow",
      icon = [[Interface\Icons\Spell_Shadow_SealOfKings]], spells = { 19876, 19895, 19896 },
      wants = { "all" } },
    { id = "fireres", name = "Fire Resistance", class = "SHAMAN", kind = "short", element = "water",
      cast = 8184, school = "fire", icon = [[Interface\Icons\Spell_FireResistanceTotem_01]],
      spells = { 8185, 10534, 10535 }, names = { 8184 }, wants = { "all" }, duration = 300,
      ask = "Fire Resistance Totem" },
    { id = "frostres", name = "Frost Resistance", class = "SHAMAN", kind = "short", element = "fire",
      cast = 8181, school = "frost", icon = [[Interface\Icons\Spell_FrostResistanceTotem_01]],
      spells = { 8182, 10476, 10477 }, names = { 8181 }, wants = { "all" }, duration = 300,
      ask = "Frost Resistance Totem" },
    { id = "natureres", name = "Nature Resistance", class = "SHAMAN", kind = "short", element = "air",
      cast = 10595, school = "nature", icon = [[Interface\Icons\Spell_Nature_NatureResistanceTotem]],
      spells = { 10596, 10598, 10599 }, names = { 10595 }, wants = { "all" }, duration = 300,
      ask = "Nature Resistance Totem" },
    -- An aspect: a second cast would turn it off, hence `form`.
    { id = "aspectofthewild", name = "Aspect of the Wild", class = "HUNTER", kind = "short",
      aura = true, cast = 20043, form = true, school = "nature",
      icon = [[Interface\Icons\Spell_Nature_ProtectionformNature]], spells = { 20043, 20190 },
      wants = { "all" } },
}

-- =============================================================
-- Debuffs on the target
-- =============================================================
-- source: vanilla spell data 1.60.1.70755
D.DEBUFFS = {
    { id = "sunder", name = "Sunder Armor", class = "WARRIOR", family = "armor", stacks = 5,
      icon = [[Interface\Icons\Ability_Warrior_Sunder]],
      spells = { 7386, 7405, 8380, 11596, 11597 }, benefits = { "physical" }, duration = 30 },
    { id = "expose", name = "Expose Armor", class = "ROGUE", family = "armor",
      icon = [[Interface\Icons\Ability_Warrior_Riposte]],
      spells = { 8647, 8649, 8650, 11197, 11198 }, benefits = { "physical" }, duration = 30 },
    { id = "faeriefire", name = "Faerie Fire", class = "DRUID", clash = "armorMinor",
      icon = [[Interface\Icons\Spell_Nature_FaerieFire]],
      spells = { 770, 778, 9749, 9907, 16857, 17390, 17391, 17392 }, names = { 16857 },
      benefits = { "physical" }, duration = 40 },
    { id = "recklessness", name = "Curse of Recklessness", class = "WARLOCK", family = "curse",
      clash = "armorMinor",
      icon = [[Interface\Icons\Spell_Shadow_UnholyStrength]],
      spells = { 704, 7658, 7659, 11717 }, benefits = { "physical" }, duration = 120 },
    { id = "elements", name = "Curse of the Elements", class = "WARLOCK", family = "curse",
      icon = [[Interface\Icons\Spell_Shadow_ChillTouch]],
      spells = { 440892, 1311676, 1311677, 1311680 },
      benefits = { "fire", "frost", "shadow", "arcane", "nature", "holy" }, duration = 300 },
    -- Only from a warlock with no other curse to put up, since it takes the
    -- place of their own Curse of Agony.
    { id = "weakness", name = "Curse of Weakness", class = "WARLOCK", family = "curse",
      optional = true, icon = [[Interface\Icons\Spell_Shadow_CurseOfMannoroth]],
      spells = { 702, 1108, 6205, 7646, 11707, 11708 }, benefits = { "tank" }, duration = 120 },
    { id = "jowisdom", learn = "Seal of Wisdom", name = "Judgement of Wisdom", class = "PALADIN", family = "judgement",
      icon = [[Interface\Icons\Spell_Holy_RighteousnessAura]],
      spells = { 20186, 20354, 20355 }, benefits = { "mana" }, duration = 40 },
    { id = "jolight", learn = "Seal of Light", name = "Judgement of Light", class = "PALADIN", family = "judgement",
      icon = [[Interface\Icons\Spell_Holy_HealingAura]],
      spells = { 20185, 20344, 20345, 20346 }, benefits = { "melee" }, duration = 40 },
    { id = "huntersmark", name = "Hunter's Mark", class = "HUNTER",
      icon = [[Interface\Icons\Ability_Hunter_SniperShot]],
      spells = { 1130, 14323, 14324, 14325 }, benefits = { "ranged" }, duration = 120 },
    { id = "jocrusader", learn = "Seal of the Crusader", name = "Judgement of the Crusader", class = "PALADIN",
      family = "judgement", optional = true, icon = [[Interface\Icons\Spell_Holy_HolySmite]],
      spells = { 21183, 20188, 20300, 20301, 20302, 20303 }, benefits = { "holy" }, duration = 40 },
    { id = "demoshout", name = "Demoralizing Shout", class = "WARRIOR", family = "apDown",
      icon = [[Interface\Icons\Ability_Warrior_WarCry]],
      spells = { 1160, 6190, 11554, 11555, 11556 }, benefits = { "tank" }, duration = 45 },
    { id = "demoroar", name = "Demoralizing Roar", class = "DRUID", family = "apDown",
      icon = [[Interface\Icons\Ability_Druid_DemoralizingRoar]],
      spells = { 99, 1735, 9490, 9747, 9898 }, benefits = { "tank" }, duration = 30 },
    { id = "thunderclap", name = "Thunder Clap", class = "WARRIOR",
      icon = [[Interface\Icons\Spell_Nature_ThunderClap]],
      spells = { 6343, 8198, 8204, 8205, 11580, 11581 }, benefits = { "tank" }, duration = 30 },
    -- Insect Swarm and Scorpid Sting both lower the target's chance to hit
    -- and don't stack. It's a druid's job, and Scorpid Sting stays off unless
    -- turned on, so we never ask a hunter.
    { id = "insectswarm", name = "Insect Swarm", class = "DRUID", talent = 1,
      clash = "hitDown", icon = [[Interface\Icons\Spell_Nature_InsectSwarm]],
      spells = { 5570, 24974, 24975, 24976, 24977 }, benefits = { "tank" }, duration = 12 },
    { id = "scorpidsting", name = "Scorpid Sting", class = "HUNTER", clash = "hitDown",
      optional = true, icon = [[Interface\Icons\Ability_Hunter_CriticalShot]],
      spells = { 3043, 14275, 14276, 14277 }, benefits = { "tank" }, duration = 20 },
}

-- Every buff and debuff by its ID, and each one knows which list it's in.
D.BY_ID = {}
for _, b in ipairs(D.BUFFS) do
    b.debuff = false
    D.BY_ID[b.id] = b
end
for _, d in ipairs(D.DEBUFFS) do
    d.debuff = true
    d.kind = "debuff"
    D.BY_ID[d.id] = d
end

-- Each buff's ranks, from RanksData.lua (bayovui/build/buffranks.py):
-- `ranks` is { spell, level, ... }, rank 1 first, and `groupRanks` the same
-- for its group version, like Prayer of Fortitude. A level of 0 is a rank a
-- talent teaches. A buff without ranks holds nobody back (Duties.lua).
do
    local data = NS.RanksData or {}
    for id, b in pairs(D.BY_ID) do
        b.ranks = data.ranks and data.ranks[id]
        b.groupRanks = data.groups and data.groups[id]
    end
end

-- =============================================================
-- Duties
-- =============================================================
-- A duty is a job and who does it. The jobs are below, in the order the
-- Assignments page lists them. `kind` says how we pick who does it:
--
--   cover     a long buff that goes on people. One giver buffs the whole raid
--             with its group version, and the others who can give it are
--             backups.
--   blessing  every paladin puts one blessing on each person, a different
--             one each, in the order the person's role likes them.
--   totem     every shaman puts down one totem of each element (D.ELEMENTS),
--             the raid-wide ones first, then ones for their own party.
--   choice    each giver puts up one of `options`, a different one each, like
--             one paladin aura per paladin, or one judgement each.
--   single    one giver for the raid, or for each party with `scope` "party".
--             With `options` of different classes (Sunder Armor or Expose
--             Armor), the first option someone on duty can give wins.
--
--   resist    for a fight that needs resistances: one giver per school the
--             fight asks for, from the cheapest source (D.SCHOOLS). It goes
--             first, and the jobs after it work around the slots it takes.
--
--   prefer    for a single job, the specs or roles we'd rather pick, best
--             first, like a tank's Sunder Armor
--   scope     "raid" (the default), "party" for a buff that only reaches
--             the giver's party, or "target" for a debuff
--   section   the heading it goes under on the Assignments page
D.ELEMENTS = { "earth", "fire", "water", "air" }

D.SECTIONS = { "Blessings", "Totems", "Long buffs", "Short buffs", "Auras", "Resistances", "Debuffs" }

-- The schools a fight can ask resistance for, and the buffs that give each,
-- the one we'd rather use first.
D.SCHOOLS = {
    { id = "fire", title = "Fire", icon = [[Interface\Icons\Spell_Fire_Fire]],
      sources = { "fireresaura", "fireres" } },
    { id = "frost", title = "Frost", icon = [[Interface\Icons\Spell_Frost_FrostNova]],
      sources = { "frostresaura", "frostres" } },
    { id = "nature", title = "Nature", icon = [[Interface\Icons\Spell_Nature_AbolishMagic]],
      sources = { "aspectofthewild", "natureres" } },
    { id = "shadow", title = "Shadow", icon = [[Interface\Icons\Spell_Shadow_AntiShadow]],
      sources = { "shadowprot", "shadowresaura" } },
}
D.SCHOOL = {}
for _, s in ipairs(D.SCHOOLS) do D.SCHOOL[s.id] = s end

D.JOBS = {
    { id = "blessings", kind = "blessing", section = "Blessings", title = "Blessings",
      options = { "kings", "might", "wisdom" } },

    -- First, so the totems and auras below work around the slots it takes.
    { id = "resistances", kind = "resist", section = "Resistances", title = "Resistances",
      options = { "fireresaura", "frostresaura", "shadowresaura", "fireres", "frostres",
                  "natureres", "aspectofthewild" } },

    { id = "totems", kind = "totem", section = "Totems", title = "Totems",
      options = { "windfury", "strengthofearth", "manaspring", "graceofair", "flametongue",
                  "healingstream", "stoneskin", "windwall" } },

    { id = "fortitude", kind = "cover", section = "Long buffs", buff = "fortitude" },
    { id = "motw", kind = "cover", section = "Long buffs", buff = "motw" },
    { id = "intellect", kind = "cover", section = "Long buffs", buff = "intellect" },
    { id = "spirit", kind = "cover", section = "Long buffs", buff = "spirit" },
    { id = "shadowprot", kind = "cover", section = "Long buffs", buff = "shadowprot" },
    { id = "thorns", kind = "cover", section = "Long buffs", buff = "thorns" },

    { id = "battleshout", kind = "single", section = "Short buffs", buff = "battleshout",
      prefer = { "fury", "arms", "protection" } },
    { id = "paladinAura", kind = "choice", section = "Auras", title = "Paladin auras",
      scope = "party", options = { "devotion", "retribution", "concentration" } },
    { id = "trueshot", kind = "single", section = "Auras", buff = "trueshot" },
    { id = "leaderofthepack", kind = "single", section = "Auras", buff = "leaderofthepack" },
    { id = "moonkin", kind = "single", section = "Auras", buff = "moonkin" },
    { id = "bloodpact", kind = "single", section = "Auras", buff = "bloodpact",
      scope = "party" },

    { id = "armor", kind = "single", section = "Debuffs", title = "Armor",
      scope = "target", options = { "sunder", "expose" }, prefer = { "tank", "protection" } },
    { id = "armorMinor", kind = "single", section = "Debuffs", title = "Minor armor",
      scope = "target", options = { "faeriefire", "recklessness" },
      prefer = { "feralcombat", "balance", "affliction" } },
    { id = "elements", kind = "single", section = "Debuffs", buff = "elements",
      scope = "target", prefer = { "affliction", "demonology", "destruction" } },
    { id = "weakness", kind = "single", section = "Debuffs", buff = "weakness",
      scope = "target", prefer = { "affliction", "demonology", "destruction" } },
    { id = "judgement", kind = "choice", section = "Debuffs", title = "Judgements",
      scope = "target", options = { "jowisdom", "jolight", "jocrusader" } },
    { id = "huntersmark", kind = "single", section = "Debuffs", buff = "huntersmark",
      scope = "target", prefer = { "marksmanship" } },
    { id = "apDown", kind = "single", section = "Debuffs", title = "Attack power down",
      scope = "target", options = { "demoshout", "demoroar" }, prefer = { "tank" } },
    { id = "thunderclap", kind = "single", section = "Debuffs", buff = "thunderclap",
      scope = "target", prefer = { "tank" } },
    { id = "hitDown", kind = "single", section = "Debuffs", title = "Hit chance down",
      scope = "target", options = { "insectswarm", "scorpidsting" }, prefer = { "balance" } },
}

-- Every job by its ID. A job's buffs are `options`, or its one `buff`. A job
-- is optional when all its buffs are (Shadow Protection, Blood Pact).
D.JOB = {}
for _, j in ipairs(D.JOBS) do
    j.options = j.options or { j.buff }
    j.scope = j.scope or "raid"
    local optional = true
    for _, id in ipairs(j.options) do
        local b = D.BY_ID[id]
        assert(b, "Data.lua: job " .. j.id .. " names an unknown buff " .. id)
        b.job = b.job or j.id
        if not b.optional then optional = false end
    end
    j.optional = optional
    D.JOB[j.id] = j
end
