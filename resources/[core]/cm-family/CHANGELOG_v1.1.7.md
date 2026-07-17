# cm-family v1.1.7

- Family-house baseline access now comes from committed membership, not a fragile legacy rank ID.
- Added DB-authoritative member/rank fallback and stale rank-id repair.
- `GetFamilyMemberCharacterIds` now reads committed rows so cm-house refresh cannot miss a newly joined member.
- Shared vehicle checks now have a DB-authoritative fallback.
- Added `GetFamilyVehicleAccessDecision(characterId, vehicleId, action)`.
- House refresh failures are logged instead of silently discarded.
