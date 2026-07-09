# cm-weapons install

`cm-weapons` is the central weapon/ammo registry for the CM framework.

## server.cfg order

```cfg
ensure oxmysql
ensure cm-items
ensure cm-inventory
ensure cm-weapons
ensure cm-gunstore
```

## permissions

```cfg
add_ace group.admin cm.weapons.admin allow
add_ace group.admin cm.items.admin allow
```

## commands

```text
/cmweaponadmin  - in-game admin UI for fixed ammo and fixed weapons
/cmweaponsync   - force sync all weapon/ammo rows to cm-items
```

## database

The resource creates tables automatically. Manual SQL is also included at:

```text
install/cm_weapons.sql
```

## flow

```text
cm-weapons saves fixed ammo and fixed guns
        ↓
cm-weapons syncs those items into cm-items
        ↓
cm-gunstore should read sellable gun/ammo list from cm-weapons
        ↓
cm-inventory stores the actual item in slots
        ↓
cm-weapons controls weapon metadata: weapon hash, ammo item, damage, magazine, pickup hash
```
