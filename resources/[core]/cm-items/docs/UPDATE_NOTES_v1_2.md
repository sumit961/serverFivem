# cm-items v1.2 cleanup / preview test update

## Added
- `worldModel` support on item definitions.
- `CMItems.GetItemWorldModel(itemName, metadata)` export.
- `CMItems.GetCategoryWorldModel(category)` export.
- `CMItems.ValidateDefinitions()` startup validation.
- Stronger metadata validation with `metadataSchema`.
- More clothing categories: mask, arms/gloves, decals, bracelet.
- Admin preview button: **Get in inventory**.

## Changed
- `clothing_legs` duplicate item was removed.
- `legs` now aliases to `pants`, and `clothing_legs` aliases to `clothing_pants` inside the API.
- Clothing catalog sync print is now debug-only.

## Preview inventory test
Open with:

```lua
/cmitempreview
```

Click **Get in inventory** on any item or catalog clothing row.

The test giver tries these exports:

```lua
exports['cm-inventory']:AddItem(source, itemName, amount, metadata)
exports['cm-inventory']:addItem(source, itemName, amount, metadata)
exports['cm-inventory']:AddPlayerItem(source, itemName, amount, metadata)
exports['ox_inventory']:AddItem(source, itemName, amount, metadata)
```

If your cm-inventory export name is different, update `server/main.lua` inside `addPreviewItemToInventory()`.
