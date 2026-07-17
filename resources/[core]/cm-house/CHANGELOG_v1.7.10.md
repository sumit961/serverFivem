# cm-house v1.7.10

- Normalized legacy family/rank/member columns in the local compatibility cache.
- Family member access-map refresh now falls back directly to committed membership rows.
- Duplicate member refreshes are deduplicated.
- Designed to pair with cm-family v1.1.7.

Note: engine/key authorization remains owned by cm-vehicles/cm-vehiclekeys and requires those exact resources for a complete family-session-key patch.
