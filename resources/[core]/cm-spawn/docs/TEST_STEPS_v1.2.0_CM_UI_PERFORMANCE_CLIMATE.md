# Test steps - cm-spawn v1.2.0

## Restart order
```cfg
restart cm-core
restart cm-auth
restart cm-playerdata
restart cm-characters
restart cm-climatime
restart cm-spawn
restart cm-hud
```

## Basic spawn selector
1. Login normally.
2. Select an existing character.
3. Confirm `cm-characters` closes and `cm-spawn` opens.
4. Confirm spawn selector uses CM blue/cyan style.
5. Confirm there is no black NUI background bug.
6. Confirm player ped remains hidden while spawn page is open.
7. Confirm HUD/minimap are hidden while spawn selector is open.

## Climatime preload
1. Set/observe active weather/time in `cm-climatime`.
2. Select a character.
3. Confirm weather/time is already synced by the time spawn selector opens or before final reveal.
4. Click Hotel or Last Location.
5. Confirm weather does not visibly snap/change after the player has already appeared.

## Spawn security
1. Open DevTools or trigger a fake NUI request with an invalid `spawnKey`.
2. Confirm server rejects invalid/locked keys.
3. Confirm client never sends coordinates.
4. Confirm server chooses final coordinates.

## Dead reconnect test
1. Kill/down a character and save death state through `cm-playerdata`.
2. Leave the server.
3. Rejoin and select the same character.
4. Click any spawn card.
5. Confirm player is forced back to saved body/death location.
6. Confirm deathscreen returns after spawn completion.
7. Confirm Hotel/Last Location cannot override dead location.

## Performance checks
1. Keep txAdmin/server console open while logging in.
2. Confirm no repeated spawn/HUD/climate logs in production mode.
3. Confirm no repeated NUI open/close flicker.
4. Confirm no server hitch from `cm-spawn` during normal spawn selection.
5. Confirm `Config.Debug` and `Config.VerboseLogs` are both false.

## Optional production setting
After running `sql/upgrade_has_spawned.sql` once on production, you may set:
```lua
Config.AutoEnsureHasSpawnedColumn = false
```
This avoids the startup schema check on every restart.
