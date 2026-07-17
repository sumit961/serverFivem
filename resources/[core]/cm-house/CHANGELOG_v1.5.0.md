# v1.5.0 — house weapon storage, placement and integration foundation

## Weapon storage

- Replaced inactive wardrobe gameplay points with secure property weapon-locker points.
- Existing template wardrobe coordinates migrate into weapon locker coordinates.
- Weapons and ammunition only; clothing/other unique items fail closed.
- Two-column ice-blue/cyan UI with live gunstore/cm-weapons images, quantity controls, search and filters.
- Preserves weapon metadata, serials, ammo stacks and images.
- Server validates house bucket, point distance, permission, database row owner and quantity.
- Per-locker transfer serialization and reserve-first withdrawal prevent duplication.
- Transfer history table and family/admin integration exports included.
- House sale, purchase, admin eviction/assignment and deletion are blocked when secured weapons remain.

## Interaction UI

- Centered transparent cyan `E` interaction retained.
- Improved Segoe-based readable typography.
- Liquid-glass gradient text and glass key treatment without `backdrop-filter`.
- Hidden while weapon storage or another focused NUI is open.

## Property creator

- Helipad placement now creates a real cyan helicopter.
- Admin flies, lands and stops the helicopter, then saves its exact transform.
- Standalone interior and garage creation both request GPS coordinates and teleport before capture.

## Template safety

- Used interior and garage templates cannot be disabled or deleted.
- UI, server usage check, atomic SQL condition and foreign keys all enforce the rule.

## Family/admin API

- Family permission keys added for weapon storage access/deposit/withdraw.
- Family and admin capability contracts updated.
- Rank-ready granular house-admin permissions added, including separate property, interior, garage, photo and recovery scopes.
- Interior/garage template ranks can capture their assigned layout type without receiving full property-creator access.
- Admin panel and creator can be opened by protected client/server exports, so cm-admin buttons do not need commands.

## Vehicle placement bridge

- `cm-vehicles` v3.4.1 adds a scoped `cm-house` placement allowlist.
- Interior/garage creator ranks can use the real placement car/helicopter without receiving general vehicle-admin permission.
- Placement vehicles are forced to admin-only temporary access.
- Placement vehicles are registered per admin source; clients cannot delete another staff member's temporary vehicle by forging a plate event.
