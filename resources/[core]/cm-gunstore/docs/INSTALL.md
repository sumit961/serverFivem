# cm-gunstore install

## 1. Put resource in server

Place this folder here:

```text
resources/[core]/cm-gunstore
```

## 2. server.cfg order

```cfg
ensure oxmysql
ensure cm-core
ensure cm-playerdata
ensure cm-items
ensure cm-inventory
ensure cm-weapons
ensure cm-gunstore
```

## 3. Weapon/ammo source

`cm-gunstore` v1.2 does **not** create gun or ammo items.

Create and edit gun/ammo definitions in:

```text
/cmweaponadmin
```

Then open:

```text
/gunadmin
```

Use gun store admin only to choose what is sold, and set:

- price
- stock
- store on/off
- optional store image/description override

## 4. Inventory item support

`cm-weapons` syncs weapons and ammo into `cm-items`.
`cm-gunstore` only gives those item names to `cm-inventory` when a player buys them.

Armor/vest items can still be created in `cm-gunstore` because they are store items, not weapon rules.

## 5. Player shop

Players press `E` at configured gun stores. Purchases go to inventory.

Weapons are not directly given to GTA weapon wheel. The item must be used/equipped from inventory/`cm-weapons`.

## 6. Permissions

```cfg
add_ace group.admin cm.gunstore.admin allow
add_ace group.admin cm.weapons.admin allow
add_ace group.admin cm.items.admin allow
add_principal identifier.fivem:YOUR_ID group.admin
```


## Playerdata wallet

Purchases now use `cm-playerdata` wallet exports only. Gun store removes `cash` or `bank` with `RemoveMoney`, gives the inventory item, and refunds with `AddMoney` if inventory fails.
