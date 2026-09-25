# cm-law persistent fleet recovery contract

Generic Law and embedded Police call the server-only `cm-vehicles` export:

```lua
exports['cm-vehicles']:RecoverPersistentWorldVehicle(source, vehicleId, spawn, {
    organizationId = 'police', -- or the caller's verified Law organization
})
```

Only `cm-law` may invoke this export. `cm-vehicles` owns per-`vehicle_id` recovery serialization, validates the existing row's organization ownership, and tries `CreateVehicleServerSetter` before a bucket-0 client-assisted fallback. It returns one result table containing the existing persistent vehicle ID and never inserts an owned-vehicle row. Startup calls may pass no source; those calls still attempt server creation and return `waiting_for_client` only when a suitable client is needed.

The separate `CreatePersistentWorldVehicle(vehicleId, spawn, context)` export remains available to `cm-law` for server-only creation. Recovery code should use `RecoverPersistentWorldVehicle` so the shared fallback and per-ID recovery state are applied.
