# v1.5.6 - Pre-spawn Climatime Prepare

## Problem
The old flow kept the selector at fixed night, spawned the player, then let `cm-climatime` change the weather/time after spawn. Even with smoothing, the player could still see the sky/time change after the character appeared.

## New flow
When the player presses Enter City:

1. Character UI closes.
2. Screen fades to black.
3. `cm-characters` releases the fixed selector world lock.
4. `cm-climatime` applies the real synced weather/time while the player is still hidden.
5. `cm-spawn` starts after the weather/time is already prepared.
6. The player appears directly in the correct weather/time.

## Config
`config.lua`:

```lua
Config.CharacterScreenWorld.preSpawnClimatePrepare = true
Config.CharacterScreenWorld.preSpawnFadeOutMs = 350
Config.CharacterScreenWorld.preSpawnClimatePrepareMs = 2600
Config.CharacterScreenWorld.preSpawnWeatherTransitionSeconds = 1.2
Config.CharacterScreenWorld.preSpawnRainRampSeconds = 1.2
Config.CharacterScreenWorld.preSpawnValidMs = 25000
Config.CharacterScreenWorld.smoothClimatimeHandoff = false
```

## Notes
- This requires `cm-climatime` v1.5.2 or newer.
- Character selection/creation still stays fixed night.
- During character creation, only `cm-hud` UI is hidden; native minimap/radar is not forced off.
- After spawn, `cm-climatime` is already active, so it should not visibly change the sky.
