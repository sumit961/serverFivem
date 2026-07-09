# cm-climatime v1.7.1 - Overflow + time speed + weather transition guard

## Fixed
- Added client time prediction speed support so manual time no longer snaps when `time.speed` is higher than 1x.
- Added weather transition generation guard so old transition threads cannot finalize stale weather after a newer global/zone/admin weather request.
- Added duplicate pre-spawn prepare throttle. This prevents `applyBeforeSpawn` + `prepareBeforeSpawn` from applying twice in the same spawn phase.
- Added pre-spawn timeout generation guard so old prepare timers cannot flip state after a newer spawn location prepare starts.
- Added server request throttling for `cm-climatime:server:requestPreSpawnClimate`.
- Disabled server-side client prepare nudge by default because current `cm-spawn` already triggers the local pre-spawn prepare event.

## Performance / safety
- Prevents reliable network event pressure during spawn.
- Keeps weather/time change notifications silent for normal players.
- Keeps cm-ui admin panel changes from v1.7.0.
