# cm-vehicles — API Reference

Everything another resource can call. Server exports, client exports, events,
and the admin/temporary vehicle system.

---

## Contents

1. [Two kinds of vehicle](#two-kinds-of-vehicle)
2. [Server exports — owned vehicles](#server-exports--owned-vehicles)
3. [Server exports — admin vehicles](#server-exports--admin-vehicles)
4. [Client exports](#client-exports)
5. [Events](#events)
6. [The database](#the-database)
7. [Recipes](#recipes)
8. [Common mistakes](#common-mistakes)

---

## Two kinds of vehicle

This distinction explains most of the API.

| | **Owned** | **Admin / temporary** |
|---|---|---|
| Row in `cm_owned_vehicles` | yes | **no** |
| Survives a restart | yes | **no** |
| Belongs to a character | yes | optionally |
| Can be stored in a garage | yes | no |
| Created by | purchase, `CreateOwnedVehicle` | `SpawnAdminVehicle` |

**Spawning is not giving.** `SpawnAdminVehicle` puts a car in the world. It
writes nothing to the database and gives nobody a vehicle. When the server
restarts it is gone.

Every access check in cm-vehicles resolves a plate to a database row. A car
with no row would therefore report *"Vehicle not found"* and refuse to start —
which is why admin vehicles get a **synthetic row**: a fake record, never
saved, that exists only so the rest of the resource can treat the car normally.
Its `id` is `-1`, so any code that tries to `UPDATE ... WHERE id = ?` touches
nothing.

---

## Server exports — owned vehicles

### `GetCharacterId(src) → number|nil`
The character id of a player. `nil` if no character is loaded.

```lua
local charId = exports['cm-vehicles']:GetCharacterId(src)
```

### `GetVehicleByPlate(plate) → table|nil`
The full vehicle row. Returns a **synthetic row** for admin vehicles — check
`row.__admin` if you need to tell them apart.

```lua
local v = exports['cm-vehicles']:GetVehicleByPlate('ABC 123')
if v and not v.__admin then
    print(v.label, v.owner_character_id, v.is_stored)
end
```

### `PlayerOwnsVehicle(src, plate) → boolean`
Strict ownership. Temporary keys do **not** count.

### `HasVehicleAccess(src, plate) → boolean`
May this player drive it? Owner **or** temp key **or** admin-vehicle access.
This is the check to use for "can they get in and start it".

```lua
if not exports['cm-vehicles']:HasVehicleAccess(src, plate) then
    return notify(src, 'You do not have keys.')
end
```

### `CreateOwnedVehicle(charId, model, label, opts) → number|nil`
Give a character a **real, permanent** vehicle. Writes to the database.

```lua
local vehicleId = exports['cm-vehicles']:CreateOwnedVehicle(
    charId, 'sultan', 'Sultan', { plate = 'ABC 123' })
```

### `SpawnVehicleFromParking(src, vehicleId, lotId, spawn, opts) → boolean, string`
Take a stored vehicle out of a garage and into the world. Clears `is_stored`,
repairs it, and creates the entity.

```lua
local ok, err = exports['cm-vehicles']:SpawnVehicleFromParking(
    src, vehicleId, 'house:12',
    { x = 100.0, y = 200.0, z = 30.0, w = 90.0 },
    { warp = false, engineOn = false }
)
```

> **There is no matching "store" export.** cm-vehicles can take a car *out* of
> parking but cannot put one back. Storing means writing `is_stored = 1` and
> `garage = '<your key>'` yourself — see [Recipes](#recipes).

### `DeleteSpawnedVehicle(plate) → boolean, reason?`
Synchronously remove the registered entity and any orphan carrying the same
`cmPlate` state. It waits for OneSync deletion acknowledgement before clearing
the registry. It does **not** delete the database row. When it returns `false`,
the caller must abort or roll back its database transition.

### `SaveVehicleModsAuthorized(src, plate, mods) → boolean`
Persist cosmetics and tuning. Authorised: only the owner may call it.

### `ServiceVehicle(src, plate, kind) → boolean`
`kind` is `'refuel'`, `'repair'` or `'wash'`.

### `HasRacingHarness(plate) → boolean`

Returns whether the permanent vehicle metadata contains a racing harness.

### `InstallRacingHarness(src, plate, netId) → boolean, reason?`

Server-only, allowlisted export for trusted resources after they consume an item or charge payment. Public installation net events and the `/installharness` command are intentionally unavailable. Configure callers under `CMVehicles.Config.Security.authorizedHarnessResources`.

### `GetLentKeys(src) → table`
Plates this player currently holds temporary keys for.

---

## Server exports — admin vehicles

### `SpawnAdminVehicle(src, model, coords, opts) → table`

A car that exists in the world but in no garage.

**Returns a single table** — FiveM's export bridge only reliably carries the
first return value, so `(ok, result)` gets silently truncated across a resource
boundary.

```lua
{ ok = true,  plate = 'ADM00001', netId = 12, entity = 34 }
{ ok = false, error = 'Could not create "banana". Is the model streamed?' }
```

**opts:**

| key | type | meaning |
|---|---|---|
| `access` | `'public'` \| `'owner'` \| `'admin'` | who may drive it. Default `'public'` |
| `ownerCid` | number | **required** when `access = 'owner'` |
| `label` | string | shown in menus |
| `plate` | string | optional; auto-generated (`ADM00001`) otherwise |
| `warp` | boolean | put the spawner in the driver's seat |
| `engineOn` | boolean | default `true` |
| `frozen` | boolean | for props and markers |
| `invincible` | boolean | |

**Access modes:**

- **`public`** — anyone may drive it. Event props, free cars, test vehicles.
- **`owner`** — only the character in `ownerCid`. Staff can always drive it too,
  or they could strand themselves with a car they cannot move.
- **`admin`** — staff only. Placement markers, staging vehicles.

```lua
-- anyone can drive this
local r = exports['cm-vehicles']:SpawnAdminVehicle(src, 'sultan', coords, {
    access = 'public',
    label  = 'Event car',
})

-- only character 42 can drive this
local r = exports['cm-vehicles']:SpawnAdminVehicle(src, 'adder', coords, {
    access   = 'owner',
    ownerCid = 42,
    label    = "Prize car for Jane",
})

if not r.ok then
    print('spawn failed: ' .. r.error)
end
```

### `DeleteAdminVehicle(plate) → boolean`
### `DeleteAllAdminVehicles(spawnedBy?) → number`
Pass a `charId` to clear only that person's, or nothing to clear everything.

### `IsAdminVehicle(plate) → boolean`
### `SetAdminVehicleAccess(plate, access, ownerCid?) → boolean, string`
Change who may drive an already-spawned car.

### `ListAdminVehicles() → table[]`

```lua
{ plate = 'ADM00001', model = 'sultan', label = 'Event car',
  access = 'public', ownerCid = nil, netId = 12, alive = true }
```

---

## Client exports

### `IsAdminVehicleClient(entity) → boolean`
Whether the car in front of you is a temporary one. Useful so a HUD does not
tell a player they *lack keys* to a car that has **no owner at all**.

---

## Events

### Server → Client

| event | args | when |
|---|---|---|
| `cm-vehicles:client:engineStartResult` | `netId, ok, message` | engine start allowed or refused |
| `cm-vehicles:client:adminEngine` | `netId, on` | start an admin car's engine |
| `cm-vehicles:client:exitTrunk` | `force` | player must leave a trunk |

### Client → Server

| event | args |
|---|---|
| `cm-vehicles:server:requestEngineStart` | `plate, netId` |
| `cm-vehicles:server:toggleLock` | `plate, netId` |
| `cm-vehicles:server:giveTempKey` | `targetSrc, plate` |

### Commands

| command | who | what |
|---|---|---|
| `/adminveh <model> [public\|owner\|admin] [charId]` | staff | spawn a temporary car |
| `/dvadmin` | staff | delete the car you are in |
| `/dvall` | staff | clear every temporary car on the map |

Staff = `cm-core` ACL `vehicles.admin`, or the ACE `cm-vehicles.admin`:

```cfg
add_ace group.admin cm-vehicles.admin allow
```

---

## The database

### `cm_owned_vehicles`

| column | type | notes |
|---|---|---|
| `id` | INT | primary key |
| `owner_character_id` | VARCHAR | the character who owns it |
| `model` | VARCHAR | `'sultan'` |
| `label` | VARCHAR | display name |
| `plate` | VARCHAR | **unique** |
| `fuel` | INT | 0–100 |
| `engine_health` · `body_health` · `tank_health` | FLOAT | 0–1000 |
| `dirt_level` | FLOAT | 0–15 |
| `is_locked` | TINYINT | |
| **`is_stored`** | TINYINT | **in a garage, or out in the world** |
| **`garage`** | VARCHAR | **which garage. Free text — `cm-house` writes `house:<id>`** |
| `parking_id` | VARCHAR | |
| `parked_at` | TIMESTAMP | |
| `last_position` | LONGTEXT | JSON |
| `mods` | LONGTEXT | JSON |
| `metadata` | LONGTEXT | JSON |

> **`is_stored` + `garage` is the single source of truth for where a vehicle
> is.** If your resource also keeps its own opinion, the two will drift — and
> the moment they disagree, the car exists twice. Store *which slot* if you
> like; never store *whether it is parked*.

---

## Recipes

### Store a vehicle in your own garage

cm-vehicles has no store export, so write it yourself — **in one transaction**,
or a crash between the two writes leaves a car that is parked and driving at
the same time.

```lua
-- Use one guarded statement and inspect affected rows. oxmysql transactions can
-- return true even when a guarded UPDATE inside them changed zero rows.
local affected = MySQL.update.await([[
    UPDATE cm_owned_vehicles v
    INNER JOIN my_slots s ON s.id = ?
    SET v.is_stored = 1,
        v.garage = ?,
        v.parked_at = NOW(),
        s.vehicle_id = v.id
    WHERE v.id = ?
      AND v.is_stored = 0
      AND s.vehicle_id IS NULL
]], { slotId, 'mygarage:5', vehicleId })

if affected and affected > 0 then
    local deleted, reason = exports['cm-vehicles']:DeleteSpawnedVehicle(plate)
    if not deleted then
        -- Roll both authorities back with another guarded multi-table UPDATE.
        print(('vehicle delete failed: %s'):format(reason or 'unknown'))
    end
end
```

The vehicle row and slot row move as one authority change. A zero affected-row
count means another request won the race and no entity should be created or
deleted for this transition.

### Everything parked in my garage

```lua
local rows = MySQL.query.await([[
    SELECT id, plate, model, label, fuel, engine_health
    FROM cm_owned_vehicles
    WHERE garage = ? AND is_stored = 1
]], { 'mygarage:5' })
```

### Reconcile after a crash

A server that dies mid-transition leaves cars that claim to be parked but are
not. Check on boot, or the space is lost forever.

```lua
MySQL.update.await([[
    UPDATE my_slots s
    LEFT JOIN cm_owned_vehicles v ON v.id = s.vehicle_id
    SET s.vehicle_id = NULL
    WHERE s.vehicle_id IS NOT NULL
      AND (v.id IS NULL OR v.is_stored = 0 OR v.garage <> ?)
]], { 'mygarage:5' })
```

---

## Common mistakes

**Comparing a database boolean with `== 1`.**
oxmysql returns `TINYINT(1)` as `true`, `1`, or `'1'` depending on its
type-casting settings. `v.is_stored == 1` is `false` when it hands back `true` —
and a stored car then reads as un-stored, which lets it be parked twice.

```lua
local function DbBool(v)
    if v == true or v == 1 then return true end
    if type(v) == 'string' then
        v = v:lower()
        return v == '1' or v == 'true' or v == 'yes' or v == 'on'
    end
    return false
end
```

**Expecting two return values from an export.**
FiveM's export bridge reliably carries only the first. Return one table.

**Trusting a plate from the client.**
Plate *text* can be forged. cm-vehicles identifies a car by the `cmPlate` state
bag, set server-side. Pass a `netId` and let `ResolvePlate` do the work.

**Keeping your own copy of `is_stored`.**
See the warning above. Store the slot; never store the state.
