# cm-vehicles v3.2.1 — garage network spawn fix

- Added a server-only `CreateGarageVehicle` export.
- A server-issued one-time token asks the garage viewer's client to load and
  create streamed/add-on models as real network vehicles.
- The server validates source, model, position, entity type and network ID
  before registering the entity.
- Rejected/timed-out entities are deleted.
- Garage entities are registered as persistent and are not deleted when the
  temporary creator disconnects.
- Added `SetSpawnContext` for promoting the same garage entity to the world.
- Improved `SafeNetId` with a short network-registration wait.
- Added stale house-garage entity cleanup for upgrades/restarts.
