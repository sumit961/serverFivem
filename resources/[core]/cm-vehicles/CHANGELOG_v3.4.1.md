# cm-vehicles v3.4.1

- Added a scoped temporary-placement bridge for `cm-house`.
- Only server resources listed in `CMVehicles.Config.Placement.authorizedResources` may use the bridge.
- Trusted placement is accepted only for `car` or `helicopter` placement kinds.
- The bridge forces admin-only access and does not grant the player permanent vehicle-admin permissions.
- Normal `/adminveh` and other temporary vehicle spawning still require the existing vehicle staff check.
