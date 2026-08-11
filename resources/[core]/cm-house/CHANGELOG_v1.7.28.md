# cm-house v1.7.28 — rank-gated cm-admin launcher

- Removed `/cmhouse`, `/cmadmin`, `/cmadminhouse`, `/cmhouseadmin` and
  `/houseadmin` as house-administration entry points. The old
  `/cmhousecheck` diagnostic command was also removed.
- House administration now opens from `cm-admin` → Developer → House Admin.
- Disabled the broad legacy `house.create` permission fallback.
- Removed the public development-admin and disabled-admin-check bypasses.
- The launcher requires `house.admin.open`; every panel section and action
  continues to enforce its own granular `house.admin.*` permission server-side.
- Existing secured client/server panel exports remain available for authorized
  integrations and still revalidate the target player's current rank.

No database migration is required.
