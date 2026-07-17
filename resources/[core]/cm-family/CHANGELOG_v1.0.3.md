# cm-family v1.0.3

- Fixed false `DATABASE NOT READY` on legacy `cm_family_members` tables without an `id` column.
- Confirmed no runtime query depends on `cm_family_members.id`.
- Kept `id` on fresh installations while accepting `character_id`/composite-key legacy tables.
- Removed the fragile `AFTER id` clause from automatic member-table repair.
- Added `sql/005_idless_members_compat_v1.0.3.sql` as the new manual fallback.
- Updated startup diagnostics and resource version.
