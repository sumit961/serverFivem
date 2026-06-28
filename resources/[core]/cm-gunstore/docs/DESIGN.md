# cm-gunstore design

This resource follows the same idea as `nv_cloth`:

- Store/catalog is the source of truth.
- Admin enables items and sets prices.
- Purchase gives an inventory item, not direct equipment.
- Metadata carries image, label, serial, ammo type, durability, and purchase timestamp.
- Inventory displays the same image through `metadata.image`.

Weapon metadata example:

```lua
{
  label = 'Pistol',
  image = 'nui://cm-gunstore/web/images/weapon_pistol.svg',
  category = 'weapon',
  itemType = 'unique',
  weaponHash = 'WEAPON_PISTOL',
  ammoType = 'ammo_9mm',
  serial = 'CMW-...',
  durability = 100
}
```

Ammo metadata example:

```lua
{
  label = '9mm Ammo Box',
  image = 'nui://cm-gunstore/web/images/ammo_9mm.svg',
  category = 'ammo',
  itemType = 'normal',
  ammoType = 'ammo_9mm',
  packSize = 24
}
```
