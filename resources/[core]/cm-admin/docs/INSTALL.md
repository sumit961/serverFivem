# CM Admin v2.5 - Character ID Admin

This resource gives you `/admin` mode, an F11 admin menu, rank permissions, player tools, inventory/vehicle bridge views, logs, noclip, and cash tools.

## Main workflow

1. Join the server normally.
2. Type `/admin` to enter admin mode.
3. Press `F11` to open the admin UI.
4. Type `/admin` again to leave admin mode and become a normal player again.

Noclip is still available, but only while admin mode is enabled:

- `F2`
- `/noclip`
- `/cmfly`
- `/fly`

## Give cash

Online player menu:

1. Type `/admin`.
2. Press `F11`.
3. Open **Players**.
4. Select a player.
5. Press **Give Cash**.
6. Enter the amount and reason.

Command option:

```text
/cmgivecash [serverId] [amount] [reason]
```

Example:

```text
/cmgivecash 3 5000 compensation
```

By default, this updates `characters.cash`:

```lua
Config.DatabaseBridge.AddCashQuery = 'UPDATE characters SET cash = GREATEST(0, COALESCE(cash, 0) + ?) WHERE id = ?'
```

The max single grant is controlled here:

```lua
Config.AdminMoney = {
    MaxGiveCash = 1000000,
    AllowSelfGiveCash = true
}
```

The action is written into `cm_admin_logs` as `money_give_cash`.

## Default owner by character id

Your config uses character id, not account identifier:

```lua
Config.OwnerCharacterIds = {
    12
}
```

Only character id `12` becomes Owner. If the same FiveM account has character id `13`, that second character is a normal player.

Change `12` to your real owner character id if needed.

## Recommended server.cfg

Keep your existing ensure order:

```cfg
ensure oxmysql
ensure cm-core
ensure cm-auth
ensure cm-characters
ensure cm-playerdata
ensure cm-admin
ensure cm-spawn
```

Do not use ACE fallback if you want admin to be character-id only. Keep `Config.AllowAceAdminBootstrap = false`.

## Created database tables

The resource auto-creates:

- `cm_admins`
- `cm_admin_ranks`
- `cm_admin_logs`

## Menu features

- Dashboard
- Online player list
- Player management: go to, bring, freeze, unfreeze, heal, armor, give cash, kick
- View player inventory through configurable SQL bridge
- View player cars through configurable SQL bridge
- View vehicle/trunk inventory by plate through configurable SQL bridge
- Add admins by character ID
- Disable admins
- Change admin rank by character ID
- Create/edit/delete ranks
- Manage rank permissions
- View admin logs

## Inventory / vehicle bridge

Your framework tables may have different names. Open `config.lua` and update:

```lua
Config.DatabaseBridge.InventoryQueries
Config.DatabaseBridge.VehicleQueries
Config.DatabaseBridge.VehicleInventoryQueries
```

The script safely tries each query. If a table does not exist, it skips it without crashing.

## Common test

1. Start server.
2. Join with your FiveM account.
3. Type `/admin`.
4. Press `F11`.
5. Go to Ranks and confirm Owner has `*` permission.
6. Add another staff member using their selected character ID, for example `12`, not `fivem:` or `license:`.
7. Go to Players, select a player, use **Give Cash**, and check that `characters.cash` increased.
