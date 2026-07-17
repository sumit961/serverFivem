# cm-family v1.4.0 — Durable family activity audit

- Added append-only `cm_family_activity_log` with event UID deduplication.
- Awaited writes plus disk-backed retry queue (`audit_pending.json`).
- Added activity categories, severity, high-risk flag, actor/target names, house/vehicle IDs, amount and source resource.
- Added Family Menu → Logs with category filtering and high-risk highlighting.
- Added `family.view_logs` permission; founder is always authorized and default Officer receives it.
- Added server-only allowlisted `WriteFamilyActivity` export for cm-house/cm-vehicles/cm-chat/cm-inventory.
- Added permission-gated cm-admin read exports and a server-only high-risk event.
- Added chat sent/blocked audit without storing message content.
- Promotion and demotion now use distinct audit actions.
- Activity history survives family deletion and is retained for 180 days by default.

- Manual family disband now records a durable `family_deleted` high-risk row after the delete transaction commits.
- External family-bank charges are audited with amount, reason, and final balance.
- Added explicit categories for family-house entry/purchase/refund, garage entry/sharing, and access grant/revoke events.
- Untouched existing Officer ranks are upgraded with `family.view_logs`; customized ranks are never overwritten.
