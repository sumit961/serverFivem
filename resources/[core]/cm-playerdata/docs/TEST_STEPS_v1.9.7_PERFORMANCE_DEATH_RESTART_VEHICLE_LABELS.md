# Test Steps - CM PlayerData v1.9.7

1. Restart `cm-playerdata`.
2. Kill a test character, then restart `cm-playerdata` while they are dead.
3. Confirm the death screen returns and the character stays at the death/body location.
4. Run several money changes and confirm no synchronous money-save hitch/spam occurs during each transaction.
5. Confirm periodic saves still persist cash/bank after waiting for the configured dirty-save interval.
6. Temporarily remove `HealthSyncInterval` or `PositionSyncInterval` from config in a test copy and confirm client script does not crash.
7. Put another player in driver/passenger seat and confirm their label appears above their seat/roof, not inside the car.
8. Put a player into a trunk/attached-to-vehicle state and confirm the label is lifted above the vehicle/trunk area.
9. Confirm G player interaction does not open for players in cars/trunks.
