# CM PlayerData Stable v1.1

This is a safe upgrade for your current working `cm-playerdata`.

## What it adds

- Keeps your old health/death/respawn/position flow.
- Uses `oxmysql` directly, so it avoids cm-core database export call-style bugs.
- Adds safer exports for money and needs.
- Adds metadata support.
- Adds playerdata_audit table.
- Adds schema check for missing columns.
- Adds better rate limiting for client sync events.
- Adds revive/export support for future EMS/police/admin systems.

## Install

1. Backup current folder:

```text
resources/[core]/cm-playerdata
```

2. Replace it with this new `cm-playerdata` folder.

3. Keep server.cfg order:

```cfg
ensure oxmysql
ensure ox_lib
ensure cm-core
ensure cm-auth
ensure cm-characters
ensure cm-playerdata
ensure cm-spawn
ensure cm-hud
```

4. Restart:

```cfg
restart cm-playerdata
```

## New exports

```lua
exports['cm-playerdata']:GetPlayerData(src)
exports['cm-playerdata']:GetMoney(src, 'cash')
exports['cm-playerdata']:AddMoney(src, 'cash', 100, 'reason')
exports['cm-playerdata']:RemoveMoney(src, 'bank', 500, 'reason')


exports['cm-playerdata']:Revive(src)
exports['cm-playerdata']:Respawn(src)
exports['cm-playerdata']:IsDead(src)
```

## For inventory later

When we build `cm-items` + `cm-inventory`, food/water items will call:

```lua
```

## Lite version note

This package does not include hunger, thirst, or stress. Keep those as a separate optional `cm-status` resource later if you want survival-style gameplay.
