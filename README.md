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
- **Per-type filters** - show only Need, Greed, Transmog and/or Pass; show/hide winners.
- **Less loot spam** - optionally hide the rest of the loot messages (picked up, crafted, quest...) in that window.
- **Class colors** - uses EllesmereUI's class colors when installed, Blizzard's otherwise.
- **Full player links** - names are real `Name-Realm` player links (the realm is not displayed), so chat addons can color and whisper them.
- **Original lines mode** - `raw` format keeps Blizzard's own roll messages, just filtered by type.
- Uses the game's loot history (`C_LootHistory`) and falls back to parsing chat messages if it is unavailable.

## Installation

- **CurseForge / addon manager** - install *Who Won That*.
- **Manual** - copy the `WhoWonThat` folder to `<WoW Forever>\_forever_\Interface\AddOns\` so that
  `WhoWonThat\WhoWonThat.toc` exists, then restart the game (a new addon needs a full restart, not just `/reload`).

## Configuration

`Esc > Options > AddOns > Who Won That`, or slash commands (`/wwt` or `/whowonthat`):

| Command | What it does |
| --- | --- |
| `/wwt` | Show current settings and the command list |
| `/wwt config` | Open the settings panel |
| `/wwt list` | List chat windows with their numbers |
| `/wwt frame <number or name>` | Choose the window that shows rolls (default: window 1) |
| `/wwt format summary` / `raw` | Readable block per item, or Blizzard's original lines |
| `/wwt rolls on/off` | Show other players' rolls |
| `/wwt need/greed/transmog/pass on/off` | Toggle a single roll type |
| `/wwt only need` (or greed/transmog/pass) | Show only that roll type |
| `/wwt all` | Show all roll types |
| `/wwt wins on/off` | Show who won / that everyone passed |
| `/wwt others on/off` | Hide the other loot messages in that window |
| `/wwt colors on/off` | Class colors on names |
| `/wwt test` | Print a sample roll to the chosen window |

The addon enables the *Loot* message group in the chosen window automatically.

## Development

- `build.ps1` builds `dist/WhoWonThat-v<version>.zip` for manual installs.
- Releases to CurseForge are built by the [BigWigs packager](https://github.com/BigWigsMods/packager)
  from a `v*` git tag (see `.github/workflows` and `.pkgmeta`).

## License

[MIT](LICENSE)
