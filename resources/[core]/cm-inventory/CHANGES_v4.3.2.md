# CM Inventory v4.3.2

- Inventory closes immediately when the player becomes unconscious.
- Inventory cannot be opened or manipulated while `isDead=true`.
- Equipped gun and ammo slot drop exactly when cm-playerdata enters unconscious state.
- Equipment is refreshed immediately after the death drop.
- Dropped-item preview, marker interaction, and pickup are disabled while inside a vehicle.
- Server rejects drop pickup while dead or inside a vehicle.
- Open-trunk ownership is checked before cm-vehicles is asked to open storage.
- A non-owner silently receives normal player inventory with no ownership notification.
