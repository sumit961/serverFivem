# CM PlayerData v1.8.5

Fixes:
- Adds persistent `death_location` separate from normal `last_position`.
- Dead reconnect spawn override now uses the saved body/death location first.
- Marks `cm-spawn:server:spawnComplete` net-safe but ignores it inside playerdata.
- Uses internal `cm-spawn:server:spawned` for trusted spawn-complete loading.
- Deathscreen waits for spawn UI states including `cmSpawnActive`.
