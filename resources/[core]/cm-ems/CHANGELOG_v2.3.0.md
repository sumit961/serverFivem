# cm-ems v2.3.0

- Fixed completed government CPR being rejected because of a stale ambulance position.
- Treatment now validates the actual networked doctor and ambulance positions before a full-health cm-playerdata revive.
- Government ambulances spawn on a clear road node roughly 850–1,250 metres from the patient and drive at a controlled response speed.
- Ambulances target a separate roadside stopping node 14–28 metres from the patient, brake and remain frozen during treatment, then leave after CPR.
- Unsafe spawn points and unreachable patient approaches fail closed and return the dispatch for reassignment.
