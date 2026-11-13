# Changelog

## 0.2.5

### Changed

- A buffer under half mana isn't whispered for at least a minute, so they can drink after a wipe. Clicking a buff to whisper its buffer still works.

## 0.2.4

### Changed

- Whispers go out only inside a dungeon or raid, and only to buffers in there with you.
- A "missing on" whisper names only players inside. A buffer who comes in later hears their assignments then.

### Fixed

- Hovering a target debuff in combat no longer throws a Lua error.

## 0.2.3

### Changed

- A buff that stays missing is whispered again every 5 minutes, until it's back up.

### Fixed

- Reading a hidden buff no longer logs a Lua warning.

## 0.2.2

### New

- In a party, the raid pane shows one wide box with bigger rows.
- A buffer without the addon is whispered when a buff has been missing for a minute.

### Changed

- "Runs out" whispers come in the last twentieth of the buff: 3 minutes before a 1-hour buff ends, 30 seconds before Thorns. In parties too.
- Whispers use short buff names and no counts.
- Group buffs and target debuffs follow the Flush look.

### Fixed

- Whispers no longer go to buffers across the zone. Only those within range of you get them.
- In a party, Kings no longer says DOWNRANK when someone has a low-rank Might or Wisdom in its place.

## 0.2.1

### New

- Screenshots for WowUp's Hub.

### Changed

- First full release, no longer beta.

## 0.2.0

### New

- Set your own blessing priority on the You page. Drag the three blessings left to right. Anyone can set their own, not only the leader and assistants.
- Needs shows players who set their own blessing priority, marked green.
- The You card shows your spec's art and your blessing priority.

### Changed

- Less memory churn and work in combat.

### Fixed

- Overrides no longer pile up on players who join while a plan is in use. Old empty ones are cleaned up on login.

## 0.1.0

### New

- First release on CurseForge.
