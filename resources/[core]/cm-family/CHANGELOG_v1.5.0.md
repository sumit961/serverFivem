# cm-family v1.5.0

- Adds opt-in nearby family-member minimap blips (300m, short-range, local KVP preference).
- Adds rank permission `vehicle.track`.
- Adds server-authoritative shared-vehicle tracking snapshots with a 5-minute cooldown.
- Tracking creates a static five-minute route/blip; it is not continuous GPS.
- Adds family audit event `vehicle_tracked`.
- Untouched stock Officer ranks receive `vehicle.track`; custom ranks are not changed.
