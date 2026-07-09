# CM weapon/ammo design

## Why separate cm-weapons from cm-gunstore?

`cm-gunstore` should only sell items. It should not be the weapon brain.

`cm-weapons` is now the central weapon brain:

- fixed ammo list
- fixed gun list
- weapon hash
- gun damage
- magazine size
- allowed ammo item for each gun
- GTA pickup hash used when ammo is dropped
- sync to `cm-items`

## Damage belongs to gun

Ammo does not store damage now. The same ammo can be used by many weapons, while every gun has its own damage.

Example:

```text
ammo_556 = 5.56 Rifle Ammo
weapon_carbinerifle uses ammo_556 and damage 32
weapon_advancedrifle uses ammo_556 and damage 30
weapon_specialcarbine uses ammo_556 and damage 32
```

## Pickup hash belongs to ammo type

Ammo has an `ammoKey`. That key chooses the GTA pickup hash:

```lua
pistol  = 544828034
smg     = 292537574
rifle   = 3837603782
mg      = 3730366643
shotgun = 2012476125
sniper  = 3224170789
grenade = 2283450536
rocket  = 2223210455
minigun = 4065984953
```

Example:

```text
ammo_556 has ammoKey rifle, so dropped ammo can use PICKUP_AMMO_RIFLE.
ammo_9mm has ammoKey pistol, so dropped ammo can use PICKUP_AMMO_PISTOL.
```

## cm-items sync

Every ammo row becomes a `cm-items` item with metadata:

```lua
{
  itemType = 'ammo',
  ammoKey = 'rifle',
  pickupHash = 3837603782,
  packSize = 60
}
```

Every gun row becomes a `cm-items` item with metadata:

```lua
{
  itemType = 'weapon',
  weaponHash = 'WEAPON_CARBINERIFLE',
  ammoItem = 'ammo_556',
  damage = 32,
  magazineSize = 30
}
```
