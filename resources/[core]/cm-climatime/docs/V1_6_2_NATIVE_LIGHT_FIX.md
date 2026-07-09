# CM Climatime v1.6.2 Native Light Fix

## Fixed

- Prevented repeated client script errors when a FiveM runtime does not expose `SetArtificialLightsState`.
- Added safe native wrappers for optional lighting and snow effect natives.
- Blackout now prefers `SetArtificialLightsState` when available and falls back to `SetBlackout`.
- Missing optional natives no longer crash the climate effects loop.

## Why

Some FiveM/GTA client runtimes do not expose every native as a Lua global. Calling those directly can spam errors every climate tick and create lag.

## Test

1. Restart `cm-climatime`.
2. Confirm no error appears for `SetArtificialLightsState`.
3. Toggle blackout/weather presets.
4. Test snow/rain/thunder effects.
5. Confirm weather sync still works without large-event warnings.
