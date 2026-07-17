# CM Inventory External Storage API

For the complete CM Inventory export/import reference, see
[EXPORTS_AND_IMPORTS.md](EXPORTS_AND_IMPORTS.md).

Use this API when another resource needs to open storage with the same inventory UI.
Vehicle trunks, warehouses, houses, businesses, motel rooms and future systems can all use this without editing the inventory UI again.

## Server export

```lua
local ok, err = exports['cm-inventory']:OpenExternalInventory(src, {
    ownerType = 'warehouse',      -- DB owner_type in inventory_items
    ownerId = 'warehouse_1',      -- DB owner_id in inventory_items
    slotPrefix = 'warehouse-',    -- DB slot prefix: warehouse-1, warehouse-2, ...
    slots = 30,                   -- current UI supports up to 30 visible slots
    kind = 'warehouse',
    label = 'Warehouse Storage',
    subtitle = 'Unit 1',
    replace = 'equipment',        -- replaces the equipment panel
    noWeightLimit = true,
    canDeposit = true,
    canWithdraw = true,
    data = { id = 1 }
})

if not ok then
    print(err)
end
```

## Vehicle trunk example

`cm-vehicles` now calls this export after it validates that:

- the trunk is open,
- the player is the vehicle owner,
- the player is close to the open trunk,
- the vehicle has trunk slots.

It stores trunk items in the existing `inventory_items` table using:

- `owner_type = 'vehicle_trunk'`
- `owner_id = vehicle.id`
- `slot = 'trunk-1'`, `trunk-2`, etc.



## 6x5 storage standard

All external storage screens now use the same 6 columns x 5 rows visual board in `cm-inventory`.
Use `displaySlots = 30` when opening an external inventory if you want the full board visible.
The actual usable slots are still controlled by `slots`. Keep `slots <= 30` in
the current UI so every usable storage slot remains visible and accessible.

Vehicle trunk example:

```lua
exports['cm-inventory']:OpenExternalInventory(src, {
  ownerType = 'vehicle_trunk',
  ownerId = tostring(vehicleId),
  slotPrefix = 'trunk-',
  slots = 6,          -- level 1 usable slots
  displaySlots = 30,  -- stable 6x5 UI board
  kind = 'vehicle_trunk',
  label = 'Vehicle Trunk',
  noWeightLimit = true
})
```

There are no category restrictions inside external storage. Any item can be placed in trunk/warehouse/house/business storage slots.
