# cm-admin integration for cm-house v1.5.0

## Server-side buttons

```lua
-- Example cm-admin server handler
RegisterNetEvent('cm-admin:server:openHousePanel', function(tab)
    local src = source
    exports['cm-house']:OpenAdminPanel(src, tab or 'houses')
end)

RegisterNetEvent('cm-admin:server:startHouseCreator', function()
    exports['cm-house']:OpenHouseCreator(source)
end)
```

The calling resource must have `admin = true` in `Config.Integration.authorizedResources`. `cm-house` then rechecks the player's current ACL/rank.

## Client-side buttons

```lua
exports['cm-house']:OpenAdminPanel('houses')
exports['cm-house']:OpenAdminPanel('interiors')
exports['cm-house']:OpenAdminPanel('garages')
exports['cm-house']:OpenAdminPanel('recovery')
exports['cm-house']:OpenHouseCreator()
```

These only request opening; they do not grant permissions.

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

The admin data payload contains capability booleans. Unauthorized tabs/actions are hidden client-side and rejected server-side.

During migration, `Config.AdminUseLegacyFallback = true` permits the old `house.create` permission. Disable the fallback when ranks are fully configured.

## Discovery

```lua
local contract = exports['cm-house']:GetHouseAdminContract()
local tabs = exports['cm-house']:GetHouseAdminPanelTabs()
```
