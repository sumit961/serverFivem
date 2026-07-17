# cm-house v1.3.2.1 hotfix

## Fixed

- Fixed `sv_templates.lua:138` crashing while saving a new interior template.
- New interior templates no longer try to read `t.stashes` from a non-existent existing-template row.
- New stash points now use the captured label/capacity or safe defaults (`Storage`, 30 slots).
- Re-walking an existing interior now correctly reads its saved stash metadata and preserves stash labels/capacities unless replacements are supplied.
- Updated the `cm-house` manifest version to `1.3.2.1`.

No SQL migration is required for this hotfix.
