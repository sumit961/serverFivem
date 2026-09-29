# cm-family v1.9.5

## Family data ownership (maintenance/architecture follow-up)

- `FinalizeHouseFamilyDeletion` (the export cm-house calls on a house-triggered family disband) is now the single authoritative entry point for family-domain deletion: it calls `CMFamilyDeleteFamilyRows` itself (transactional, idempotent, already used by cm-family's own disband/leave flows) and then clears runtime caches and online members' state, in one authorized call. cm-house no longer deletes any `cm_family_*` row directly.
- Still invoker-restricted to cm-house (or self); unknown callers are rejected. Calling it twice for the same family remains safe (second call finds nothing left to delete and reports success).

## Housekeeping

- Removed `server/sv_meeting.lua` and `client/cl_meeting.lua`. Confirmed dead: neither file is referenced by `fxmanifest.lua`, and the live `setMeetingPoint` flow (`sv_menu.lua` + `cl_tracking.lua`) already covers everything they did, plus a map blip/GPS route the dead client file lacked. Removing them changes zero runtime event registrations.
- `audit_pending.json` (the runtime audit-retry queue) is no longer tracked by git; it remains on disk and is now gitignored by exact path.
- Rewrote `README.md` for the current architecture (ranks/permissions, family house integration, vehicles, tracking, treasury, HQ/progression, objectives/contributions, event engine, reward lifecycle, and the public-vs-private `cmFamily` state contract from v1.9.4), replacing the stale v1.5.1 description.

No reward algorithms, event scoring, HQ costs, contribution values, or gameplay UI changed.
