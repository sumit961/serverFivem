# cm-discovery

`cm-discovery` is a standalone city exploration resource. It owns only the
administrator-configured landmark registry and Character ID discovery records.
It does not create jobs, contracts, rewards, progression, organization data,
phone services, inventory entries, vehicles, or economy activity.

## Setup

Apply `sql/001_cm_discovery.sql` through the normal migration process. The
resource checks the two required tables and the composite discovery primary key
at startup, but never applies SQL automatically. No landmarks or production
coordinates are seeded. The registry remains empty until an administrator
creates configured landmarks.

## Owner contracts

- `cm-playerdata:IsCharacterLoaded(source)`, `GetCharacterId(source)`, and
  `IsDead(source)` provide loaded Character ID and lifecycle state.
- `cm-admin:HasPermission(source, 'orgs.manage')` authorizes the restricted
  administrator exports. The export caller must be `cm-admin`; `cm-discovery`
  does not modify administrator permissions or add an admin UI.
- `cm-ui:ShowInteract` and `HideInteract` provide the shared cyan proximity
  prompt. `ox_lib` notifications and callbacks follow existing CM conventions.

`cm-admin` currently has no discovery-specific CRUD screen. The narrow server
exports below are the documented integration point for an owner-side admin
surface; they are server-only and cannot be invoked by clients:

```lua
exports['cm-discovery']:AdminCreateLandmark(adminSource, {
    landmarkId = 'city_museum',
    name = 'City Museum',
    description = 'A configured city landmark.',
    category = 'Culture',
    enabled = true,
    x = 0.0, y = 0.0, z = 0.0, radius = 3.0,
    heading = 0.0,
    displayLabel = 'DISCOVER LANDMARK',
    routingBucket = nil,
    blip = { enabled = false, sprite = nil, color = nil, scale = nil },
})
exports['cm-discovery']:AdminUpdateLandmark(adminSource, 'city_museum', data)
exports['cm-discovery']:AdminSetLandmarkEnabled(adminSource, 'city_museum', false)
local response = exports['cm-discovery']:AdminListLandmarks(adminSource)
```

Landmark IDs are stable lower-case identifiers. Enabled landmarks require valid
coordinates and a discovery radius; disabled records clear location and blip
configuration, so they cannot be discovered accidentally. Coordinates and
metadata are validated server-side. A future admin UI should call these exports
from `cm-admin` rather than writing the tables directly.

## Player use

Players use `E` at a configured landmark through the shared `cm-ui` prompt.
`/discoveries` opens the compact personal checklist. The checklist uses the
current Character ID, shows discovered and undiscovered enabled landmarks,
category filtering, progress, and original discovery date. A previously
discovered landmark remains visible as archived if an administrator disables it.

The server revalidates character load, death state, landmark configuration,
entity health, routing bucket, distance, cooldown, and the unique discovery
record. Replayed requests return the existing discovery timestamp and never
award anything or alter the record.
