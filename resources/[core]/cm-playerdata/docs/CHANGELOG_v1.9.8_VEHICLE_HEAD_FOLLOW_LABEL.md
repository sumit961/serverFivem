# cm-playerdata v1.9.8 — In-vehicle label follows the head, above the roof

Refines the in-vehicle label from v1.9.7.

## What was wrong
- The label sat too low — reading as "in the middle of the car" rather than
  clearly above it.
- Pressing F to get in dropped the label to car level and snapped, because
  during the get-in animation the ped is not "in" the vehicle yet
  (`GetVehiclePedIsIn` returns 0), so it briefly fell back to the on-foot anchor.

## Fix
The in-vehicle label now:
- **Follows the head bone** (smooth, tracks the head like the on-foot label),
  then lifts it above the roof so it floats like a nameplate over the car.
- **Detects the entering vehicle** (`GetVehiclePedIsEntering`) as well as the
  seated and attached (trunk) cases, so it stays anchored through the whole F
  get-in animation — no drop to car level, no snap.
- **Clamps to a roof floor** (`GetModelDimensions` roof height + clearance), so
  even while the head ducks during entry the label never dips into the car.

x/y follow the head; z is `head + VehicleHeadLift`, floored at
`roof top + VehicleRoofZOffset`. On-foot labels are unchanged.

## Config (Interactions)
- `VehicleHeadLift = 0.62` — height above the head bone in a vehicle.
- `VehicleRoofZOffset = 0.30` — minimum clearance above the roof (floor).

Raise `VehicleHeadLift` if you want it higher above the car; raise
`VehicleRoofZOffset` if a tall vehicle's roof still clips the label.
