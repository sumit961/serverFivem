# cm-ems v1.2.0

- Added a server-authorized activity log dashboard for ranks with `ems.view_logs`.
- Confirmed the unique EMS leader always receives every configured EMS permission.
- Added a red EMS-specific dashboard theme while preserving the shared CM layout and typography.
- Added clear organization activity labels for duty, outfit, rank, membership, invitation and leadership actions.
- Reconciled the organization leader with the protected leader membership rank during startup.
- Added server-derived dashboard capabilities so leader management controls cannot disappear because of stale client state.
- Fixed oxmysql `TINYINT(1)` boolean decoding so the EMS leader receives all permissions and management controls reliably.
