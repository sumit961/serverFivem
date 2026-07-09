# CM PlayerData v1.9.3 - Stable G Prompt, Cyan ID, Vehicle Label Split

## Changes
- Normal overhead label ID now displays as `ID: <characterId>` instead of only `(id)`.
- Normal overhead ID line is CM cyan/blue.
- Player overhead labels remain visible even when the target player is inside a vehicle.
- Player G interaction is disabled while the target player is inside a vehicle.
- Added a small target hold window so the `G` prompt no longer blinks from one missed raycast/frame while still looking at a player.
- Added server-side validation to reject player interaction actions when the target is inside a vehicle.
- Kept database character ID only; no server ID is shown.
- Kept admin label replacement behavior from v1.9.2.

## Config added
```lua
TargetHoldMs = 260
BlockInteractionWhenTargetInVehicle = true
```
