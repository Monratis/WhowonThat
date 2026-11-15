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
- **Per-type filters** - show only Need, Greed and/or Pass; winners on/off.
- **Less loot spam** - optionally hide the rest of the loot messages (picked up, crafted, quest...) in that window.
- **Class colors** - names are colored by class: your custom palette if you use one (EllesmereUI or the ClassColors addon), Blizzard's standard colors otherwise. No other addon needed.
- **Grouped by boss** - the boss name is printed once above the items of one kill.
- **Impossible Need rolls flagged** - a Need roll on armor the class cannot wear (e.g. plate for a mage) gets a red X at the end of its line (also when that player won). Weapons and jewelry are never flagged.
- **Optional group announcement** - off by default; send only your own wins, or all results, to party/raid chat. It waits a random moment, never repeats a line another player's addon already sent, and an announced result is not printed again as your own block (option).
- **Compact layout** - on a narrow chat window it uses smaller indents and shortens long names (automatic, or choose in the settings).
- **Real player links** - names are full Name-Realm links (the realm is not shown), so other chat addons can color, whisper and inspect them.
- **Original lines mode** - keep Blizzard's own roll messages, just filtered by type.
- Built on the game's loot history (`C_LootHistory`), with a chat-message fallback.

## Setup

Everything is in the settings panel: Esc > Options > AddOns > **Who Won That** (or type `/wwt`). The default window is 1 (General) - pick your party tab there. Chat commands: `/wwt` opens the settings, `/wwt help`, `/wwt test` prints a sample roll.

## Compatibility

Made for WoW Forever (Midnight engine). Source, issues and feedback: https://github.com/Monratis/WhowonThat

MIT licensed.
