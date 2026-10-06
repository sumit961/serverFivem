# cm-tuning ↔ cm-mechanic ↔ cm-billing ↔ cm-vehicles: authorized mechanic tuning service

Source of truth: `server/service_core.lua` (journal + state machine), `server/service_store.lua` (SQL), `server/service.lua` (exports/session wiring), `server/main.lua`, `shared/config.lua` (`Service`).

## Ownership (unchanged, nothing duplicated)

| Owner | Owns |
|---|---|
| cm-tuning | tuning catalog, compatibility, **price**, the actual modification, the operation journal (`cm_tuning_service_operations`) |
| cm-mechanic | request, work order, business/permission checks, customer approval, **invoice orchestration**, completion/reconciliation around the order |
| cm-billing | invoice, payment state, settlement into the business |
| cm-commercial-ownership | mechanic business, employees, permissions, balance |
| cm-vehicles | vehicle identity (`vehicle_id`), ownership/access, base state |

Repair/restoration is **cm-mechanic's** (cm-tuning's former engine rebuild stays closed; `cm-tuning` is not a trusted `ServiceVehicle` caller). Tuning/modification is **cm-tuning's**.

## Operation catalogue (from source) and who prices/applies it

| Operation (shop) | Class | Price (cm-tuning config) | Persistent effect | Self-service | Mechanic service |
|---|---|---|---|---|---|
| Engine / brakes / transmission / suspension / armor level (`chip`) | PERFORMANCE | `pricePerLevel × (index+1)`: 12,000 / 8,000 / 10,000 / 6,000 / 9,000 | `mods[modType] = index` | direct cash charge | **yes** |
| Turbo (`chip`) | PERFORMANCE | 25,000 | `turbo` | direct cash | **yes** |
| Tyre level (`chip`) | PERFORMANCE | 7,000 × level | `tyreLevel`, `bulletproofTyres` (level ≥ 3) | direct cash | **yes** |
| Spoiler, bumpers, skirts, exhaust, cage, grille, hood, fenders, roof, horn, wheels (`workshop`) | COSMETIC | 1,200 – 6,000 × (index+1) | `mods[modType]` | direct cash | **yes** |
| Respray (primary / secondary), wheel colour, window tint, plate style, xenon, headlight colour, neon, neon colour (`workshop`) | COSMETIC | 2,500 / 2,500 / 1,800 / 1,500 / 900 / 4,000 / 2,200 / 6,000 / free | `primaryColor`, `secondaryColor`, `wheelColor`, `windowTint`, `plateIndex`, `xenon`, `headlightColor`, `neons`, `neonColor` | direct cash | **yes** |
| Livery (`livery`) | COSMETIC | 2,500 × (index+1) | `mods['48']` / `livery` | direct cash | **yes** |
| Racing harness (`chip` session) | MODIFICATION | 18,000 | cm-vehicles `InstallRacingHarness` | direct cash | **no** (stays self-service; needs the owner at the wheel) |
| Engine rebuild | REPAIR | (closed) | — | **closed** | mechanic repair services |

Self-service tuning is unchanged: validation, tuning-owned pricing, **direct cash charge** (`charge()`), refund on failed save. It remains non-journalled (a crash between charge and save is the pre-existing limitation of that path; it is out of scope here).

## Lifecycle (one authorization = one quote = one invoice = one payment = one modification)

```
created --Quote--> quoted --BindInvoice--> invoiced --MarkPaid--> paid --Execute--> applying --> committed
   |__________cancel / expire___________|      \--ReleaseInvoice (voided/expired, never paid)--> cancelled
```
* Only `cm-mechanic` may call the exports (`Config.Service.Trusted`, `GetInvokingResource()`); every other resource gets `forbidden`. No client event creates, binds, pays or executes an authorization (the only service net event is the mechanic's **proposal**, which has no charge path).
* The authorization row binds: work order, mechanic CID, customer CID, business type/id, `vehicle_id`, shop, owner snapshot, revision, max amount, request hash. The quote adds amount, the approved **diff**, the base-state hash, the invoice reference. A client replaces none of it.
* **Pre-payment** states expire (`authorizationSeconds` 900, `quoteSeconds` 420 > the mechanic's 300 s approval window) and can be cancelled/released. **After payment** the operation never expires and cannot be cancelled (cm-billing has no generic refund): it is forward-only.
* One live authorization per work order (`active_key`) and one per vehicle (`vehicle_key`, UNIQUE): two mechanic tuning operations on one vehicle serialize deterministically; a changed request for the same order supersedes the unpaid one.

## Exports (server only, trusted caller `cm-mechanic`)

| Export | Returns |
|---|---|
| `CreateMechanicTuningAuthorization(ctx)` ctx = `{ workOrder, mechanicCid, customerCid, businessType, businessId, vehicleId, shop, maxAmount? }` | `true, { reference, shop, expiresAt }` / `false, reason` (`unsupported_operation`, `vehicle_not_found`, `vehicle_busy`, `authorization_active`, `invalid_request`) |
| `OpenMechanicTuningSession(ref, mechanicSrc, netId)` | opens the existing tuning UI for the mechanic. Server-validated: mechanic character, `vehicle_id` from entity state (not the net handle), bucket, distance, vehicle lock. |
| `GetMechanicTuningQuote(ref)` | the bound quote (work order, parties, vehicle, amount, description, revision) |
| `ValidateMechanicTuningQuote(ref)` | re-prices against the **current** vehicle: `vehicle_changed`, `ownership_changed`, `quote_changed` (price rose), `expired` |
| `BindMechanicTuningInvoice(ref, invoiceRef)` / `ReleaseMechanicTuningInvoice(ref)` | one invoice per authorization; release only before payment |
| `MarkMechanicTuningPaid(ref, invoiceRef)` | cm-tuning asks **cm-billing** (`GetInvoiceStatus`) itself; only `paid` for the bound invoice moves it. `billing_unavailable` is transient. |
| `ExecuteMechanicTuning(ref)` | applies once; replay returns `replayed`; `busy` / `vehicle_unavailable` / `conflict_retry` are transient (retry) |
| `GetMechanicTuningStatus(ref)`, `CancelMechanicTuning(ref, reason)` | status; cancel only before an invoice exists |

Local (non-network) event `cm-tuning:service:quoted (ref)`: cm-tuning → cm-mechanic nudge after a proposal was priced. cm-mechanic pulls the quote through the trusted export and verifies every binding, so a forged trigger binds nothing.

## Quote and price ownership

cm-tuning computes the price with the same calculator as self-service (`calculatePurchase`: server config, server-side current mods, level/range/palette validation). The mechanic UI sends only the selection and the vehicle's option caps (as the self-service UI does; the server bounds them by `Config`). Client price fields are ignored. The stored **diff** (absolute field values) is the quote; later config changes cannot change a quote that was approved and invoiced.

**Invoice limit.** cm-billing owns a provider-specific creation limit for `cm-mechanic` (now **2,000,000**; cm-commercial-ownership keeps 50,000) and cm-mechanic passes it as `ctx.maxAmount`; it is never duplicated here (the 50,000 `Service.maxAmount` in this config is only a conservative default for a caller that passes none). cm-tuning still owns every price. Largest legitimate quotes under this config: performance bundle 242,000 (engine 48,000 + brakes 32,000 + transmission 40,000 + suspension 24,000 + armor 45,000 + tyres 28,000 + turbo 25,000), livery at the 200-index ceiling 502,500, one wheel at the 200-index ceiling 1,105,500. A bundle above the limit (e.g. wheels + two bumpers at the ceiling, 2,713,500; the theoretical all-slots-at-ceiling workshop bundle is ~8.7M) is **refused** with `amount_over_limit`; nothing is clamped, repriced or split.

## Payment (exactly one path)

customer → cm-billing → `business:mechanic:<shop>` (the invoice cm-mechanic already issues for repairs; destination `mechanic:<shop>`). cm-tuning never calls `RemoveMoney`/`AddMoney` in this path; self-service direct charging is separate and untouched. There is no commission and no parts consumption.

## Apply, idempotency and recovery (forward-only)

* The journal stores the approved change as a **diff** (`set` fields + `mods` slots). `Execute` re-reads the current state, merges the diff (absolute values → replays never stack and never overwrite unrelated later work), and writes with a compare-and-swap (`UPDATE cm_owned_vehicles SET mods = ? WHERE id = ? AND mods <=> ?`), retried against the fresh state.
* "Target already installed" (write landed, journal did not) is recognised and reconciled to `committed` without a second write. A committed row replays.
* A player tuning session on the vehicle holds the vehicle lock: the paid apply answers `busy` (transient) and succeeds when the session ends, so self-service and service tuning serialize and never lose modifications.
* After payment nothing cancels it: mechanic/customer disconnect, cm-mechanic or cm-tuning restart, cm-billing outage, a temporarily missing vehicle, or an ownership change all recover forward (cm-mechanic's reconcile/auto-commit keeps retrying `Execute` with backoff; the order only completes when cm-tuning reports committed).
* Before payment, a changed vehicle/ownership/price invalidates the quote (the order returns to diagnosing; the mechanic requotes).

## Mechanic phone service

`tuning` is a request category (phone creates only a mechanic request: no price, option or mod data). After the mechanic claims and scans the vehicle the work panel offers **PERFORMANCE / BODY & PAINT / LIVERY**; the server authorizes the session and the existing tuning UI opens for the mechanic. The mechanic's "purchase" is a **proposal** (server-priced) the customer approves; the customer pays the invoice from Bills; the service applies after payment.
UI limits (manual verification pending): the tuning UI keeps its self-service wording ("purchase", balances), and preview on a vehicle the mechanic does not own relies on the engine applying cosmetic mods locally.
