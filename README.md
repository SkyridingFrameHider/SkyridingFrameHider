# SkyridingFrameHider

A World of Warcraft addon that lets you hide any frame while skyriding, flying, or mounted. Frames are made invisible (alpha set to 0) rather than hidden, and mouse interaction is disabled to prevent clicking on invisible elements.

## Commands

| Command | Description |
|---|---|
| `/sfh` or `/skyridingframehider` | Show help with all available commands |
| `/sfh add <framename>` | Add a frame to the hide list |
| `/sfh remove <framename>` | Remove a frame from the hide list |
| `/sfh list` | List all tracked frames |
| `/sfh mode` | Show current hide mode |
| `/sfh mode skyriding` | Only hide while skyriding (default) |
| `/sfh mode flying` | Hide while flying (skyriding + regular flying) |
| `/sfh mode mounted` | Hide whenever mounted |

## Modes

- **skyriding** (default) -- Frames are only hidden while actively skyriding.
- **flying** -- Frames are hidden during any type of flying, including both skyriding and regular flying.
- **mounted** -- Frames are hidden whenever you are on any mount, regardless of whether you are flying.

## Finding Frame Names

To add a frame you need its global name. You can discover frame names using:

- `/fstack` -- WoW's built-in frame stack tooltip (shows frame names on mouse hover)
- Addons that help inspect the UI

## License

GNU General Public License v3.0
