# cm-house v1.3.2

- Preserves genuine zero vehicle health.
- Captures and stores complete physical condition before exterior deletion.
- Adds per-database-vehicle operation tokens, timeout/disconnect handling, and guarded rollback.
- Fixes last-occupant drive-out cleanup deleting the promoted vehicle.
- Uses vehicle ID for entity lookup, deletion, occupant validation, locks, and slot operations.
- Adds startup slot reconciliation and migration 009 unique constraints.
- Merges visual wear monotonically so normal storage cannot repair broken parts.
