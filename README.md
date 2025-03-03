# CritTracker

A World of Warcraft Classic addon for tracking critical hits on spells, abilities, melee attacks, and wand shots.

## Features

- Track critical hits for:
  - Spells (including DoTs)
  - Abilities
  - Melee attacks
  - Wand shots
- Record and analyze crit statistics
- Session tracking
- Alert options:
  - Chat frame messages
  - Floating combat text
  - Sound alerts
- Group/raid announcements for impressive crits
- Slash commands for managing the addon

## Installation

1. Download the addon
2. Extract the folder to your `World of Warcraft\_classic_\Interface\AddOns` directory
3. Ensure the folder is named "CritTracker"
4. Launch the game and make sure the addon is enabled in the character selection screen

## Dependencies

None!

## Slash Commands

Use `/ct` or `/crittracker` followed by:

- `help` - Show command options

## Configuration

The addon settings can be configured through:
1. In-game interface options panel
2. Slash commands

## Notes for Developers

The addon uses the following structure:
- CritTracker.toc - Table of contents file with metadata
- CritTracker.lua - Main addon file with all functionality

The database is organized by categories (spells, abilities, melee, wand) and tracks:
- Total hits
- Critical hits
- Hit amounts
- Timestamps
- Min/max values

## License

This addon is released under the MIT License.
