# Ammo Slot Flow v3.6

This version changes weapon/ammo behavior:

- Right-click/use `weapon_pistol` equips it to the `weapon` slot.
- When weapon is equipped, the first matching ammo stack is moved into the `ammo` slot.
- Right-click/use `ammo_9mm` moves that ammo stack into the `ammo` slot.
- If ammo is already in the `ammo` slot, using it reloads the equipped weapon.
- Pressing `R` / `reloadinv` reloads from the `ammo` slot.
- Reloading consumes ammo from the `ammo` slot only.

Example:

1. `testgive weapon_pistol 1`
2. `testgive ammo_9mm 30`
3. `testgive ammo_9mm 50`
4. Open inventory.
5. Use pistol. It goes to weapon slot and the first ammo stack goes to ammo slot.
6. Press R. Ammo is consumed from ammo slot.
