# cm-vehicles v3.3.1

## Placement/admin vehicle condition hotfix

- Temporary admin vehicles now publish a complete healthy condition state and `cmConditionReady = true`.
- Added `cmAdminAutoEngine` so placement vehicles requested with `engineOn = true` remain immediately driveable after the player is warped into them.
- Client and server engine checks treat registered admin vehicles as already initialized, preventing replication timing from producing a permanent loading message.
- Owned vehicles still require the normal strict finalize pipeline; this bypass applies only to `cmAdmin` temporary vehicles.
