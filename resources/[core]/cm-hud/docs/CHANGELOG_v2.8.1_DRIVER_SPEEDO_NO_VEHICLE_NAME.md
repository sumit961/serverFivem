# CM HUD v2.8.1 - Driver-only Speedometer + No GTA Vehicle Name Popup

## Changed
- Speedometer now shows only when the local player is in the driver seat.
- If the player is a passenger, the speedometer stays hidden.
- If the player moves from driver to passenger, the speedometer hides immediately.
- GTA default vehicle name/class popup is hidden while the player is inside a vehicle.
- Existing GTA default ammo/weapon preview hiding is kept.

## Performance
- No new server work added.
- Vehicle HUD still sends NUI updates only when the payload changes.
- The per-frame native HUD hide loop runs only while the player is logged in, HUD is visible, and no external UI is hiding the HUD.
