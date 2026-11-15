<p align="center">
  <img src="logo.webp" alt="Who Won That Logo" width="180" />
</p>

# Who Won That

**Who Won That** is a World of Warcraft addon that cleans up and consolidates loot rolls and results in your chat window. Instead of cluttering your chat frame with dozens of individual roll notifications, it gathers roll information and displays a single, clean, readable summary per item upon roll completion.

## Features

- **Consolidated Loot Rolls**: Combines roll attempts into a clean single line per item (e.g. `[Item] > Player won (Need 74) | OtherPlayer Greed 55, Another Pass`).
- **Winner Highlights**: Easily see who won with an intuitive crown icon (`♔`) and win status.
- **Class Colors**: Player names are colored according to their class (compatible with custom class colors such as EllesmereUI).
- **Target Chat Frame**: Route rolls and win summaries to a designated chat tab or window (e.g. Chat Frame 4 for Dungeons/Party) while keeping your main chat clean.
- **Granular Filtering**: Toggle Need, Greed, Transmog, Disenchant, and Pass visibility individually.
- **Loot Suppression**: Option to hide non-roll loot clutter (crafted items, quest rewards, normal drops) in the designated chat frame.
- **Retail & C_LootHistory Integration**: Leverages modern WoW loot history APIs with automatic chat-parsing fallback.

## In-Game Configuration

Open the Blizzard Settings menu:
`Game Menu (Esc) > Options > AddOns > Who Won That`

Or use slash commands:
- `/wwt` or `/whowonthat` - Show current status and available commands.
- `/wwt frame <1-10>` - Choose which chat window receives loot summaries.
- `/wwt format summary|raw` - Switch between single-line summary or Blizzard raw lines.
- `/wwt rolls on|off` - Toggle display of other players' rolls.
- `/wwt need on|off` - Toggle Need rolls.
- `/wwt greed on|off` - Toggle Greed rolls.
- `/wwt transmog on|off` - Toggle Transmog rolls.
- `/wwt pass on|off` - Toggle Pass notifications.
- `/wwt wins on|off` - Toggle display of winners.
- `/wwt colors on|off` - Toggle class coloring on player names.
- `/wwt others on|off` - Toggle hiding of other non-roll loot messages.
- `/wwt only <need|greed|transmog|pass>` - Show only a specific roll type.
- `/wwt test` - Display sample test roll lines.

## Installation

1. Download or clone this repository.
2. Place the `WhoWonThat` folder into your World of Warcraft directory:
   `World of Warcraft\_retail_\Interface\AddOns\WhoWonThat\`
   *(Ensure `WhoWonThat.toc` and `WhoWonThat.lua` are directly inside the `WhoWonThat` folder)*
3. Restart or reload World of Warcraft (`/reload`).

## License

[MIT](LICENSE)
