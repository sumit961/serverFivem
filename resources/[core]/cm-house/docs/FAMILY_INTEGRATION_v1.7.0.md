# cm-family integration — cm-house v1.7.0

`cm-house` remains the property authority. `cm-family` verifies active membership
and the linked family house. Every active member receives `door.enter` and
`garage.access` automatically; other permissions remain rank-controlled.

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

Basic house and garage entry does not grant vehicle use. Taking family vehicles
still requires `garage.take` and the vehicle's family access-level check;
storing a personal vehicle still requires `garage.store`.
