# cm-weapons v1.2.0 Changelog

## Fixed / cleaned
- Added `DoesWeaponExist`, `DoesAmmoExist`, `IsWeaponItem`, and `IsAmmoItem` exports for clean checks from `cm-gunstore`, inventory, itemactions, and future black-market/police armory systems.
- Added export cache throttling so repeated `cm-gunstore` catalog reads do not spam full DB reloads.
- Added upgrade-safe SQL `ALTER TABLE` checks for older installs.
- Kept weapon/ammo price as legacy DB compatibility only; store price belongs in `cm-gunstore` `/gunadmin`.
- `GetAmmoPickupHash` and `GetAmmoDropData` now use the same DB fallback as `GetAmmo`.

## Responsibility rule
- `cm-weapons` creates and manages weapon/ammo definitions: item name, image, weapon hash, ammo type, pickup hash, damage, magazine size, durability, cm-items sync.
- `cm-weapons` does not decide shop price or store visibility.

## Test steps
1. Ensure order: `cm-items` -> `cm-weapons` -> `cm-gunstore`.
2. Start server and confirm console shows `CM-WEAPONS started | ammo=... | weapons=...`.
3. Run `/cmweaponadmin` as an ACE-approved admin.
4. Create or save an ammo item, upload an ammo image, and press Sync to cm-items.
5. Create or save a weapon linked to that ammo.
6. In console or another resource, test:
   - `exports['cm-weapons']:DoesAmmoExist('ammo_9mm')`
   - `exports['cm-weapons']:DoesWeaponExist('weapon_pistol')`
   - `exports['cm-weapons']:GetWeapon('WEAPON_PISTOL')`
