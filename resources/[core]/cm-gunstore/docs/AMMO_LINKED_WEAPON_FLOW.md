# Ammo-linked weapon flow

This update makes `cm-gunstore` use `cm-items` as the central item registry.

## Admin flow

1. Open `/gunadmin`.
2. Go to the Ammo tab.
3. Create ammo first, for example `7mm`, `6mm`, or `9mm`. The system creates an item name like `ammo_7mm` and registers it in `cm-items`.
4. Go to the Weapons tab.
5. Pick a gun from the weapon catalog.
6. Use the **Ammo Used By This Gun** dropdown to select one of the ammo items you already created.
7. Click Create or Update. The gun is saved into `cm-items` and `cm_gun_catalog`; the selected ammo name is stored as `ammo_item`.

## Delete flow

Admin rows and weapon cards now have **Delete** buttons. Delete removes the row from `cm_gun_catalog` and also tries to remove the runtime SQL item from `cm-items` using `DeleteCatalogItem`. Static code-defined items in `shared/items.lua` cannot be deleted from the UI; remove those from code if needed.

If ammo is deleted, any gun rows that were using that ammo have `ammo_item` cleared, so you can recreate/select ammo again.
