# cm-family v1.9.6

## G-menu privacy/functionality fix

- The v1.9.4 privacy fix (removing the permission map from the replicated `cmFamily` state) had unintentionally hidden the family G-menu's invite/promote/demote/kick shortcuts from non-founder ranks that hold the specific server-side permission for that action. Fixed by delivering each player's own effective permission map privately (a targeted `TriggerClientEvent`, never a replicated state bag) alongside the existing state sync, and having the client's local G-menu read that private cache instead of a founder-only shortcut. A player's own permissions are never derived from another player's state, and the server independently re-validates every action regardless of client-side visibility.
- `BuildFamilyMemberState` now returns `(publicState, permissions)`; the public value is still the only one ever replicated. Found and fixed a related bug while making this change: the `GetMemberIdentity` export used `return BuildFamilyMemberState(...)`, a Lua tail call that would have forwarded the private permissions as a second return value to any caller.

## Family cleanup completeness

- `CMFamilyDeleteFamilyRows` now also clears the in-memory event-cooldown cache for the deleted family (`sv_events.lua`'s `CooldownCache`), which the DB-row delete alone did not touch. Found via the new regression test below; effectively harmless in production since family ids are never reused, but incorrect and now fixed.

## Regression coverage

- Added hardening tests 63-67: full family-domain table coverage against an explicit registry (fails if a future new `cm_family_*` table is added to one list and not the other), family isolation between two synthetic families, cleanup idempotency, an end-to-end `FinalizeHouseFamilyDeletion` run verifying both the authoritative delete and runtime cache/online-state clearing, and a regression guard for the `GetMemberIdentity` tail-call bug above. All 67/67 tests pass.
- Also see `tools/cm-house-family-contracts/check_contracts.py` (added in cm-house v1.8.18) for static regression coverage shared across both resources.

## Documentation

- README now tracks the current version instead of a stale label the previous rewrite still had to catch up to.

No reward algorithms, event scoring, HQ costs, contribution values, or gameplay UI changed.
