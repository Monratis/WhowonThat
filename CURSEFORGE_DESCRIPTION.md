**Who Won That** shows who rolled what and who won your group loot rolls - in a chat window of your choice, without the "X picked up Y" spam.

For every item you get one short block once the roll is finished:

```
              Who Won That
        Loot from: [Edwin VanCleef]
[icon] [Worn Shortsword]
   (crown) Brakk  WON  (dice) Need 74
        Seluna  (coin) Greed 55
        Monra   (dice) Need OS 31  (red X) can't use
        (pass) Passed: Morv, Rax
```

## Features

- **Readable roll summary** - the winner first with a crown and the winning number in green, everyone else sorted by roll, those who passed on one quiet line. Roll types are colored (Need, Greed).
- **Centered title and boss** - the addon title and `Loot from: <boss>` are centered above the items of one kill. If you have DungeonJournal or AtlasLoot, the boss name is a link that opens it.
- **Pick the chat window** - choose among the chat windows you actually have, e.g. your party/dungeon tab. Other windows are never touched, and other loot messages are hidden in the chosen one.
- **Detail level** - everyone's rolls, winner and Need/Greed only, or the winner only.
- **Impossible Need rolls flagged** - a Need roll on armor the class cannot wear (e.g. plate for a mage) gets a red X at the end of its line, also when that player won. Weapons and jewelry are never flagged.
- **Optional group announcement** - off by default; send only your own wins, or all results, to party/raid chat. It waits a random moment, never repeats a line another player's addon already sent, and an announced result is not printed again as your own block (option).
- **Class colors** - names are colored by class: your custom palette if you use one (EllesmereUI or the ClassColors addon), Blizzard's standard colors otherwise. No other addon needed.
- **Compact layout** - on a narrow chat window it uses smaller indents and shortens long names (automatic, or choose in the settings).
- **Real player links** - names are full Name-Realm links (the realm is not shown), so other chat addons can color, whisper and inspect them.
- Built on the game's loot history (`C_LootHistory`), with a chat-message fallback.

## Setup

Everything is in the settings panel: Esc > Options > AddOns > **Who Won That** (or type `/wwt`). The default window is 1 (General) - pick your party tab there.

Chat commands: `/wwt` opens the settings, `/wwt help`, `/wwt test` prints a sample roll.

## Compatibility

Made for WoW Forever (Midnight engine). Source, issues and feedback: https://github.com/Monratis/WhowonThat

MIT licensed.
