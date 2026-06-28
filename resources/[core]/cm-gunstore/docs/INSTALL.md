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
ensure cm-inventory
ensure cm-gunstore
```

## 3. Inventory item support

The store gives weapons and ammo as inventory items. `cm-inventory` or `cm-items` must know these item names.

This resource includes:

```text
install/cm-inventory-gun-items-patch.lua
```

Merge that patch into your inventory config, or add equivalent item definitions into `cm-items`.

## 4. Admin command

```text
/gunadmin
```

Admin can:
- enable/disable weapon/ammo items
- set price
- set label
- set image path
- edit description

## 5. Player shop

Players press `E` at configured gun stores. Purchases go to inventory.

Weapons are not directly given to GTA weapon wheel. The item must be used/equipped from inventory.

## 6. Permissions later

For production, lock admin:

```cfg
add_ace group.admin cm.gunstore.admin allow
add_principal identifier.fivem:YOUR_ID group.admin
```
