# cm-playerdata v1.9.11 — In-vehicle label rigidly stuck to the car

Refines v1.9.10. Position/height is unchanged (above the head, where you liked it);
this removes the residual movement while driving.

## What was wrong
The label recomputed its offset from the head bone every frame, so tiny per-frame
head/interpolation wobble made it swim slightly relative to the car while driving.

## Fix
Once the player is fully seated, the label's offset is **cached** in the car's
local frame and reused, so the label is a fixed point on the car:

- **Settle window** (`VehicleLabelLockDelay`, default 700 ms): right after sitting
  down it briefly tracks the head so it lands cleanly after the get-in animation.
- **Then it locks**: from that point the position is a fixed offset rebuilt through
  the car's matrix each frame, so it moves ONLY when the car moves — no jitter or
  swim while driving, turning, or over bumps.
- Entering (F) and trunk/attached cases still live-follow smoothly, then lock once
  seated. The cache clears when the player is on foot again or changes vehicle.

Height/placement above the head is identical to v1.9.10.

## Config (Interactions)
- `VehicleHeadLift = 0.58` — height above the head.
- `VehicleLabelLockDelay = 700` — ms of settle before the label locks to the car.
