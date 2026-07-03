# Racing Harness Item Integration

This resource now supports a permanent racing harness installed per vehicle.

## What it does

When a vehicle has a racing harness installed:

- seatbelt crash ejection is disabled for that vehicle
- the normal seatbelt chime/ejection logic is bypassed
- the vehicle information screen shows `Racing Harness: Installed`
- the value is stored in `cm_owned_vehicles.metadata.racingHarness`

## Call from your item system

When the player uses your item named `racing_harness`, trigger this client event:

```lua
TriggerClientEvent('cm-vehicles:client:useRacingHarness', source)
```

If your item system can only trigger server events first, use:

```lua
TriggerEvent('cm-vehicles:server:useRacingHarness')
```

If your item system runs client-side item actions, use:

```lua
TriggerEvent('cm-vehicles:client:useRacingHarness')
```

## Test command

For testing without item integration:

```txt
/installharness
```

The player must be inside or near/look at the vehicle and must have access/keys.
