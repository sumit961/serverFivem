# Vehicle legal state: registration and insurance (v1)

`cm-vehicles` is the single authority. State lives on `cm_owned_vehicles`; `cm-law` only reads it and calls the
trusted mutation exports after its own officer / duty / permission checks.

## Identity

| Concept | Field | Role |
|---|---|---|
| Persistent identity | `cm_owned_vehicles.id` (`vehicle_id`) | authoritative key for every operation |
| Internal plate | `plate` | framework lookup key (keys, trunk, spawn); unchanged by registration |
| Public registration | `license_number` (`REG-123456`) | public legal number, UNIQUE index, rendered as the visible plate; never an identity |

## Columns (additive, nullable)

`registration_expires_at BIGINT` (epoch seconds; NULL on a numbered registration = legacy permanent),
`registration_revoked_at BIGINT`, `insurance_expires_at BIGINT`, `insurance_owner_id VARCHAR(100)`.
New append-only table `cm_vehicle_legal_events` (vehicle_id, event, actor_character_id, source, registration, amount, details).
Events: `registration_issued|renewed|revoked|reinstated`, `insurance_purchased|renewed|invalidated`,
`charge_refunded`, `refund_queued`, `legal_state_removed`. Each is mirrored into `cm_vehicle_audit` as `legal_<event>`.

## Status model

Registration: `UNREGISTERED | ACTIVE | EXPIRED | REVOKED | EXEMPT`. Insurance: `NONE | ACTIVE | EXPIRED | EXEMPT`.
`EXEMPT` = non-personal ownership (`owner_type` not in `Config.Legal.EligibleOwnerTypes`, i.e. organization fleets).
A policy is valid only while `insurance_owner_id` equals the current owner, so a transfer through any path invalidates it.

## Pricing (`shared/config.lua` -> `Config.Legal`)

`value = max(MinimumValuation, state_value | catalog price)`;
`registration = clamp(baseFee + value * valueRate, baseFee, maxFee)`;
`insurance = clamp(value * rate, minimum, maximum)`. Prices are always computed server-side.

## Server exports

| Export | Caller | Notes |
|---|---|---|
| `GetVehicleLegalStatus(vehicleId, {includeOwner})` | any | owner fields only for `TrustedOwnerLookupResources` |
| `GetVehicleLegalStatusByRegistration(number, {includeOwner})` | any | same |
| `IssueVehicleLicense(plate)` | `TrustedLawResources` | free officer issue; legacy signature kept `(ok, message, number)` |
| `RevokeVehicleRegistration(vehicleId, reason, actorCid)` | `TrustedLawResources` | returns `(ok, err)` |
| `ReinstateVehicleRegistration(vehicleId, reason, actorCid)` | `TrustedLawResources` | |
| `OnVehicleOwnershipChanged(vehicleId, reason)` | `TrustedOwnershipResources` | invalidates insurance, keeps registration |
| `QuoteVehicleLegalServices(src, vehicleId)` | `TrustedServiceResources` | owner only |
| `GetPlayerVehicleLegalOverview(src)` | `TrustedServiceResources` | owned eligible vehicles + quotes |
| `PurchaseVehicleLegalService(src, vehicleId, 'registration'\|'insurance', {requestId, expectedPrice})` | `TrustedServiceResources` | |

Untrusted resources are rejected and logged. Calls from `cm-vehicles` itself are always allowed.

## Client contract (for a future registry UI host; no UI ships here)

`cm-vehicles:legal:requestOverview` -> `cm-vehicles:legal:overview` (result table).
`cm-vehicles:legal:requestPurchase(vehicleId, service, requestId, expectedPrice)` -> `cm-vehicles:legal:purchaseResult`.
Source is the authenticated event source; ownership, price and state are always recomputed on the server. `expectedPrice`
is only a confirmation check (`price_changed` is returned if it differs from the server quote).

## Money / concurrency flow

quote -> validate owner/state -> per-vehicle lock -> re-read row under lock -> debit once -> single guarded UPDATE
(pins owner, refuses a pending state sale) -> event -> release lock. A failed UPDATE refunds; a failed refund is journaled
in `cm_vehicle_pending_payouts` (paid by the existing payout processor). `requestId` makes retries replay-safe.
Registration number + expiry are written by one UPDATE, so a half-registered row cannot exist.

## Insurance and recovery

An active policy halves `Config.Rules.ParkingInsuranceFee` (the destroyed-vehicle recovery fee in `spawn.lua`).
It never repairs for free, never restores damage, and has no claims system in v1.

## Tests

`lua tests/legal_selftest.lua` (from the resource folder): deterministic, no FiveM or database.
