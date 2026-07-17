# cm-vehicles v3.3.6

## Non-blinking garage/world handoff

- Removed repeated `NetworkFadeInEntity` calls from the garage release convergence loop.
- Removed the temporary always-prerender toggle from the release handoff.
- Alpha and visibility are now changed only when the local entity is actually hidden or transparent.
- The short convergence pass now repairs only idempotent physics, collision, freeze, gravity and access state.
- Reduced the convergence window from 20 to 12 passes while preserving late ownership-migration recovery.
- Parked vehicles remain visible and protected; released vehicles no longer flash for several seconds.
