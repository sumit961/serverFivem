# cm-weapons v1.3.0 - Fixed Catalog + 7 Ammo Families

## Changed
- Converted `cm-weapons` into a fixed config-driven weapon/ammo registry.
- Admin panel can upload/replace ammo and weapon images only.
- Damage, magazine size, ammo link, weight, enabled state, and description now come from `shared/defaults.lua`.
- Defaults are synced into the database on every start while preserving existing custom uploaded images.
- Deprecated/non-config rows are disabled and hidden from exports when `Config.StrictFixedCatalog = true`.

## Ammo model
Only 7 ammo items are used:
1. `ammo_9mm` - 9mm Parabellum for regular pistols.
2. `ammo_44magnum` - .44 Magnum for heavy revolvers.
3. `ammo_9x19_smg` - 9x19mm for all SMGs.
4. `ammo_556nato` - 5.56 NATO for all rifles.
5. `ammo_762nato` - 7.62 NATO for all machine guns.
6. `ammo_12gauge` - 12 Gauge for all shotguns.
7. `ammo_308win` - .308 Winchester for snipers/marksman rifles.

No RPG, grenade launcher, rocket, or explosive ammo is included.

## Test steps
1. Ensure `cm-weapons` after `oxmysql` and before `cm-gunstore`.
2. Start the server and run `/cmweaponadmin`.
3. Confirm exactly 7 ammo rows show.
4. Confirm weapon rows use one of the 7 ammo items.
5. Upload an ammo or weapon image and confirm it syncs to `cm-items`.
6. Restart `cm-weapons`; confirm damage/weight/description stay from config and the uploaded image remains.
