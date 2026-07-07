# CM Characters v1.5.3 - cm-climatime clean pause/resume

## Why the weather was blinking

The previous world lock forced weather every few hundred milliseconds while `cm-climatime` was also syncing weather/time. That means the sky kept switching between `cm-characters` fixed night and `cm-climatime` live weather.

## What changed

- `cm-characters` now asks `cm-climatime` to pause once when selector/creator opens.
- It applies fixed selector weather once instead of every 350ms.
- It keeps only clock/HUD/radar locked while the character screen is open.
- When character creation/selection finishes, it releases the lock and requests `cm-climatime` sync several times.
- Added `cm-characters:client:releaseWorldLockNow` and `ReleaseCharacterWorldLock()` for manual recovery.

## Config

```lua
Config.CharacterScreenWorld = {
    enabled = true,
    weather = 'CLEAR',
    hour = 23,
    minute = 0,
    second = 0,
    hideHud = true,
    hideRadar = true,
    suppressClimatime = true,
    hudPulseMs = 650,
    reapplyWeatherWhileLocked = false,
    weatherSoftPulseMs = 8000,
    clockPulseMs = 0,
    resumeRetries = 4,
    resumeRetryDelayMs = 900
}
```

## Important

For perfect fixed weather with no blinking, `cm-climatime` must respect at least one of these:

- LocalPlayer state `cmClimatimePaused == true`
- event `cm-climatime:client:setPaused`
- event `cm-climatime:client:pause`
- export `SetPaused`
- export `Pause`
- export `SetCharacterScreenMode`

If your current `cm-climatime` ignores all of these, it will still be able to overwrite selector weather. In that case, add the compatibility bridge from `compat/cm-climatime_pause_bridge_client.lua` into your `cm-climatime` client file.

## Manual recovery command from F8

```lua
TriggerEvent('cm-characters:client:releaseWorldLockNow')
```
