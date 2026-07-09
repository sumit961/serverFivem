# CM Items v1.3 - Preview delete + binary image save fixes

## Fixed
- `server/image_upload.lua` now decodes base64 PNG data before saving clothing images. This prevents corrupted text-based `.png` files.
- `server/main.lua` export wrapper now uses `table.pack` / explicit `table.unpack(args, 1, args.n)` so nil export arguments are preserved.
- Preview give fallback no longer passes metadata as the 5th inventory export argument, preventing strict inventory type crashes.

## Added
- `/cmitempreview` / `/cmitemsui` now shows item source: `static`, `catalog`, or `clothing_catalog`.
- Admin preview now has a Delete button for SQL-backed catalog items and clothing catalog rows.
- Delete is ACE-protected using `cm.items.admin` or compatible command ACEs.

## Notes
- Static items from `shared/items.lua` are code-defined and are not deleted from the UI. Remove them from `shared/items.lua` and restart the resource if you want them gone permanently.
- SQL catalog items are removed from `cm_items_catalog`. Clothing catalog rows are removed from `clothing_catalog`.

## Added after review
- SQL item catalog now syncs to clients so `/cmitempreview` can show database-created catalog items, not only static shared items.
- `GiveCatalogItem` now uses safer inventory export argument ordering.
