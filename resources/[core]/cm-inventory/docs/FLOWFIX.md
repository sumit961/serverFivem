# v3.5 Flow Fix

Changes:
- Press `I` while inventory NUI is open closes it.
- Right-click menu uses only USE, DIVIDE, GIVE, DROP 1, DROP ALL. Equip/Reload buttons are removed.
- Using a weapon equips it to the weapon slot and attempts to reload from the first matching ammo stack.
- Reload now consumes ammo from the first matching ammo stack in inventory order instead of requiring ammo in the ammo slot.
- Giving, picking up, and receiving items refresh the UI only if inventory is already open. They no longer force-open the inventory.
