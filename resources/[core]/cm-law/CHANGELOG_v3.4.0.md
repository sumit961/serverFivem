# CM Law v3.4.0

## Unified impound and tow

- Routed Police and generic Law impound authorization through `AuthorizeEnforcement`, including organization capability, duty, suspension, rank, and permission checks.
- Kept the Police impound implementation as the shared compatibility workflow and the existing `cm_police_impounds` and `cm_police_impound_evidence` tables as shared ledgers.
- Bound evidence, tow sessions, and completion to registered `cm-vehicles` entities and persistent `vehicle_id`; network IDs are transient transport references and plates remain display/search data.
- Validated same-organization persistent tow fleet ownership and normal `vehicle.drive` access. Rejected ambient, temporary, admin, preview, occupied, already-impounded, and active fleet targets.
- Added tow-session expiry, actor/org/entity checks, network-ID re-resolution by persistent identity, server cancellation, cleanup on disconnect/resource stop/vehicle-service restart, and a per-vehicle completion lock.
- Restricted tow delivery to the current organization's configured impound facility. Combined and deduplicated generic Law and Police locations while leaving generic facility NPC rendering with the generic Law facility owner.
- Preserved photo evidence, owner-only public release, bank fees, release locks, transaction rollback/refund, and `IMPOUND` to `STORED` release behavior.
- Routed J-menu tow actions directly to shared functions. `/policetow`, `/policeimpound`, and `/impoundlot` remain compatibility aliases.
- Added organization labels/reasons to existing MDT impound records without changing the MDT layout or Vehicle G-menu.

No database rename or destructive migration is required. The legacy Police-named ledger tables intentionally remain shared for compatibility.
