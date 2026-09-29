# cm-house v1.8.17

## Family data ownership (maintenance/architecture follow-up)

- cm-house no longer directly deletes any `cm_family_*` table. `sv_family_lifecycle.lua`'s hardcoded delete block is removed; `FL.FinalizeDeletedFamily` now calls cm-family's single authoritative `FinalizeHouseFamilyDeletion` export instead, and both admin eviction and admin house-deletion flows now call it *before* mutating any cm-house table.
- If cm-family is stopped or the authoritative cleanup call fails, the eviction/deletion request now fails closed with an actionable error instead of silently reporting success (previous behavior treated "cm-family unavailable" as success).
- `cm_house_shared_vehicles` cleanup (house-owned data) moved into cm-house's own house-side transaction, since it was previously bundled into the now-removed cross-resource delete block.

## Documentation

- Corrected `docs/ADMIN_INTEGRATION_v1.7.0.md`: documented the actual live cm-admin integration (`RegisterDevTool` + `cm-house:dev:openAdmin`), and removed the example `cm-admin:server:openHousePanel` / `cm-admin:server:startHouseCreator` events that were never implemented in cm-admin. `OpenAdminPanel`/`OpenHouseCreator` exports are still real and documented, but marked as a secondary path cm-admin's current build does not use.

No gameplay UI, garage/vehicle handoff, or reward logic changed.
