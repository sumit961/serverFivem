# CM Inventory v4.3.0 - cm-weapons ammo sync

## Fixed
- Inventory now uses the same 7 fixed ammo item names as `cm-weapons`.
- Rifles now request `ammo_556nato`, not old `ammo_556`.
- SMGs now request `ammo_9x19_smg`, not pistol ammo.
- Machine guns now request `ammo_762nato`.
- Shotguns now request `ammo_12gauge`, not old `ammo_shotgun`.
- Snipers/marksman rifles now request `ammo_308win`, not old `ammo_762`.
- Heavy revolvers now request `ammo_44magnum`.
- `cm-weapons` export `GetWeaponAmmoItem` is checked first, so weapon config is the source of truth.
- Old ammo item names are accepted as temporary aliases if players already have them, but stores should only sell the 7 fixed ammo items.

## Test
1. `ensure cm-weapons` before `cm-inventory`.
2. Buy a pistol and `ammo_9mm`; equip pistol and shoot.
3. Buy an SMG and `ammo_9x19_smg`; equip SMG and shoot.
4. Buy a rifle and `ammo_556nato`; equip rifle and shoot.
5. Buy a shotgun and `ammo_12gauge`; equip shotgun and shoot.
6. Buy a sniper/marksman rifle and `ammo_308win`; equip and shoot.
7. Buy heavy revolver and `ammo_44magnum`; equip and shoot.
