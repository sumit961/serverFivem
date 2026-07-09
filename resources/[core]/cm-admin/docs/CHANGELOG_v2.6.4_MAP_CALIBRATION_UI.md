# CM Admin v2.6.4 - Map Calibration UI

## Changes
- Added an in-admin **Calibrate Map** panel to the live staff map.
- Staff with `map.calibrate`, `ranks.manage`, or `dev.tools` can tune:
  - `minX`
  - `maxX`
  - `minY`
  - `maxY`
- Calibration previews live without restarting the resource.
- Added quick nudge buttons:
  - Map Left / Right
  - Map Up / Down
  - Wider / Narrower X
  - Taller / Shorter Y
- Added **Save For Every Restart** button.
- Saved map bounds are written to:
  - `data/map_bounds.json`
- Added copyable `Config.Map.Bounds` output so the final tuned values can also be copied into `config.lua`.
- Added `map.calibrate` permission.
- Existing player, vehicle, admin, GPS TP, logs, and developer tools remain unchanged.

## Notes
- `Config.Map.UseSavedBounds = true` makes `data/map_bounds.json` override `Config.Map.Bounds`.
- To force only config values, set `Config.Map.UseSavedBounds = false`.
