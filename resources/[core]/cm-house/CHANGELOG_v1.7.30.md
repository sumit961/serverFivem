# cm-house v1.7.30

- Uses `MarkerTypeHelicopterSymbol` (marker type 34) for house helipads.
- Guards the helipad vehicle-list callback so an out-of-date or partially restarted server reports a controlled notification instead of an ox_lib callback error.
- The `cm-house:server:helipadVehicles` callback remains registered by `server/sv_helipad.lua` through the resource manifest.
- Helipad markers are visible only to the owner or family ranks authorized by `helipad.use`.
- Reduced the helicopter-symbol marker scale from `2.5` to `1.35`.
