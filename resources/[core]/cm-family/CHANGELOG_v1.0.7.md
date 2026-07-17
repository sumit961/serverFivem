# cm-family v1.0.7

- Integration pair for cm-house v1.7.6.
- Family creation no longer depends on a circular callback from cm-house into cm-family while `SetFamilyHouseLink` is still executing.
- Added server-side diagnostics when the cm-house linking export itself throws.
- No SQL migration is required.
