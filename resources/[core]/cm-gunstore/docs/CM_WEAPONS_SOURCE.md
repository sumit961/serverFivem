# cm-gunstore + cm-weapons source flow

`cm-gunstore` no longer creates weapon or ammo definitions.

## Correct flow

1. Use `/cmweaponadmin` to create/edit fixed ammo and weapons.
   - Ammo name, label, ammo pickup type/hash, pack size, weight, image.
   - Weapon name, GTA weapon hash, allowed ammo item, damage, magazine size, weight, image.
   - These items sync into `cm-items`.

2. Use `/gunadmin` to sell them.
   - Lists all server weapons from `cm-weapons`.
   - Lists all server ammo from `cm-weapons`.
   - Gun store only controls price, stock, store visibility, and optional store override image/description.

3. Delete meaning:
   - `/gunadmin` Remove Store = remove only from store catalog.
   - `/cmweaponadmin` Delete = delete the actual weapon/ammo item definition and remove from `cm-items` catalog.

## Why prices are not in cm-weapons

`cm-weapons` is the weapon registry. A weapon can be sold in multiple future shops, black markets, police armories, crafting systems, or admin rewards. Each place can have its own price, so price belongs to the selling system, not the weapon definition.
