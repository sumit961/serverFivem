# cm-hotel

`cm-hotel` is the CM Roleplay beginner/first-spawn Hotel resource. It owns
Hotel-specific configuration, NPCs, reception help, lift endpoints, the
beginner rental station, and temporary rental lifecycle. It does not own
general onboarding progression, licences, jobs, rooms, bookings, or a generic
elevator implementation.

## Existing Hotel MLO

The repository contains the map resource `[mlo]/hotel`, which depends on
`[mlo]/tstudio_zmapdata`. The verified Hotel gameplay coordinates are owned
by `cm-hotel/config.lua`. The streamed map files do not contain readable
Lua/config coordinates for these points.

## Coordinates/models still required

The captured core points are hardcoded in `config.lua`:

- first spawn
- receptionist model and position
- rental NPC position and rental vehicle spawn
- both Hotel lift interaction and destination pairs

The rental NPC model remains unset until a valid model is selected. Fill that
model in `config.lua` before enabling the rental NPC.

Still optional/unconfigured until supplied:

- `HelpLocations.license`, `jobCentre`, and `hospital` if waypoint help is wanted
- optional blip coordinates/sprite/colour/scale
- real models for `RentalVehicles`

`cm-spawn` resolves `Config.DefaultFirstSpawn = 'hotel'` through the Hotel
export. It uses a generic airport recovery fallback only if this export is
unavailable or invalid.

## First spawn

```lua
local spawn = exports['cm-hotel']:GetFirstSpawn()
-- { key = 'hotel', label = 'HOTEL', coords = vector4(...) }
```

`cm-spawn` resolves `Config.DefaultFirstSpawn = 'hotel'` through this export.
No Hotel coordinate remains in `cm-spawn`.

## Lift integration

The client sends only lift/floor IDs. The server validates the player against
the configured interaction point, constructs the destination data from
`config.lua`, and calls `exports['cm-lift']:OpenLift(...)`. With two valid
floors it passes one validated destination for direct transfer; with three or
more it passes all floors so `cm-lift` opens its menu. `cm-lift` emits the
server-local `cm-lift:server:completed` event, which this resource converts to
`cm-hotel:server:liftUsed` with character ID, lift ID, and selected floor ID.

## Reception and waypoints

Reception uses `cm-ui`'s shared `OpenNpcDialogue` component and the shared CM
interaction prompt. Help choices are server-resolved. Missing locations show
`LOCATION NOT AVAILABLE`; no zero-coordinate waypoint is created.

## Temporary rentals

Rental choices, price, model, duration, and vehicle spawn are resolved on the
server. A rental option ID is the only client-submitted choice. Temporary
vehicles use `cm-vehicles`' existing admin/temporary vehicle registry with
owner character access, recognizable `CMR####` plates, and no database row.
They cannot enter a garage or become owned vehicles. One active rental is
allowed per character; returns require the player to be near the tracked
vehicle and Hotel rental desk. Expiry and resource restart cleanup remove the
temporary registry entry safely.

`FirstRentalFree` is reserved for future `cm-onboarding`; current free/paid
behaviour comes only from each configured option's price. No onboarding
resource is created here.

## Admin Hotel Setup

The coordinate editor is separate from onboarding. Admins with the
`hotel.setup` permission can use:

```text
/hotelsetup
/hotelstatus
```

The editor captures positions from the current player location, supports
heading nudges, previews local NPCs and rental vehicles, tests waypoints, and
tests both lift directions through the real `cm-lift` API. Editor markers are
only drawn for the admin while setup mode is active.

Saved coordinates and optional NPC models are stored in
`data/hotel_setup.json`. The server validates permission, coordinate bounds,
finite numeric values, and heading ranges before writing. Config is
authoritative for the captured core points, so stale saved JSON cannot
override first spawn, receptionist/rental positions, rental vehicle spawn, or
the Hotel lift endpoints. Saved setup remains available for future editable
points such as help locations, blips, and NPC model selection.

Core Config changes require a resource restart. Other saved setup values are
hot-reloaded without a restart.

Reset is confirmation-protected in the editor and clears only the saved JSON;
it does not create a migration or start `cm-onboarding`.
