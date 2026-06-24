# CM Items Update Notes

## Changed
- Removed duplicate `clothing_legs` item. `legs` now aliases to `pants` and uses `clothing_pants`.
- Added missing clothing categories: mask, arms/gloves, decals, bracelet.
- Added `worldModel` support for items and category fallback props.
- Added stronger metadata validation with type checks.
- Added startup item definition validation.
- Made clothing catalog client sync log respect `CMItems.Config.Debug`.
- Added admin preview `Get` button to give test items to inventory.

## Inventory test button
The preview UI calls:

```lua
exports['cm-inventory']:AddItem(src, itemName, amount, metadata)
```

It also tries common fallback signatures. If your `cm-inventory` uses a different export name, update:

```lua
CMItems.Config.Inventory.Resource = 'cm-inventory'
CMItems.Config.Inventory.AddItemExport = 'AddItem'
```
