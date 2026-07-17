# cm-family v1.1.5

- Fixed invite acceptance failing while inserting into legacy `cm_family_members` schemas.
- Reconciles and removes orphan member rows left by deleted/failed families before accepting an invite.
- Reads the complete installed member-table metadata at startup.
- Populates required legacy columns (for example `grade`, `citizenid`, `name`, `role`, status/JSON fields) during membership insertion.
- Supports current AUTO_INCREMENT IDs, id-less schemas, legacy numeric IDs, and legacy text IDs.
- Makes same-family membership insertion idempotent.
- Logs the exact generated column list and database error to the server console if an unknown custom constraint still rejects the row.
