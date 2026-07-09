# CM PlayerData v1.9.7 - Performance, Dead Restart, Vehicle/Trunk Labels

## Fixed
- Resource restart while dead no longer leaves players in a half-dead state without the death screen.
- The fallback death-state thread now forces `hasSpawnCompleted = true` for restored dead characters and starts the death UI once playerdata is loaded.
- Removed immediate synchronous `SaveMoneyOnly()` DB writes from `SetMoney`, `AddMoney`, and `RemoveMoney`.
- Money changes still mark playerdata dirty and are persisted by the existing background dirty-save loop.
- Added safe default fallbacks for vitals sync intervals:
  - `HealthSyncInterval` fallback: `5000`
  - `PositionSyncInterval` fallback: `6000`
- Player labels for vehicle occupants now lift above the vehicle roof while keeping the ped X/Y seat/trunk position.
- Player labels still show in cars/trunks, but the player G-menu remains disabled for vehicle occupants.

## Notes
- This update does not add full EMS carry/frisk/persistent identity DB gameplay yet. Those should be added through `cm-admin`, `cm-inventory`, EMS/police, family, and organization resources using `cm-playerdata` exports.
