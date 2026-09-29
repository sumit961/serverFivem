# cm-house v1.8.18

## Central admin audit coverage

- `sellHouse` now emits a central `Audit()` record (`house_sale`) alongside its existing `LogHouse` entry, matching the existing `buyHouse`/`admin_evict`/`admin_delete` pattern. Only logged after the ownership-release transaction has already committed.
- `TransferFamilyHouseOwnership` now emits a central `Audit()` record (`house_ownership_transfer`) for the house-ownership change itself, attributed to the actor cm-family identified. This is a separate audience from cm-family's own leadership-change activity log entry, not a duplicate of it.
- No sensitive payloads (permission maps, inventory contents, recovery blobs, SQL errors) are included in any new log entry.

## Regression coverage

- Added `tools/cm-house-family-contracts/check_contracts.py`, a read-only static source scanner that protects the recent security/privacy/ownership-boundary fixes against a future refactor silently reintroducing one of them (an auth check moved after a side effect, the family permission map creeping back into replicated state, cm-house directly deleting a `cm_family_*` table again, a stale doc claim, etc). Does not require a running server or database.

No UI, vehicle handoff (`sv_garage.lua`), or reward logic changed.
