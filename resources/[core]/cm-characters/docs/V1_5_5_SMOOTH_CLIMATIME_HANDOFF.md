# CM Characters v1.5.5 - Smooth Climatime Handoff

This patch prevents the ugly snap when leaving fixed character selection night and entering live cm-climatime.

## What changed

- Character world-lock no longer instantly clears fixed night/weather when smooth handoff is enabled.
- It sends `cm-climatime:client:beginSpawnHandoff` with the selector scene as the starting weather/time.
- cm-hud UI is restored, but GTA minimap/radar is not touched except safety restore.

## Config

`Config.CharacterScreenWorld.smoothClimatimeHandoff = true`

Adjust:

- `handoffHoldMs`
- `handoffWeatherTransitionSeconds`
- `handoffTimeBlendSeconds`
- `handoffRainRampSeconds`
