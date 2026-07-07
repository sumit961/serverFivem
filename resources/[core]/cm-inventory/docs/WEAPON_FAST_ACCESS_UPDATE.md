# Weapon Fast Access + Gun Slot Update

## New flow
- GTA weapon wheel and native weapon scroll are blocked.
- A weapon can only be used when it is in the `weapon` equipment slot.
- Pressing fast access keys `1-5` now talks to inventory instead of GTA weapon slots.

## Hotkey behavior
- If the pressed fast slot has a gun, that gun moves into the `weapon` slot and becomes the active weapon.
- If another weapon is already equipped/in hand, the two guns are swapped.
- If the equipped gun is in hand and the pressed fast slot is empty, the gun is stored into that fast slot.
- If the equipped gun is in hand and the pressed fast slot has a non-gun item, inventory blocks the action to avoid overwriting the item.

## Ammo behavior
- The `ammo` slot must match the equipped weapon ammo type.
- When changing weapon, inventory looks for matching ammo in quick slots, pockets, or backpack.
- If matching ammo is found, it is moved/swapped into the `ammo` slot automatically.
- GTA ammo is set from the inventory ammo count only. No more fake 250 ammo.

## Animations
- Pickup: pickup animation.
- Clothing equip/remove: clothing animation.
- Weapon out/change/store: weapon animation.
