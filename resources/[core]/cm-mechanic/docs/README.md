# cm-mechanic: mechanic business / service platform (v1.0)

`cm-mechanic` owns **mechanic service requests and work orders**. It is a platform foundation, not a mechanic minigame: it connects
systems that already exist and leaves physical gameplay (towing, lifts, part-install minigames) to later content work.

```
PLAYER -> cm-phone (Services > Mechanic)
       -> cm-mechanic request (source owner)  -> cm-contracts  (publish / claim / lease / expiry)
       -> eligible mechanic employee (cm-commercial-ownership permission) -> work order
       -> diagnose (cm-vehicles condition) -> server-priced quote -> customer approves
       -> cm-billing invoice (destination business:mechanic:<shop>) -> customer pays
       -> paid detected -> service action -> cm-vehicles ServiceVehicle (once) -> contract completes
```

## Who owns what (nothing is duplicated)

| Concern | Owner |
|---|---|
| Request, work order, service catalogue, price formulas, quote, audit timeline | **cm-mechanic** |
| Request frontend (create / status / cancel / push) | cm-phone (`RegisterPhoneService`, no phone core change) |
| Claim, exclusivity, lease, release, expiry trigger | cm-contracts (`mechanic_request`, provider `mechanic`) |
| Business owner, employees, ranks, permissions, **balance** | cm-commercial-ownership (type `mechanic`) |
| Invoice, payment, settlement into the business balance | cm-billing |
| `vehicle_id`, ownership/access, persisted condition, the repair itself | cm-vehicles |
| Modification / paint / wheels / mod persistence | **cm-tuning** (not touched; see Boundaries) |

## Classification

**NEW RESOURCE.** The repository audit found no mechanic owner anywhere: no resource, no business type, no service export consumer.
`cm-phone` (Sources + Catalog entry), `cm-contracts` (`mechanic_request` type) and `cm-billing` (README) already reserved the slot.

## Business model (no second owner table or treasury)

`cm-commercial-ownership` keeps ownership and `business_balance` in each business type's own table. `cm-mechanic` provides that table
(`cm_mechanic_shops`: `shop_id`, `owner_character_id`, `owner_name`, `business_balance`) and the registry entry
`Config.BusinessTypes.mechanic`. Employees, ranks, invites, payroll and the staff panel are the shared foundation (`/businessstaff mechanic main`).

* Shops are a configurable registry (`Config.Shops` in `config.lua`: id, label, optional workshop `location`, `roadside`). Seeded idempotently,
  never overwriting an owner or balance. There is no player purchase flow yet: an admin assigns an owner with the console command
  `cm_mechanic_setowner <shopId> <characterId> [name]` (or the `AdminSetMechanicShopOwner` export from cm-admin).
* **WORKSHOP LOCATION CONFIG REQUIRED**: no mechanic MLO/location exists in the repository. The default shop `main` has no `location`, so
  roadside services work and workshop-only services (`repair_full`) answer `workshop_not_configured` until a `location = { x, y, z, radius }` is set.
* Permissions (cm-commercial-ownership `Config.Permissions`, scoped with `types = { mechanic = true }` so only mechanic businesses list them):
  `mechanic.accept_requests`, `mechanic.create_quote`, `mechanic.service_vehicle`, `mechanic.complete_work`, `mechanic.manage_services`
  (the last is reserved for a future service-settings section). Default ranks for mechanic businesses: Manager (all), Mechanic (accept/quote/service/complete),
  Trainee (accept only). Authority always comes from `HasBusinessPermission`, never rank names.

## Request and work-order lifecycle

Request (`cm_mechanic_requests`): `open -> assigned -> completed`, or `cancelled` / `expired`. One open request per character (UNIQUE `active_key`).

Work order (`cm_mechanic_work_orders`), one live order per request (UNIQUE `active_key`):

```
assigned -> diagnosing -> quoted -> awaiting_payment -> servicing -> completed        (cancelled from any pre-payment state)
                  ^          |            |
                  +----------+------------+   decline / quote expiry / invoice expired or voided (new invoice attempt, new key)
```

Public phone vocabulary (the phone accepts only its fixed states; finer text goes in `detail`):
`searching` Looking for a mechanic, `assigned` Mechanic on the way, `active` Diagnosing / Awaiting your approval / Awaiting payment - open Bills / Service in progress,
`completed`, `cancelled`, `no_provider` No mechanic available. Contract and work-order state names never leave the resource.

### Decision: PAY BEFORE FINAL MUTATION

The vehicle is changed **only after cm-billing reports the invoice paid**, then exactly once. A paid-but-unfinished order can never be left unserved
and an unpaid order can never produce a free repair:

1. approve -> invoice created (idempotency key `mechinv:<work>:<attempt>`); the order waits in `awaiting_payment`.
2. The sweep (5 s while work is open, 15 s idle) reads `GetInvoiceStatus`; `paid` -> `servicing` (journalled once).
3. The mechanic starts the service (server stores `service_started_at`) and finishes it after the service duration; the server rejects early finishes
   and re-validates mechanic/customer/vehicle proximity, routing bucket and vehicle identity.
4. Commit: CAS `commit_state none -> committing`, call `cm-vehicles:ServiceVehicleById(vehicle_id, patch, -1)`, CAS `servicing -> completed/committed`.
   Patches are **absolute target values** (health = 1000, condition snapshot with only the repaired parts cleared), so replaying after a crash writes the
   same state and cannot "repair twice". A failed vehicle call keeps the order `servicing` and retries with backoff (20 s, 40 s ... 10 min, 8 attempts, then an admin alert).
5. If the mechanic never finishes, the **server applies the paid service itself** after `Commit.autoCommitAfterSeconds` (300 s). The customer paid, so the service is owed.
6. After commit the contract is completed by this resource (it is both source and provider) and the request closes.

Payment failure: unpaid / expired / voided invoices return the order to `diagnosing` (new key, no duplicate invoice, no business credit, no repair).
The mechanic can re-quote or abandon; the customer can cancel (a pending invoice is voided; a settling/paid one cannot be cancelled).

## Service catalogue (V1, `config.lua > Services`)

| Service | Category | Mode | Restores | Base | Min-Max |
|---|---|---|---|---|---|
| `diagnostic` | DIAGNOSTIC | both | nothing (inspection) | 1,500 flat | 1,500 |
| `repair_basic` | BASIC_REPAIR | both | engine, fuel tank | 1,500 + parts | 2,000 - 45,000 |
| `repair_body` | BODY_REPAIR | both | body, windows/doors | 1,000 + parts | 1,500 - 40,000 |
| `tire_service` | TIRE_SERVICE | roadside | tyres | 300 + parts | 500 - 6,000 |
| `repair_full` | BASIC_REPAIR | workshop only | everything | 2,500 + parts | 4,000 - 49,000 |
| `tuning_request` | TUNING | both | cm-tuning modification (priced and applied by cm-tuning) | cm-tuning quote | <= the cm-billing `cm-mechanic` provider limit (2,000,000; larger jobs are refused, never clamped or split) |

Part formulas (only parts that need work are billed; `needed` = at least 30 of 1000 health points missing):

* engine = `1200 + 6.0 x missing + 0.004 x vehicleValue x (missing/1000)`
* tank = `400 + 1.5 x missing + 0.0005 x vehicleValue x (missing/1000)`
* body = `900 + 4.0 x missing + 0.003 x vehicleValue x (missing/1000)`
* windows + damaged doors = 250 each (max 16); burst/rim tyres = 350 each (max 8)
* amount = `serviceBase + sum(parts)`, clamped to the service min/max (repair services stay far below the cm-billing provider limit).

Inputs are all server-resolved: `missing` comes from the authoritative condition (`cm-vehicles:GetSpawnedVehicleCondition`, falling back to the stored row),
`vehicleValue` from `cm_vehicle_catalog.price` (fallback 300,000, cap 20,000,000). A genuine stored health of `0` is maximum severity; a **missing** value is
`unknown` and is never quoted as full health or silently repaired (`condition_unknown`).

Worked example (Sultan, 400,000, engine 40%, body 70%): `repair_basic` = 1,500 + (1,200 + 3,600 + 960) = **7,260**; `repair_body` = 1,000 + 900 + 1,200 + 360 = **3,460**.

### Economy rationale (`agent-docs/CM_ECONOMY_STANDARD.md`)

An active-work hour is about 87.5k; consumable/small services sit at 0.01-0.2 h (1k-18k) and the worst legitimate repair of a 2.2M performance car
(engine 0%, ~20k) is about 0.23 h. The price scales with vehicle value and severity, so a cheap car is never charged supercar prices and a scratch costs less than a rebuild.
Everything is revenue to the player-owned business (no minted money). Hourly values are **MEASURE** items for a live economy pass.

**Resolved pricing overlap:** cm-tuning's self-service engine rebuild (`800 + 4/point`, which undercut this formula and bypassed the business) is closed; mechanic repair is the only engine/body/tank restoration price authority.

## Phone integration

`RegisterPhoneService('mechanic', { create, status, cancel, availability })` on start and on `cm-phone:server:serviceRegistryReady`. The Coming Soon flag was removed
from the phone catalogue and the request enum is now `diagnostic | repair | body | tires | tuning` (`tuning` maps to `tuning_request`, see below) (the old `tow`/`refuel` options had no owner). Fields: category + a short note.
The vehicle is **not** chosen in the phone: it is bound at diagnosis from the physical vehicle next to the mechanic. Availability is `false` when no mechanic business has an owner.
`PushPhoneServiceStatus` is called on every transition.

## Contract integration

* Source and provider: `Sources['cm-mechanic']`, `Providers['cm-mechanic']` (provider `mechanic`, lease 600 s, grace disconnect policy 120 s).
* Published metadata is minimal: rounded area (100 m grid), hint, safe description. Exact location is given only to the mechanic who claimed it. No money, invoice, vehicle row or identity.
* Source callbacks: `ContractSourceComplete` (requires a committed work order, idempotent), `ContractSourceFallback`, `ContractSourceCancel`, `ContractSourceEvent`.
* **Fallback policy:** no mechanic within the window (default 8 min, broker clamps 5-15) -> the request **expires**, the callback answers `source_terminal`, the contract ends `cancelled`,
  the phone shows "No mechanic available". It never repairs the vehicle and nobody is rewarded. A worker holding the job at the deadline gets the broker's single deferral;
  after that, live work answers `work_in_progress` (retried with backoff) while an unstarted/stale order is cancelled.
* No job payout is minted: `rewardable` from `CompleteContract` is intentionally ignored. Employee commission is **deferred**: revenue stays in the business balance and staff are paid
  through the existing bounded manual payroll. Mechanic payroll/commission can be added once the business platform has an exactly-once periodic settlement.

## Billing integration

`Config.Providers['cm-mechanic']` in cm-billing: `business` issuer, `business` destination only (id must start `mechanic:`), max 2,000,000 (`maxAmount`, provider-specific), `allowOffline = false`, metadata namespace `mechanic.`, voidable, refundable.
Invoice: recipient = customer character, issuer = the business label, `issuerEntityId = mechanic:<shop>`, destination `business:mechanic:<shop>`, key per work order and attempt,
expiry 600 s. The business credit is cm-billing's atomic, idempotent `CreditBusinessAtomic`; cm-mechanic never moves money.

## Vehicle integration

* `vehicle_id` is the persistent identity. The client sends only a net-id **handle**; the server maps it with `Entity(e).state.cmVehicleId`, confirms it against `GetSpawnedVehicleInfo`,
  and stores `vehicle_id` plus a short label. Plates and net ids are never identities.
* Eligibility: the vehicle exists, belongs to the order (a different vehicle is `wrong_vehicle`), is not an admin/organization/fleet vehicle, is not stored, shares a routing bucket with
  mechanic and customer, the mechanic is within 8 m and the customer within 30 m (roadside), and the customer passes `CanUseVehicle(src, vehicle_id, 'vehicle.info')`
  (owner, key holder or family key). `access = 'owner'` services use `PlayerOwnsVehicle`.
* Ownership/access is re-checked at quote and at approval; a changed owner snapshot invalidates the quote. After payment the paid service still applies to that `vehicle_id` (audit event); cm-billing has no refund API.
* Repair goes through `cm-vehicles:ServiceVehicleById(vehicle_id, patch, -1)` (keyed by the persistent id, not the plate). `cm-mechanic` is allowlisted in cm-vehicles
  `Config.Service.TrustedCallers` for `engineHealth/bodyHealth/tankHealth/conditionState/clearVisualDamage` only; anything else is `forbidden_caller` / `field_not_permitted`.
  Contract: `cm-vehicles/docs/API_SERVICE.md`. `cm_owned_vehicles` is never written directly.

## Tuning service (`tuning_request`, authority `cm-tuning`)

Same work order, approval, invoice and payment machinery as repairs; the quote and the modification belong to cm-tuning.

```
phone "tuning" -> request -> claim -> scan (vehicle_id bound) -> StartTuning(shop) -> cm-tuning authorization + tuning UI for the mechanic
  -> the mechanic's selection is a PROPOSAL priced by cm-tuning -> local event -> OnTuningQuoted binds it to the order (quoted)
  -> customer approves (cm-tuning re-prices against the current vehicle) -> ONE cm-billing invoice to the mechanic business
  -> paid (cm-billing; cm-tuning verifies it too) -> service step -> commit: cm-tuning ExecuteMechanicTuning (idempotent) -> completed
```
* `patch_json` holds `{ tuning = <authorization reference> }`; the commit calls cm-tuning instead of `ServiceVehicleById`. A failed call keeps the order `servicing` and retries with backoff (forward-only; no refund API).
* Pre-payment cancellation/decline/expiry/void releases the cm-tuning authorization; after payment it is never cancelled.
* The invoice limit is **cm-billing's provider policy** (read through `GetProviderPolicy`, never configured or hard-coded here). One authorization -> one quote -> one invoice -> one payment up to that limit (2,000,000: covers the full performance bundle, 242,000, and a single wheel at the 200-index ceiling, 1,105,500). A proposal above it is refused with an explicit message (`amount_over_limit`); nothing is clamped, repriced or auto-split. A billing `amount_exceeds_provider_limit` at invoice time maps to the same message.
* Mechanic permission is checked against cm-commercial-ownership (`quote` + `service`), the customer must own the vehicle (`access = owner`), and the vehicle is identified by `vehicle_id`.
* Tests: the TUNING section of `tests/selftest.lua` runs the real mechanic core against cm-tuning's real server code (`cm-tuning/tests/harness.lua`).

## Boundaries and shared integrations

* **cm-tuning:** repair/rebuild is mechanic-owned (cm-tuning's duplicate engine rebuild is closed). Tuning/modification is cm-tuning's and is now offered as `tuning_request`:
  see "Tuning service" below and `cm-tuning/docs/SERVICE_INTEGRATION.md`.
* **cm-vehicles:** `ServiceVehicle*` is caller-allowlisted and documented in `cm-vehicles/docs/API_SERVICE.md`.
* Parts economy (future): Mining/Recycling (materials) -> Crafting (mechanic parts) -> Warehouse/Trucking (supply) -> the mechanic business consumes them.
  Service definitions already allow a future `requiredParts` list; **no parts, items or restock system exist here**. Mechanic stock must use the cm-commercial-ownership supply/orders platform, not a mechanic-specific restock.
* Not built (by design): towing/impound, roadside recovery, lift/part minigames, loans, custom plates, a second employee dashboard, a second contract broker.

## Security summary

* Server resolves identity (character id from the session), business (membership + permission), vehicle (entity state + registry), service, price, invoice destination and completion.
  The client never supplies a worker id, business, vehicle id, amount, severity or completion.
* The order a mechanic acts on is looked up from **their own character id** (`woActiveByMechanic`); the customer's response is looked up from **their own** character id. There is no way to name a foreign order.
* Every mutating entry is rate-limited (`Config.RateLimits`) and serialised per order/request (`_lock`) on top of SQL compare-and-swap guards.
* `phone`, `cm-contracts` and `cm-admin` entry points check `GetInvokingResource()`; the mechanic/customer entry points are ox_lib callbacks (no net events exist that mutate).

## Idempotency and recovery

* One phone request = one request row (UNIQUE `active_key`) = one contract (broker UNIQUE source reference). Retries return the existing request.
* One invoice per work-order attempt (billing idempotency key); a crash between approval and storing the invoice reference is repaired by the sweep re-calling `CreateInvoice` with the same key.
* Commit is guarded by `commit_state` CAS plus once-only journal keys (`<work>:committed`); completion callbacks and contract completion replay safely.
* On start and every sweep: payments are detected, interrupted commits replayed, stale orders released, unpublished requests published or expired, orders whose mechanic/customer vanished are cancelled after the offline grace
  (mechanic 180 s, customer 180 s) unless the invoice is already paid.
* Admin/console: `cm_mechanic_inspect <ref>`, `cm_mechanic_cancel <ref>` (refuses a paid order), `cm_mechanic_reconcile [ref]` (commits a stuck paid order once), `cm_mechanic_setowner <shop> <cid>`;
  exports `AdminInspectMechanic`, `AdminCancelMechanic`, `AdminReconcileMechanic`, `AdminSetMechanicShopOwner` (caller must be `cm-admin`). cm-admin UI wiring is deferred (SHARED INTEGRATION REQUIRED).

## Public contracts

Exports (server): `PhoneServiceCreate/Status/Cancel/Availability` (cm-phone only), `ContractSource{Complete,Fallback,Cancel,Event}`, `ContractEligible`, `ContractEvent` (cm-contracts only),
`AdminInspectMechanic`, `AdminCancelMechanic`, `AdminReconcileMechanic`, `AdminSetMechanicShopOwner` (cm-admin only). Client exports: `OpenMechanicPanel`, `CloseMechanicPanel`.
ox_lib callbacks: `cm-mechanic:state | claim | diagnose | quote | abandon | startService | finishService | respondQuote | pendingQuote`.
Client events (server -> client only): `cm-mechanic:client:quote`, `cm-mechanic:client:update`. There are **no** client -> server net events.
Command: `/mechanic` (opens the panel for mechanics). Permissions: the five `mechanic.*` ids above.
Database: `cm_mechanic_shops`, `cm_mechanic_requests`, `cm_mechanic_work_orders`, `cm_mechanic_events` (additive, `CREATE TABLE IF NOT EXISTS`, applied at start; no existing table is altered).

## Tests

* `lua tests/selftest.lua` (deterministic, no FiveM/DB): runs the **real** cm-mechanic core + pricing + config, the **real** cm-phone services core and phone config, and the **real** cm-contracts broker
  core and config. Fake stores mirror the SQL CAS/UNIQUE semantics. cm-billing, cm-commercial-ownership and cm-vehicles are **labelled test doubles** (their real implementations need MySQL/FiveM).
* `node tests/nui-smoke.js`: headless Chrome against `ui/` + `dev-mock.js` (open, board, claim, scan, quote, abandon confirmation, ESC semantics, XSS-safe text, no backdrop-filter / CDN, viewport fit).
* Not run by design (user instruction): any FiveM runtime / gameplay session. The real SQL store has not been executed against MySQL yet.

## Manual gameplay checks still required

1. Own a shop (`cm_mechanic_setowner main <cid>`), hire a second character via `/businessstaff mechanic main`. 2. Customer: phone > Services > Mechanic > Repair. 3. Mechanic: `/mechanic`, Accept, drive to the customer,
Scan vehicle, Quote. 4. Customer approves in the dialog, pays in `/bills`. 5. Mechanic Start service, wait, vehicle is repaired and the business balance rises once. 6. Let a request expire with no mechanic and confirm nothing is repaired.
7. Disconnect each party at each stage and confirm no stuck order. 8. Check the repaired condition survives a recall/relog (client applies the trusted condition).
