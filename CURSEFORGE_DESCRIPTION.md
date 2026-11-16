**Who Won That** shows who rolled what and who won your group loot rolls - in a chat window of your choice, without the "X picked up Y" spam.

In a group, the default game output for loot rolls is a stream of separate lines ("X has selected Need for: [Item]", "X rolls 74 (1-100)", "X won: [Item]") that scrolls your chat away. Who Won That collects all of it and prints a single compact, color-coded summary per item once everyone has rolled or passed. It works for Need/Greed/Pass rolls in party and raid, needs no other addon, and does not change any loot rules or rolls - it only changes how results are displayed (and, optionally, announced).

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
- **Optional group announcement** - off by default; send only your own wins, or all results, to party/raid chat. It posts the same block you see (item, winner, rolls, who passed) with raid markers, waits a random moment, never repeats an item another player's addon already posted, and an announced result is not printed again as your own block (option).
- **Class colors** - names are colored by class: your custom palette if you use one (EllesmereUI or the ClassColors addon), Blizzard's standard colors otherwise. No other addon needed.
- **Compact layout** - on a narrow chat window it uses smaller indents and shortens long names (automatic, or choose in the settings).
- **Real player links** - names are full Name-Realm links (the realm is not shown), so other chat addons can color, whisper and inspect them.
- Built on the game's loot history (`C_LootHistory`), with a chat-message fallback.

## Setup

Everything is in the settings panel: Esc > Options > AddOns > **Who Won That** (or type `/wwt`). The default window is 1 (General) - pick your party tab there.

### Choosing the chat window

Who Won That prints its block straight into the chat tab you pick in the settings, so **that tab does not need the game's *Loot* messages enabled** - and neither does any other tab. That gives you two good setups:

- **Quiet (recommended)** - turn *Loot* off in every tab (right-click the tab > Settings > Loot). The game's own roll lines ("X has selected Need", "X rolls 74", "X won") are gone everywhere, and you only see the Who Won That blocks in your chosen tab. Note that this also hides pickup lines like "You receive loot".
- **Keep pickups** - leave *Loot* on in one tab (for example General) and choose a different tab for Who Won That. Other loot messages are hidden in the chosen tab only, so that tab stays clean.

Which tab to choose: your **Party / Dungeon** tab is ideal, or create a small dedicated **Loot** tab (right-click a tab > Create New Window) and dock it next to General. A wide tab shows the full layout; on a narrow one the block switches to the compact layout automatically. The combat log and temporary (whisper) tabs are not offered.

Chat commands: `/wwt` opens the settings, `/wwt help`, `/wwt test` prints a sample roll.

## Compatibility

Made for WoW Forever (Midnight engine). Source, issues and feedback: https://github.com/Monratis/WhowonThat

MIT licensed.
