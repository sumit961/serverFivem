# Equipment slots

This version adds equipment support on top of the working v3.1 inventory.

## Features

- Drag armor to `bodyarmor` slot.
- Drag `weapon_pistol` to `weapon` slot to equip it.
- Right-click compatible item -> Equip.
- Right-click equipped item -> Unequip.
- `/refreshgear` reapplies current equipment after spawn/reload.

## Test

```text
testgive armor 1
testgive weapon_pistol 1
inv
```

Drag armor to Body Armor, drag pistol to Weapon, or right-click -> Equip.
