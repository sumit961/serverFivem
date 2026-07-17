# cm-family v1.2.0

- Added authoritative action-specific family vehicle decisions.
- Enforces shared-family status, rank permission and per-vehicle minimum tier.
- Added `trunk.access` rank permission with `storage.access` compatibility for older ranks.
- Founder authority uses `cm_families.founder_cid`, independent of legacy rank flags.
- Revokes family session keys on unshare, tier changes, kick, leave, demotion/promotion, permission changes, rank deletion, leadership changes and family deletion.
- Family vehicle list now uses the exact image from rn-vehicleshop's catalog.
- Legal `owner_character_id` remains unchanged.
