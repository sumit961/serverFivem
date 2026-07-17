# cm-house v1.2.7 — Garage vehicle exit fix

- The interior vehicle-exit marker is always visible in cyan.
- The exit prompt no longer depends on a delayed `cmHouseGarageDisplay` state bag.
- Pressing E as the driver resolves the parking slot from the authoritative network ID.
- Server can rebuild the netId-to-slot mapping after a resource restart or delayed propagation.
- Clear error is shown when a garage template has no valid vehicle-exit point.
