# cm-gunstore v1.8.0 - Config Prices + New Store UI

## Changed
- Store prices now come from `shared/config.lua` only (`Config.StoreCatalog`).
- `/gunadmin` no longer edits weapon/ammo prices, images, damage, ammo link, weight, or descriptions.
- `/gunadmin` can still set stock and Store/Hidden for weapon/ammo rows.
- Weapon/ammo source data comes from `cm-weapons` fixed catalog.
- Ammo can be bought as exactly 1 round or any chosen quantity.
- Added default buyable armor item: `armor_light`.
- Added a fullscreen Ammu-Nation-style UI with left category list, center item preview, right item information, stat bars, and ammo quantity panel.

## Config
- Edit prices in `Config.StoreCatalog`.
- Edit the default armor item in `Config.DefaultArmor`.
- Edit ammo max/min purchase quantity in `Config.AmmoQuantity`.

## Test steps
1. Ensure order: `cm-weapons`, then `cm-gunstore`.
2. Restart both resources.
3. Open the shop and confirm weapons, ammo, and armor appear.
4. Select an ammo item, set quantity to `1`, and buy it.
5. Confirm inventory receives 1 ammo item/round and money is removed through `cm-playerdata`.
6. Run `/gunadmin` and confirm weapon/ammo price fields are disabled/config-only.
7. Toggle one item Store/Hidden and confirm it appears/disappears in the player shop.
8. Buy `Light Armor Vest` and confirm it is added as an inventory item.
