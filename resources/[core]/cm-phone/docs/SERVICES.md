# cm-phone Service Marketplace (Services app)

The phone is a **frontend**. It lists services, collects a validated request, forwards it to the **source owner**, and shows the owner's
status. It keeps **no requests and no history**, creates **$0 / 0 items / 0 XP**, and adds no service fee (payment belongs to the owner).

```
PHONE (NUI)  ->  cm-phone server  ->  service adapter  ->  SOURCE OWNER (authoritative request)
                                                              ->  cm-contracts (publishes work)  ->  PROVIDER job (gameplay, reward)
status:  PROVIDER -> cm-contracts -> SOURCE OWNER -> (status export / push) -> cm-phone -> player
```

The phone never calls a provider job and never mutates the broker. Cancellation goes phone -> owner -> (owner releases/cancels its contract).

## Where things live

| Thing | Owner |
|---|---|
| Service **display + validation definition** (name, icon, fields, one-active policy) | `cm-phone/config.lua` -> `Config.Services.Catalog` (trusted, static) |
| Which resource may serve which service | `Config.Services.Sources` (resource-name allowlist, `GetInvokingResource()`) |
| The request, its state, price, assignment, completion | the **source owner** (taxi, courier, mechanic, ...) |
| Work publication, claim, lease, fallback | `cm-contracts` (called by the source owner) |
| Gameplay, reward, XP | the provider job |

Adding a service = one `Catalog` entry + one `Sources` entry + the owner's adapter. **No phone core change.**

## Availability

`available` (owner started + adapter registered), `limited` (owner's availability export says so), `offline` (owner not running / not registered / says offline),
`soon` (catalog `comingSoon = true`; an adapter cannot override it). Only `available`/`limited` services accept requests; nothing fakes a success.
`Config.Services.HideOffline = true` hides unavailable owners instead of showing them as Unavailable.

## Owner adapter contract

Register on start **and** on `cm-phone:server:serviceRegistryReady` (registration is in memory):

```lua
local function register()
    exports['cm-phone']:RegisterPhoneService('taxi', {
        create = 'PhoneServiceCreate',          -- required
        status = 'PhoneServiceStatus',          -- required
        cancel = 'PhoneServiceCancel',          -- optional: omit and the phone never offers Cancel
        availability = 'PhoneServiceAvailability', -- optional
    })
end
AddEventHandler('onResourceStart', function(r) if r == GetCurrentResourceName() then register() end end)
AddEventHandler('cm-phone:server:serviceRegistryReady', register)
```

Each export must check `GetInvokingResource() == 'cm-phone'`, derive ownership from the **character id** it is given, and return `true, data` / `false, reason`:

| Export | Called as | Returns |
|---|---|---|
| `create(characterId, serviceId, fields, ctx)` | `fields` = validated, whitelisted keys only; `ctx.position = {x,y,z,bucket}` is **server-observed** | `true, { ref, state, etaSeconds?, workerLabel?, detail?, canCancel? }` or `false, reason` |
| `status(characterId, serviceId)` | the character's current request | `true, nil` (none) or `true, { ref, state, ... }` |
| `cancel(characterId, serviceId, ref)` | only after the phone confirmed `ref` is this character's own open request and `canCancel` | `true` or `false, reason` |
| `availability(serviceId)` | | `true` / `'limited'` / `false` |

`ref` is a public request reference (`[%w_-:.]`, <= 40). Safe `reason` values: `already_active, service_unavailable, no_provider, invalid_destination, too_far,
cooldown, dead, not_allowed, busy, not_found, cancel_not_allowed` (anything else is shown as a generic failure; internals are never echoed).

### Player-facing states (the only vocabulary the phone accepts)

`searching` (Looking for a worker, yellow) · `assigned` (Worker assigned, green) · `enroute` (Worker on the way, green) · `active` (Service in progress, cyan) ·
`completed` (Completed, green) · `fallback_completed` (Completed automatically, green) · `cancelled` (red) · `no_provider` (red).
Anything else (`fallback`, `claimed`, `claim_expires_at`, `claimed_character_id`, ...) is rejected and never reaches the NUI. For owners that use `cm-contracts`,
`exports['cm-phone']:TranslateContractStatus(contractStatus, completionMode)` maps broker states to this vocabulary.
Worker identity: only an optional `workerLabel` (<= 40 chars, e.g. "Driver assigned") chosen by the owner; no source id, account or hidden CID is ever carried.

### One active request

`Catalog[service].activePolicy`: `'single'` (default; the phone returns `already_active` with the current request before calling `create`) or `'multi'` (owner decides).
The owner should enforce its own policy too.

### Status push (optional, event-driven; no polling)

```lua
exports['cm-phone']:PushPhoneServiceStatus(characterId, 'taxi', { state = 'assigned', ref = ref, workerLabel = 'Driver assigned', etaSeconds = 240 })
```
Only the resource registered for that service may push. The status is reduced to the public shape and shown as a toast (or refreshes the open screen); identical
repeats within 2 s are dropped. Returns `false, 'offline'` if the requester is not online (the owner does not need to care; they see it on next open).

## Client / NUI surface

`cm-phone:services`, `serviceStatus(serviceId)`, `serviceRequest{ serviceId, fields }`, `serviceCancel{ serviceId, ref }` (ox_lib callbacks, rate-limited per character:
request 1 / 2.5 s and 4 / min, cancel 1 / 1.5 s). `cm-phone:client:serviceStatus` (server -> client push). There are no client -> server net events.

Request fields are defined per service: `text` (cleaned, bounded), `enum` (allowlist), `waypoint` (`{x, y[, z]}`, finite, |x|,|y| <= `WorldLimit`; the NUI sends the marker `'@waypoint'`
and the client resolves the player's own map waypoint, the server re-validates the shape/range). Unknown keys, wrong types, oversized text and nested tables are rejected.
The requester's own position is sampled **once, server-side** per request and passed in `ctx`; there is no tracking.

## Why no request history

Source owners already own their request records. The phone shows the **current** request (asked of the owner on open/refresh) and pushes; a second history table would duplicate
source data and drift. If a cross-service history is ever wanted it must be justified and read from owners, not copied.

## Copy-ready: Taxi owner adapter (cm-taxi) — SHARED INTEGRATION REQUIRED

`cm-taxi` has no server exports; `requestTaxi(src)` is a local function and the working tree has other uncommitted `cm-taxi` changes, so the phone integration was **not** written there.
Minimal owner-side change (inside `cm-taxi/server/main.lua`, next to `requestTaxi`): split `requestTaxi(src)` so the chat command and the phone share one function that returns a result
instead of only notifying, then add:

```lua
-- returns true, { ref = fare id, state = 'searching' } | false, 'already_active' | 'service_unavailable' | 'dead'
local function createPlayerTaxiRequest(src, fields, ctx) ... end   -- extracted from requestTaxi (same fare record, same rate limit)

local PHONE = 'cm-phone'
local function characterSource(cid) return exports['cm-playerdata']:GetSourceByCharacter(cid) end -- or the existing lookup in cm-taxi

exports('PhoneServiceCreate', function(cid, service, fields, ctx)
    if GetInvokingResource() ~= PHONE then return false, 'not_allowed' end
    local src = characterSource(cid); if not src then return false, 'service_unavailable' end
    return createPlayerTaxiRequest(src, fields, ctx)               -- fields.destination / fields.details already validated
end)
exports('PhoneServiceStatus', function(cid)
    if GetInvokingResource() ~= PHONE then return false end
    local fare = findOpenPlayerFare(characterSource(cid))          -- fare.playerRequested and fare.requestedBy == src
    if not fare then return true, nil end
    local map = { queued = 'searching', searching = 'searching', accepted = 'enroute', completed = 'completed', cancelled = 'cancelled', expired = 'cancelled' }
    return true, { ref = tostring(fare.id), state = fare.phase == 'boarded' and 'active' or map[fare.status] or 'searching',
                   canCancel = fare.phase ~= 'boarded', workerLabel = fare.driver and 'Driver assigned' or nil }
end)
exports('PhoneServiceCancel', function(cid, service, ref)
    if GetInvokingResource() ~= PHONE then return false, 'not_allowed' end
    return cancelPlayerTaxiRequest(characterSource(cid), ref)       -- same code path as /taxicancel; refuses once boarded
end)
```
`notifyTaxiRequester(fare, status, data)` can additionally call `PushPhoneServiceStatus` (it already runs on every status change). Taxi keeps its own assignment/claim logic; a later migration of
driver assignment onto `cm-contracts` (`courier_delivery`-style `taxi_ride` type) is a separate task.

## Copy-ready: Courier owner (future, uses cm-contracts)

```lua
-- cm-courier (or the parcel owner): the PARCEL record is the source of truth
exports('PhoneServiceCreate', function(cid, service, fields, ctx)
    if GetInvokingResource() ~= 'cm-phone' then return false, 'not_allowed' end
    local parcel = createParcel(cid, fields.details, fields.destination, fields.size, ctx.position)   -- owner validates, prices, charges
    if not parcel then return false, 'service_unavailable' end
    exports['cm-contracts']:CreateContract({ contractType = 'courier_delivery', sourceReference = parcel.ref,
        title = 'Parcel delivery', pickupHint = 'Pickup point', destinationHint = 'Delivery point', cargoClass = fields.size or 'small' })
    return true, { ref = parcel.ref, state = 'searching', canCancel = true }
end)
exports('PhoneServiceStatus', function(cid)
    local parcel = openParcelOf(cid); if not parcel then return true, nil end
    local ok, c = exports['cm-contracts']:GetSourceContract('courier_delivery', parcel.ref)   -- source resource reads its own contract
    local state = ok and exports['cm-phone']:TranslateContractStatus(c.status, c.completionMode) or 'searching'
    return true, { ref = parcel.ref, state = state, canCancel = state == 'searching' or state == 'assigned' }
end)
exports('PhoneServiceCancel', function(cid, service, ref)
    if GetInvokingResource() ~= 'cm-phone' then return false, 'not_allowed' end
    local parcel = openParcelOf(cid); if not parcel or parcel.ref ~= ref then return false, 'not_found' end
    local ok = exports['cm-contracts']:CancelContract('courier_delivery', ref, 'requester_cancel')   -- fails with in_progress if a delivery is being applied
    if not ok then return false, 'cancel_not_allowed' end
    cancelParcelAndRefund(parcel); return true
end)
-- plus the cm-contracts source callbacks (ContractSourceComplete / ContractSourceFallback / ContractSourceCancel) -> mark delivered / auto-deliver (NPC parcel service)
```
The courier **provider** (the player claiming the work) is a normal `cm-contracts` provider; the phone is not involved in it.

## Services in this repository

| Service | Source owner | Status |
|---|---|---|
| `taxi` | `cm-taxi` | **SHARED INTEGRATION REQUIRED — cm-taxi** (catalog ready; shows Unavailable until `cm-taxi` registers) |
| `mechanic` | `cm-mechanic` | **LIVE** once `cm-mechanic` is running (adapter registered on start; enum `diagnostic/repair/body/tires`; see `cm-mechanic/docs/README.md`) |
| `courier` | `cm-courier` | **PROVIDER UNAVAILABLE** (resource empty on disk; Agent 3 must restore it) |

Not marketplace services: Police/EMS (the Emergency app keeps its own owner contracts), residential garbage/recycling routes.

## Tests

`lua tests/services_selftest.lua` (deterministic, no FiveM): registry, listing, request validation, status vocabulary, cancel, push, security.
`node tests/nui-smoke.js` (headless Chrome against `ui/` + `dev-mock.js`): Services icon, list/unavailable/soon states, form, waiting / assigned / active / completed / fallback / cancelled,
confirmations, ESC/back, 720p + 1080p, no overflow, no console errors, user text rendered as text.
