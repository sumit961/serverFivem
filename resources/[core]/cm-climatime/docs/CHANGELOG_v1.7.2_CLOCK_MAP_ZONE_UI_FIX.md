# CM Climatime v1.7.2 - Clock Drift, Calibrated Map, Zone UI Cleanup

## Fixed
- Fixed manual server time drift/freezing when `time.speed` is below 1 or fractional.
- `rebaseManualTime()` now preserves fractional elapsed seconds instead of resetting `baseUnix` every minute.
- Rebase save now only writes state when a full in-game minute was actually baked.
- Time speed change now rebases using the old speed before applying the new speed.
- Manual time speed now supports fractional values down to `0.1x`.

## Map
- Added calibrated `Config.Map.Bounds`:
  - `minX = -3900`
  - `maxX = 4619`
  - `minY = -4764`
  - `maxY = 7510`
- Climatime zone map reads these bounds from config and uses the same calibrated values as admin.

## Zone UI
- Removed the visible weather dropdown from zone creation.
- Zone weather is selected by clicking weather chips.
- Static zones are now labelled `All-Time Weather`.
- Rotation minutes only show for dynamic/mix zones.
- Zone form is hidden by default and appears when you click the map, press New Zone, use current position, or edit an existing zone.
