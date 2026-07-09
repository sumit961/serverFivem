# cm-playerdata v1.9.12 — Locked vehicle label follows seat changes

Fixes the seat-change bug in the v1.9.11 locked label.

## What was wrong
The locked offset was cached per vehicle only. If a player switched seats inside
the same car (driver -> passenger, front -> back), the cache key still matched, so
the label stayed locked over the OLD seat and never moved to the new one.

## Fix
The cache key now includes the player's seat index (`GetPedInVehicleSeat` scan).
When the vehicle OR the seat changes, the label re-settles (brief head-track) and
re-locks at the new seat. So changing seats moves the label to the player's new
position, then locks again and stays rock-solid while driving.

Everything else is unchanged: above the head, locked to the car, smooth on entry.

## Config (Interactions)
- `VehicleHeadLift = 0.58`
- `VehicleLabelLockDelay = 700`
