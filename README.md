<p align="center">
  <img src="logo.webp" alt="Who Won That" width="180" />
</p>

# Who Won That

Shows **who rolled what and who won** for group loot, in a chat window of your choice, without the pickup spam.

For every item you get one short, readable block once the roll is finished:

```
[Worn Shortsword]
   (crown) Brakk  WON  (dice) Need 74
        Seluna  (coin) Greed 55
        Monra   (dice) Need OS 31
        Morv    (pass) Pass
```

Made for **WoW Forever** (Midnight engine, Interface `16001`).

## Features

- **Readable roll summary** - winner first with a crown icon, everyone else sorted by roll.
- **Choose the window** - send rolls to e.g. your party/dungeon tab; other chat windows are not touched.
- **Per-type filters** - show only Need, Greed and/or Pass; show/hide winners.
- **Less loot spam** - optionally hide the rest of the loot messages (picked up, crafted, quest...) in that window.
- **Class colors** - names are colored by class: your custom palette if you use one (EllesmereUI or the ClassColors addon), Blizzard's standard class colors otherwise. No other addon is required.
- **Grouped by boss** - the boss name is printed once above the items of one kill.
- **Impossible Need rolls flagged** - a Need roll on armor the class cannot wear (e.g. plate for a mage) is marked in red. Weapons and jewelry are never flagged.
- **Optional group announcement** - off by default; send only your own wins, or all results, to party/raid chat.
- **Compact layout** - on a narrow chat window the block uses smaller indents and shortens long names; automatic, or force it in the settings.
- **Full player links** - names are real `Name-Realm` player links (the realm is not displayed), so chat addons can color and whisper them.
- **Original lines mode** - `raw` format keeps Blizzard's own roll messages, just filtered by type.
- Uses the game's loot history (`C_LootHistory`) and falls back to parsing chat messages if it is unavailable.

## Installation

- **CurseForge / addon manager** - install *Who Won That*.
- **Manual** - copy the `WhoWonThat` folder to `<WoW Forever>\_forever_\Interface\AddOns\` so that
  `WhoWonThat\WhoWonThat.toc` exists, then restart the game (a new addon needs a full restart, not just `/reload`).

## Configuration

Everything is configured in the game's settings panel: `Esc > Options > AddOns > Who Won That`
(or type `/wwt` to open it). Options:

- chat window that shows the rolls, and the output format (readable block / Blizzard's original lines)
- show other players' rolls, with separate Need / Greed / Disenchant / Pass toggles
- show who won
- hide other loot messages in that window
- group by boss, flag impossible Need rolls
- announce to group chat: off / only my wins / all results (off by default)
- class colors on names
- addon name in front of each item line (on/off)
- layout: automatic / normal / compact (for small chat windows)
- a *Print sample roll* button to preview the output

Chat commands: `/wwt` (open settings), `/wwt help`, `/wwt test` (print a sample roll).

The addon enables the *Loot* message group in the chosen window automatically.

## Development

- `build.ps1` builds `dist/WhoWonThat-v<version>.zip` for manual installs.
- Releases to CurseForge are built by the [BigWigs packager](https://github.com/BigWigsMods/packager)
  from a `v*` git tag (see `.github/workflows` and `.pkgmeta`).

## License

[MIT](LICENSE)
