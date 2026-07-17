# cm-family integration — cm-house v1.7.0

`cm-family` should provide the rank decision only. `cm-house` remains the property authority.

Expected import:

```lua
exports('HasHousePermission', function(characterId, familyId, houseId, permissionKey, internalAction)
    return true_or_false
end)
```

Relevant permission keys:

- `door.enter`
- `door.lock`
- `garage.access`
- `garage.take`
- `garage.store`
- `garage.manage_shared`
- `weapon_storage.access`
- `weapon_storage.deposit`
- `weapon_storage.withdraw`
- `storage.access`
- `helipad.use`

Garage appearance customization was removed. No family rank should receive or call `garage.customize`.
