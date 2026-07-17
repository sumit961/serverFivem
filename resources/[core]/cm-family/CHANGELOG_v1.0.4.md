# cm-family v1.0.4

## Fixed

- Detects legacy `cm_family_ranks.perms` columns at startup.
- Dual-writes rank permission JSON to both `permissions` and `perms` when the legacy column exists.
- Detects whether a legacy JSON_TYPE constraint requires an object or array and writes the matching shape; the canonical `permissions` column uses an object.
- Reads permissions from `permissions`, falling back to `perms` for older data.
- Rank creation now accepts both permission arrays and permission maps.
- Added optional backfill migration `006_rank_permissions_compat_v1.0.4.sql`.

This fixes MariaDB errors such as:

`CONSTRAINT cm_family_ranks.perms failed`
