# cm-contracts: generic contract broker (v1.0)

One reusable broker for the **player-first, auto-fallback** model:

```
SOURCE creates a request  ->  BROKER publishes it  ->  eligible workers see it  ->  one worker claims it
  -> PROVIDER job runs the gameplay  ->  SOURCE applies the service (completion)  ->  PROVIDER pays its worker
nobody finishes before the deadline  ->  BROKER says "deadline expired"  ->  SOURCE completes it itself  ->  NO worker is paid
```

The broker creates **no money, no items, no stock and no XP**, never writes another resource's tables, and exposes
**no client events** (workers act through their job resource; there is nothing for a hostile client to call).

## Who owns what

| Owner | Owns |
|---|---|
| **cm-contracts** | publication, availability, claim, exclusivity, lease, release, timeout, state transitions, fallback *trigger*, audit, crash recovery |
| **Source** (e.g. `cm-commercial-ownership`) | the request/order, payment, stock/data, final service application, the fallback *implementation* |
| **Provider** (e.g. `cm-trucking`) | gameplay, vehicle, route, cargo, eligibility rules, XP, reward via `cm-payday` |
| `cm-hub` | job discovery. `cm-payday` | pay. `cm-phone` | communication frontend (future). None of them hold contract state. |

Character ID (`claimed_character_id`) is the only persisted worker identity. No server source/ID is stored.

## States

```
available -> claimed -> active -> completing -> completed (mode=player)
claimed|active -> available            release / lease expiry / provider failure / worker gone
available|claimed|active -> fallback -> completed (mode=fallback)      deadline; the SOURCE applies it
available|claimed|active -> cancelled                                    source cancel / admin
fallback|completing -> cancelled                                         source reports `source_terminal`
```

Every transition is one guarded SQL `UPDATE ... WHERE status IN (...)` (compare-and-swap). Terminal states never reopen.
`cm_contract_events` is an append-only timeline; a `terminal` journal key is unique per contract, so a terminal event is written once.

## Database (additive, idempotent)

`cm_contracts`: `reference` UNIQUE, **UNIQUE(source_resource, source_reference, contract_type)** (one contract per source request),
`status`, `claimed_character_id`, `claim_expires_at` (lease), `fallback_at`, `fallback_deferrals/attempts/next_at`, `completion_mode`
(`player`|`fallback`), safe display fields + `metadata` JSON (<= 2 KB). Times are epoch seconds.
`cm_contract_events`: contract timeline (`created, claimed, released, lease_expired, active, active_expired, completing,
completed_player, fallback_started, fallback_deferred, fallback_retry, completed_fallback, failed, cancelled, source_terminal, recovered, grace_started`).

## Configuration (`config.lua`)

* `Sources[resource] = { types, completeExport, fallbackExport, cancelExport, eventExport }`: the trusted-source allowlist.
* `Providers[resource] = { providerTypes }`: the trusted-provider allowlist (resource-name based, `GetInvokingResource()`).
* `Types[type] = { providerType, fallbackMinutes (+Min/Max), leaseSeconds, activeTimeoutMinutes, onActiveExpire, maxClaimsPerCharacter, maxFailures, deferFallbackWhileWorked, deferSeconds, maxDeferrals }`.
  Shipped: `business_supply, bulk_material_transport, courier_delivery, commercial_waste, recycling_pickup, mechanic_request, construction_work, warehouse_task`.
  **Adding a contract type or job is configuration only.**

| Type | Provider | Player-first window (default, min-max) |
|---|---|---|
| business_supply | trucking | 30 min (20-45) |
| bulk_material_transport | trucking | 60 min (40-120) |
| courier_delivery | courier | 15 min (10-25) |
| commercial_waste / recycling_pickup | garbage / recycling | 30 min (20-60) |
| mechanic_request | mechanic | 8 min (5-15) |
| construction_work / warehouse_task | construction / warehouse | 60 (30-180) / 30 (15-90) |

A source may pass `fallbackAfterSeconds`; the broker clamps it to the type's window. A worker who is claimed/active at the
deadline gets `deferSeconds` (10 min) up to `maxDeferrals` times before fallback fires, so players are not stripped of a job at the boundary.

## Source contract (what a source must do)

Call (server exports, caller resolved by `GetInvokingResource()`):

* `CreateContract(data)` -> `true, { reference, status, existing }` | `false, reason`. `data`: `contractType, sourceReference` (required),
  `title, description, pickupHint, destinationHint, cargoClass, urgency (low|normal|high), region, fallbackAfterSeconds, metadata`.
  Idempotent: a repeat returns the existing contract (or its terminal state). Do **not** copy prices/balances/refund state into it.
* `CancelContract(contractType, sourceReference, reason)`: the source ended the request. Fails with `in_progress` if a completion is being applied.
* `GetSourceContract(contractType, sourceReference)`: status for source-side reconciliation.

Implement (the broker calls them; each must check `GetInvokingResource() == 'cm-contracts'` and be **idempotent**):

* `completeExport(ctx)` player completion; `ctx = { reference, sourceReference, contractType, workerCharacterId, mode='player', payload }`.
* `fallbackExport(ctx)` deadline fallback; `ctx.attempt` counts retries.
* `cancelExport(ctx)` admin cancel (the source decides whether it permits it and refunds).
* `eventExport(ctx)` optional `claimed | active | released` notices.

Return `true[, { replayed = true }]` on success, `false, 'source_terminal'` when the request is over (the broker stops), or any other
reason to be retried (completion -> the worker may retry; fallback -> exponential backoff 60 s ... 30 min, never every tick).
Reference implementation: `cm-commercial-ownership` (`ContractSource*`).

## Provider contract (what a job resource must do)

```lua
-- once on start AND on 'cm-contracts:server:providerRegistryReady' (registration lives in memory)
exports['cm-contracts']:RegisterProvider('trucking', {
    types = { 'business_supply', 'bulk_material_transport' },
    eligibilityExport = 'ContractEligible',   -- (characterId, view) -> true | false, reason   (job access, level, licence, session)
    eventExport = 'ContractEvent',            -- optional (reference, characterId, event, reason): lease_expired|fallback|cancelled|released
    disconnectPolicy = 'grace',               -- 'grace' (graceSeconds, default 120) | 'release'
})
exports['cm-contracts']:ListAvailableContracts('trucking', { contractType, cargoClass, region, urgency }, characterId)
exports['cm-contracts']:ClaimContract(reference, characterId, { providerRef })      -- one winner; lease starts
exports['cm-contracts']:MarkContractActive(reference, characterId)                   -- real gameplay began (no heartbeats)
exports['cm-contracts']:CompleteContract(reference, characterId, { payload })        -- -> true, { mode='player', rewardable }
exports['cm-contracts']:ReleaseContract(reference, characterId, reason)              -- abandon: back to the board, no reward
exports['cm-contracts']:FailContract(reference, characterId, reason)                 -- vehicle lost etc.: back to the board / fallback
exports['cm-contracts']:ReportWorkerDisconnected('trucking', characterId)            -- call from playerDropped
exports['cm-contracts']:GetWorkerContracts('trucking', characterId)                  -- resume after relog
```

All calls return `true, data` | `false, reason`. The provider derives `characterId` server-side from its own session
(never from a client). **Pay and XP only when `CompleteContract` returns `true` with `rewardable == true`**: it is true exactly once;
a replay returns `rewardable = false`, and a contract completed by fallback returns `false, 'completed_by_fallback'`.
The provider owns cleanup of vehicles/cargo/routes: the broker never deletes job entities.

## Admin / recovery (cm-admin callers or server console)

Exports (caller must be in `Config.AdminCallers`): `AdminInspectContract, AdminListContracts, AdminReleaseContract, AdminCancelContract (source must permit), AdminReconcileContracts`.
Console: `cm_contracts_inspect <ref>`, `cm_contracts_list [status] [providerType]`, `cm_contracts_release <ref>`, `cm_contracts_cancel <ref>`, `cm_contracts_reconcile`.

## Restart recovery

On start the broker sweeps: expired claims release; elapsed fallbacks run (once); a `completing` contract left by a crash is replayed against
the idempotent source; completed contracts stay terminal. Providers must re-register (the broker fires `cm-contracts:server:providerRegistryReady`).

## Future sources and providers

| Future work | Source (owns request + payment) | contract type | Provider |
|---|---|---|---|
| parcel request | courier/phone request owner | `courier_delivery` | cm-courier (fallback: NPC parcel service) |
| commercial garbage pickup | property/business | `commercial_waste` | cm-garbage (fallback: city sanitation) |
| industrial salvage pickup | industrial demand source | `recycling_pickup` | cm-recycling |
| bulk materials | `cm-commercial-ownership` material demand (**implemented** as a source; provider integration pending Agent 3; fallback = the demand expires, no stock is created) | `bulk_material_transport` | cm-trucking / mining / lumber |
| construction | project/work order | `construction_work` | construction |
| warehouse | warehouse inbound/outbound | `warehouse_task` | warehouse |
| mechanic | `cm-mechanic` (phone request; billing handles payment) | `mechanic_request` | `cm-mechanic` (same resource, source and provider; **implemented**, fallback = cancel/expire, never an auto-repair) |

A new source needs: one `Sources` entry, the four callbacks, and `CreateContract`. A new job needs: one `Providers` entry and the provider calls above.
