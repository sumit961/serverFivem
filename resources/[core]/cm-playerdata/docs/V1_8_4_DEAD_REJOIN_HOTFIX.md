# CM PlayerData v1.8.4 Dead Rejoin Hotfix

Fixes dead reconnect flow where spawn placement could overwrite the saved death/body location.

Changes:
- `cm-playerdata:server:updatePosition` ignores position saves while `isDead = true`.
- The saved death location captured by `SetDead` remains authoritative.
- Works with `cm-spawn` v1.1.2 which confirms client spawn completion and reopens deathscreen only after spawn UI closes.
