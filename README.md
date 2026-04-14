# GamePadFlightMap

A gamepad-friendly flight point list overlay for World of Warcraft's taxi/flight map.

## Features

- Scrollable flight point list panel next to the native flight map
- Click to highlight route on map, double-click to fly
- Gamepad D-pad navigation support (up/down single step, left/right jump 5 steps)
- Search filter for flight points
- Toggle unreachable flight points visibility
- Filter out current location automatically
- ESC key to close

## Installation

1. Download or clone this repository
2. Copy the `GamePadFlightMap` folder to your WoW addon directory:
   - **Retail**: `World of Warcraft\_retail_\Interface\AddOns\`
   - **Classic**: `World of Warcraft\_classic_\Interface\AddOns\`
3. Restart WoW or reload UI (`/reload`)

## Usage

The overlay automatically appears when talking to a flight master.

### Mouse Controls

| Action | Behavior |
|--------|----------|
| Hover | Highlight item in list |
| Left Click | Select & draw route on map |
| Double Click | Fly to selected point |
| Right Click | Close flight map |
| Scroll Wheel | Navigate up/down |

### Gamepad Controls

| Button | Behavior |
|--------|----------|
| D-Pad Up/Down | Navigate list |
| D-Pad Left/Right | Jump 5 items |
| A / PAD1 | Fly to selected |
| B / PAD2 | Close flight map |
| X / PAD3 | Toggle unreachable filter |
| Y / PAD4 | Focus search box |
| Left Stick | Navigate list |

### Slash Commands

```
/gpfm debug   - Toggle debug mode
/gpfm show    - Force show overlay
/gpfm hide    - Force hide overlay
/gpfm toggle  - Toggle overlay
```

## Configuration

Saved variables are stored in `GamePadFlightMapDB`:

- `enabled` - Enable/disable the addon (default: true)
- `debugMode` - Enable debug logging (default: false)

## Compatibility

- WoW Retail 11.x (Interface 120005)
- Optional dependency: [ConsolePort](https://www.curseforge.com/wow/addons/consoleport) for enhanced gamepad support

## License

MIT
