# cm-playerdata v1.9.7 — Restart recovery, async money, vehicle-roof labels

Builds on v1.9.6. Four fixes.

## 1. Dead players no longer break on resource/server restart (client)
On restart, `hasSpawnCompleted` resets to false and the spawn resource may not
re-emit `spawnComplete`, so `StartPendingDeathState` kept bailing out and a dead
player was left in a broken half-dead state (no death screen, no NUI focus).

The recovery thread at the bottom of `client/main.lua` now also fires when the
loaded data says the player is dead (`PlayerData.isDead`), rebuilds
`pendingDeathData` from that data if it was lost, forces `hasSpawnCompleted = true`,
and kickstarts the death screen. A dead player is always re-shown their overlay.

## 2. No more synchronous DB hitching on economy transactions (server)
`SetMoney` / `AddMoney` / `RemoveMoney` each called `SaveMoneyOnly`, which uses
`MySQL.update.await` — a blocking write on every transaction. Those calls are
removed. The functions now just set `data.dirty = true` and the existing async
batch saver (every `Config.Save.FullSaveInterval`) persists cash/bank. Disconnect
and resource-stop still force a full save, so nothing is lost on a clean exit.

Note: with the per-transaction write gone, a hard crash could lose up to
`FullSaveInterval` (default 3 min) of money changes. If you want tighter
durability without the hitch, `SaveMoneyOnly` can be switched to a non-blocking
`MySQL.update` and re-added — say the word.

## 3. Vitals loop can't crash on a missing config key (client)
The health/position sync intervals now use inline fallbacks
(`Config.Vitals.HealthSyncInterval or 4000`, `PositionSyncInterval or 6000`), so
omitting either key from the config no longer throws a nil-comparison error that
kills the thread.

## 4. In-vehicle labels sit above the car roof, over the seat
Previously the ID sat at head height inside the car (on the glass). It now
anchors above the vehicle ROOF, horizontally over the player's seat, so it reads
like it is on their head above the car. It also covers players attached to a
vehicle (e.g. stuffed in a trunk). x/y come from the seat position (stable, no
head-bone idle jitter) and z from the vehicle roof, so the label follows the car
and the player only — it does not drift when the viewer moves the camera.
On-foot labels are unchanged. Tunable via `Interactions.VehicleRoofZOffset`.

## Config
- Removed: `Interactions.VehicleHeadZOffset`, `Interactions.VehicleOverheadZOffset`
- Added: `Interactions.VehicleRoofZOffset = 0.32`

## Not included (your "recommended additions")
Downed/comatose variety + finisher states, dragging/escorting + frisking, and the
persistent identity-memory DB table are larger features, not fixes. Happy to build
them next, one at a time, in impact order — they aren't in this build.
