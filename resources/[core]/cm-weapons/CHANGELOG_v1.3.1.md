# cm-weapons v1.3.1

## Fixed
- Added export-cache self-healing from `shared/defaults.lua` if older DB rows fail to seed.
- Prevents `cm-gunstore` from receiving an ammo-only catalog while `cm-weapons` is warming up or after an old migration.

## Test
1. Restart `cm-weapons`. Console should show ammo and weapon counts.
2. Open `/cmweaponadmin` and confirm both ammo and weapons show.
3. Restart `cm-gunstore` and run `/gunstoresync`.
