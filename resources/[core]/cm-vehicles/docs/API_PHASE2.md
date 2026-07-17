# cm-vehicles 3.4.0 — Phase 2 Integration API

This document describes the supported public API for permanent vehicles, physical entities, persistence, locations, operations, recovery, access, keys and service integrations.

## Authority boundary

`cm-vehicles` owns:

- `cm_owned_vehicles` and the permanent database vehicle ID;
- the one active physical network entity;
- spawn registry and duplicate prevention;
- condition, fuel, dirt, mileage, modifications and lock state;
- keys, temporary keys, trunk and vehicle service operations;
- unified vehicle location and durable lifecycle operations.

`cm-house` owns the permanent vehicle-to-property-slot assignment. Never create a competing house-slot cache inside `cm-vehicles`.

## Discover the contract

```lua
local contract = exports['cm-vehicles']:GetVehicleIntegrationContract()
```

The table contains authority ownership, access actions, location states and all supported server/client exports.

## Identity and record exports

### `CreateOwnedVehicle(source, model, label, trunkLevel, metadata)`

Creates a permanent owned vehicle for the source character and returns success plus the new row summary. Call only from trusted purchase/admin resources.

### `GetVehicleById(vehicleId)`

Returns the normalized permanent vehicle row.

### `GetVehicleByPlate(plate)`

Returns the permanent row matching the normalized plate.

### `GetVehiclesByOwner(characterId, options)`

Returns up to `options.limit` rows, including decoded metadata/mods/condition and unified location.

### `GetCharacterId(source)`

Returns the active character ID resolved from player state/core compatibility.

### `PlayerOwnsVehicle(source, plateOrVehicleId)`

Checks legal ownership.

### `HasVehicleAccess(source, plateOrVehicleId)`

Compatibility access check.

### `CanUseVehicle(source, vehicleIdOrPlate, action)`

The unified authorization gate for new integrations.

```lua
local allowed, accessKind, vehicle = exports['cm-vehicles']:CanUseVehicle(
    source,
    vehicleId,
    'vehicle.drive'
)
```

Supported actions include:

- `vehicle.drive`
- `vehicle.lock`
- `vehicle.engine`
- `vehicle.info`
- `vehicle.trunk.open`
- `vehicle.trunk.deposit`
- `vehicle.trunk.withdraw`
- `vehicle.keys.manage`
- `vehicle.family.share`
- `vehicle.sell`
- `vehicle.tune`
- `vehicle.repair`
- `vehicle.track`
- `vehicle.delete`

Owner-only actions fail closed for temporary key/family users. Family access delegates to `cm-house:CanAccessProperty`; police/admin overrides are optional runtime integrations.

## Physical entity and spawn exports

### `CreateVehicleForPlayer(source, vehicleRow, coords, options)`

Creates and registers a normal owned world entity.

### `SpawnVehicleFromParking(source, vehicleIdOrPlate, coords, options)`

Retrieves a stored vehicle, applies insurance rules, creates the entity and restores the saved condition.

### `CreateGarageVehicle(source, vehicleRow, spawn, context)`

Creates a house-garage display entity through the controlled client-assisted path.

### `GetSpawnedVehicleInfo(vehicleIdOrPlate)`

Returns the registered active entity information.

### `ConfigureHouseGarageVehicle(vehicleId, houseId, slotIndex, bucket)`

Marks the active entity as the display vehicle for one property slot.

### `GetSpawnedVehicleCondition(vehicleId, fallbackRow)`

Captures/returns the best trusted condition snapshot.

### `IsPlayerDrivingSpawnedVehicle(source, vehicleId, expectedNetId)`

Server-side driver/entity verification.

### `PromoteHouseGarageVehicle(vehicleId, source, worldSpawn)`

Moves the same garage entity to the world during drive-out.

### `RecallWorldVehicle(vehicleId, source, garageSpawn)`

Recovers an outside entity for garage recall.

### `ReturnHouseGarageVehicle(vehicleId, houseId, slotIndex, bucket, spawn)`

Returns/repositions a registered entity to its garage display context.

### `SetSpawnContext(vehicleId, source, context)`

Updates authoritative registry context.

### `DeleteSpawnedVehicle(vehicleIdOrPlate)`

Synchronously deletes the registered entity. Treat `false` as a transition failure and roll back database changes.

### `RemoveDuplicateVehicleEntities(vehicleId, keepEntity)`

Removes other OneSync entities carrying the same permanent `cmVehicleId`.

### `CleanupHouseGarageVehicles()`

Deletes temporary garage display entities while preserving database assignments.

### `ReconcileSpawnRegistry()`

Rebuilds registry identity by database vehicle ID and removes stale/duplicate entities.

## Immediate persistence and dirty-state exports

### `PersistVehicleState(source, packet, reason)`

Internal/trusted server persistence entry. Client packets are validated against entity identity, distance and a current or very recent server-recorded driver session.

### `CaptureVehicleState(vehicleId, reason)`

Captures the current registered entity state into the persistence cache.

### `FlushVehicleState(vehicleId, reason)`

Writes pending dirty fields immediately.

```lua
exports['cm-vehicles']:CaptureVehicleState(vehicleId, 'before_custom_transition')
local ok, reason = exports['cm-vehicles']:FlushVehicleState(vehicleId, 'before_custom_transition')
```

### `FlushAllVehicleStates(reason)`

Flushes all cached dirty states, including during resource stop.

### `GetVehiclePersistenceStatus(vehicleId)`

Returns the in-memory cached snapshot/dirty metadata for diagnostics.

### Client: `FlushCurrentVehicle(reason)`

Requests an immediate save for the local driver's current/recent vehicle.

Dirty-state thresholds are configured in `CMVehicles.Config.Persistence`. Natural wear may be persisted by the client; paid repairs/refuels/washes still require trusted service paths.

## Unified location exports

Location states:

- `OUTSIDE`
- `HOUSE_GARAGE`
- `PUBLIC_GARAGE`
- `JOB_GARAGE`
- `IMPOUND`
- `POLICE_SEIZED`
- `DESTROYED`
- `PENDING_STORE`
- `PENDING_SPAWN`
- `PENDING_MOVE`
- `PENDING_DELETE`
- `STORED`

### `GetVehicleLocation(vehicleIdOrPlate)`

Returns `{ vehicleId, plate, state, ref, slot, isStored, garage, parkingId, updatedAt }`.

### `GetVehicleLocationStates()`

Returns the state constants.

### `TransitionVehicleLocation(vehicleId, state, data)`

Protected by `CMVehicles.Config.Location.authorizedResources`.

```lua
local ok, location = exports['cm-vehicles']:TransitionVehicleLocation(
    vehicleId,
    'HOUSE_GARAGE',
    {
        ref = tostring(houseId),
        slot = slotIndex,
        reason = 'house_store',
        actorCharacterId = characterId,
    }
)
```

It updates unified fields and compatible legacy fields, then writes location history.

### `ReconcileVehicleLocation(vehicleId)`

Rebuilds unified location from legacy columns after a compatibility workflow.

### `ReconcileAllVehicleLocations()`

Backfills/reconciles all permanent vehicle rows.

## Durable operation journal exports

Use these around every multi-step operation that can otherwise duplicate, delete or strand a vehicle.

### `BeginVehicleOperation(vehicleId, operationType, source, details)`

Protected by `CMVehicles.Config.Operations.authorizedResources`.

```lua
local ok, token = exports['cm-vehicles']:BeginVehicleOperation(
    vehicleId,
    'custom_store',
    source,
    {
        ttl = 45,
        stage = 'validated',
        targetState = 'PUBLIC_GARAGE',
        targetRef = 'public:central',
        targetSlot = 12,
    }
)
```

Only one active operation can own a vehicle.

### `AdvanceVehicleOperation(vehicleId, token, stage, details)`

Updates the durable stage and expiry.

### `CompleteVehicleOperation(vehicleId, token, stage, details)`

Completes the journal row, releases the lock and reconciles location.

### `FailVehicleOperation(vehicleId, token, stage, details)`

Records failure and releases the lock after the caller performs its rollback.

### `IsVehicleOperationActive(vehicleId)`

Returns whether a live in-memory operation owns the vehicle.

### `GetVehicleOperations(vehicleId, limit)`

Returns recent durable operation rows for admin tools.

### `RecoverInterruptedVehicleOperations()`

Reconciles rows marked `recovery_required` after restart.

## Recovery and diagnostics exports

### `GetVehicleDiagnostics(vehicleIdOrPlate)`

Returns permanent row, location, house assignment, active registry record, matching OneSync entities, duplicate count, operation history and detected issues.

### `ListVehicleRecoveryProblems(limit)`

Returns vehicles with location/assignment/entity inconsistencies plus live duplicate groups.

### `DeleteDuplicateVehicleEntities(vehicleId, keepEntity)`

Deletes duplicate physical entities while retaining one valid entity when supplied.

### `RunVehicleRecoveryAction(source, vehicleIdOrPlate, action, data)`

Staff-protected recovery actions:

- `inspect`
- `reconcile`
- `duplicates`
- `clear_assignment`
- `public`
- `impound`
- `recall`
- `delete_entity`

```lua
local ok, result = exports['cm-vehicles']:RunVehicleRecoveryAction(
    source,
    vehicleId,
    'reconcile',
    {}
)
```

### `IsVehicleRecoveryAdmin(source)`

Checks `cm-admin`, `cm-core` or ACE recovery permission.

Command fallbacks:

```text
/cmvehinspect [vehicleId|plate]
/cmvehrecover [vehicleId|plate] [reconcile|duplicates|recall|public|impound|clear_assignment|delete_entity]
```

## Keys, service and modification exports

### `GetLentKeys(source)`

Returns temporary/lent keys for the active character.

### `ServiceVehicle(source, vehicleIdOrPlate, patch, reason)`

Trusted server service operation for mechanic/admin/inventory integrations.

### `SaveVehicleModsAuthorized(source, vehicleIdOrPlate, mods, reason)`

Trusted modification persistence.

### `HasRacingHarness(source, vehicleIdOrPlate)`

Returns harness state.

### `InstallRacingHarness(source, plate, netId)`

Server-only allowlisted installation path. The calling resource must already have charged money or consumed the harness item.

## Temporary/admin vehicle exports

- `SpawnAdminVehicle(source, model, coords, options)`
- `DeleteAdminVehicle(plate)`
- `DeleteAllAdminVehicles(spawnedBy)`
- `IsAdminVehicle(plate)`
- `SetAdminVehicleAccess(plate, access, ownerCharacterId)`
- `ListAdminVehicles()`

Temporary admin vehicles have no permanent `cm_owned_vehicles` row and disappear on restart.

## Client vehicle exports

- `TryOpenNearbyTrunkInventory()`
- `HasRacingHarness(vehicle)`
- `GetVehicleFuel(vehicle)`
- `AddFuel(vehicle, amount)`
- `SetFuelExact(vehicle, percent)`
- `RepairVehicle(vehicle, options)`
- `WashVehicle(vehicle)`
- `SaveVehicleMods(vehicle, mods)`
- `ApplyVehicleMods(vehicle, mods)`
- `ApplyPerformance(vehicle, metadata)`
- `GetTuningMultiplier(vehicle)`
- `ApplyTyreLevel(vehicle, level)`
- `GetTyreLevel(vehicle)`
- `EstimateTopSpeed(vehicle, engineLevel)`
- `RunServiceProgress(kind, vehicle, durationMs)`
- `ShowServiceProgress(kind, title, subtitle)`
- `UpdateServiceProgress(percent)`
- `HideServiceProgress()`
- `FlushCurrentVehicle(reason)`
- `IsAdminVehicleClient(entity)`

Client exports are presentation/native helpers, not authorization. The server must revalidate identity, ownership/access, proximity, bucket and operation state.

## Resource imports used by cm-vehicles

`cm-vehicles` may call:

- `cm-house`: permanent assignment, family access and recovery;
- `cm-playerdata` / `cm-core`: character identity and economy compatibility;
- `cm-admin` / `cm-core`: staff ACL checks;
- `cm-police`: optional police action override;
- `cm-inventory`: trunk and service-item inventory;
- `cm-vehiclekeys`: key ownership/engine integration.

## Integration rules

1. Use permanent database vehicle ID as primary identity; plate is compatibility/display identity.
2. Never spawn before checking the registry and duplicate entities.
3. Capture and flush state before delete/move/store operations.
4. Acquire one durable operation token before changing physical and database state.
5. Roll back legacy and unified location fields if a required physical step fails.
6. Do not pay, repair or consume items from an untrusted client event.
7. Use `CanUseVehicle` for new access decisions instead of duplicating owner/key/family logic.
8. Use `cm-house` exports for slot assignments; never write its tables directly.
