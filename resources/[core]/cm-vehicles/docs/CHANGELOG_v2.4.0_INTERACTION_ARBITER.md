# cm-vehicles v2.4.0 — Single-prompt interaction arbiter (with cm-playerdata)

Stops the double-G when a player and a vehicle are both in view. The vehicle menu
now coordinates with cm-playerdata's player menu so only one G shows at a time.

## What changed (client/menu.lua)
- Publishes `LocalPlayer.state.cmVehicleInteractDist` = distance to the currently
  looked-at vehicle (or false when none).
- Reads cm-playerdata's `cmPlayerInteractDist` and hides the vehicle G / refuses to
  open on G when the player menu owns the prompt this frame.
- Pulls the arbiter settings (enabled / priority / tie) live from cm-playerdata via
  `exports['cm-playerdata']:GetInteractionArbiter()`, so the two can never drift
  out of sync. Falls back to sensible defaults if cm-playerdata isn't running.

Seated-in-own-vehicle menu is unaffected (no player-target conflict there). The
tie-break matches cm-playerdata exactly, so at a shared distance the player wins
and both prompts never show together.

## Tuning
All arbiter settings live in cm-playerdata's config
(`Interactions.InteractionArbiter`, `InteractionPriority`, `InteractionArbiterTie`).
Because this resource reads them at runtime, change them there only.

- If the vehicle prompt should lose to aiming at a person, keep `'closest'` (both
  are aim-gated) or set `'player'`.
- Set `InteractionArbiter = false` to disable and restore the old behavior.
