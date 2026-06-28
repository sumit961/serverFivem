# Wearable Vest via Clothing Studio (model B)

Armor vests are **gun-store items** (they live in `cm_gun_catalog`, sold on the
weapon side). They are **not** clothing-store items. The clothing store
(`nv_cloth`) is used only as a **PNG factory**: it photographs the vest on a
green studio backdrop and produces a clean transparent icon, then hands the
image + component/drawable/texture back to the gun admin form.

## Flow

1. Admin opens `/gunadmin`, sets **Type = Wearable Vest / Armor**.
2. Admin clicks **Capture Vest (Clothing Studio)**.
   - Gun UI closes and `nv_cloth` opens its admin studio locked to the **Armor**
     category only.
3. Admin picks a vest drawable/texture, frames it, and captures (same buttons
   the clothing admin uses). `nv_cloth`:
   - chroma-keys the green backdrop into a transparent PNG,
   - saves it to `cm-gunstore/web/images/custom/<file>.png`,
   - calls `exports['cm-gunstore']:ReceiveArmorImage(src, payload)`.
4. The gun admin form re-opens with **Image Path**, **Component (9)**,
   **Drawable**, **Texture**, and **Gender** pre-filled.
5. Admin types **Name**, **Item Name**, **Price**, **Armor Health**, picks
   **Store** or **Hidden**, and clicks **Create**.
6. The row is written to `cm_gun_catalog` with `item_type='armor'`,
   `component_id/drawable_id/texture_id/armor_value`.

## Wearing the vest

When a player uses an `armor_*` item:

- `cm-gunstore` applies GTA **component 9** (drawable/texture from metadata),
- sets armor health (`armorValue`),
- saves the look via `cm-characters:SaveAppearance()` if that resource is
  running (so it survives respawn/relog).

`cm-gunstore` does this itself — `cm-itemactions` does **not** need to
understand clothing components. (You can later add a `cm-itemactions` handler if
you prefer; the gun store's own handler is self-contained.)

## Install steps

1. Replace your `nv_cloth` and `cm-gunstore` resources with these updated
   folders (or apply the diffs).
2. Run the SQL once (if not already):
   `install/cm_gun_catalog_upgrade_v3_wearable_vests.sql`
3. Ensure `cm-gunstore/web/images/custom/` exists and is writable by the server
   (the `.keep` file keeps it in git).
4. `server.cfg` load order — `nv_cloth` and `cm-gunstore` can start in any
   order, but both must be started:
   ```
   ensure screenshot-basic
   ensure nv_cloth
   ensure cm-gunstore
   ```
5. `screenshot-basic` must be started for capture to work (clothing studio uses
   it).

## Notes / gotchas

- The vest PNG lives inside `cm-gunstore`, so it ships with your gun store
  resource — no dependency on `cm-items` for armor icons.
- Captures from this flow never create a `clothing_catalog` row, so vests will
  not appear in the clothing store.
- Existing armor rows are re-registered as usable on resource start, so vests
  bought before a restart still work.
- If `cm-gunstore` is stopped when you capture, `nv_cloth` aborts with a clear
  notification instead of saving a clothing item.
