# cm-playerdata v1.9.9 — In-vehicle label locked to the car

Refines v1.9.8.

## What changed
The head-follow anchor let the in-vehicle label sway/drift independently, so it
appeared to move while driving. The label is now **locked to the vehicle**:

- The occupant's seat position is converted into the vehicle's local space, the Z
  is pinned to the roof line, and the point is converted back to the world through
  the vehicle's matrix **every frame**.
- Because it is derived from the car's own transform, it moves and rotates exactly
  with the vehicle — no lag, swim, or independent drift while driving, turning, or
  going over bumps. It reads as attached to the car, above the occupant's head.

Seated, entering (F animation), and attached (trunk) cases are all covered.
On-foot labels are unchanged.

## Config (Interactions)
- `VehicleRoofZOffset = 0.30` — clearance above the roof line where the label sits.
- Removed `VehicleHeadLift` (no longer used).
