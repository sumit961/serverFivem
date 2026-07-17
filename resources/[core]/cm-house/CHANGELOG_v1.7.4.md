# cm-house v1.7.4 — Admin panel crash fix + correctness pass

Audit-driven fixes. Each was verified against the actual code before changing.

## Critical
- **Admin panel no longer crashes.** `adminData` referenced an undefined
  `anchors` global (`anchors.walls/lights/props`) — leftover garage-customization
  fields — which threw `attempt to index a nil value (global 'anchors')` every
  time the panel opened. Removed those three dead fields. This was the real
  reason the panel appeared inaccessible even with public admin enabled.

## Server correctness
- Interior template listing now uses the protected `decodeAdminJson` helper
  instead of bare `json.decode`, so one malformed legacy row can no longer
  crash the whole admin callback.
- **House sale is now safe.** The owner is paid first and the payout is
  confirmed before ownership is cleared or storage wiped. If the bank export
  fails the sale is cancelled and the player keeps the property — previously
  the house could be lost with no payment. Storage/access deletes are now
  awaited.
- **Admin evict / delete / giveTo now wipe house general storage.** Previously
  a reassigned house could hand the previous owner's stored items to the new
  owner, and deleting a house left orphan inventory rows. A shared
  `wipeHouseStorage` helper is called in all three paths.
- **House creation is transactional.** Garage slots are inserted in a single
  transaction; if it fails the just-created house is rolled back (and its
  pending photo discarded) instead of publishing a property with a partial
  garage.
- **Weapon-storage deposit rollback is now durable.** If the locker insert
  fails and returning the weapon to the player also fails, a row is written to
  the new `cm_house_weapon_recovery` table and the player is told to contact
  staff — the weapon can no longer silently vanish. Added
  `ListWeaponStorageRecovery` and `RestoreWeaponStorageRecovery` admin exports,
  and migration `017_weapon_storage_recovery_v1.7.4.sql`.
- **House-number sorting is numeric-aware and crash-safe.** Admin list sorted
  numbers as text (1, 10, 11, 2, …) and could error on mixed rows; it now sorts
  numerically when both values parse and falls back to a safe string compare.

## Client
- Removed the redundant duplicate `cm-house:client:forceExit` handler in
  cl_create (it only faded the screen). The authoritative handler in
  cl_interior does the real work.

## UI
- Fixed the interface font: `--cm-font` now resolves to the "Google Sans Flex"
  face that `index.html` actually loads, instead of `Inter` (which was never
  loaded, so the UI silently fell back to Segoe UI).

## Still open (deliberately deferred to a dedicated cleanup pass)
- Public admin bypass (`Config.DevelopmentPublicAdmin = true`) is intentionally
  left ON per current testing needs. Set it to `false` before production.
- ~500 lines of dead interior/garage template-walking code remain in
  cl_create.lua (superseded by the cm-admin template flow in v1.7.0). Its
  callbacks already reject, so it is inert — removal is a separate surgical
  pass to avoid regressing the working template flow.
- style-v110.css and phase2-ice-cyan-v173.css overlap heavily (253 !important
  overrides). Consolidating to one authoritative stylesheet needs a full visual
  regression pass and is deferred.
