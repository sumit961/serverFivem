# cm-family v1.1.6 — Family house and shared vehicle access

## Fixed

- Merge `cm_family_ranks.permissions` and legacy `perms` instead of letting an empty `{}` column hide valid grants.
- Normalize numeric/string family and rank cache keys.
- Re-read one membership from the database on a genuine cache miss.
- Refresh every family member's cm-house access map after join/rank/kick operations.
- Upgrade only untouched stock Recruit ranks with basic family-house permissions. Customized ranks are not changed.
- New Recruit ranks can enter the house, open the garage, take/store shared vehicles, use family weapon storage, and use general storage.
- Family vehicle authorization now confirms that the vehicle is actually shared with that family.
- Choosing a minimum rank on your own private vehicle automatically shares it.
- Added `GetHousePermissionDecision` for server-side diagnostics.

## Important

A vehicle remains private until its legal owner shares it from **Family → Vehicles**, or selects a minimum rank on that vehicle. The minimum rank tier must be less than or equal to the member's tier.
