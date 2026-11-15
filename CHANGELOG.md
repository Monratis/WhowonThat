# Changelog

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
