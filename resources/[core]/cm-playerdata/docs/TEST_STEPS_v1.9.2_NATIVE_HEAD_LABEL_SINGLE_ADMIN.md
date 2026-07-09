# Test Steps - CM Playerdata v1.9.2

1. Restart `cm-playerdata` and `cm-admin`.
2. Join with two players.
3. Stand near another player and move your camera.
4. Confirm the overhead label stays anchored above that player's head/body and does not trail or float separately.
5. Confirm the style is simple/non-bold:
   - `Name`
   - `(Character ID)`
6. Confirm you do not see your own overhead label.
7. Type `/admin` on an admin character.
8. Confirm the normal label is replaced by one red admin label, not duplicated:
   - `Administrator`
   - `Character Name (Character ID)`
9. Enable noclip and confirm the admin label disappears.
10. Disable noclip and confirm the red admin label returns.
