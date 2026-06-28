# Server Structure Split

The old large `server/main.lua` has been split into these files:

- `server/db.lua` - config locals, helpers, table creation, owner resolution.
- `server/items.lua` - item definitions, item display labels/descriptions, row conversion.
- `server/slots.lua` - slot rows, weight, bag slot validation, inventory payload.
- `server/bags.lua` - metadata cleaning/decorating and serial generation.
- `server/equipment.lua` - add/remove/move/split/drop/use/equipment/weapon/ammo logic.
- `server/drops.lua` - give item, dev helpers, world drops, pickup, use progress.
- `server/events.lua` - server events and commands.
- `server/exports.lua` - exports and startup thread.

`server/main.lua` is now only a bootloader. It concatenates these modules into one Lua chunk in the same order as the original file. This avoids scope bugs from moving old `local function` code into separate FiveM server scripts.

Do not add these module files directly to `fxmanifest.lua` as separate `server_scripts`; that would break local scope.
