# cm-playerdata v1.10.0-ems-protection

- Added trusted server exports `ProtectDeathTimer` and `ReleaseDeathTimerProtection` for assigned medical responders.
- A protected timer is server authoritative, is never shortened, is persisted when extended, and reschedules automatic bleed-out.
- Added a synchronized AI EMS arrival countdown beside the existing bleed-out timer.
- Cleans response protection whenever death is resolved, while preserving the normal ambulance/death lifecycle.

This version is coordinated with `cm-ems` v3.0.0.
