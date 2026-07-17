# cm-vehicles v3.2.9-garage-lifecycle-final

- Added garage-only health normalization that rejects nil/zero/negative condition skeletons.
- Retained client-owned network creation and physics-alive health initialization for streamed/addon vehicles.
- Added verified retry before revealing parked vehicles.
- Added continuous parked condition protection across ownership migration.
- `DeleteSpawnedVehicle` now cancels pending creates, deletes registry and orphan entities synchronously, and reports failure.
- Added per-plate shared creation promises and safe re-linking of valid existing garage entities.
- Updated API documentation to require affected-row-checked guarded multi-table database transitions.
