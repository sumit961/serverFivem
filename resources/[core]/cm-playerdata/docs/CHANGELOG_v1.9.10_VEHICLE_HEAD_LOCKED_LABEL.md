# cm-playerdata v1.9.10 — In-vehicle label: above the head AND locked to the car

Fixes the two issues from v1.9.9.

## What was wrong in v1.9.9
The label was locked to the car but pinned to the bounding-box roof height, which
for most cars lands around window level — so it read as "in the middle of the car"
instead of above the head. Entering also jumped, because it snapped from the
on-foot head position down to that roof point.

## Fix
The in-vehicle label now references the player's **head** for its position (so it
sits above the head like the on-foot label), but that point is converted into the
**vehicle's local frame** and rebuilt through the car's matrix every frame. The
round-trip uses the same frame's vehicle transform, so the label is:

- **Above the head** — uses the head bone + a lift, not the low roof line.
- **Locked to the car** — derived from the vehicle matrix, so no lag/sway/drift
  while driving, turning, or over bumps.
- **Smooth on entry** — it tracks the head continuously through the get-in
  animation instead of snapping to a fixed roof point.

## Config (Interactions)
- `VehicleHeadLift = 0.58` — how far above the head to float the label.
- Removed `VehicleRoofZOffset` (no longer used).

Raise `VehicleHeadLift` if you want it a bit higher above the head.
