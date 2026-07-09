# cm-core v1.1.0 foundation clean

This resource is now treated as a shared foundation only.

## Owns
- config helpers
- database wrappers
- server/client callbacks
- logger/audit helper
- validation/sanitization
- security/rate limited event helper
- state registry
- player state compatibility cache
- notification bridge
- plugin hooks/scheduler/cache

## Does not own long-term
- admin menus, ranks, permissions, or staff UI: move to `cm-admin`
- money balance ownership: move to `cm-playerdata`
- price/payout/reward calculation: move to `cm-economy`
- level/playtime/task unlocks: move to `cm-progression`

## Compatibility notes
`AddMoney`, `RemoveMoney`, `SetMoney`, `GetMoney`, `CanAfford`, and `TransferMoney` are still exported as compatibility bridges.
They first try `cm-playerdata`, then use a legacy `characters.cash/bank` fallback if `cm_core_legacy_money` is true.

After `cm-playerdata` is upgraded, set this in server.cfg:

```cfg
set cm_core_legacy_money false
```


## 1.1.1 DB wait fix

- Database exports now wait briefly for cm-core migrations to finish instead of immediately returning nil.
- Repeated `[CM-CORE] DB not ready` spam is rate-limited.
- cm-core waits for oxmysql to be started before running migrations.
