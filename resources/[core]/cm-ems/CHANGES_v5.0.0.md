# cm-ems v5.0.0 — co-op mission studio

## Mission creator

- F11 → Quick Tools → Open EMS Management now opens the resource-owned EMS admin panel.
- Admins can create, edit, enable, disable and delete persistent EMS missions.
- Each route supports up to 12 ordered stages.
- **Place in world** temporarily hides the menu so the administrator can walk or drive to each route point, then press E to capture it without losing the draft.
- Custom missions are database-backed and become available without restarting.
- Missions can optionally be included in automatic NPC emergencies.

## Co-op crews

- Nearby on-duty medics can join an active crew from `/ems` → Employee Tasks.
- Any crew member may complete the current objective.
- Stage actions are locked server-side so two medics cannot complete the same objective.
- The leader can leave and leadership transfers safely.
- Only medics who complete at least one objective receive money, XP and task credit.
- Authorized EMS vehicle validation now allows the crew driver or a passenger to complete transport checkpoints.

## Automatic NPC emergencies

- The server creates random public emergencies only while EMS is on duty.
- Calls expire, have a maximum open-call count, and are claimed atomically by one crew.
- All on-duty EMS receive a notification and can accept through `/ems`.
- Public calls use eligible built-in or admin-created missions.
- Public incident state is persisted and stale calls are reconciled after restarts.
