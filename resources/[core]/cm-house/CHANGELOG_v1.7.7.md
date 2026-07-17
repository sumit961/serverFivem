# cm-house v1.7.7 — Authoritative Family House Lifecycle

- A linked property is now the family's authoritative home.
- House entry, lock, general storage, weapon storage, garage and helipad continue to use cm-family rank permissions through `CanAccessProperty`.
- Family storage and weapon-storage payloads now identify themselves as family facilities.
- Garage and interior payloads include family-house metadata.
- `SetFamilyHouseLink` now synchronizes both `cm_houses.family_id` and `cm_families.house_id` in one transaction.
- A family cannot be linked to two houses, and a house cannot be linked to two families.
- Selling a family house atomically deletes the linked family, ranks, members, invites, bank logs and family vehicle access.
- Selling is blocked until secured weapon storage is empty and the family bank balance is withdrawn.
- House-sale payout is journaled and conditionally claimed to prevent repeat payouts.
- Admin eviction disbands the linked family and clears family storage/vehicle sharing.
- Admin deletion also removes any orphan linked family.
- General storage cleanup now fails closed instead of continuing after a database error.
- Startup clears stale `cm_houses.family_id` values that point to missing families.
- Public development administration is disabled by default.
