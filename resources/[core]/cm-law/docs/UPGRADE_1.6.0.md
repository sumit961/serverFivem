# cm-law 1.6.0

This release turns the organization overview into a live command dashboard while preserving every existing FiveM NUI callback and server-authoritative gameplay flow.

## Included

- Live emergency-call, assigned-unit, personnel, and fleet-readiness metrics.
- Priority-call banner with permission-gated response and server-validated routing.
- Direct Dispatch and Shared MDT navigation for on-duty authorized members.
- Live systems indicator, local dashboard clock, refresh control, and end-duty control.
- Correct F6 terminal labeling and `/laworg` dashboard behavior.
- Responsive layout polish based on the supplied legal-organization mock-up; no `backdrop-filter` is used.
- Dispatch history isolation by routing bucket.
- Tracking access is revalidated while active and is revoked immediately when duty or permission is lost.
- Meeting points only broadcast to on-duty, non-suspended recipients; clearing still removes stale blips from all online organization members.
- Malformed legacy rank-permission or activity-log JSON now fails closed instead of breaking the dashboard.
- Default supervisor/command rank seeds include member-map and meeting-point permissions on new installations.

Existing database rank rows remain authoritative and are not overwritten. On an upgraded server, use **Ranks & Access** once to grant `View organization members on the map` and `Set and clear organization meeting points` to any existing ranks that should have them.

## Recommended next systems

These need new data models and gameplay decisions, so they are intentionally not represented with fake dashboard data:

1. Divisions and specialist units with division leaders and per-division permissions.
2. Persistent shift sessions, callsigns, partners, patrol time, and end-of-shift reports.
3. Certifications for firearms, pursuit, pilot, K9, marine, and first aid access.
4. Case-centric MDT linking reports, evidence, warrants, citations, suspects, and vehicles under one case number.
5. Fleet service history, mileage, assigned callsign, maintenance state, and certification gates.
6. Command notices and scheduled briefings with attendance logging.
7. Evidence chain-of-custody, capacity alerts, audit requests, and transfer signatures.
8. Inter-agency operations that temporarily share calls, radio channels, intelligence, and command roles.

## Upgrade

Replace the previous `cm-law` folder, keep your database, then restart `cm-law`. The resource continues to create its required tables automatically. No destructive migration is included.
