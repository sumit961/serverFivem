# v1.5.2 - Pre-spawn Weather Prepare

## Problem
Applying live weather/time only after `cm-spawn:client:spawned` made the sky or clock visibly change when the player appeared.

## New solution
`cm-characters` can now call `cm-climatime` before the real spawn reveal:

```lua
exports['cm-climatime']:PrepareBeforeSpawn({
    reason = 'cm-characters-pre-spawn',
    prepareMs = 2600,
    validMs = 25000,
    weatherTransitionSeconds = 1.2,
    rainRampSeconds = 1.2
})
```

or:

```lua
TriggerEvent('cm-climatime:client:prepareBeforeSpawn', payload)
```

This does:

- clears the selector weather override,
- unpauses climatime,
- applies the latest synced global/zone weather,
- applies the latest synced time,
- ramps rain quickly while the screen is black,
- marks the weather as prepared so `cm-spawn:client:spawned` does not start the old post-spawn handoff.

## Config
`shared/config.lua`:

```lua
Config.PreSpawnPrepare = {
    Enabled = true,
    WeatherTransitionSeconds = 1.2,
    RainRampSeconds = 1.2,
    PrepareMs = 2600,
    ValidMs = 25000,
    Debug = false
}

Config.SpawnHandoff.Enabled = false
```

## Exports

```lua
exports['cm-climatime']:PrepareBeforeSpawn(payload)
exports['cm-climatime']:IsPreSpawnPrepared()
```

## Result
The player should spawn directly into the real synced climatime weather/time, with no visible post-spawn snap.
