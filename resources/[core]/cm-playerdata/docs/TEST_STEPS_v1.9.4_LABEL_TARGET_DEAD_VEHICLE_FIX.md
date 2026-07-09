# Test Steps - cm-playerdata v1.9.4

1. Restart `cm-playerdata`.
2. Stand near another player on foot.
3. Confirm overhead label shows:
   - name/Stranger in white
   - `ID: <characterId>` in white
4. Look directly at the player until the G prompt appears.
5. Confirm the ID line turns CM cyan only while G is visible.
6. Look away and confirm the ID returns to white and the G prompt disappears without flicker.
7. Ask the player to sit inside a car.
8. Confirm the overhead label still shows above the player's head/passenger position.
9. Confirm player G prompt/menu does not appear while that target is in the car.
10. Kill/down the player.
11. Confirm the label shows `unconscious | <name/Stranger>` with the same `ID: <characterId>` line.
12. Confirm no server ID is displayed anywhere.
