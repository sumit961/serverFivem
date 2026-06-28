# Inventory Cleanup Applied - v3.9.1

This patch keeps the existing cm-inventory resource structure and event names intact, but cleans the most important data/display problems.

## Applied changes

- `Config.Debug` is now `false` by default.
- Dev-only test receiver events/commands now return immediately unless `Config.Debug = true`.
- New metadata normalisation in `server/main.lua`:
  - normal stackable items save `{}` metadata so they merge correctly and reduce DB size;
  - `bag_level`, `level`, `backpackLevel`, and `backpack_level` are normalised into `bagLevel`;
  - `drawable` / `texture` are normalised into `drawableId` / `textureId`;
  - clothing and bag items keep only useful catalog/equip metadata;
  - weapons and armour still get serial/durability metadata.
- Bag display is improved in both server payload and UI:
  - generic `clothing_bags` labels now show as `Level X Bag`;
  - bag description shows unlocked backpack slots and max carry weight;
  - item card shows `LVL X` badge;
  - top bag pill shows bag level, unlocked slots, and KG carry weight.
- Clothing display is improved:
  - clothing item cards show friendly category/drawable/texture subtitle;
  - clothing item cards show a small `FIT` badge;
  - tooltip/context panel uses the improved label resolver.

## Next safe structural split

The resource is still one large server file because splitting local functions can easily break load order. The safest next split is:

1. Move pure helpers into `server/helpers.lua`.
2. Move SQL bootstrap into `server/db.lua`.
3. Move dev commands into `server/dev.lua` and load it only when debug is enabled.
4. Move exports into `server/exports.lua`.

Do that after testing this patch in-game.
