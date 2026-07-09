# cm-playerdata v1.9.0 — Extensible G Menu + Performance Cleanup

## Changed

- Added `cm-ui` as the shared UI dependency for the playerdata NUI.
- Added `cm-ui` theme/component stylesheet references to `ui/index.html`.
- Updated local playerdata UI CSS variables to use CM shared theme variables with safe fallbacks.
- Bumped resource version to `1.9.0-extensible-g-menu-performance`.

## G Menu Extension System

- Removed hard dependency on hardcoded future family/organization/admin actions inside the client G menu.
- Added configurable empty extension pages in `config.lua`:
  - `family`
  - `organization`
  - `admin`
- Added client exports for future resources:
  - `RegisterInteractionPage(page)`
  - `RegisterInteractionOption(pageId, option)`
  - `RegisterInteractionMenu(menu)`
  - `UnregisterInteractionOption(pageId, optionId)`
  - `ClearInteractionOptions(pageId)`
- Added client events with the same purpose:
  - `cm-playerdata:client:registerInteractionPage`
  - `cm-playerdata:client:registerInteractionOption`
  - `cm-playerdata:client:registerInteractionMenu`
  - `cm-playerdata:client:clearInteractionOptions`
- Added server action registry for extension actions:
  - `exports['cm-playerdata']:RegisterInteractionAction(meta)`
  - `exports['cm-playerdata']:UnregisterInteractionAction(action)`
  - `TriggerEvent('cm-playerdata:server:registerInteractionAction', meta)`
  - `TriggerEvent('cm-playerdata:server:unregisterInteractionAction', action)`
- Added validated server bridge:
  - Client extension selection sends only the target and registered action ID to `cm-playerdata`.
  - `cm-playerdata` validates source loaded state, target loaded state, distance, dead-state rules, and rate limit.
  - Then it dispatches a server-side event to the owning resource.

## Performance

- Removed startup print spam from `client/interactions.lua`.
- Quieted server log fallback in production unless debug/warn/error.
- Added `Config.Interactions.LabelUpdateInterval = 50` to avoid sending overhead-label NUI messages every frame.
- Interaction marker still draws every frame only when actively looking at a target.
- G menu input protection still runs only while the menu is open.

## Safety Rules Preserved

- Server ID is not shown to players.
- Visible player ID stays database character ID only.
- Client does not decide final validation for G menu extension actions.
- Distance and dead-state validation remain server-side.
- Existing built-in actions are preserved:
  - handshake
  - share ID
  - greet
  - give cash
  - documents
  - check status
  - patch/treat dead body

## Example: Adding Family G Menu From `cm-family`

Client side:

```lua
CreateThread(function()
    while GetResourceState('cm-playerdata') ~= 'started' do Wait(500) end

    exports['cm-playerdata']:RegisterInteractionOption('family', {
        id = 'family.invite',
        label = 'Invite Family',
        icon = 'family',
        type = 'extension',
        action = 'family.invite',
        order = 10
    })
end)
```

Server side:

```lua
CreateThread(function()
    while GetResourceState('cm-playerdata') ~= 'started' do Wait(500) end

    exports['cm-playerdata']:RegisterInteractionAction({
        id = 'family.invite',
        event = 'cm-family:server:gMenuInvite',
        allowDeadTarget = false
    })
end)

AddEventHandler('cm-family:server:gMenuInvite', function(src, target, action, payload, context)
    -- src and target are already validated by cm-playerdata.
    -- Use context.sourceCharacterId and context.targetCharacterId for DB logic.
end)
```

## Example: Adding Admin G Menu From `cm-admin`

Client side:

```lua
exports['cm-playerdata']:RegisterInteractionOption('admin', {
    id = 'admin.inspect',
    label = 'Inspect Player',
    icon = 'shield',
    type = 'extension',
    action = 'admin.inspect',
    order = 10,
    allowDeadTarget = true
})
```

Server side:

```lua
exports['cm-playerdata']:RegisterInteractionAction({
    id = 'admin.inspect',
    event = 'cm-admin:server:gMenuInspect',
    allowDeadTarget = true
})
```
