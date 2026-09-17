# cm-gunstore v1.11.0 — vest add/remove fix + access control + weapon ban

## Fixed: captured vests couldn't stay "In Store" (or actually get removed)
Two separate bugs were combining to make the vest-capture admin flow feel
broken:

1. **`Config.StrictStoreCatalog` was disabling admin-created armor.** Every
   catalog sync ran `UPDATE cm_gun_catalog SET enabled = 0 WHERE item_name
   NOT IN (<Config.StoreCatalog names>)` across the WHOLE table. Armor rows
   created from `/gunadmin`'s vest capture flow are never listed in
   `Config.StoreCatalog` (they're DB/admin-owned, not config-owned) — so a
   vest you just clicked "Create In Store" for got silently flipped back to
   Hidden within seconds. The query is now scoped to
   `item_type IN ('weapon','ammo')`, so armor rows are left alone.
2. **Delete buttons used native `confirm()`**, which FiveM's CEF NUI does not
   reliably support (it can return without actually blocking/prompting). Every
   "Remove"/"Delete" button now awaits `CMUI.confirm()` (a real DOM modal,
   `Promise<boolean>`) from `cm-ui`, styled to match this page. Falls back to
   native `confirm()` only if `cm-ui` truly isn't running.

## New: per-item access control (Public / Gang Members / Law Org)
Every catalog item — weapon, ammo, or armor — in the **All** admin tab (and
the vest creator form) now has an **Access** control:
- **Public Store** (default) — anyone can buy it.
- **Gang Members** — buyer must be in the selected gang, or *any* gang if
  left on "Any Gang". Checked via `cm-characters`' `GetCharacterId` +
  `cm-gang`'s `GetGangForCharacter`.
- **Law Org (any)** — buyer must be an employee of any `cm-law` organization
  (SAHP/Sheriff/FIB/Army/etc), via `cm-law`'s `IsLawMember`.

Players never see a row they don't qualify for in their own store view, and
the server re-checks access at purchase time regardless of what the client
sent — access-gating is not just cosmetic filtering.

## New: server-wide weapon ban ("Banned everywhere")
Weapon rows in the **All** admin tab get a second, red-styled "Banned
everywhere" checkbox (separate from the ordinary Store/Hidden toggle). A
banned weapon:
- Can't be purchased (checked in `processPurchase` alongside access control).
- Can't be equipped from inventory — `cm-inventory` now calls
  `exports['cm-gunstore']:IsWeaponBanned(itemName)` before letting a player
  move a weapon into their weapon slot, and again on every equipment
  resync (login, etc.), so a weapon banned *after* being equipped stops
  being drawn on the ped without deleting it from anyone's inventory.

## Schema
New columns on `cm_gun_catalog` (added via the existing `alters` migration
pattern, so this is a no-op restart, not a manual SQL step):
`access_scope` (`public`/`gang`/`law`), `access_gang_id`, `banned`.

## New exports
- `exports['cm-gunstore']:IsWeaponBanned(itemName)` — used by cm-inventory.

## To apply after updating
1. Restart `cm-gunstore` (adds the new columns automatically).
2. Restart `cm-inventory` (now soft-depends on cm-gunstore's `IsWeaponBanned`
   export — see the comment in `cm-inventory/fxmanifest.lua`).
3. Re-open `/gunadmin` → **All** tab: existing vests should now show and stay
   "In Store" correctly, and Remove/Delete buttons will actually prompt and
   work.
