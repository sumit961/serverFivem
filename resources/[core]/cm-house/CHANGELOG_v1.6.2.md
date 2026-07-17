# cm-house v1.6.2 — Admin and Schema Error Hotfix

## Fixed

- Fixed `sv_admin.lua:181 attempt to call a nil value (global 'decodeAdminJson')`.
  The JSON helper is now declared before the admin callback closes over it.
- Added startup repair for missing `weapon_storages`, multi-exit garage fields,
  customization fields, weapon-transfer history, and garage customization data.
- Existing wardrobe coordinates are migrated to weapon-storage coordinates.
- Admin/template callbacks no longer depend on migrations having been run in an
  accidental order on a local development database.
- Removed the unused `ox_target` startup dependency warning; cm-house uses its
  own centered E interaction.
- Kept temporary public admin access enabled through
  `Config.DevelopmentPublicAdmin = true`.
- Kept Google Sans Flex and the cyan liquid-glass E interaction typography.

## Configuration

- `Config.AutoRepairSchema = true` automatically performs additive schema
  repairs at startup.
- Set `Config.DevelopmentPublicAdmin = false` before allowing normal players on
  a production server.

## Optional SQL

`sql/014_v1.6.2_error_hotfix.sql` contains the same additive database repair for
manual database administration.
