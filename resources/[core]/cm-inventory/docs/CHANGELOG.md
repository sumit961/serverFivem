# cm-inventory v3.1-devtest

- Added `givetest <item> <amount>` F8 command.
- Added `showtestreceiver` F8 command.
- Added `cleartestreceiver` F8 command.
- Added txAdmin commands: `invgivetest`, `invshowtest`, `invcleartest`.
- Keeps normal nearby-player Give Item system from v3.0.

## v3.3 armorfix
- Fixed armor/bodyarmor slot validation.
- Equipment validation now checks item name, category, type, and equipmentSlot aliases.
- Right-click Equip now detects armor by item name too.


## v3.4-ammo
- Added weapon reload system.
- Added ammo slot consumption.
- Added `reloadinv` command and R key mapping.


## v3.5 Flow Fix
- Press I closes open inventory.
- Right-click menu no longer shows Equip/Reload. Use handles item behavior.
- Reload consumes first matching ammo stack in inventory order.
- Inventory no longer opens automatically after item add/pickup.

## v3.6 Ammo Slot

- Using ammo moves it into the ammo slot.
- Using ammo while it is already in the ammo slot reloads the equipped weapon.
- Equipping weapon automatically moves first matching ammo stack into the ammo slot.
- Reload now consumes from the ammo slot only.
