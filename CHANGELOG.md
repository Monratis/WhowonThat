# Changelog

## 4.2.0

- Removed the chat configuration commands: all settings live in the settings panel. Remaining commands: `/wwt` (open settings), `/wwt help`, `/wwt test`.

## 4.1.1

- Removed the Transmog option: Transmog rolls are no longer shown or configurable.

## 4.1.0

- `/wwt` now opens the settings panel; `/wwt help` lists the chat commands.
- Settings panel: added Disenchant toggle and buttons for the sample roll and the command list, so everything is available in the UI.

## 4.0.2

- EllesmereUI declared as an optional dependency (its class colors are used when installed).

## 4.0.1

- First public release (packaging and CI fixes on top of 4.0).

## 4.0

- First public release.
- One readable block per loot roll: item, winner with a crown, then every other player's roll.
- Per-type filters (Need / Greed / Pass), winners on/off, hide other loot messages.
- Output goes to a chat window of your choice; other windows are untouched.
- Class-colored names (EllesmereUI colors if installed); player links carry the full Name-Realm.
- Settings panel in Esc > Options > AddOns, plus `/wwt` commands and `/wwt test`.
