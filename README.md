<p align="center">
  <img src="logo.webp" alt="Who Won That" width="180" />
</p>

# Who Won That

Shows **who rolled what and who won** for group loot, in a chat window of your choice, without the pickup spam.

For every item you get one short, readable block once the roll is finished:

```
              Who Won That
        Loot from: [Edwin VanCleef]
[icon] [Worn Shortsword]
   (crown) Brakk  WON  (dice) Need 74
        Seluna  (coin) Greed 55
        Monra   (dice) Need OS 31  (red X) can't use
        (pass) Passed: Morv, Rax
```

Made for **WoW Forever** (Midnight engine, Interface `16001`).

## Features

- **Readable roll summary** - winner first with a crown and the winning number in green, everyone else sorted by roll, those who passed on one quiet line. Roll types are colored (Need, Greed).
- **Centered title and boss** - the addon title and `Loot from: <boss>` are centered above the items of one kill. If you have DungeonJournal or AtlasLoot, the boss name is a link that opens it.
- **Pick the chat window** - choose among the chat windows you actually have, e.g. your party/dungeon tab. Other windows are never touched, and other loot messages are hidden in the chosen one. See *Choosing the chat window* below.
- **Detail level** - everyone's rolls, winner and Need/Greed only, or the winner only.
- **Impossible Need rolls flagged** - a Need roll on armor the class cannot wear (e.g. plate for a mage) gets a red X at the end of its line (also when that player won). Weapons and jewelry are never flagged.
- **Optional group announcement** - off by default; send only your own wins, or all results, to party/raid chat. It posts the same block you see (item, winner, rolls, who passed) with raid markers, as a single chat line (cut with "+N more" if the group is too big). It waits a random moment and never repeats an item another player's addon already posted; an announced result is not printed again as your own block (option).
- **Class colors** - names are colored by class: your custom palette if you use one (EllesmereUI or the ClassColors addon), Blizzard's standard class colors otherwise. No other addon is required.
- **Compact layout** - on a narrow chat window the block uses smaller indents and shortens long names; automatic, or force it in the settings.
- **Full player links** - names are real `Name-Realm` player links (the realm is not displayed), so chat addons can color and whisper them.
- Uses the game's loot history (`C_LootHistory`) and falls back to parsing chat messages if it is unavailable.

## Installation

- **CurseForge / addon manager** - install *Who Won That*.
- **Manual** - copy the `WhoWonThat` folder to `<WoW Forever>\_forever_\Interface\AddOns\` so that
  `WhoWonThat\WhoWonThat.toc` exists, then restart the game (a new addon needs a full restart, not just `/reload`).

## Configuration

Everything is in the game's settings panel: `Esc > Options > AddOns > Who Won That` (or type `/wwt`).

- **Chat window** - the tab that shows the results.
- **Layout** - automatic / normal / compact.
- **Detail** - everyone's rolls / winner and Need/Greed / winner only.
- **Announce results** - off / only my wins / all results, and *hide my block when announced*.
- **Print sample roll** - a preview button.

Chat commands: `/wwt` (open settings), `/wwt help`, `/wwt test` (print a sample roll).

## Choosing the chat window

Who Won That prints its block straight into the chat tab you pick in the settings, so **that tab does not need the game's *Loot* messages enabled** - and neither does any other tab. That gives you two good setups:

- **Quiet (recommended)** - turn *Loot* off in every tab (right-click the tab > Settings > Loot). The game's own roll lines ("X has selected Need", "X rolls 74", "X won") are gone everywhere, and you only see the Who Won That blocks in your chosen tab. Note that this also hides pickup lines like "You receive loot".
- **Keep pickups** - leave *Loot* on in one tab (for example General) and choose a different tab for Who Won That. Other loot messages are hidden in the chosen tab only, so that tab stays clean.

Which tab to choose: your **Party / Dungeon** tab is ideal, or create a small dedicated **Loot** tab (right-click a tab > Create New Window) and dock it next to General. A wide tab shows the full layout; on a narrow one the block switches to the compact layout automatically. The combat log and temporary (whisper) tabs are not offered.

## Development

- `build.ps1` builds `dist/WhoWonThat-v<version>.zip` for manual installs.
- Releases to CurseForge are built by the [BigWigs packager](https://github.com/BigWigsMods/packager)
  from a `v*` git tag (see `.github/workflows` and `.pkgmeta`).

## License

[MIT](LICENSE)
