# v1.5.4 Character World Lock / HUD Minimap Fix

## Why it was forcing night after spawn
The character world lock was still able to stay active if any selector/creator statebag or lock reason was left true. While active it kept the clock fixed at night and kept sending pause/sync messages to `cm-climatime`.

This update fixes the stale `cmCharactersWorldLocked` flag and adds a stronger release path on:
- `cm-characters:client:characterReady`
- `cm-spawn:client:spawned`
- `cm-playerdata:client:loaded`

The release clears all selector/creator statebags, clears clock/weather overrides, restores native HUD/radar, and asks `cm-climatime` to resume.

## Why minimap was hidden after closing character
`cm-characters` was calling native functions like `DisplayRadar(false)` and `HideHudAndRadarThisFrame()`. Also the old `cm-hud` hide event hides both CM HUD and GTA radar.

This update changes character creation/selection to hide only the CM HUD NUI through new UI-only `cm-hud` events/exports:
- `cm-hud:client:hideUiOnly`
- `cm-hud:client:showUiOnly`
- `cm-hud:client:setUiVisible`
- `exports['cm-hud']:SetUiVisible(...)`
- `exports['cm-hud']:HideUiOnly(...)`
- `exports['cm-hud']:ShowUiOnly(...)`

## Important
Install the patched `cm-hud` with the patched `cm-characters`. If you only install `cm-characters`, older `cm-hud` versions may ignore the UI-only event names.
