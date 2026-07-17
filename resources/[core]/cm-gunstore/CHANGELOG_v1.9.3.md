# cm-gunstore v1.9.3 — weapon/ammo images now follow cm-weapons

## Root cause of the "ammo image not showing" issue
The gun store kept its OWN cached copy of each weapon/ammo image in
`cm_gun_catalog.image`. That cached copy (usually the default `images/*.svg`)
was preferred over the real image from cm-weapons, and the config sync never
overwrote an existing image. So after you uploaded a new ammo image in
/cmweaponadmin, the store row — and therefore the purchase metadata AND the
cm-items base icon — still pointed at the old default SVG.

## Fix
- `mergeWeaponRow` / `mergeAmmoRow` now prefer the cm-weapons image over the
  stored store image, EXCEPT when the store image is a deliberate custom upload
  (a `nui://` path). Default `images/*.svg` always yields to cm-weapons.
- Config sync now refreshes the weapon/ammo `image` column from cm-weapons unless
  the stored value is a custom `nui://` upload (`image NOT LIKE 'nui://%'`).
  Armor images stay gun-store-owned as before.
- Combined with the v1.9.2 `ensureAmmoImageInCmItems`, a bought ammo item now
  carries the correct image in both its metadata and the cm-items base
  definition that the inventory reads for stacked items.

## To apply after updating
1. Restart cm-weapons and cm-gunstore (or run `/gunstoresync`) so the store rows
   pull the new images.
2. Run `/cmweaponsync` so cm-items base ammo/weapon defs also get the image.
3. Relog / restart cm-inventory if old stacks still show the old icon.
