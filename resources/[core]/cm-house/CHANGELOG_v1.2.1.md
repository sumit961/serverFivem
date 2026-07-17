# cm-house v1.2.1 — garage network spawn fix

- Replaced unreliable server-side garage `CreateVehicle` with the trusted
  `cm-vehicles` client-assisted network spawn export.
- Garage vehicles are accepted only after OneSync returns a valid network ID.
- Added stale-slot validation before call/drive-out.
- Call/drive-out now uses one guarded multi-table database update, preventing
  repeated calls from producing duplicate vehicles.
- Promotes the same registered garage entity to the world instead of spawning
  another copy.
- `cm-vehicles` is now a required dependency.
- Cleans stale networked garage-display entities when `cm-house` starts.
