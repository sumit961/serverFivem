# Business Supply / Orders platform (v2.2.0)

Businesses order stock through one authoritative platform. **This resource owns demand, wholesale pricing, payment, lifecycle, refunds, stock credit and audit.
A fulfilment provider (future trucking) only moves cargo and reports status; it never touches stock, prices, money or refunds.** No trucks, routes, cargo props,
driver pay or XP live here. Supply orders are not customer invoices: `cm-billing` is not involved.

## Which businesses order supplies

| Type | Class | Stock authority | Order lines |
|---|---|---|---|
| `store` | PHYSICAL (pooled stock) | `cm_stores.stock` | items from the new read-only `cm-store:GetCatalog()` export |
| `clothing` | PHYSICAL (pooled stock) | `cm_clothing_stores.stock` | one line per `clothing_catalog` category (average enabled price) |
| `gasstation` | COMMODITY | `cm_gas_stations.stock` (fuel % units) | one `fuel` line |
| `barber`, `parking` | SERVICE ONLY | n/a | not orderable (no `Config.Supply.Types` entry) |

The business's own table is the only stock total; the adapter credits it with one guarded `UPDATE ... stock + ? <= capacity`. Capacities in `Config.Supply.Types`
must match the owner resources (`cm-store` 5000, `cm-gasstations` 25000, `nv_cloth` 15000).

## Wholesale model (`Config.Supply`)

`unit cost = max(floor, ceil(retail * percent))`; rules merge **type default < category < item** (`fixed` allowed per item). Retail is always resolved server-side
from the price owner; the client sends only `{ id, qty }`.

| Type | percent | floor | Why |
|---|---|---|---|
| store | 0.60 | 1 (consumable 2) | price tiers 0.85 / 1.00 / 1.25 with an 80% owner share leave 8% / 20% / 40% of base retail |
| clothing | 0.60 | 5 | same tiers |
| gasstation | 0.50 | 1 | tiers 6 / 8 / 11 per % give the owner 4.8 / 6.4 / 8.8; 0.50 (= the old flat 4) is the highest percent that never loses at LOW |

Sample margins from the self-test (owner share = 80% of base retail at NORMAL; LOW = `ceil(retail x 0.85) x 0.8`):

| item | retail | wholesale | owner @NORMAL | margin | margin @LOW |
|---|---|---|---|---|---|
| water | 15 | 9 | 12 | 3 | 1 |
| sandwich | 25 | 15 | 20 | 5 | 2 |
| worms (bait) | 5 | 3 | 4 | 1 | 1 |
| basic fishing rod | 50 | 30 | 40 | 10 | 4 |
| pickaxe L1 | 2,500 | 1,500 | 2,000 | 500 | 200 |
| lottery ticket | 10,000 | 6,000 | 8,000 | 2,000 | 800 |
| clothing item | 400 | 240 | 320 | 80 | 32 |

Retail catalogs and business prices were **not** changed. The self-test asserts every real `cm-store` item keeps a non-negative margin at LOW tier.

## Lifecycle (server-authoritative; every transition is a SQL compare-and-swap)

> v2.2.0: `claimed` and `in_transit` are legacy statuses. Provider claims/leases live in `cm-contracts`; see "Fulfilment: the generic broker" below.

```
pending_payment -> awaiting_fulfillment            (business debit succeeded)
pending_payment -> failed                          (debit failed)
awaiting_fulfillment -> claimed | cancelled        (provider claim | business cancel, refunded)
claimed -> awaiting_fulfillment | in_transit | failed
in_transit -> delivering -> delivered              (stock credited once)   | failed (provider / timeout, refunded)
any open state -> cancelled                        (admin, refunded)  | ownership change (no refund, see below)
```

Terminal states never reopen. A delivered order cannot be delivered, cancelled or failed again. The client can only request quote / place / cancel / view.

* **Payment:** charged when placed, from the business balance, through the atomic business debit (ledger key `supply-debit:<ref>`). The order becomes
  `awaiting_fulfillment` only after the debit succeeded.
* **Refunds:** business cancel (only from `awaiting_fulfillment`), provider failure, transit timeout and admin cancel credit the business exactly once through ledger
  key `supply-refund:<ref>`; retries and reconciliation replay the same key. No fee in V1.
* **Quotes:** bound to actor + business + owner epoch, single use, 120 s. Placement re-prices from the authoritative catalog and rejects (`price_changed`) if the total differs.
* **Capacity:** current stock + all open orders + the new order must fit; delivery re-checks and fails closed (`over_capacity`, the order stays `in_transit`). V1 is full-order fulfilment.
* **Idempotency:** optional `idempotencyKey` (scoped to actor and business); a replay returns the same order and debits once.

## Fulfilment: the generic broker (`cm-contracts`) (v2.2.0)

External orders are **published to `cm-contracts`** as `business_supply` contracts; the broker owns provider claims, leases, the player-first window and the
fallback timer. This resource keeps no claim/lease/transit state for them and still owns the order, payment, stock credit and refunds.

```
Place -> awaiting_fulfillment -> CreateContract (work-facing facts only; no prices/balance)        [this resource]
   trucker claims -> active -> CompleteContract                                                   [cm-contracts + cm-trucking]
        -> ContractSourceComplete(ctx): awaiting_fulfillment -> delivering -> delivered, stock +units once [this resource]
        -> cm-trucking rewards the worker (this resource and the broker pay nothing)
   nobody finishes by the deadline (ExternalFallbackMinutes, clamped 20-45) -> broker ContractSourceFallback(ctx)
        -> same exactly-once stock credit (provider 'supplier'), no worker, no reward                [this resource]
```

Source callbacks (caller must be `cm-contracts`; all idempotent; `false, 'source_terminal'` = the order is over): `ContractSourceComplete`, `ContractSourceFallback`,
`ContractSourceCancel` (admin cancel + refund), `ContractSourceEvent`. A contract that does not match the order's `contract_ref` is rejected. A fallback that can never
succeed (over capacity / ownerless) after 8 attempts fails the order and refunds the business once.

* **Cancel:** the business can cancel only while the broker agrees no delivery is being applied; the order is then cancelled and refunded once.
* **Ownership change:** every uncommitted order is cancelled without refund (funds were forfeited) and the broker is told. (`in_transit` no longer occurs.)
* **Publish failure:** if the broker was down at placement, `Reconcile` publishes the order later (idempotent). If the broker is not running at all, an unpublished
  order is supplier-delivered after `BrokerDownFallbackMinutes` (safety net only).
* **Modes:** `external` = broker-managed, player-first. `scheduled` = NPC-only supplier (never published, no player work, so no competing timer). `instant` = dev/test.
* **Deprecated:** `ListAvailableSupplyContracts, ClaimSupplyOrder, ReleaseSupplyOrder, MarkSupplyOrderInTransit, CompleteSupplyOrder, FailSupplyOrder, GetSupplyOrderStatus`
  now return `false, 'deprecated_use_cm-contracts'`. There is one claim system. `Config.Supply.Providers` was removed; providers are allowlisted in `cm-contracts/config.lua`.

## Business-facing exports (actor = server source; need `business.manage_orders`)

`GetSupplyCatalog, QuoteSupplyOrder, PlaceSupplyOrder(actorSrc, type, id, { token | lines, idempotencyKey? }), CancelSupplyOrder, GetSupplyOrders`.
The staff panel **Orders** tab uses the same code through `...:server:request` actions `supplyCatalog | supplyQuote | supplyPlace | supplyCancel | supplyDetail`.
Notifications are HUD-only to the requester and the owner (no phone coupling, no employee spam).

## Admin / recovery (caller must be cm-admin; UI wiring deferred because cm-admin has other agents' changes)

`AdminListSupplyOrders({ stuck? })`, `AdminInspectSupplyOrder(ref)` (with events), `AdminCancelSupplyOrder(ref, reason)` (refunds once), `AdminReconcileSupplyOrders()`,
`AdminDeliverSupplyOrder(ref)` (test fulfilment; only when `cm_environment=development` or `Config.Supply.AllowAdminFulfill`).
`Reconcile` (startup, then every 60 s) settles `pending_payment` by the ledger, `delivering` by the stock journal, releases expired claims, fails timed-out transits,
runs `scheduled` deliveries and retries interrupted refunds.

## Ownership change while orders are pending

Orders belong to the business, but the prepaid funds belong to the owner tenure that ended. Policy (least exploitable): on any owner change **uncommitted orders
(`pending_payment`, `awaiting_fulfillment`, `claimed`) are cancelled with NO refund** (the money left with the forfeited balance; refunding would let an owner launder
a balance past forfeiture). **`in_transit` orders continue** so drivers are not stranded and deliver into the current tenure. The old owner loses all order authority
immediately; the new owner can view and manage the business's orders. If the business is unowned, delivery is rejected (`no_owner`); the transit timeout then fails
the order and the refund is recorded as forfeited (nothing is minted).

## Known limitation (NOT fixed by this task)

`cm-store`, `nv_cloth` and `cm-gasstations` still deduct **one pooled stock unit per item sold regardless of price** and read stock before deducting it
(`GREATEST(0, stock - n)`). The **customer-side oversell race and the "cheap item refills the pool, expensive item sells" flaw still exist.** This platform prices every
unit by item, but until the sale side consumes stock in proportion to value an owner can still fill the pool with the cheapest line. Follow-up for the economy agent
(needs `cm-store` / `nv_cloth` changes): consume `ceil(unitPrice / stockUnitValue)` units per item and use an atomic `UPDATE ... WHERE stock >= n`. The legacy flat-price
"restock" buttons remain until those resources migrate to Orders: `SHARED INTEGRATION REQUIRED`.

## Database

`cm_business_supply_orders` (UNIQUE `reference`, UNIQUE `idempotency_key`, status ENUM above, indexes `(business_type, business_id, status)` and `(status, claim_expires_at)`),
`cm_business_supply_order_lines` (UNIQUE `(order_id, item_id)`; label, retail and unit cost are server-resolved snapshots), `cm_business_supply_events`
(order timeline; UNIQUE `(order_id, journal_key)` makes the stock credit a once-only journal). Applied additively by `server/schema.lua`.
