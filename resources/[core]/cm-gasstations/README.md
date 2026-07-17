# cm-gasstations v2.0.0

Secure gas-station and vehicle-supply resource for the CM framework.

## Main changes

- Replaced the native FiveM help box with a custom cyan NUI interaction prompt.
- Added a compact right-side gas-station UI so the vehicle remains visible.
- The selected vehicle is stopped, handbraked, frozen and switched off while the menu is open.
- Fuel price and final fuel are calculated and authorised by the server.
- The client can no longer choose a cheap `fuelAdd` value and a different `fuelTarget`.
- Fuel orders are bound to a short-lived pump, player and vehicle session.
- Vehicle network ID, plate, model, distance, routing bucket and key access are validated.
- Added per-player order locks, request cooldowns and quantity limits.
- Added refund handling for failed item delivery or failed vehicle updates.
- Jerry can, repair kit and wash kit use server-authorised vehicle updates.
- Supports either `cm-items` or `cm-item` for catalogue registration.
- No `backdrop-filter` is used.

## Required resources

Recommended order:

```cfg
ensure cm-playerdata
ensure cm-items       # or cm-item
ensure cm-inventory
ensure cm-vehiclekeys
ensure cm-vehicles
ensure cm-gasstations
```

This version is designed for the secure `cm-vehicles` build that provides:

```lua
exports['cm-vehicles']:GetVehicleByPlate(plate)
exports['cm-vehicles']:HasVehicleAccess(source, plate)
exports['cm-vehicles']:ServiceVehicle(plate, patch)
```

OneSync must be enabled because the server validates the real networked vehicle entity.

## Interaction

At a configured gas-station forecourt, a custom on-screen prompt appears:

- With an accessible nearby vehicle: `Refuel vehicle & open store`
- Without a vehicle: `Open gas station store`

When `E` is pressed with a vehicle selected, the vehicle is secured in the same position until the UI closes:

```lua
VehicleHold = {
    enabled = true,
    zeroVelocity = true,
    handbrake = true,
    freezePosition = true,
    engineOff = true,
}
```

The vehicle is unfrozen when the menu closes, but the engine remains off so the driver starts it normally.

## Secure refuel flow

1. Client identifies a nearby vehicle and asks to open the station.
2. Server validates the player, pump, vehicle entity, routing bucket, plate, model and keys.
3. Server creates a short-lived session bound to that exact vehicle and pump.
4. UI sends only the requested target fuel and item quantities.
5. Server rereads live fuel and recalculates the complete price.
6. Server charges through `cm-playerdata`.
7. Server persists fuel through `cm-vehicles:ServiceVehicle`.
8. Client only applies the server-approved result visually.

## Items

Default catalogue names:

| Item | Purpose |
|---|---|
| `fuel_can` | Adds configured portable fuel amount |
| `repair_kit` | Repairs bodywork, deformation, windows and tyres; engine health is preserved |
| `wash_kit` | Resets dirt and washes decals |

`cm-inventory` usable-item contract:

```lua
exports['cm-inventory']:RegisterUseableItem(itemName, 'cm-gasstations', 'UseItem')
```

The exported handler returns:

```lua
{ success = boolean, remove = 0|1, message = string }
```

The inventory removes the item only after the timed action and server validation succeed.

## Important configuration

`shared/config.lua` contains:

- prices;
- station and pump positions;
- custom interaction text;
- vehicle hold behaviour;
- session expiry and cooldowns;
- distance and routing validation;
- maximum item quantities;
- portable item service amounts and durations;
- blip appearance.

## Suggested next additions

- Physical nozzle and hose attached to the player and pump.
- Pump occupancy so only one vehicle can use a nozzle at a time.
- Petrol, diesel and electric charging types.
- Different fuel tank capacities and litres instead of percentages.
- Station-specific dynamic fuel prices.
- Business ownership, stock, revenue and employee management.
- Cash/bank payment selector and printed transaction receipts.
- Refuelling animation after payment with litres increasing in real time.
- Emergency fuel-can prop and empty/full can metadata.
- `cm-admin` transaction, exploit-rejection and refund logs.
