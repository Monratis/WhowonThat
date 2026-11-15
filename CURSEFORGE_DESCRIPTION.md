**Who Won That** shows who rolled what and who won your group loot rolls - in a chat window of your choice, without the "X picked up Y" spam.

For every item you get one short block once the roll is finished:

```
[Worn Shortsword]
   (crown) Brakk  WON  Need 74
        Seluna  Greed 55
        Monra   Need OS 31
        Morv    Pass
```

## Features

- **Readable roll summary** - the winner first with a crown, everyone else sorted by roll.
- **Pick the chat window** - e.g. your party/dungeon tab. Other windows are never touched.
- **Per-type filters** - show only Need, Greed, Transmog and/or Pass; winners on/off.
- **Less loot spam** - optionally hide the rest of the loot messages (picked up, crafted, quest...) in that window.
- **Class colors** - uses EllesmereUI's class colors if installed, Blizzard's otherwise.
- **Real player links** - names are full Name-Realm links (the realm is not shown), so other chat addons can color, whisper and inspect them.
- **Original lines mode** - keep Blizzard's own roll messages, just filtered by type.
- Built on the game's loot history (`C_LootHistory`), with a chat-message fallback.

## Setup

Esc > Options > AddOns > **Who Won That**, or type `/wwt`.

| Command | Does |
| --- | --- |
| `/wwt` | current settings + command list |
| `/wwt config` | open the settings panel |
| `/wwt list` | list chat windows |
| `/wwt frame <number or name>` | choose the window |
| `/wwt format summary` / `raw` | readable block / Blizzard's lines |
| `/wwt need/greed/transmog/pass on/off` | toggle a roll type |
| `/wwt only need` | show only one roll type |
| `/wwt wins on/off` | show winners |
| `/wwt others on/off` | hide other loot messages |
| `/wwt colors on/off` | class colors |
| `/wwt test` | print a sample roll |

Default window is 1 (General) - pick your party tab in the settings.

## Compatibility

Made for WoW Forever (Midnight engine). Source, issues and feedback: https://github.com/Monratis/WhowonThat

MIT licensed.
