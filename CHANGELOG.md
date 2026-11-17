# Changelog

## 4.6.3

- Lighter: the chat filter no longer parses loot messages, loot-history updates are batched (one check per item instead of one per roll), and the group-chat events are only registered while announcements are on.
- Better first run: a short welcome a few seconds after login with a sample block in the chosen chat tab. `/wwt welcome` shows it again.

## 4.6.2

- Same code as 4.6.1, re-released so that the current version is the one on the project page. Loot that does not come from a boss ("Miscellaneous") shows just the item, without "Loot from:".

## 4.6.1

- A group announcement is now ONE chat line (the game accepts a single line of up to 255 characters). Rolls are grouped by type so the type is written once: `{star} Winner WON Greed 93, Second 88 - Need OS: Third 40 - Passed: Fourth`. If the group is too big, the end is cut as "+N more".
- Your own block is now ONE chat message too (one timestamp, nothing can get in between its lines).
- "Loot from: [Boss]" shares the line with the first item of the kill. Loot the game files under "Miscellaneous" (not from a boss) no longer says "Loot from: Miscellaneous"; it just shows the item.
- Players without a roll number (for example Greed when someone rolled Need) are listed on one line per type instead of one line each. The "(You)" tag is gone.
- Rolls are sorted by type first (Need, Need OS, Greed), then by number, so a high Greed no longer sits above a lower Need.
- The addon no longer changes your chat window settings (it used to add the Loot message group to the chosen window). Who Won That does not need Loot enabled anywhere; for a quiet chat turn Loot off in all tabs. A short tip explains this once after the update and in `/wwt help`.
- README and the CurseForge page explain how to choose a good chat window.

## 4.6.0

- Group announcements now post the same structure as your own block: boss line (once per kill), item, winner, everyone's rolls and who passed. They follow the Detail setting and flag impossible Need rolls.
- Raid markers stand in for colors and icons (gold star winner, orange Need, blue Greed, grey moon pass, red X cannot use), because group chat accepts neither color codes nor custom icons.
- Lines go out one at a time with a short pause, from one queue shared by all items, and stop if the game restricts addon chat.
- Detecting "someone already announced this" now works on the first line of a block, so two copies of the same item in one kill are handled correctly, and your own lines are never counted as someone else's.

## 4.5.1

- Fixed: opening the chat window list could permanently change your saved chat window to window 1 when the saved window was not shown at that moment. Your choice is now never overwritten; the main window is used until the saved one is back.
- Old unused entries from test versions are removed from the saved settings file.

## 4.5.0

- Redesigned block: item icon, colored roll types, everyone who passed on one quiet line, the winning number in green.
- Centered title ("Who Won That") with "Loot from: <boss>" under it. With DungeonJournal or AtlasLoot installed the boss name is a link that opens it.
- A Need roll the class cannot use is marked with a red X at the end of the line (also for the winner).
- Group announcements wait a random moment and never repeat a line another player's addon already sent; a result that was announced is not printed again as your own block (option).
- Settings panel reduced to the essentials in two sections: chat window, layout, detail level, announcements and a sample button. Grouping by boss, impossible-Need flags, hiding other loot and class colors are always on.
- The chat window list only offers windows you really have.

## 4.4.2

- A Need roll the player's class cannot use is now marked with a red X at the end of the line (with "can't use" next to it on a wide window). It also applies to the winner.

## 4.4.1

- Group announcements are now polite: they wait a random 2-7 seconds after the roll ends, and nothing is sent if another player's addon already announced the same item and winner.
- New option *Hide my roll block when announced* (on by default, only matters when announcements are on): a result that was announced in group chat is not printed again as your own block.

## 4.4.0

- Group by boss: the boss name is printed once above the items of one kill (option, on by default).
- Impossible Need rolls are flagged in red, e.g. a mage rolling Need on plate. Only armor and shields are checked; weapons and jewelry are never flagged (option, on by default).
- Optional announcement to party/raid chat: off, only my wins, or all results. Off by default; skipped while the game restricts addon chat.

## 4.3.2

- The winner's roll number is now green.

## 4.3.1

- The item line now starts with the addon name ("Who Won That", "WWT" on a narrow window). Can be turned off with the new *Show addon name* option.

## 4.3.0

- New Layout setting (Automatic / Normal / Compact): on a narrow chat window the block uses smaller indents and shortens long names.
- EllesmereUI is no longer declared as a dependency. Class colors still use the EllesmereUI or ClassColors palette when present, and Blizzard's standard class colors otherwise.

## 4.2.1

- The chat window list now shows only windows the player really has (shown or docked). Combat Log, temporary (whisper) windows and unused slots are not offered. A saved window that no longer exists falls back to the main chat window.

## 4.2.0

- Removed the chat configuration commands: all settings live in the settings panel. Remaining commands: `/wwt` (open settings), `/wwt help`, `/wwt test`.

## 4.1.1

- Removed the Transmog option: Transmog rolls are no longer shown or configurable.

## 4.1.0

- `/wwt` now opens the settings panel; `/wwt help` lists the chat commands.
- Settings panel: added Disenchant toggle and buttons for the sample roll and the command list, so everything is available in the UI.

## 4.0.2

- EllesmereUI declared as an optional dependency (its class colors are used when installed).

## 4.0.1

- First public release (packaging and CI fixes on top of 4.0).

## 4.0

- First public release.
- One readable block per loot roll: item, winner with a crown, then every other player's roll.
- Per-type filters (Need / Greed / Pass), winners on/off, hide other loot messages.
- Output goes to a chat window of your choice; other windows are untouched.
- Class-colored names (EllesmereUI colors if installed); player links carry the full Name-Realm.
- Settings panel in Esc > Options > AddOns, plus `/wwt` commands and `/wwt test`.
