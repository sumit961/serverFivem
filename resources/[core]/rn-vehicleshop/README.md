# rn-vehicleshop CM Adapted

This version keeps the rn-vehicleshop showroom UI but removes QBCore, qb-target, player_vehicles and qb-vehiclekeys.

Ownership now goes through your current `cm-vehicles` resource:

- Purchases create rows in `cm_owned_vehicles` using `exports['cm-vehicles']:CreateOwnedVehicle(...)`.
- Trunk level is saved into the owned vehicle row.
- `/vehicleadmin` controls which cars are allowed on the server.
- Cars that are not saved/enabled in `/vehicleadmin` are hidden and should not be used.

## Install

1. Replace your old `rn-vehicleshop` folder with this folder.
2. In `server.cfg`, ensure order is:

```cfg
ensure oxmysql
ensure cm-vehiclekeys
ensure cm-vehicles
ensure rn-vehicleshop
```

3. Restart the server.
4. In game, run:

```text
/vehicleadmin
```

For each car:

- Set price.
- Set trunk level.
- Tick **Available in server** if it should be visible/allowed.
- Tick **Available in store** if players can buy it.

Event/task vehicles: tick only **Available in server**. They will show in the store as Event / Task only and cannot be bought.

Normal dealership vehicles: tick both **Available in server** and **Available in store**.

Hidden / unused vehicles: untick both or press **Disable / Hide**.

## Giving event vehicles

Admins can give any enabled catalog vehicle to themselves:

```text
/vehgivecatalog sultan
```

Other scripts can use:

```lua
local ok, vehicleData = exports['rn-vehicleshop']:GiveCatalogVehicle(source, 'sultan', {
    source = 'event_reward'
})
```

Only cars enabled in the vehicle admin catalog can be given.
