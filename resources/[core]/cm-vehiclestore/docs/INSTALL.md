# CM Vehicle Pack v1

Resources:
- cm-vehicles: ownership, locks, G menu, trunk inventory
- cm-vehiclekeys: temporary shared vehicle keys until logout
- cm-vehiclestore: dealership NPC and buy UI

## Required order

```cfg
ensure oxmysql
ensure ox_lib
ensure cm-core
ensure cm-auth
ensure cm-characters
ensure cm-playerdata
ensure cm-items
ensure cm-inventory
ensure cm-vehiclekeys
ensure cm-vehicles
ensure cm-vehiclestore
```

## Controls

- `G` near vehicle: vehicle menu
- `L`: lock/unlock

## Test commands

In F8, type without `/`:

```text
vehgive sultan 3
myvehicles
```

## Trunk levels

- 0 = no trunk
- 1 = 6 slots
- 2 = 12 slots
- 3 = 18 slots
- 4 = 24 slots
- 6 = 36 slots

Vehicle trunks have no kg/weight limit. They are slot-limited only.
