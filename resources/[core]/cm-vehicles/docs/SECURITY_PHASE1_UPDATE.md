# CM Vehicles — Phase 1 Security Update

## Included

- `/vehgive` is disabled by default and requires ACE permission when enabled.
- Vehicle/entity proximity checks now fail closed.
- Plate, vehicle ID, model, routing bucket and network entity are cross-checked.
- Purchased vehicle spawn accepts only a database vehicle ID and reloads the record server-side.
- `saveState` reads live server entity state and allows normal wear only.
- Mileage is calculated from server-observed movement and clamped by elapsed time.
- `persistService` cannot improve fuel, health or cleanliness from a client request.
- Direct client `saveMods` calls are rejected.
- Passenger removal verifies the target is a passenger in the caller's exact vehicle.
- Radio starts on OFF but remains enabled so the player can select a station.
- Engine start now uses a short configurable key-turn animation.
- Vehicle information UI is a compact right-side dashboard.

## `/vehgive`

It is disabled by default in `shared/config.lua`:

```lua
Commands = {
    adminSpawnOwned = false,
    vehGiveAce = 'cmvehicles.vehgive'
}
```

To use it, set `adminSpawnOwned = true` and grant the ACE permission to the appropriate admin group:

```cfg
add_ace group.admin cmvehicles.vehgive allow
```

## Secure service integration

Petrol stations, mechanics and car washes must calculate payment and entitlement on their server, then call:

```lua
exports['cm-vehicles']:ServiceVehicle(plate, {
    fuel = serverCalculatedFuel,
    engineHealth = serverCalculatedEngineHealth,
    bodyHealth = serverCalculatedBodyHealth,
    tankHealth = serverCalculatedTankHealth,
    dirtLevel = serverCalculatedDirtLevel
})
```

Only include fields that the service is authorised to change.

## Secure tuning integration

After the tuning server validates the selected parts, calculates the price and successfully charges the player, save the approved modification table with:

```lua
local ok, err = exports['cm-vehicles']:SaveVehicleModsAuthorized(
    source,
    plate,
    vehicleNetId,
    approvedMods
)
```

The old client event `cm-vehicles:server:saveMods` is intentionally rejected. This prevents a modified client from applying unpaid upgrades.

## Not contained in this resource

`/vehicleadmin`, the tuning price catalogue and gas-station payment calculation are not implemented in `cm-vehicles`. Their owning resources must still be updated separately.
