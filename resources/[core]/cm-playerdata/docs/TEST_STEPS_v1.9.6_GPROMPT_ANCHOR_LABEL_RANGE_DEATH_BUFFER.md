# Test steps — v1.9.6

`ensure cm-playerdata`. Two players (plus an admin for the last check).

## G prompt anchored to the body
1. Look at a player within ~4.5 m so the cyan G shows on their body.
2. Strafe / move your camera around while keeping the crosshair on them: the G
   should stay locked to their body and not drift or wobble as you move.
3. Have the other player walk: the G moves with them. Look away: G disappears.

## Label range + spacing
1. Names/IDs now only appear on players within ~12 m (closer than before).
2. Walk away from a player to the edge of range: the `Name` and `ID` lines stay
   tight together — no growing gap between them as the text shrinks.

## Death — unconscious buffer
1. Kill a player once. They go down (Unconscious label, bleed-out screen).
2. Keep shooting the downed body. After a short burst (the 10% buffer) they are
   **finished** → sent straight to hospital and respawned, without waiting out
   the bleed-out timer.

## Death — patch = full revive in place
1. Down a player. As the other player, look at the body, open G → treat/patch.
2. On success the downed player gets up **at full health, at the same spot** —
   no hospital, no weak state.

## Death — admin heal in place
1. Down a player. Admin heals them to full (cm-admin heal, `exports.Heal`).
2. They come **back from death at the same location, full health** — no teleport.

## Regression
- Bleed-out with nobody helping still auto-respawns at hospital.
- Call Ambulance / Give Up buttons still work.
- Unconscious red label still shows; in-car labels still show; no G while the
  viewer is in a vehicle.
