# cm-ems v5.2.0 — Simple Treatment & Response Quality

The medical loop remains intentionally simple: patch conscious patients or
revive unconscious patients.

## Treatment

- Added CPR/treatment animations and clearer medic/patient progress labels.
- Replicates an active treatment marker so other EMS can see that a patient
  is already being treated.
- Added a configurable server-owned treatment cooldown.
- A successful field revive now attaches the treating medic to the patient's
  active dispatch incident before that incident resolves.
- Reward, XP and task credit continue to use the existing database-backed
  idempotency keys, so one death can pay and progress only once.

## Transport and dispatch

- Added an optional **Load into Ambulance** action for unconscious players.
- Added a rebindable active-call backup key (default `B`).
- Added a rebindable EMS panic key (default `F9`) with a prominent flashing
  dispatch blip and a server-side 30-second panic cooldown.
- Backup requests re-send the priority incident card with GPS information.
- Government-doctor auto response now respects the configurable
  `Config.Dispatch.governmentDoctor.minimumOnDutyEMS` threshold.

## Statistics

- The EMS overview shows successful patients treated, resolved calls and
  average call-created-to-on-scene response time for the current character.
- Statistics are derived from existing authoritative reward and incident
  history tables; no database migration is required.
