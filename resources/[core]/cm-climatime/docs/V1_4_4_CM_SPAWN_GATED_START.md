# CM Climatime v1.4.4 - cm-spawn gated start

## What changed

cm-climatime no longer applies time/weather as soon as the resource starts or when `cm-characters` opens.

The client now stores synced state but only starts applying weather/time after:

```lua
cm-spawn:client:spawned
```

This prevents weather blinking during character selection/creation because cm-characters owns the character screen world lock there.

## New config

```lua
Config.Startup = {
    StartMode = 'cm-spawn',
    RequireCmSpawn = true,
    ActivateIfAlreadySpawned = true,
    StartDelayMs = 900,
    RequestDebounceMs = 1500,
    DebugLifecycle = false
}
```

## New client bridge events

```lua
TriggerEvent('cm-climatime:client:setPaused', true, 'cm-characters')
TriggerEvent('cm-climatime:client:setPaused', false, 'cm-characters')
TriggerEvent('cm-climatime:client:requestSync')
TriggerEvent('cm-climatime:client:startAfterSpawn')
```

## New exports

```lua
exports['cm-climatime']:SetPaused(true, 'cm-characters')
exports['cm-climatime']:SetPaused(false, 'cm-characters')
exports['cm-climatime']:StartAfterSpawn('cm-spawn')
exports['cm-climatime']:RequestSync()
exports['cm-climatime']:IsActive()
exports['cm-climatime']:IsPaused()
```

## Recommended ensure order

```cfg
ensure cm-auth
ensure cm-characters
ensure cm-spawn
ensure cm-climatime
```

The order is not strict now, because cm-climatime also starts if it is restarted after the player is already spawned and `LocalPlayer.state.characterFullySpawned` is true.
