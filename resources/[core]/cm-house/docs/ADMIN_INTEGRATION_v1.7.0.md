# cm-admin integration — cm-house v1.7.0 (corrected)

This file previously described a "recommended production workflow" built
around per-tab `exports['cm-house']:OpenAdminPanel(...)` button calls and an
example `cm-admin:server:startHouseCreator` event. Source inspection
(`server/sv_admin.lua`) confirmed cm-admin never implemented those events,
and the earlier "client-side buttons" example called a server-only export
directly from client code, which cannot work. This revision documents the
mechanism that is actually wired up and running today.

## The real, active mechanism

cm-house registers itself as a launcher inside cm-admin's own Developer
Tools panel, not as a set of buttons cm-admin's UI calls directly:

```lua
-- server/sv_admin.lua, runs once cm-admin has started
exports['cm-admin']:RegisterDevTool({
    id = 'house', label = 'House Admin', category = 'World', icon = 'house',
    permission = 'house.admin.open',
    actions = {
        { id = 'open', label = 'Open House Admin', type = 'launcher', realm = 'server',
          event = 'cm-house:dev:openAdmin', hint = 'Opens the cm-house admin panel.' }
    }
})
```

Clicking that launcher in cm-admin's Developer section fires the plain
server event `cm-house:dev:openAdmin`, which cm-house handles itself:

```lua
AddEventHandler('cm-house:dev:openAdmin', function(src)
    openPanel(tonumber(src), 'houses')
end)
```

`openPanel` re-checks the player's current rank/ACL (`HasHouseStaffPermission`)
before opening anything — cm-admin's `permission = 'house.admin.open'` gate on
the launcher button is a UI convenience, not the authority boundary.

## Direct integration points (still valid, not what cm-admin currently uses)

These exports exist, are authorized (require the caller's resource to have
`admin = true` in `Config.Integration.authorizedResources`), and still work
if a future integration wants a custom button instead of the Developer Tools
launcher above. They are documented here for completeness, but cm-admin's
current build does not call them:

```lua
-- Server-side only; both re-check the target player's rank/ACL again.
exports['cm-house']:OpenAdminPanel(src, tab)   -- tab: 'houses' | 'interiors' | 'garages' | 'recovery'
exports['cm-house']:OpenHouseCreator(src)
exports['cm-house']:GetHouseAdminContract()
exports['cm-house']:GetHouseAdminPanelTabs()
```

Two same-resource network events exist for a client-triggered request (e.g.
a keybind or a different admin UI), also re-checked server-side:

```lua
TriggerServerEvent('cm-house:server:requestAdminPanel', tab)
TriggerServerEvent('cm-house:server:requestHouseCreator')
```

## Removed from this document

`cm-admin:server:openHousePanel` and `cm-admin:server:startHouseCreator`
(shown in `ADMIN_INTEGRATION_v1.5.0.md` as an example cm-admin-side handler)
were never implemented in cm-admin and are not an active contract. Do not
build against them.

## Permission keys

```text
house.admin.open
house.create
house.admin.properties
house.admin.interiors
house.admin.garages
house.admin.pricing
house.admin.photos
house.admin.recovery
```

The admin data payload (`cm-house:server:adminData`) contains capability
booleans per tab. Unauthorized tabs/actions are hidden client-side and
rejected server-side either way.
