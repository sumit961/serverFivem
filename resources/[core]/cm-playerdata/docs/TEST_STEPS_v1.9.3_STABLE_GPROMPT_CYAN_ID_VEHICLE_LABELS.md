# Test Steps - CM PlayerData v1.9.3

1. Restart `cm-playerdata` after `cm-admin` is installed.
2. Stand near another player on foot.
3. Confirm overhead shows:
   - player name or `Stranger`
   - `ID: <database character id>` in cyan/blue
4. Look at the player's body/head and confirm `G` stays stable instead of blinking.
5. Press `G` and confirm the player menu opens.
6. Ask the target player to sit inside a vehicle.
7. Confirm their overhead name and `ID:` still show above them.
8. Look at the target inside the vehicle and confirm `G` does not open a player menu.
9. Use the vehicle interaction system for vehicle/passenger/trunk actions.
10. Toggle `/admin` and confirm normal label is replaced by the admin label, not duplicated.
