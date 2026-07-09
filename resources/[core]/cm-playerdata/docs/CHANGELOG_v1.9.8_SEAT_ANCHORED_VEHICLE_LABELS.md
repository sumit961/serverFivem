# CM PlayerData v1.9.8 - Seat-Anchored Vehicle Labels

## Fixed
- In-car overhead labels no longer use the vehicle/ped origin center, which made the ID appear between seats.
- Vehicle occupant labels now use the player's head bone X/Y position so the label stays above the correct driver/passenger seat.
- Reduced vehicle label height so it sits closer above the roof/windscreen instead of too high above the player.
- Trunk/attached vehicle fallback still lifts labels above the vehicle when a head bone cannot be read.

## Config
```lua
VehicleSeatHeadZOffset = 0.34
VehicleLabelMaxAboveHead = 0.58
VehicleRoofClearance = 0.10
VehicleOverheadZOffset = 1.45
```
