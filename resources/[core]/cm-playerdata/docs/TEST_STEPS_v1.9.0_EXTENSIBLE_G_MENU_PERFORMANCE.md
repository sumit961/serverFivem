# Test Steps — cm-playerdata v1.9.0

## Restart Order

```cfg
restart cm-ui
restart cm-core
restart cm-auth
restart cm-playerdata
restart cm-characters
restart cm-climatime
restart cm-spawn
restart cm-hud
```

## Basic Load Test

1. Join the server.
2. Login and select a character.
3. Confirm there is no `cm-playerdata` startup print spam in F8/server console.
4. Confirm player cash/bank still load.
5. Confirm death screen still opens if the player dies.

## Overhead ID Test

1. Join with two players.
2. Stand near another player.
3. Confirm the overhead label shows:
   - `Stranger`
   - `ID: <database character id>`
4. Confirm no server ID appears anywhere.
5. Aim/look at the player and confirm the cyan `G` prompt appears.

## Built-In G Menu Test

1. Look at another player and press `G`.
2. Test:
   - Basic Actions
   - Documents
   - Check Status
   - Close
3. Confirm numbered click/keyboard selection still works.
4. Confirm right mouse goes back and ESC closes.

## Extension Menu Test

Create a temporary client test in another resource:

```lua
CreateThread(function()
    Wait(2000)
    exports['cm-playerdata']:RegisterInteractionOption('family', {
        id = 'family.test',
        label = 'Family Test',
        icon = 'family',
        type = 'extension',
        action = 'family.test',
        order = 10
    })
end)
```

Create a temporary server test in the same resource:

```lua
CreateThread(function()
    Wait(2000)
    exports['cm-playerdata']:RegisterInteractionAction({
        id = 'family.test',
        event = 'testresource:server:familyTest'
    })
end)

AddEventHandler('testresource:server:familyTest', function(src, target, action, payload, context)
    print(('validated g-menu action %s from char %s to char %s'):format(
        action,
        context.sourceCharacterId,
        context.targetCharacterId
    ))
end)
```

Then:

1. Restart `cm-playerdata` and the test resource.
2. Look at a player and press `G`.
3. Confirm `Family Menu` appears only after the option is registered.
4. Select `Family Test`.
5. Confirm the server prints character IDs, not server IDs.
6. Move far away and try again; it should be rejected by server distance validation.

## Performance Test

1. Stand around 5 to 10 players.
2. Confirm labels still follow players smoothly.
3. Confirm no reliable event overflow.
4. Confirm no heavy console spam.
5. Confirm `resmon` does not spike from `cm-playerdata` while only standing near players.
