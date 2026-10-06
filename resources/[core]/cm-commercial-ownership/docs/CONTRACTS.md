# cm-commercial-ownership contracts

Two layers live in this resource:

1. **Ownership engine** (unchanged): `Register / GetRow / GetPriceMultiplier / BuildDetailsPayload / Buy / Manage / PayTax / Withdraw`,
   used by `cm-characters` (barber) and `nv_cloth` (clothing).
2. **Business employment foundation** (new, v2.0.0): employees, ranks, permissions, invites, activity log, atomic business balance,
   bounded manual payroll, business invoices, shared staff panel. It *attaches to* existing ownership and never copies it.

3. **Supply / orders platform** (v2.1.0): see [SUPPLY.md](SUPPLY.md) (wholesale model, order lifecycle, trucking provider contract, admin recovery).

## Identity model

A business is `businessType + businessId` (strings), e.g. `store:3`, `gasstation:7`, `clothing:davis`, `barber:1`, `parking:<id>`.
The registry is `Config.BusinessTypes` (table + id/owner/balance column per type). **Ownership and `business_balance` stay in each
business's own table**: the foundation reads/updates those columns, so there is no second owner record and no second treasury.
Everything is keyed by **character id**; FiveM sources are never persisted. A character may work for several businesses.

`mechanic:<shopId>` is registered too (table `cm_mechanic_shops`, created by `cm-mechanic`; owner assigned by an admin for now). It adds mechanic-scoped permissions
(`mechanic.accept_requests, create_quote, service_vehicle, complete_work, manage_services`, `types = { mechanic = true }`, enforced by `cm-mechanic` through `HasBusinessPermission`)
and per-type default ranks (`Config.TypeDefaultRanks.mechanic`: Manager / Mechanic / Trainee).

Not registered: ATMs (`bank_atm_locations` has no `business_balance`; add a type when it gets one).
`cm-store` and `cm-gasstations` keep their own purchase/tax/stock logic untouched; they are resolved through the registry like any other type.

## Server exports (read)

| Export | Returns |
|---|---|
| `GetBusiness(type, id)` | `{ type, id, label, owned, ownerCharacterId, balance, epoch }` or `nil` |
| `GetBusinessOwner(type, id)` | `characterId, ownerName` or `nil` |
| `IsEmployee(type, id, cid)` / `GetEmployee(...)` | bool / `{ characterId, isOwner, rankId, rankName, tier, rankMissing }` |
| `GetEmployeePermissions(type, id, cid)` | list of permission ids (owner: all) |
| `HasBusinessPermission(type, id, cid, permission)` | bool. **Future resources ask this instead of building employee tables.** Unknown permission / unowned business / non-member = `false` |
| `GetEmployees(type, id)`, `GetRanks(type, id)` | arrays |
| `GetPlayerBusinesses(cid)` | `{ { type, id, role = 'owner'|'employee' } }` |
| `GetBusinessBalance(type, id)` | integer or `nil` |

## Server exports (mutations; actor = server source, authority re-checked inside)

`InviteEmployee(actorSrc, targetSrc, type, id, rankId?)`, `RespondToInvite(src, token, accept)`, `RemoveEmployee(actorSrc, type, id, targetCid, reason?)`,
`SetEmployeeRank(actorSrc, type, id, targetCid, rankId)`, `CreateRank / UpdateRank / DeleteRank(actorSrc, type, id, ...)`,
`PayEmployee(actorSrc, type, id, targetCid)`, `CreateBusinessInvoice(actorSrc, recipientSrc, type, id, { amount, label, idempotencyKey? })`,
`OpenStaffPanel(src, type, id)`. All return `true, ...` or `false, reasonCode`.

### Balance contract (server-only, allowlisted callers)

`CreditBusinessAtomic(type, id, amount, reason, { idempotencyKey?, reference?, targetCharacterId?, actorCharacterId? })` and
`DebitBusinessAtomic(...)` return `true, { balance, transactionId, replayed }` or `false, reason`
(`forbidden, invalid_amount, invalid_business, unknown_business, no_owner, insufficient_funds, idempotency_conflict, rejected`).
Callers are allowlisted in `Config.BalanceCallers` (`credit`: cm-billing; `debit`: this resource and cm-billing, the latter only for invoice refunds with idempotency key `cm-billing-rfd-debit:<invoice>:<journal id>`). Each movement is one SQL transaction:
a guarded `UPDATE` of the business's own `business_balance` (owner must exist, no overdraw, cap 2,000,000,000) plus a ledger row in
`cm_business_transactions` whose UNIQUE `idempotency_key` aborts and rolls back a duplicate. `HasBusinessTransaction(key)` lets a credit
caller prove a settlement happened (used by cm-billing crash recovery).

### Admin recovery (caller must be `cm-admin`; cm-admin remains the permission gate)

`AdminInspectBusiness`, `AdminGetActivity`, `AdminRemoveEmployee`, `AdminResetEmployeeRank`, `AdminRepairBusiness` (reseeds missing ranks and
re-homes employees whose rank vanished). **cm-admin UI wiring is deferred** (its tree has other agents' uncommitted work): `SHARED INTEGRATION REQUIRED`.

## Client / NUI

* Client export `OpenStaffPanel(type, id)` (and dev command `/businessstaff <type> <id>`): asks the server, which opens the panel only for
  an owner or an employee with `business.view_employees`. The panel is **bound server-side** to that business; NUI actions never choose
  business, owner, tier, permission list, amount or target identity.
* Events: `cm-commercial-ownership:server:open|close|request|respondInvite` (all re-validated), `...:client:state|candidates|result|invite|close`.
  There is no event that mutates without the server re-checking the actor.
* Business resources can open the panel from their own owner UI with one call; no business should clone the panel.
* **Player G-menu wiring is deferred** (the G-menu is owned by cm-family/playerdata work and the vehicle G-menu is protected). Until then, invites
  come from the panel's **Invite nearby** button (server-computed nearby candidates; strangers show as `Stranger #<characterId>`).

## Permissions

`business.view_employees, invite, manage_employees, manage_ranks, manage_permissions, view_activity, view_finance, pay_employees,
manage_payroll, create_invoice` are enforced here. `deposit, withdraw, manage_stock, manage_prices, manage_orders` are **future-safe names**
(consumer resources may check them with `HasBusinessPermission`; existing owner UIs are not migrated in this release).
The owner is virtual (tier `Config.OwnerTier` = 100, every permission) and cannot be invited, removed, re-ranked, paid or resign through staff UI.

## Ranks and hierarchy

Defaults (seeded only when a business has no ranks): Manager 80, Employee 40 (entry), Trainee 10. The database is authoritative afterwards; restarts
never overwrite or re-seed. Rules: a non-owner can only manage targets and create/edit/assign ranks with a **tier strictly below their own**, can
only grant permissions they hold, cannot strip a permission they do not hold, and cannot change their own rank. A rank in use cannot be deleted and
the last rank cannot be deleted. Powers come from permissions, never from rank names.

## Invites

Server-side, in memory, 60 s expiry, one pending per target per business, max 5 per business. Created only for a nearby (5 m, same routing
bucket) loaded character by an actor holding `business.invite`; the entry rank is validated server-side. Acceptance re-validates ownership epoch,
inviter authority, rank, duplicate employment and proximity (2x). Offline staff can still be re-ranked/removed (character id based); *hiring* needs
the target present (admin recovery excepted).

## Ownership transitions (one policy)

Each business has a `cm_business_state` snapshot `(owner_character_id, epoch)`. The foundation detects a changed owner on every access, via the
engine's purchase/forfeiture hooks, and in a 60 s sweep. On **any** owner change (sale, tax forfeiture, admin transfer, re-purchase):
employees are **removed**, custom ranks **reset to defaults**, pending invites **die** (epoch bump), the old owner/staff authority is gone
immediately, payroll stops, and the change is written to `cm_business_activity` (`ownership_changed`, with counts). Credits/debits need an owner.
A business with **no owner** grants nothing. Normal restarts never wipe (first observation only records the snapshot).

## Payroll (BUSINESS FUNDS -> EMPLOYEE)

Manual only. Rank `pay_amount` (0 = none; bounded `Config.Payroll.MinPayment..MaxPayment` = 100..20,000) is the only amount; the client sends only a
target. Requires `business.pay_employees`; target must be a lower-tier employee; self-pay and owner-pay are rejected. Flow: claim the per-employee
cooldown atomically (600 s) -> guarded debit of the business balance (ledger `pending`) -> `AddMoneyToCharacter` (bank, offline-safe, reason
`cm-business-payroll:<txId>`) -> ledger `settled`; if the credit fails the business is refunded (ledger `refunded`) and the cooldown restored.
`ReconcilePayroll` settles/refunds `pending` rows after a crash. **Periodic/automatic payroll is NOT implemented** (no scheduler policy yet); money is
never minted: every payment is a debit of existing business funds.

## Billing

`business` is an enabled `cm-billing` destination (`id = '<type>:<id>'`, credited through `CreditBusinessAtomic` with key `billing-credit:<ref>`).
The only enabled business issuer is this resource's `CreateBusinessInvoice`, which first checks `business.create_invoice`, bounds (max 50,000),
customer presence and distance, then calls cm-billing as the trusted provider `cm-commercial-ownership`.

## Database (additive, idempotent; `sql/001_business_foundation.sql`, applied by `server/schema.lua`)

`cm_business_state`, `cm_business_ranks` (UNIQUE name per business), `cm_business_employees` (UNIQUE `business_type+business_id+character_id`),
`cm_business_activity`, `cm_business_transactions` (UNIQUE `idempotency_key`). No existing table is altered.

## Rate limits and locks

Per actor: invite 5/60 s, mutate 12/30 s, rank 10/30 s, payroll 6/30 s, invoice 6/30 s, open 10/10 s. Operation locks: per business for ranks,
employees, payroll and ownership sync; the SQL-level guard makes balance moves safe across restarts.

## Self-test

Console: `cm_business_selftest` (requires `cm_environment=development`; uses synthetic characters 91000xx and a QA-only fixture table, cleaned up).

## Manual tests still required

1. Buy a store/gas station/clothing store; run `/businessstaff store <id>`. 2. Invite a nearby player; target Accepts. 3. Employee appears; owner
changes rank; an employee without `business.invite` cannot invite. 4. Owner sets a rank pay and pays an employee; business funds drop once.
5. Remove the employee; reconnect and verify persistence. 6. Let tax lapse or force a re-sale: staff and custom ranks are cleared. 7. Issue a
business invoice to a nearby player (`CreateBusinessInvoice`), pay it with `/bills`, verify the business balance rises exactly once.
