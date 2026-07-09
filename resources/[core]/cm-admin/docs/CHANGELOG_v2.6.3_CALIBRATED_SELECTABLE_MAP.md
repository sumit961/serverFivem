# CM Admin v2.6.3 - Calibrated Selectable Admin Map

## Changes
- Recalibrated the admin live-map projection for the stitched 6-tile GTA atlas.
- Added `Config.Map.Bounds` so map coordinate alignment can be tuned from config instead of rewriting UI code.
- Changed admin map default camera to focus around Los Santos/Pillbox area.
- Vehicles are now enabled by default while the Map tab is open.
- Added click selection on the live map:
  - click player blip to open an action card
  - click vehicle blip to open a vehicle action card
  - click empty map point to optionally teleport there
- Player map actions are permission-based:
  - Inspect
  - Go To
  - Bring
  - Freeze / Unfreeze
  - Heal / Armor
  - Inventory
  - Cars
  - Kick
- Vehicle map actions are permission-based:
  - Inspect details in map card
  - Go To Vehicle
  - Repair streamed vehicle
  - Delete vehicle
- Added server-side validation for map teleport and vehicle map actions.
- Added vehicle `netId` to map payload and plate fallback for safer vehicle targeting.
- Kept admin tags, GPS TP, logs, ranks, dev launchers, and existing staff permissions unchanged.

## Performance notes
- Map refresh still only runs while the Map tab is open.
- Vehicle scan is still permission-gated and limited by `Config.Map.MaxVehicles`.
- Canvas draw is throttled with `requestAnimationFrame`.
