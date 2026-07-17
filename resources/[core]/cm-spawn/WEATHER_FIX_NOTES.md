# cm-spawn + cm-climatime — weather timing fix

## The bug you reported
When a player clicked "hotel" or "last location", they spawned first and THEN the
sky snapped from the character-creation night to the real world weather (night->day).

## Why it happened
cm-climatime deliberately does not apply world weather while cm-characters owns the
character screen — the weather loop literally comments "never fight cm-characters".
The pre-spawn prepare that clears that pause could be immediately re-paused by
cm-characters' worldlock loop in a race, so a single prepare call at selector-open
was often undone a frame later. Result: the real weather only took hold at the
reveal, after the player had already picked a spawn — the visible snap.

## The fix (additive, no rewrite)
New file: `cm-spawn/client/selector_weather.lua`.

While the spawn selector is open, it re-asserts the real synced climate on a short
self-healing loop (fast for the first ~2s to win the pause race, then a cheap 1s
hold). Whichever writer races last, cm-climatime is re-nudged within ~250ms, so the
sky settles on the correct weather well before the player chooses a spawn.

Because the loop keeps cm-climatime's pre-spawn "prepared" window fresh, the spawn
reveal then sees `wasPreSpawnRecentlyPrepared() == true` and SKIPS the old
CLEAR-night handoff entirely — so there is no post-spawn change either. Both halves
of the snap are gone.

The loop sleeps at 500ms when the selector is closed, so there is zero cost during
normal gameplay. It uses the export `PrepareBeforeSpawn` when available and falls
back to the events cm-climatime already listens for, so it is version-tolerant and
never edits cm-climatime.

## What was NOT changed
Both resources were already solid on performance and security: tick loops are
correctly gated (debug draws sleep at 500ms), server events read `source` and the
sensitive ones are rate-limited, and cm-climatime's server paths are throttled. No
issues were invented; only the reported bug was fixed. Versioned changelog/test-step
docs were pruned.

## If you still see any residual snap
Increase the valid window so the prepared state can't lapse on a slow selector:
`cm-spawn/config.lua` -> `Config.SpawnPageClimateValidMs` (default 30000). The loop
already re-asserts within it, but a larger window adds margin.
