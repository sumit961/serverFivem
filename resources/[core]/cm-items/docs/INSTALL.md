# CM-Items install

Put this folder here:

```text
resources/[core]/cm-items
```

Add to `server.cfg` after `cm-core` and before future inventory:

```cfg
ensure cm-core
ensure cm-items
# ensure cm-inventory later
```

`cm-items` has no database and no UI. It is only an item registry used by future resources.

## Important design

Phone and keys are not inventory items in this design.

They are listed in `shared/virtual.lua` only as virtual/system definitions:

```text
phone        -> cm-phone later
vehicle_key  -> cm-keys later
house_key    -> cm-keys later
business_key -> cm-business later
```

Inventory should only use:

```lua
exports['cm-items']:GetInventoryItems()
exports['cm-items']:IsInventoryItem(itemName)
```

So phone/keys will not appear in normal inventory slots.
