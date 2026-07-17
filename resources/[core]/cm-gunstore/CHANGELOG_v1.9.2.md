# cm-gunstore v1.9.2 — ammo image in inventory

## Fix: bought ammo now shows its image in the inventory
- Ammo is a STACKABLE item, so cm-inventory renders its icon from the cm-items
  base definition — not from per-purchase metadata. Previously the gun store put
  the image in the purchase metadata (which a stacked item ignores) and relied on
  cm-weapons having already pushed the image to cm-items.
- On every ammo purchase the gun store now calls `ensureAmmoImageInCmItems`,
  which pushes the store's ammo image into the cm-items base definition if it is
  missing or different. Deduped per item so it runs at most once unless the image
  changes.
- Ammo purchase metadata also now carries `img` / `imageUrl` in addition to
  `image` / `icon`, covering the different keys inventories read.

## If the image still doesn't show
1. Add/replace the ammo image in **/cmweaponadmin** (cm-weapons owns the ammo
   definition), then run **/cmweaponsync** to push it to cm-items.
2. Make sure the image file is included in the owning resource's `files{}` block
   and that the saved path is a valid `nui://<resource>/web/images/...` URL.
3. Restart cm-items → cm-weapons → cm-gunstore so the base catalog reloads.
