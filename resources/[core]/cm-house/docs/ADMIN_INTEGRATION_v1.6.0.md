# cm-admin integration for cm-house v1.6.0

Existing button exports remain:

```lua
exports['cm-house']:OpenAdminPanel(source, 'garages')
exports['cm-house']:OpenHouseCreator(source)
```

The server always re-checks the player's current rank permission. A button does
not grant access.

## Garage layout workflow

The Garage Layouts panel supports:

1. GPS teleport.
2. Player entry capture.
3. Multiple internal vehicle exits.
4. Fixed Garage Settings point.
5. Optional wall/light/decor anchors.
6. Real placement-car parking slots.
7. Preview, rename, re-walk, disable, enable and delete.

A template referenced by any property cannot be disabled or deleted. The server
repeats the usage check and the database foreign key remains the final guard.

## Permission

Use the existing rank-ready key:

```text
house.admin.garages
```

or the configured equivalent in `Config.AdminPermissions.garages`.
