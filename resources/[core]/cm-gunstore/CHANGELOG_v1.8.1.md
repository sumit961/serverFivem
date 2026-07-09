# cm-gunstore v1.8.1

## Fixed
- Fixed player store opening in the last admin/category filter. This was why the normal store could show only `Ammunition` after you used the ammo/admin tab.
- Store now resets to `All` every time a player opens the public gun store.
- Fixed config sync so store catalog entries have explicit `itemType` and no longer depend on auto-detection.
- Config sync now forces `stock`, `enabled`, and `price` from `shared/config.lua` for config-owned weapons/ammo/armor.
- Old/stale DB rows not listed in `Config.StoreCatalog` are hidden when `Config.StrictStoreCatalog = true`.
- Added `/gunstoresync` admin command to force rebuild the store catalog from config and show counts.

## Test
1. Ensure `cm-weapons` starts before `cm-gunstore`.
2. Restart `cm-weapons`, then `cm-gunstore`.
3. Run `/gunstoresync` once.
4. Open the normal store. It should show ammunition, pistols, SMGs, rifles, shotguns, snipers, machine guns, and armor if enabled in config.
5. Open `/gunadmin`, click Ammo, close it, then open the normal store again. It should still show All, not only ammo.
