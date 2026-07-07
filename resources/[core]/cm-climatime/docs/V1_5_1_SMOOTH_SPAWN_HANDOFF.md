# CM Climatime v1.5.1 - Smooth Spawn Handoff

This patch adds a smooth transition from the character selector fixed night scene into live synced cm-climatime.

## Why

Before this patch, `cm-characters` released `CLEAR 23:00` and cm-climatime immediately applied the live server weather/time. That caused a visible sky/time snap.

## Added

- `Config.SpawnHandoff`
- Client event: `cm-climatime:client:beginSpawnHandoff`
- Export: `BeginSpawnHandoff(data)`
- Smooth weather transition during spawn
- Smooth time blend during spawn
- Rain intensity ramp so RAIN/THUNDER does not pop on instantly

## Example

```lua
TriggerEvent('cm-climatime:client:beginSpawnHandoff', {
    fromWeather = 'CLEAR',
    fromHour = 23,
    fromMinute = 0,
    holdMs = 1200,
    weatherTransitionSeconds = 32,
    timeBlendSeconds = 9,
    rainRampSeconds = 10
})
```
