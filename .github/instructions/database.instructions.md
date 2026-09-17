---
applyTo: "**/*.sql,**/*db*.lua,**/*database*.lua,**/*mysql*.lua,**/*migration*.lua"
---

# FiveM Database

- Use parameterized oxmysql values and repository conventions.
- Add safe, explicit, repeatable migrations in new version files; never destructively edit applied migrations or silently wipe persistent data.
- Use transactions for authoritative multi-row money, inventory, ownership, house, family, and vehicle mutations.
- Use unique constraints, operation locks, idempotency keys, or journals where duplicate execution matters.
- Preserve administrator configuration and distinguish deterministic repair from ambiguous corruption.
- Never run destructive migrations against an unknown database automatically.
