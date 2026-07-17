# cm-vehicles v3.3.4

## Parked visibility and entity-preserving recall

- Added a `cmConditionReady` state-bag listener that reveals protected house-garage vehicles on every streaming client.
- Added one pooled stream/restart recovery scan for both parked and released garage vehicles.
- Parked protection now reasserts alpha 255, visibility and collision after condition readiness.
- Garage client-assisted creation applies and verifies the real saved condition locally before the finalize event.
- Delayed finalize events no longer reset a vehicle that is already ready back to hidden/loading state.
- Added guarded condition finalizers to prevent overlapping retries.
- Added `RecallWorldVehicle`, which moves the same registered world entity instead of deleting/recreating it.
- Repeated owned-vehicle spawn requests now recall an existing world vehicle and reject vehicles still stored in a house garage.
- Added `CreateVehicleForPlayer` export for trusted server integrations when a registered entity is genuinely missing.
- Added immediate `cmGarageDriving` state handling so approved engine starts release parked physics on every client.
- World recall refuses to move a vehicle currently driven by another player.
