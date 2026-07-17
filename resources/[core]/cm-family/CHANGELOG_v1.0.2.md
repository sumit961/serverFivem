# cm-family v1.0.2

- Fixed MySQL errno 150 while creating `cm_family_invites` against legacy
  `cm_families` schemas.
- Child tables no longer require exact parent/child FK type and engine matching.
- Added `idx_invite_family` and complete additive repair definitions for all
  seven family tables.
- Added atomic child-first family deletion through `MySQL.transaction.await`.
- Updated disband to stop when the house cannot be unlinked and to restore the
  link if database cleanup fails.
- Updated partial family-creation rollback to use the same atomic cleanup path.
- Normalized invite `family_id` and `rank_id` values before cache lookups.
- Added manual migration `sql/004_legacy_fk_compat_v1.0.2.sql`.
