# CM PlayerData v1.8.3 - Dead Spawn Override

## Rule

If a character is dead and reconnects, the player may still see the spawn selector, but every selected spawn must resolve to the character's last/death location. The player remains dead and the deathscreen appears after spawn completes.

This prevents players from using the spawn selector to escape death or move their body to hotel/hospital/org/base.

## New exports

```lua
exports['cm-playerdata']:GetDeathSpawn(source)
exports['cm-playerdata']:GetSpawnOverride(source, requestedSpawnKey)
```

### GetDeathSpawn(source)

Returns the saved dead/body location when the character is dead, otherwise `nil`.

### GetSpawnOverride(source, requestedSpawnKey)

Returns an override object when spawn should be forced by player state.

Current override:

```lua
{
    forced = true,
    reason = 'dead_character',
    key = 'dead_location',
    requestedKey = requestedSpawnKey,
    label = 'LAST BODY LOCATION',
    description = 'You are still down. You will return to where you died.',
    coords = { x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
    isDead = true,
    remainingMs = 60000
}
```

## cm-spawn usage

Before accepting any clicked spawn key, `cm-spawn` should call:

```lua
local override = exports['cm-playerdata']:GetSpawnOverride(source, spawnKey)
if override and override.coords then
    TriggerClientEvent('cm-spawn:client:spawn', source, override.key, false, override.coords, appearance)
    return
end
```

## Admin logs

Death, ambulance, revive, and hospital respawn logs are still available through:

```lua
exports['cm-playerdata']:AdminGetDeathLogs(adminSource, characterId, limit)
exports['cm-playerdata']:AdminGetAuditLogs(adminSource, characterId, action, limit)
```
