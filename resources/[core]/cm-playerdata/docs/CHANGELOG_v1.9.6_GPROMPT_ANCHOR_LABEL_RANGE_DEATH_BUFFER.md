# cm-playerdata v1.9.6 — Anchored G, closer/tighter labels, unconscious health buffer

Builds on v1.9.5.

## Labels & G prompt (interactions.lua / config.lua)

### G prompt is now body-anchored (no camera-move drift)
The G was rendered through NUI on a throttled interval, so it lagged/wobbled
behind the body whenever the *viewer* moved the camera. It is now drawn natively
every frame via `SetDrawOrigin` on the target's body (`DrawNativeGPrompt`), the
same technique the overhead labels use. Result: the G is glued to the player and
only moves when the *player* moves. The NUI G channel is kept for the non-native
label mode and stays hidden under native mode.

### Reduced name/ID render distance
`Interactions.OverheadDistance` 18.0 → **12.0**. Names/IDs only show on closer
players now. Tune freely.

### Name/ID no longer spread apart at distance
Native label line spacing was a fixed screen offset, so as the text shrank with
distance the gap looked wider and wider. Spacing is now proportional to the
label's text scale (`Interactions.OverheadLineGap`, default `0.075`), so the two
lines stay tight together at any range.

## Death logic (client/main.lua + server/main.lua + config.lua)

### Unconscious health buffer (finishing)
On death the body now carries a finishing buffer of
`Vitals.UnconsciousHealthPercent` (default **10%** of max) above the downed
floor — i.e. it goes down at ~121 HP instead of being pinned at the 101 floor.

- A client monitor arms once the buffer is in place, then watches the body.
- If someone keeps shooting and drains the buffer (health back to/below the
  downed floor, or a real kill), the player is **finished** → the client fires
  `cm-playerdata:server:finishedOff` → **immediate hospital respawn**, skipping
  the bleed-out timer.

### Patch = full revive in place ("back from death")
A successful street patch used to leave the target weak (30%). It now **fully
revives them in place** at full health, same location, no hospital trip
(`Medical.PatchFullHeal = true`). Set it to `false` to restore the old weak
partial revive via `StreetPatchHealthPercent`.

### Admin heal on an unconscious player revives in place
`exports.Heal` previously refused while the target was dead. Now, healing an
unconscious player brings them **back from death in place**: a full heal → full
in-place revive; a partial heal → up weak at the same spot. No teleport, no
hospital.

## Summary of what each outcome does now
- Killed once → unconscious with a 10% finishing buffer, bleed-out timer runs.
- Killed again (buffer drained) → straight to hospital + respawn.
- Patched → full health, get up where you fell.
- Admin full heal while down → full health, get up where you fell.
- Bleed-out timer hits 0 with nobody helping → hospital respawn (unchanged).

## New / changed config keys
- `Vitals.UnconsciousHealthPercent = 10`
- `Medical.PatchFullHeal = true`
- `Interactions.OverheadDistance = 12.0`  (was 18.0)
- `Interactions.OverheadLineGap = 0.075`
- `Interactions.PromptNativeScale = 0.44`
