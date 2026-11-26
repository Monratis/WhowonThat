**Who Won That** turns the flood of group loot roll lines into a small live roll window: who picked what, the numbers spinning in, and who won.

**New in 4.10:** the roll window. Every loot roll plays out like a slot machine, right above your chat, in the look of your UI. The game's roll spam is hidden in chat; other loot messages stay.

## The roll window

**While an item is rolled for:**

- The item with its type, slot and item level, over a glow in its quality color, and a countdown.
- Everyone's pick (Need / Greed / Pass) pops in as they choose. Once someone needs, the Greed players drop out at once, just like in the game.
- The numbers spin in one after another and the best one lands last. The deciding number spins longest while its row pulses.
- Your place, live: "You lead!" or "You: #2 of 4". Your row flashes red when someone takes the lead from you.
- The winner gets a crown, a flash and sparks. "Photo finish!" when it was close, and "Missed by 2" when you lost by a hair.
- Epic and better items get the big finale: a longer spin, a double burst, and they stay on screen longer.
- Several items at once are shown one after the other.

**Between rolls:**

- Everyone in your group with the items they won and the roll that won them (tooltips, Shift-click to link).
- Luck for the run: each player's average and best roll, a star for the luckiest and a skull for the unluckiest.
- With a price addon, the value of what each player won.
- A ninja loot flag on a Need win of an item the class can't use (armor, weapon type or main stat).

**Your way:**

- It opens in dungeons and raids and whenever a roll starts. Outside instances it fades away after the result.
- It starts right above your chat. Drag it anywhere, drag its corner to make it wider, Ctrl + mouse wheel to scale it.
- It can also be placed from Edit Mode, EllesmereUI Unlock Mode and the ElvUI / TukUI / SpartanUI movers.
- It matches your UI: EllesmereUI (it follows your accent color and font), ElvUI, TukUI or the Blizzard look.
- Close it and it stays away until the next roll. `/wwt window` brings it back, `/wwt demo` plays a sample roll.

## Announce to party chat

Optional, **off by default**, and it works next to the roll window. It posts all results to party/raid, so the whole group sees the same short line:

`<WWT> [Item] (Boss) - won by Winner:94 // Second:88, Third:74 // Fourth`

- Raid markers stand in for Need / Greed / Pass.
- The winner of a ninja loot gets a "ninja loot" note.
- **No spam:** players who have the addon talk to each other behind the scenes, so only one of them announces each item.

## Dungeon loot summary

When a dungeon ends, a small button slides out with the dungeon name, what you won and the top winners. Click it for the full window:

- one row per player with their items (tooltips, Shift-click to link, click a name to whisper)
- a star for the top looter, your own row highlighted
- a *Details* view with item, winner and roll
- ninja loot highlighted

`/wwt summary` reopens the last one. Everyone / Only my items / Off in the options.

## Quick start

1. Install the addon and restart the game.
2. Type `/wwt demo` to see the roll window, and drag it where you like.
3. Type `/wwt` for the options.

## More

- Announcements say as much as you like: everyone's rolls, winner + Need/Greed, or the winner only.
- Item values come from Auctionator, TradeSkillMaster, Booty Bay Broker, AuctionDB, Naowh Forever or Forever Ledger, if you have one. Cheap items below a limit you set are skipped.
- Settings and messages follow your game language (English, German, French, Spanish, Italian, Portuguese, Russian, Korean, Chinese).
- A quiet one-line notice appears when a group or guild member runs a newer version.

Works on its own, in party and raid. It only changes how rolls are shown, never the rolls.

Made for WoW Forever. Source and issues: https://github.com/Monratis/WhowonThat - MIT licensed.
