# cm-playerdata v1.9.13 — Single-prompt interaction arbiter

Stops the double-G when a player and a vehicle are both in view.

## The problem
The player G (this resource) and the vehicle G (a separate resource) each detect
their own target, so when both are in view you saw two G prompts at once.

## The approach (and why not one file)
Merging both menus into one resource would pull vehicle logic out of its own
resource and break the clean-boundary pattern the framework uses. Instead, both
resources keep their own menu and coordinate through a shared local statebag so
only ONE G shows at a time.

## What this build adds (cm-playerdata's half)
- Publishes `LocalPlayer.state.cmPlayerInteractDist` (distance to the player
  target, or false).
- Reads `LocalPlayer.state.cmVehicleInteractDist` and, when the vehicle target
  wins, hides its own G and refuses to open on G — so pressing G opens the vehicle
  menu instead.
- Tie-break fixed so near-ties go to the player (prevents both showing).

## To finish it
Add the mirror to your vehicle resource — full drop-in snippet in
`docs/INTERACTION_ARBITER.md`. No cross-resource edits, no merged files.

## Config (Interactions)
- `InteractionArbiter = true` — enable/disable the whole thing.
- `InteractionPriority = 'closest'` — `'closest'` | `'player'` | `'vehicle'`.
  Use `'player'` if your vehicle prompt is proximity-based (aiming at a person
  should beat merely standing next to a car).
- `InteractionArbiterTie = 0.1` — metres of dead-zone before `'closest'` flips.
