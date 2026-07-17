# cm-vehicles v3.5.1

- Adds trusted `GetTrackableVehicleLocation` export for cm-family.
- Returns live world coordinates when the registered entity exists.
- Returns family-house garage coordinates for stored house vehicles.
- Falls back to the last persisted position when no live entity exists.
- Authorizes cm-family for read-only location resolution.
