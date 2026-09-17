# Live Operations & Incident Command — cm-law 2.2

Live Operations extends the existing shared dispatch feed. It does not create a
second call or responder system.

## Officer workflow

- Open F9 Dispatch or the Dispatch tab in either the LSPD or legal-organization dashboard.
- Set a 3–12 character callsign and choose Available, Busy, or Unavailable.
- Accept a call to become En Route. The call waypoint is set automatically.
- Select On Scene from your unit card after arrival.
- Resolve the call to release every unit assigned to it back to Available.
- Clear your assignment without resolving the incident when another unit takes over.
- Use Route on any visible unit to set a fresh server-verified waypoint.

LSPD's existing 10-8/10-6 quick-menu status is synchronized with the new board.
Assignments, On Scene, and Unavailable appear as 10-6 in the legacy Police state.

## Command workflow

Leaders and ranks with `law.manage_dispatch` see the Incident Command panel.
They can select an active call, set P1/P2/P3 priority, assign the nearest
available unit, release or reassign responders, and command-close the incident.
Available units are ordered by live server-verified distance from the selected
call. The server validates the
commander, unit membership, duty, suspension, dispatch permission, routing
bucket, organization-only audience, current availability, and duplicate assignment.

Supervisors and command ranks receive `law.manage_dispatch` in the default
configuration. Existing custom ranks can be granted it from Ranks & Access.
For LSPD, the existing `police.set_meeting` permission maps to command dispatch.

## Authority and privacy

- Unit coordinates are read from the server-side ped; clients never submit positions.
- The tactical map exposes character IDs internally but never FiveM source IDs.
- Civilians and off-duty, suspended, or unauthorized members receive no snapshot.
- Unit routing is revalidated at click time and respects routing buckets.
- Organization-only calls can only be assigned to members of that organization.
- Calls and responders remain persisted by the existing `cm_legal_incidents` record.
- Priority changes and command actions are audited in the acting organization's activity log.
- Disconnecting or ending duty removes stale responders and returns an empty call to Waiting.
- Callsigns and manual availability are session state and reset safely after restart.

## Statuses

| Status | Meaning |
| --- | --- |
| Available | Ready for dispatch assignment |
| Busy | On duty but not preferred for assignment |
| Unavailable | Cannot be command-assigned |
| En Route | Assigned and travelling to a call |
| On Scene | Assigned and present at the incident |
