# cm-house v1.7.3 — Circular E interaction, cleanup, recovery fix

## Interaction prompt
- Interaction is now text-only: a circular cyan `E` badge followed by the
  clean interaction text. No door card, no panel, no glass gradient.
- Removed the five stacked `#cm-interaction` override blocks (v1.5.0 → v1.7.2)
  that were fighting each other in the CSS. The base block is now the single
  source of truth.
- Label renders in readable sentence-case (no forced uppercase, no ellipsis
  truncation); long labels wrap instead of being clipped.
- Bumped NUI filenames to bust FiveM cache: `phase2-ice-cyan-v173.css`,
  `interaction-v203.js`.

## Admin access
- `Config.DevelopmentPublicAdmin = true` is intentionally left ON — every
  connected player can open and use the house admin tools for now.
  The startup warning still fires. Set this to `false` before opening the
  server to normal players; the underlying ACL gates are all intact and take
  over automatically when it is off.

## Photos
- Property photos are captured with `screenshot-basic`
  (`requestClientScreenshot` → `html/img/houses/house_<id>.jpg`). No change to
  behaviour — confirmed as the active and only capture path.

## Bug fix
- `RecoverOrphanedHouseVehicles` now derives `house_id` from the same
  reference (`garage` vs `location_ref`) that the WHERE clause matched on,
  using a CASE expression instead of a blanket COALESCE. Previously a stale
  `garage` string coexisting with a `location_ref` match could report the
  wrong `previousHouseId` to cm-vehicles during startup recovery.

## Cleanup (dead weight removed)
- Deleted orphaned `server/sv_garage_customization.lua` (not in manifest).
- Deleted `garage-customization-v160.{js,css}` (v1.7.0 removed the feature).
- Deleted stale `garage-slot-v110/111/112/113.js` (only v114 is loaded).
- Deleted stale `interaction-v200/v201/v202.js` (superseded by v203).
- Deleted stale `phase2-ice-cyan.css` and `phase2-ice-cyan-v171.css`.
- Manifest verified: every referenced file exists, no file is orphaned.
