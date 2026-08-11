# cm-playerdata v1.11.0

- Death respawn now requests the nearest available bed from `cm-doctor`.
- Supports Pillbox and Sandy Shores without placing two patients in one bed.
- When every configured bed is occupied, the server waits and retries instead of overlapping a fallback spawn.
- Hospital billing and the assigned hospital/bed are server-authoritative and included in audit data.
