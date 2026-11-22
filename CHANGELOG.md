# Changelog

## 4.8.6

- Fixed the dungeon summary listing some players twice (once with their items, once with none) when the loot history wrote the realm after a space.

## 4.8.5

- New entry in the minimap addon menu: click it to open the settings.
- The addon description in the AddOns list is now translated into the game languages.
- Auctionator and GearQuest are declared as optional dependencies, so they load before this addon.

## 4.8.4

- The addon now shows its own icon in the in-game AddOns list.

## 4.8.3

- Loot summary: with the Auctionator addon and scanned prices, each item's auction value shows in its tooltip and the total value at the bottom of the window. A new option "Show item values" turns it off.
- Ninja loot check: when the game has no stats for an item yet, the GearQuest Forever addon's item data is used if that addon is installed.
- The dungeon end detection now uses an own, smaller dungeon book (last boss of each dungeon by fight ID and name; every boss for Ragefire Chasm and The Stockade) instead of data taken from another addon. A boss that is not the last one of a known dungeon never ends the run.
- README: credits for the source of the classic dungeon fight IDs (warcraft.wiki.gg, CC BY-SA 4.0).

## 4.8.2

- Language: the settings, the loot summary window and pop-up and the messages shown to you now follow the game's language (English, German, French, Spanish, Italian, Portuguese, Russian, Korean, Simplified and Traditional Chinese). You can also pick a language in the settings (Language). Messages sent to the group always stay in English.
- Loot summary pop-up: more ways to notice that a dungeon ended: the death message of a boss ("X dies.") now counts too, besides the fight events and the boss creature's death. Fixes the pop-up missing after Sunken Temple, where the game reports Shade of Eranikus under a new fight ID.

## 4.8.1

- Loot summary pop-up: the end of a dungeon is now recognized like Podium does it. A built-in dungeon book knows every boss, so the last boss is found by its fight ID or, when the game reports ID 0 or none (new WoW Forever dungeons), by its name. A dungeon also ends once every required boss is down, and a boss creature's death counts as a kill when the game sends no fight event.
- Ninja loot is now marked with a ninja icon instead of a red X, on the item slot in the loot summary, in the chat block and in the group announcement (the winner's line says "ninja loot" in words).

## 4.8.0

- Loot summary pop-up: the window now slides out of the button, downwards or upwards depending on where there is room on the screen.
- Loot summary pop-up: it now shows the dungeon name and what matters to you (the item you won, with its icon, or how much dropped and how many players).
- Loot summary pop-up: you can move it from Esc > Options > AddOns > Who Won That (Move pop-up button / Reset position), and from the layout editors of Blizzard's Edit Mode, EllesmereUI, ElvUI, TukUI and SpartanUI.
- Ninja loot: a Need roll on an item that is not for the winner's class (armor the class cannot wear, a shield, a bow, gun or wand it cannot use, or a primary stat that is not the class's) is marked in red in the loot summary (pulsing glow, "ninja loot" label, count in the footer) and in the chat block.
- A newer version of the addon is now announced in chat, also from guild members (not only from your group).
- The code is split into modules; Edit Mode support uses the embedded LibEditMode library.

## 4.7.2

- Loot summary pop-up redesigned: dialog-style frame with an icon, a preview of the top winners (class-colored, e.g. Monra x3 - Casandra x2) and a tooltip with everyone. It sits at the top edge of the screen, fades after 25 seconds (longer while hovered); click opens the full window, `/wwt summary` reopens it later.
- `/wwt test` now shows the pop-up (like a real dungeon end) instead of opening the window, and the sample never replaces your last real summary.

## 4.7.1

- Loot summary: at the end of a dungeon a small pulsing button (LOOT SUMMARY) appears instead of the window opening by itself. Click to open, right-click to dismiss, drag to move (position remembered), it disappears after 10 minutes.
- Loot summary: more reliable end-of-dungeon detection (also listens to BOSS_KILL, for dungeons where the boss fight event never fires). A built-in list of last bosses (by boss fight ID, language independent) is checked before the Encounter Journal, and dungeons without a single last boss (Ragefire Chasm, The Stockade) end once every boss is down. WoW Forever's own dungeons no longer end early on a side boss.

## 4.7.0

- New: a loot summary window at the end of a dungeon. One row per player with the items they won (item tiles with tooltip, Shift-click links the item, click a name to whisper), your own row highlighted, a star for the top looter, and a "Details" view with item, winner and roll. Draggable (the position is remembered), Esc closes it.
- It opens after the last boss (or the dungeon completion event, or when you leave the instance), waits for open rolls to finish and never opens during combat.
- Options: Everyone / Only my items / Off. `/wwt summary` reopens the last one, `/wwt test` shows a sample.

## 4.6.10

- Group announcement is clearer: the winner is named with "won by", every raid marker stands before the names it describes, groups are separated by ` // `, rolls are `Name:89`, and there are no Need/Greed/Pass words: `<WWT> [Item] (Boss) - won by {rt2} Winner:94 // {rt6} Second:88, Third:74 // {rt5} Fourth`.
- Fewer double announcements: the player who won the item announces first (after 1-2 s), everyone else only as a fallback (4-7 s) and only if nobody did yet.
- Players with the addon now talk to each other (addon messages, prefix `WWT`): the one who announces tells the group, so the others stay quiet and their own block is settled at once. Without other addon users, or during a boss fight, the old timings apply.
- Your own block waits up to about 10 s for someone else's announcement before it is printed, so a result is no longer shown twice.
- The chat-message fallback now also honours "Hide my block when announced".
- A quiet one-line notice when a group member runs a newer version.
- The "only my wins" announce mode is gone; a saved "mine" becomes "all".

## 4.6.9

- Group announcements write rolls as `Name:89` and use the raid markers alone (no "Need"/"Greed"/"Pass" words): `{star} Winner:93 {greed} / {greed} Second:88 / {pass} Third`.

## 4.6.8

- The result block in your chat now shows the game's own Need (dice), Greed (coin) and Pass icons instead of the words. Off-spec Need gets a small "OS" tag, and the "Passed:" / "Need:" prefixes are gone.
- Group announcements write rolls as `Name:89` instead of `Name 89`.

## 4.6.7

- The addon name in group announcements is now `<Who Won That>` the first time and `<WWT>` after that (angle brackets, so it cannot be mistaken for an item link). The older prefixes are still recognised.
- The "full name once" and "boss line once" state is only marked after the line was really sent, and it starts over with every new group.
- A very long item link plus boss name can no longer push the winner out of the announcement.

## 4.6.6

- Group announcements: the first one of a session starts with "Who Won That:", every later one with the short "WWT:". Both are recognised, so two players with the addon still do not announce the same drop twice.

## 4.6.5

- Nicer group announcement: first names only (no surnames), the winner first with the roll in brackets, then one group per roll type with its marker, separated by `/`: `{star} Winner (Need 83) / {greed} Greed: Second 71, Third 40 / {pass} Pass: Fourth`.

## 4.6.4

- Sturdier: an error from another addon while a result is being printed can no longer stop later results from showing.
- The welcome is only marked as seen once it was shown (a quick /reload after login no longer skips it).
- A roll that finished a moment before a /reload is no longer skipped; small guards against missing event data.

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
