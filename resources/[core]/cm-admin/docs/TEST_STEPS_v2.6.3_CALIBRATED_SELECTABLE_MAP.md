# Test Steps - CM Admin v2.6.3

1. Restart `cm-admin`.
2. Open admin menu and go to **Map**.
3. Press **Focus Self** and compare your marker with the GTA pause map.
4. Move around Pillbox/Legion area and confirm the marker follows correctly.
5. Click your own player blip and confirm a player card opens.
6. Click another player blip and test permitted actions:
   - Inspect
   - Go To
   - Bring
   - Freeze / Unfreeze
   - Heal / Armor
   - Inventory
   - Cars
7. Enable/confirm **Vehicles** is checked.
8. Click a vehicle blip and confirm the vehicle card shows plate/model/net ID/coords.
9. Test permitted vehicle actions:
   - Go To Vehicle
   - Repair
   - Delete
10. Click an empty map point and confirm the map point card opens.
11. With permission, use **Teleport Here** and confirm server validates the action.

## Permissions to add if missing
- `map.view`
- `map.vehicles`
- `map.admins`
- `map.teleport`
- `players.view`
- `players.teleport`
- `players.freeze`
- `tools.heal`
- `inventory.view`
- `vehicles.view`
- `vehicles.manage`
