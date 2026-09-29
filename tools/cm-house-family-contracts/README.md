# cm-house / cm-family contract checks

Read-only static regression checks protecting the house/family security,
privacy, and ownership-boundary hardening already applied to this repo. Run:

```
python tools/cm-house-family-contracts/check_contracts.py --root .
```

Exit code is non-zero if any check fails. This does not require a running
FXServer, a database, or network access, and it never modifies anything.

Each check guards a specific fix against a future refactor silently undoing
it -- an authorization gate moved after a database read, the family
permission map creeping back into the replicated `cmFamily` state, cm-house
directly deleting a `cm_family_*` table again, a stale integration doc claim,
a removed dead file reappearing, etc. See the docstring in
`check_contracts.py` and the comment on each `check_*` function for what it
verifies and why.

This complements, and does not replace, `tools/cm-validate/validate.py`
(repository/manifest structure) and cm-family's own live
`server/sv_hardening_tests.lua` (concurrency/idempotency/transaction
behavior, run inside a live FXServer with `Config.DevTests = true`).
