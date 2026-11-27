<p align="center">
  <img src="logo.webp" alt="Who Won That" width="180" />
</p>

# Who Won That

Turns the flood of group loot roll lines into **a live roll window**: who rolled what, the numbers spinning in, and who won.

Made for **WoW Forever** (Midnight engine, Interface `16001`). No other addon needed.

## Features

- **Live roll window** - every roll plays out in a small window: Need / Greed / Pass choices, the numbers spinning in like a slot machine (the best one lands last) and the winner with a crown and sparks. Between rolls it lists your group with what everyone won. Opens in dungeons, raids and whenever a roll starts; matches EllesmereUI, ElvUI, TukUI or the Blizzard look. Starts above the chat - drag it anywhere, drag the corner to resize, Ctrl + mouse wheel to scale.
- **Rarity finales** - the rarer the item, the more its roll shows, always in its own quality color: grey and white stay quiet, green and blue get a light and a thin ring, purple dims the window around the last number, a legendary fades its name in with drifting embers and slow rays. With a price addon an expensive item counts its value up and gets the finale of the next rarity.
- **Roll from the window** - Need, Greed, Disenchant and Pass for every item you can roll on, right at the roll window, in place of the game's roll frames; and when you win, the addon's own loot toast in place of the game's alert. Both can be turned off.
- **A quiet chat** - the game's roll lines (who picked Need / Greed / Pass, rolled, won) are hidden in every chat tab while the roll window is on; other loot messages stay. Instead you get one short line per result, only for you: the item, who won it and the roll. Click the item to see its tooltip and replay the roll in the window.
- **Your timing** - choose how long a result stays before the window fades (10 seconds by default), or turn fading off so it stays until you close it.
- **Class-colored names** (your custom palette if you use one) and a ninja icon on ninja loot: a Need roll on an item that is not for that class (armor it can't wear, wrong main stat).
- **Your language** - settings, windows and messages follow the game's language (English, German, French, Spanish, Italian, Portuguese, Russian, Korean, Chinese) or the language you pick in the settings. Messages to the group are always in English.
- **Optional group announcement** (off by default) - all results to party/raid, next to the roll window; everyone's rolls, winner + Need/Greed, or winner only; skips items another player already posted.

## Quick start

1. Install via CurseForge, or copy the `WhoWonThat` folder to `<WoW Forever>\_forever_\Interface\AddOns\`, then restart the game.
2. Type `/wwt demo` to see the roll window and drag it where you like.
3. Type `/wwt` (or Esc > Options > AddOns > Who Won That) for the options.

## Tips

- **Dungeon loot summary:** when a dungeon ends, a small pop-up shows the top winners; click it to open a window that lists who got which items (hover for the tooltip, Shift-click to link, "Details" for the rolls). Choose Everyone / Only my items / Off in the options; `/wwt summary` reopens it.
- **Item values (optional):** with a price addon (Auctionator, TradeSkillMaster or Booty Bay Broker), the loot summary shows each item's auction value in its tooltip and the total at the bottom. Items worth less than a limit you set (default 20 silver) are left out of the roll window and group announcements.
- **Works with other addons when installed:** Auctionator, TradeSkillMaster, Booty Bay Broker (prices), GearQuest Forever (item stats for the ninja loot check), EllesmereUI / ElvUI / TukUI (the roll window's look). Nothing is needed for the addon to work.
- Commands: `/wwt` settings, `/wwt window` show / hide the roll window (`/wwt window reset` puts it back above the chat), `/wwt demo [poor..legendary] [win]` sample roll in the roll window, `/wwt test` checks roll message recognition and shows the sample windows, `/wwt summary` last dungeon summary, `/wwt help`.

## Development

- `build.ps1` builds `dist/WhoWonThat-v<version>.zip`.
- CurseForge releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager) from a `v*` tag.
- Changes: [CHANGELOG.md](CHANGELOG.md)

## Credits

- Fight IDs of the classic dungeons: [warcraft.wiki.gg DungeonEncounterID](https://warcraft.wiki.gg/wiki/DungeonEncounterID), licensed [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
- The dungeon end detection was shaped by how the Podium addon decides when a run is over.

## License

[MIT](LICENSE)
