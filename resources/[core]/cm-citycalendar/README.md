# cm-citycalendar

`cm-citycalendar` is a standalone administrator-created civic and social event
calendar. It owns only event listings, Character ID RSVP state, and optional
physical attendance records. It is separate from family, gang, club, job,
contract, crime, phone, business, economy, and progression systems.

## Setup and configuration

Apply `sql/001_cm_citycalendar.sql` through the normal migration process. The
resource checks the three required tables and their composite keys at startup,
but never applies SQL automatically. `Config.DefaultEvents` is intentionally
empty, so no permanent production coordinates or events are invented.

Events use Unix timestamps in administrator exports. An event may be enabled
without a physical location; optional attendance requires complete coordinates,
an attendance radius, and optionally a routing bucket. Partial locations are
rejected. Events are validated to a maximum one-year window.

## Owner contracts

- `cm-playerdata:IsCharacterLoaded(source)`, `GetCharacterId(source)`, and
  `IsDead(source)` provide loaded Character ID and lifecycle state.
- `cm-admin:HasPermission(source, 'orgs.manage')` protects administrator
  exports. The caller of each export must be `cm-admin`; this resource does not
  modify administrator permissions.
- `cm-ui:ShowInteract` and `HideInteract` provide the shared cyan check-in
  prompt. `ox_lib` callbacks and notifications follow existing CM conventions.

`cm-admin` currently has no city-calendar CRUD UI. The restricted exports below
are the narrow integration contract for a future owner-side admin surface:

```lua
exports['cm-citycalendar']:AdminCreateEvent(adminSource, {
    eventId = 'community_market',
    title = 'Community Market',
    description = 'A civic social gathering.',
    category = 'Community',
    enabled = false,
    startAt = 1800000000,
    endAt = 1800003600,
    capacity = 100, -- nil for open capacity
    location = {
        x = 0.0, y = 0.0, z = 0.0, radius = 5.0,
        heading = 0.0, routingBucket = nil,
    },
    colour = '#00E5FF',
    displayLabel = 'CHECK IN',
})
exports['cm-citycalendar']:AdminUpdateEvent(adminSource, 'community_market', data)
exports['cm-citycalendar']:AdminSetEventEnabled(adminSource, 'community_market', true)
exports['cm-citycalendar']:AdminCancelEvent(adminSource, 'community_market', 'Weather closure')
local response = exports['cm-citycalendar']:AdminListEvents(adminSource)
```

`AdminSetEventEnabled(false)` disables listing and physical markers without
deleting RSVP or attendance history. `AdminCancelEvent` marks the event
cancelled, disables it, and preserves all history. Cancelled events cannot be
re-enabled.

## Player use

Players use `/events` or `/citycalendar` to open the compact calendar. They can
RSVP to upcoming or active events and cancel an active RSVP before the event
ends. Capacity is enforced on the server. At an active configured location,
players with an active RSVP can use the shared `E` prompt to check in.

The server validates event state, Character ID, loaded/death state, entity
health, RSVP state, routing bucket, distance, cooldown, and duplicate state.
RSVP and attendance records use composite primary keys, and repeated requests
return idempotent results without creating additional records.
