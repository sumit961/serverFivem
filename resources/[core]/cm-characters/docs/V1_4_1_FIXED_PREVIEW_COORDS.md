# v1.4.1 Fixed Selector Preview Coordinates

Character preview now uses the provided fixed scene:

- Player/dummy position: `vector4(927.4528, 11.8477, 113.5550, 296.7522)`
- Camera position: `vector3(931.2687, 14.1728, 114.5444)`
- Camera rotation: `vector3(-3.8893, 0.0, 116.2193)`
- FOV: `50.0`
- Weather: `CLEAR`
- Time: `23:00`
- Selector routing bucket: player server ID

The resource now sets these state bags during selector preview:

- `isInCharacterSelector = true`
- `characterFullySpawned = false`
- `skipPositionSave = true`

When the real character finishes spawning, it sets:

- `isInCharacterSelector = false`
- `characterFullySpawned = true`
- `skipPositionSave = false`

`cm-playerdata` should ignore position saves while `skipPositionSave == true` or `isInCharacterSelector == true`.
