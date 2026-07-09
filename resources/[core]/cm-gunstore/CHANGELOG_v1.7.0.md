# cm-gunstore v1.7.0 Changelog

## Fixed / cleaned
- Removed confusing legacy default gun/ammo catalog seed from config. `cm-gunstore` now only sells items made in `cm-weapons`.
- Admin weapon/ammo picker still lists all weapons/ammo from `cm-weapons`, but only saves price, stock, image override, description override, and In Store/Hidden.
- Optimized admin/store catalog loading by reading weapon/ammo definitions in bulk instead of doing one export lookup per item row.
- Fixed ammo stock handling: buying a 30-round ammo box now decreases store stock by 1 purchase, not 30.
- Added atomic stock reservation so two players cannot buy past the last limited-stock item.
- Added stock refund/release if money removal or inventory add fails.
- Disabled the old `guntargetdebug` command unless `Config.EnableDebugCommand = true`.
- Image save now checks `SaveResourceFile` result.
- Armor sync to `cm-items` is protected with `pcall` so an item export error does not crash the gunstore resource.

## Responsibility rule
- `/cmweaponadmin`: create/manage gun and ammo definitions/images/rules.
- `/gunadmin`: choose which existing gun/ammo/armor items are sold and set price/stock/visibility.

## Test steps
1. Ensure order: `cm-items`, `cm-weapons`, `cm-playerdata`, `cm-inventory`, then `cm-gunstore`.
2. Run `/cmweaponadmin`, save at least one ammo and one weapon.
3. Run `/gunadmin`, open Weapons tab, set price/stock, tick In Store, save.
4. Open Ammo tab, set price/stock, tick In Store, save.
5. As a normal player, walk to gun store, buy with cash and bank.
6. Confirm:
   - Money is removed from `cm-playerdata`.
   - Item goes to inventory, not GTA weapon wheel directly.
   - Weapon has serial/durability/ammo metadata.
   - Ammo stock decreases by 1 purchase, while inventory receives the configured pack size.
   - If inventory add fails, money is refunded and stock is restored.
