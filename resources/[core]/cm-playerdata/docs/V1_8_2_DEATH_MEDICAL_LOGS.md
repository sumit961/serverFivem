# CM PlayerData v1.8.2 — Death/Rejoin, Medical Exports, Admin Log Preview

## Why this update exists

A player who died, left the server, and rejoined could see the death screen over the spawn UI, then the death timer could reach `00:00` and stay stuck. The old system saved `is_dead` to the database but kept the bleed-out deadline only in server memory.

## What changed

- Death deadline is now persisted in the `characters` table.
- Dead rejoin restores a valid bleed-out timer.
- Death screen is delayed until after spawn completes, so it should not blink over the spawn selector.
- Client has a watchdog that requests respawn when its timer reaches zero.
- Server still validates the timer, so players cannot trigger early respawn from the client.
- Hospital respawn now returns the player with weak health based on `Config.Respawn.HealthPercent`.
- Ambulance request export added for future EMS/doctor systems.
- Read-only admin log exports added so `cm-admin` can preview playerdata/death/economy logs.

## New database columns

```sql
ALTER TABLE characters ADD COLUMN IF NOT EXISTS death_deadline_at BIGINT NULL;
ALTER TABLE characters ADD COLUMN IF NOT EXISTS ambulance_called TINYINT(1) DEFAULT 0;
ALTER TABLE characters ADD COLUMN IF NOT EXISTS death_reason VARCHAR(100) NULL;
```

The resource applies these automatically on start.

## New/updated config

```lua
Config.Respawn.HealthPercent = 20
Config.Respawn.MinimumRejoinBleedOut = 15000
```

Important: GTA/FiveM health is not a simple `0-100` UI bar. 20% respawn health is calculated as weak but alive health above the downed threshold.

## Medical exports for future EMS/doctor resources

```lua
exports['cm-playerdata']:GetDeathInfo(source)
exports['cm-playerdata']:RequestAmbulance(source, reason, metadata)
exports['cm-playerdata']:CallAmbulance(source, reason, metadata)
exports['cm-playerdata']:Heal(source, amountOrPercent, reason)
exports['cm-playerdata']:RevivePartial(source, percent, reason)
exports['cm-playerdata']:Revive(source)
exports['cm-playerdata']:Respawn(source, spawnCoords, cost)
```

## Ambulance event for future EMS dispatch

Listen to:

```lua
AddEventHandler('cm-playerdata:server:ambulanceRequested', function(src, data)
    -- data.characterId
    -- data.name
    -- data.coords
    -- data.remainingMs
    -- data.reason
    -- data.metadata
end)
```

Legacy event still exists:

```lua
AddEventHandler('cm-playerdata:server:ambulanceCalled', function(src, coords)
end)
```

## Admin log preview exports for cm-admin

These are read-only and permission-gated through `cm-admin`/ACE:

```lua
exports['cm-playerdata']:AdminGetAuditLogs(adminSource, characterId, action, limit)
exports['cm-playerdata']:AdminGetMoneyTransactions(adminSource, characterId, limit)
exports['cm-playerdata']:AdminGetDeathLogs(adminSource, characterId, limit)
```

Recommended `cm-admin` permissions:

```text
logs.view
playerdata.logs.view
```

## Testing

1. Die normally.
2. Confirm death screen opens after death.
3. Leave server while dead.
4. Rejoin and select the character.
5. Confirm spawn selector does not show deathscreen over it.
6. Confirm after spawning at the death location, the death screen appears.
7. Let timer reach zero.
8. Confirm hospital respawn happens.
9. Confirm health is weak/partial, not full.
10. Call ambulance and confirm the timer extends.
11. Check `cm-admin` can later use the log exports to show death/money/audit logs.
