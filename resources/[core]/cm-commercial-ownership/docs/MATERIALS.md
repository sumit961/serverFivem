# Business Material Demand & Settlement (v2.3.0)

The first authoritative **destination** for approved materials. Nothing here enables gathering: no job produces these items yet (see `agent-docs/CM_MATERIAL_ECONOMY.md`).
Materials are never minted by this platform; custody **moves** from a player's `cm-inventory` to a business **material balance**, exactly once.

## Owners

| Concern | Owner |
|---|---|
| Material catalog (what a material is, approved / DEFERRED, reference value) | `cm-materials` (read-only; unchanged) |
| Player custody, the atomic consume | `cm-inventory` (new consume-only **item sink** on the existing atomic engine) |
| Business material balance, material demand, delivery settlement | **this resource** |
| Routing the *work* of delivering (optional) | `cm-contracts` (type `bulk_material_transport`; broker only) |
| Physical collection / transport / delivery gameplay | Agent 3 content (`cm-trucking`, `cm-warehouse`, mining/lumber/construction) |

**Classification: EXTENSION.** Audit: there is no business/society item container. `inventory_items` is generic by `(owner_type, owner_id, slot)` but its external containers
(`vehicle_trunk`, `gang_stash`, `house_weapon_storage`) are slot/weight based, player-withdrawable stores. Business material balance is a server-side commodity counter that only
trusted systems credit/consume, so it is a narrow ledger beside the business balance, not a container. Retail product stock (`cm_stores.stock`, a pooled integer, with the known
oversell flaw) is **not** reused or touched. `cm-materials` stays read-only; `cm-contracts` stays a broker.

## Tables (additive, `server/schema.lua`; `sql/002_business_materials.sql` is the reviewable copy)

| Table | Purpose / keys |
|---|---|
| `cm_business_material_stock` | `PRIMARY (business_type, business_id, material_id)`, `quantity BIGINT UNSIGNED` (the database itself refuses a negative balance) |
| `cm_business_material_events` | append-only journal: `reference`, `delta`, `resulting_quantity`, `event_type` (`credit`,`consume`,`delivery`,`ownership_reset`), `source_resource`, `character_id` (no FiveM source), **`UNIQUE journal_key`** (`credit:<ref>`, `consume:<ref>:<material>`, `delivery:<ref>`) |
| `cm_business_material_demands` | `UNIQUE reference`, `UNIQUE idempotency_key` (scoped caller:business:key), `quantity_required/fulfilled/reserved`, `status ENUM(open,published,partially_fulfilled,fulfilled,cancelled,expired)`, `deadline_epoch`, `publish_requested`, `contract_ref`, `end_reason` |
| `cm_business_material_deliveries` | `UNIQUE reference`, **`UNIQUE inventory_reference`** (`BMD-<reference>`), `demand_id/reference`, `character_id`, `quantity`, `payload` (canonical identity), `status ENUM(prepared,inventory_committed,completed,cancelled,failed)`, `failure_reason`, epochs; index `(status, updated_epoch)` |

## Business material balance

Validation on every mutation: business exists **and is owned**; material passes `cm-materials:IsMaterial` **and** is not `DEFERRED` (plastic is rejected); positive bounded integer
quantity (<= 10,000/operation, <= 100,000 per material per business); durable `reference` (8-40 chars); allowlisted caller (`Config.Materials.Callers`, `GetInvokingResource()`).

* `CreditBusinessMaterial(reference, type, id, materialId, quantity, context)` -> `true, { quantity, replayed }`. Journal key `credit:<ref>`; replay returns the stock without crediting; same reference with a different
  business/material/quantity -> `reference_conflict`. Caller allowlist today: this resource only.
* `ConsumeBusinessMaterial(reference, type, id, requirements, context)` (`requirements = { { material, quantity } ... }`, <= 4 lines, no duplicates) -> all-or-nothing: every balance row is locked in
  sorted order (`FOR UPDATE`), every line checked, then guarded `UPDATE ... WHERE quantity = <read value>` per line plus one journal row per line. Idempotent by reference. `insufficient_material` leaves every
  line untouched. Caller allowlist today: this resource only. **`cm-mechanic` is intentionally not allowlisted** (see Mechanic).
* Reads (any server resource, no client path): `GetBusinessMaterialStock(type, id, materialId)`, `GetBusinessMaterials(type, id)`.
* No withdrawal exists. Ownership change (sale/forfeiture) zeroes the balances (journaled `ownership_reset`), exactly like the forfeited business balance, and cancels open demands that have no delivery in flight.

## Material demand

`CreateMaterialDemand({ businessType, businessId, materialId, quantity, category?, deadlineMinutes?, idempotencyKey?, publish?, characterId? })` -> `true, view`. Allowlisted callers only (no player-facing path, no UI).
Categories: `business_need`, `production_input`, `project_supply`. Limits: 5 open demands per business, quantity <= 5,000, stock + open demand + new quantity <= 100,000. Idempotent by `idempotencyKey`.
States: `open` (unpublished) -> `published` (a broker contract exists) -> `partially_fulfilled` -> `fulfilled`; terminal `cancelled`, `expired`.

**Partial vs full:** a plain (non-contract) demand accepts **partial deliveries**: each has its own reference and a quantity *reserved* against `required - fulfilled - reserved`. A **contract-routed demand is whole-delivery
only** (the broker allows one contract per source reference, so the contract is bound to one complete delivery by one worker).

Cancellation (`CancelMaterialDemand`, `AdminCancelMaterialDemand`, broker admin cancel) is refused while any quantity is reserved (`delivery_in_progress`): once the player debit may have committed, the credit must settle.
Read: `GetMaterialDemand(reference)`, `GetMaterialDemands(type, id)`.

## Player -> business delivery (the settlement saga)

`DeliverBusinessMaterials(reference, demandReference, characterId, quantity, context)`; **callers: `cm-trucking`, `cm-warehouse`** (physical owners; they validate the physical task first, this resource settles it).
`context.contractReference` is required for contract-routed demands. Returns `true, { reference, status = 'completed', quantity, material, replayed }` | `false, reason` | `false, 'unavailable'` (settlement continues via reconciliation).

```
1 prepare   : ONE txn: SELECT demand FOR UPDATE; remaining = required - fulfilled - reserved; reserve qty (guarded UPDATE); INSERT delivery (prepared)       [concurrent deliveries serialize here: no overfill]
2 debit     : cm-inventory ExecuteItemSinkTransaction('BMD-<reference>', characterId, { {material, qty} })   (atomic, UNIQUE-reference ledger, idempotent)
3 committed : delivery prepared -> inventory_committed.  From here the debit is IRREVERSIBLE: there is no refund path, only retry-until-credited.
4 credit    : ONE txn: balance += qty (journal delivery:<ref>), demand fulfilled/reserved progress, delivery -> completed      [credit + demand + status cannot be half-applied]
```
Idempotency: `reference` is unique; replay returns the previous result; a different demand/character/quantity/contract under the same reference -> `reference_conflict`. A `failed`/`cancelled` reference replays as that failure and never debits.

Recovery (`Reconcile` on start and every 30 s; `AdminReconcileMaterialDeliveries`):

| Found | Action |
|---|---|
| `prepared`, inventory ledger `committed` (crash/lost response after the debit) | mark inventory_committed, **credit only** (no second debit) |
| `prepared`, ledger `not_applied`, younger than 120 s | retry the same idempotent debit |
| `prepared`, ledger `not_applied`, older than 120 s (re-checked) | **cancel**, release the reservation (the player never lost anything) |
| `prepared`, ledger `unknown` | leave it (never guess) |
| `inventory_committed` | retry the credit transaction until it settles |
| credit already journaled but status lost | reconstruct `completed` **without** crediting again |
| `completed` | nothing on either side ever replays |

Definite inventory refusals (`insufficient_input`, `invalid_item`, ...) release the reservation and fail the delivery before anything was removed. Only the commit boundary matters: there is **no** "remove item, credit fails, refund item" loop.

## Contracts (`bulk_material_transport`)

`publish = true` publishes the **work** to `cm-contracts` (work-facing facts only: material, quantity, destination type; no balance/price/identity). `cm-contracts/config.lua` lists `bulk_material_transport` for this source.
Source callbacks are the existing `ContractSource*` exports, dispatched by `ctx.contractType`:

* **Complete:** refused (`delivery_not_settled`, retryable) until the worker's delivery for that contract is `completed`; refused if another character delivered. **It never creates stock, items or money.**
* **Fallback (deadline):** the demand simply **expires**; **no stock is created, no worker is paid** (no free material generation). Deferred (`busy`) while a delivery is settling.
* **Cancel / events:** cancel the demand (blocked while settling); events are acknowledged.
* Broker down at publish time: the demand stays `open` + `publish_requested`; reconciliation publishes it exactly once later.

## Exports summary (all server-only; allowlists in `Config.Materials.Callers`)

`GetBusinessMaterialStock`, `GetBusinessMaterials`, `CreditBusinessMaterial`, `ConsumeBusinessMaterial`, `CreateMaterialDemand`, `CancelMaterialDemand`, `GetMaterialDemand`, `GetMaterialDemands`,
`DeliverBusinessMaterials`, `GetMaterialDeliveryStatus`; admin (caller `cm-admin`): `AdminListMaterialDemands`, `AdminInspectMaterialDemand`, `AdminListMaterialDeliveries`, `AdminGetBusinessMaterials`,
`AdminCancelMaterialDemand`, `AdminReconcileMaterialDeliveries`. No new permission ids were added (no UI); a future staff UI should reuse `business.manage_orders` (or add `business.materials.*` then).

## Integration contracts for Agent 3 / future owners

**cm-trucking / cm-warehouse (material delivery provider)** - `AGENT 3 INTEGRATION READY` on the business side (trucking would add `bulk_material_transport` to its supported types and the call below; no business authority change):
1. Register for `bulk_material_transport` with `cm-contracts` (`RegisterProvider`), list/claim/activate as it does for `business_supply`.
2. Gameplay completes server-side (cargo loaded where the source says, truck at the destination). The provider derives `characterId` itself, never from a client.
3. `exports['cm-commercial-ownership']:DeliverBusinessMaterials(<provider-generated durable reference>, <demandReference from the contract's metadata/source>, characterId, quantity, { contractReference = <contract reference> })`.
   The reference must be persisted by the provider before the call (retry with the same value). The player must hold the materials in `cm-inventory` (they come from a real source such as a processing recipe output).
4. On `true`: call `CompleteContract(...)`; pay the worker's **labour** (cash/XP) only when it returns `rewardable == true`. Material value is transferred, not minted; do not also pay market value for the material.
5. On `false, 'unavailable'` keep retrying the same reference; on any other `false` the delivery did not happen.
(The demand reference is not exposed by the broker's provider view; the provider needs it as part of its own cargo record. If that is unwanted, extend the broker `metadata` with `demand` - an Agent 2 follow-up.)

**cm-construction - `AGENT 3 INTEGRATION REQUIRED - cm-construction`** (empty scaffold today; Agent 2 must not write project gameplay). Proposed authoritative contract (project state is Agent 3's):
```lua
exports['cm-construction']:GetProjectMaterialDemand(projectRef)  -- -> { { material, remaining } ... } | false, reason   (server-owned project state)
-- the construction owner settles a worker's delivery with the SAME pattern, destination = project progress:
--   1) reserve remaining on its project row (compare-and-swap),  2) exports['cm-inventory']:ExecuteItemSinkTransaction('PRJ-<ref>', characterId, items)
--   (add 'cm-construction' to cm-inventory Cfg.sinkTrusted),  3) credit/consume project material state, idempotent by <ref>, retry until credited, no refund path.
```
The player-item consume half is generic (`ExecuteItemSinkTransaction`); only the destination credit is owner-specific. cm-materials never holds project state.

**cm-mechanic - DEFERRED.** The material-stock foundation is ready (`ConsumeBusinessMaterial` is atomic, multi-material, idempotent, never negative, `mechanic` is a registered business type), but mechanic prices repairs in cash and has no
parts model, and no approved component material exists (raw ore/scrap must not be consumed just to create a sink). When an approved component exists: allowlist `cm-mechanic` under `Config.Materials.Callers.consume`
and consume with a per-work-order reference.

**cm-warehouse** - empty scaffold; it may later stage pallets and call `DeliverBusinessMaterials` after its own physical validation. It must not own balances.

## Boundaries and economy

No gathering, construction or mechanic behaviour is enabled; no player cash/XP is created; no NPC material sale; no free fallback material (a deadline fallback only expires the demand). Business funds are not touched by this platform.

## Tests

`lua tests/materials_selftest.lua` (production `materials.lua` + real `cm-materials` exports + real `cm-inventory` sink over doubles), `python tests/materials_mysql_smoke.py` (scratch MySQL, statements extracted from the source),
`cm-inventory/tests/craft_selftest.lua` (the sink engine). Live gameplay is untested by instruction.
