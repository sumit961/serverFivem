# cm-lift

`cm-lift` is a generic, server-authoritative lift/elevator engine. It owns no
building, hotel, police, EMS, apartment, business, or house lift locations.
The resource that owns a location detects proximity, validates access, and
calls the server export below.

## Public server API

```lua
local ok, sessionId = exports['cm-lift']:OpenLift(source, {
    id = 'hotel_main',
    label = 'Hotel Elevator',
    currentFloor = 'rooms',
    floors = {
        { id = 'ground', label = 'Ground Floor', coords = vector4(250.0, -1000.0, 29.0, 180.0) },
        { id = 'rooms', label = 'Hotel Rooms', coords = vector4(250.0, -1000.0, 45.0, 180.0) },
        { id = 'roof', label = 'Rooftop', coords = vector4(250.0, -1000.0, 60.0, 180.0), locked = true, lockedReason = 'Restricted Access' }
    }
})
```

For a direct connection, no floor menu is opened:

```lua
local ok, sessionId = exports['cm-lift']:OpenLift(source, {
    id = 'small_office_lift',
    label = 'Elevator',
    destination = vector4(300.0, -950.0, 30.0, 90.0)
})
```

`CreateLiftSession` is a compatibility alias for `OpenLift`. A one-floor
`floors` definition also becomes a direct lift. `exitOffset` is optional and
is applied along the supplied heading; the supplied Z remains authoritative.
Direct owners may provide `destinationFloorId` so the generic completion hook
can identify the selected floor without exposing coordinates.

The export is server-only. The owner must perform its own proximity,
ownership, permission, routing-bucket, and character checks before calling it.
Building-specific permission logic does not belong in this resource.

## Security and lifecycle

- Sessions are stored per player for 30 seconds and are single-use.
- The client/NUI receives only session/presentation data until the server
  validates a floor selection.
- NUI callbacks submit only `sessionId` and `floorId`; they never submit
  coordinates, heading, money, permissions, or ownership data.
- Invalid, locked, current, expired, and forged selections are rejected.
- Server-side rate limits prevent repeated open and selection requests.
- Routing buckets are never changed by `cm-lift`.
- Vehicles are rejected; the vehicle is never teleported.
- Destination collision loading, screen fading, control restoration, NUI
  cleanup, and failure recovery are bounded and fail closed.
- On successful server validation, cm-lift emits the server-local
  `cm-lift:server:completed` event with `ownerResource`, `liftId`, `source`,
  and `selectedFloorId` only.

## Interaction ownership

The owning resource should use the shared prompt:

```lua
exports['cm-ui']:ShowInteract({ key = 'E', label = 'USE ELEVATOR' })
-- On E, call the owner's server event; the server then calls OpenLift.
exports['cm-ui']:HideInteract()
```

`cm-lift` does not scan the world or register permanent interaction zones.

## Development smoke test

When `Config.Debug` is enabled in a development server, `/testlift multi`
creates a dynamic menu with two selectable destinations from the player's
current position and `/testlift direct` exercises the direct path. These
commands are not registered when `Config.Debug` is false and do not define
permanent locations. The local development config currently enables this
diagnostic mode; disable it before production deployment.

## Example owner architecture

`cm-hotel` would show the shared prompt from its client proximity loop, send
`cm-hotel:server:useMainLift` on E, validate the player is near its elevator
on the server, then call `exports['cm-lift']:OpenLift(source, {...})`. The
example is documentation only; no `cm-hotel` resource or locations are added
here.
