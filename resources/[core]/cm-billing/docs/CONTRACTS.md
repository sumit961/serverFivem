# cm-billing contracts

## Server exports (caller = `GetInvokingResource()`, must be an enabled `Config.Providers` entry)

| Export | Returns |
|---|---|
| `CreateInvoice(data)` | `true, { reference, id, existing? }` or `false, reason` |
| `VoidInvoice(reference, reason)` | `true` or `false, reason`. Only the issuing provider (`canVoid`), only while `pending` |
| `GetInvoice(reference)` | view (adds `recipientCharacterId`, `metadata`) or `nil, reason`. Only invoices issued by the caller |
| `GetInvoiceStatus(reference)` | `'pending'|'processing'|'paid'|'voided'|'expired'` or `nil` |
| `GetPendingInvoices(characterId)` | array of views for invoices issued by the caller |

### `CreateInvoice` data

```lua
{
  recipientCharacterId = '12',            -- required, must exist; offline allowed if the provider allows it
  amount = 12500,                         -- required whole number (a Lua number, never a string), 1..min(provider.maxAmount, HardMaxAmount)
  label = 'Vehicle repair',               -- required, 80 chars
  description = '...',                    -- optional, 400 chars
  issuerType = 'system'|'organization'|'business'|'character',  -- must be in provider.issuerTypes
  issuerLabel = 'LS Customs',             -- required display name shown to the recipient (64 chars)
  issuerCharacterId = '7',                -- optional, must exist
  issuerEntityId = 'shop_3',              -- optional opaque id, never shown to the recipient
  destination = { type = 'city' },        -- city | character{id} | family{id} | business{id='<type>:<id>'}; must be in provider.destinations
  expiresInSeconds = 3600,                -- optional, 60..2592000
  dueInSeconds = 86400,                   -- optional, informational
  idempotencyKey = 'order-991',           -- optional; same key from the same provider returns the same invoice
  metadata = { ['law.case'] = 'A-12' },   -- optional; every key must start with provider.metadataNamespace .. '.'
}
```

Failure reasons: `forbidden` (unknown, disabled or non-provider caller), `invalid_request, invalid_recipient, recipient_offline, invalid_amount`
(non-number, NaN, infinity, fraction, < 1), `amount_exceeds_provider_limit` (above the provider's own limit), `amount_exceeds_platform_limit` (above the
platform ceiling), `forbidden_issuer_type, invalid_issuer, invalid_destination` (unknown/unavailable/invalid target), `destination_not_allowed`
(destination type, or id prefix, not in the provider's policy), `destination_unavailable, invalid_expiry, invalid_metadata, unavailable, internal_error`.
`amount_too_large` was replaced by the two `amount_exceeds_*` reasons.

### Provider policy (`Config.Providers[<resource>]`, server config only)

`enabled, maxAmount, issuerTypes, destinations, destinationIdPrefixes?, allowOffline, metadataNamespace, canVoid, canRefund`. The caller is always
`GetInvokingResource()` and the invoice pins it as `issuer_resource`; nothing the caller passes (data fields, names) changes which policy applies.
Effective creation limit = `min(provider.maxAmount, Config.HardMaxAmount)`; a missing/invalid `maxAmount` means 0 (fail closed). `HardMaxAmount`
(5,000,000) is the platform emergency ceiling. Limits are evaluated only when an invoice is **created**: payment, refund and reconciliation never
re-check them, so lowering a limit later affects new invoices only and never strands an invoice that was legal when issued. Rejections for limit
or destination reasons are audited (`cm_billing_invoice_rejected`: provider, amount, limit, reason).

`GetProviderPolicy()` -> `{ provider, maxInvoiceAmount, platformMaxAmount, canRefund, canVoid, allowOffline, issuerTypes, destinations }` or
`nil, 'forbidden'`: read-only, returns only the **calling** provider's own policy (so a provider can surface a meaningful limit instead of duplicating
the number). There is no export or event that registers or changes a provider or its limit.

| Provider | Limit | Destinations | Refund |
|---|---:|---|---|
| cm-mechanic | 2,000,000 | business `mechanic:<shop>` | yes |
| cm-commercial-ownership | 50,000 | business | yes |
| cm-law / cm-ems / cm-doctor (disabled) | 250,000 / 150,000 / 100,000 | city (ems also family) | no |

### Business destinations

`destination = { type = 'business', id = 'store:3' }` credits the business's own `business_balance` through
`cm-commercial-ownership:CreditBusinessAtomic` with idempotency key `billing-credit:<reference>` (exactly-once even when settlement is
retried after a crash). Only owned businesses validate; a business that loses its owner before payment fails the credit and the payer is
refunded. The only enabled business issuer is `cm-commercial-ownership` itself (`CreateBusinessInvoice`, which first validates
`business.create_invoice`, customer presence and distance).

`cm-mechanic` is also an enabled provider (business issuer + business destination only, max 50,000, no offline recipients, metadata namespace `mechanic.`): it creates an invoice only after the customer approved a server-calculated quote for a work order (`cm-mechanic/docs/README.md`).

### Registering a provider

Add the resource to `Config.Providers` with `enabled = true` and conservative limits. Do not enable a provider for a resource that does not
validate role, service context and amount first. cm-billing hard bounds are a backstop, not the authorisation.

## Refunds (server exports; provider must have `canRefund = true`; caller = `GetInvokingResource()`)

A refund returns money from a **paid** invoice to its **original payer** after reversing the same value out of the invoice's **original
destination**. It is its own operation (never a negative invoice), never mints money, and never rewrites history: `invoice.status` stays
`paid`; `refund_state` (`none|processing|partial|refunded`), `refunded_amount` and `refunded_at` carry the refund facts. A provider can only
refund invoices **it issued**; there is no client/net event (a customer-facing request must go through the owning provider's workflow).

| Export | Returns |
|---|---|
| `RequestRefund(invoiceReference, refundReference, amount?, reason)` | `true, view` or `false, reason`. `amount = nil` refunds everything still refundable |
| `GetRefundStatus(refundReference)` | `view` or `nil, reason` (the caller's own refunds only) |
| `GetInvoiceRefundState(invoiceReference)` | `{ status, refundState, paidAmount, refundedAmount, inFlightAmount, refundableAmount, netPaidAmount }` or `nil, reason` |
| `RetryRefund(refundReference)` | `true, view` or `false, reason`. Continues the provider's own refund forward; never alters the request |
| `AdminListStuckRefunds(limit)`, `AdminInspectRefund(ref, provider?)`, `AdminReconcileRefund(ref, provider?)`, `AdminAbandonRefund(ref, provider?, note?)` | Only `Config.Refund.AdminResources` (cm-admin). Console: `cm_billing_refund_stuck / _inspect / _reconcile / _abandon` |

`view = { refundReference, invoiceReference, amount, reason, status, final, debitState, creditState, failureReason?, createdAt, completedAt? }`.
`true` means the refund is journaled and owned by the saga (read `view.status`); `false` means nothing was reserved or moved.

**Status:** `pending` -> `destination_debited` -> `completed`; `needs_reconciliation` (before any debit only: destination short of funds,
owner unavailable, owner outcome unknown); `failed` (admin abandon with ledger proof that nothing was debited; releases the reservation).
Once the destination debit commits the refund is forward-only and is never expired or cancelled.

**Reasons** (closed set, a label not an authorisation): `service_failed, service_cancelled, duplicate_charge, provider_reversal, admin_reconcile`.

**Failure reasons (`false, reason`):** `forbidden, unavailable, not_found, not_paid, invalid_refund_reference, invalid_reason, invalid_amount,
destination_not_refundable, payment_account_unknown, paid_amount_unknown, already_refunded, refund_in_progress, refund_exceeds_paid,
idempotency_conflict`.

**Idempotency:** the journal is unique per `(provider, refundReference)`. Same reference + same invoice + same amount mode/amount = replay
(drives the saga forward if unfinished, returns the stored result); different invoice, amount, or full-vs-exact = `idempotency_conflict`.
The payer and destination are never request inputs: they come from the invoice.

**Partial refunds** are supported: the invoice row carries a locked aggregate (`refund_reserved_amount` = completed + in flight,
`refunded_amount` = completed) and a guarded `UPDATE ... refund_reserved_amount + ? <= paid` reserves the amount in the same SQL transaction
that inserts the journal row, so `refunded <= reserved <= paid` always holds (two concurrent 15,000 refunds on a 20,000 invoice: one wins).
`paid` is what the destination actually received (a family treasury that accepted less at payment time lowers it).

**Destination reversal (owner APIs only):** `business` -> `cm-commercial-ownership:DebitBusinessAtomic` (key `cm-billing-rfd-debit:<invoice>:<journal id>`);
`family` -> `cm-family:DebitFamilyTreasuryAtomic` (reason = same key; ledger `withdraw`/`refund`); `character` -> `cm-playerdata:RemoveMoneyFromCharacter`
(same key, from the account the payer paid with, offline-safe). **`city` is not refundable**: it is a sink with no treasury, so a refund would
mint cash (`Config.Destinations.city.refundable = false`); revisit only when a city treasury exists. An insufficient destination balance never
goes negative: the refund waits in `needs_reconciliation` (reservation held) and the sweep retries it as funds arrive; an operator may abandon it.

**Crash boundaries** (every external step is preceded by a durable `*_state = 'attempting'` and followed by an owner-ledger evidence check on retry):
before debit -> safe retry; debit applied/response lost -> evidence found, no second debit, credit continues; debit committed, credit not -> credit only;
credit applied, journal stale -> complete without crediting again; completed -> no-op; owner unreachable/unknown -> stays reconciliation-pending.

**Service boundary:** billing cannot know whether the service was physically delivered. A provider may request a refund only **before** its
own irreversible service commit, and must make "refund authorised" and "service commit" mutually exclusive in its own guarded work-order
state. After the service commit there is no automatic refund. Forward-only recovery (mechanic/tuning) remains valid; refund is an additional tool.

Owner contracts (all callable only by the invoking resource `cm-billing`; no net event/callback exists). Character and family money use an
**owner-local durable operation journal** with `UNIQUE(reference)`, so exactly-once never depends on a process lock, on `Config.Money.TransactionLog`
or on `cm_family_bank_log`: the balance change and the journal row commit in ONE SQL transaction and a duplicate reference rolls it back.
Same reference + same payload = replay (applied at most once); same reference + different payload = `idempotency_conflict`; a debit short of
funds journals nothing, so the same reference stays retryable (refund `needs_reconciliation` retries it later).

| Owner export | Journal | Result |
|---|---|---|
| `cm-playerdata:RemoveMoneyFromCharacter(cid, account, amount, reference, meta?)` | `cm_character_money_operations` | `true, 'applied'\|'replayed'` or `false, reason` (`insufficient_funds, idempotency_conflict, not_found, busy, invalid_*, forbidden, unavailable`) |
| `cm-playerdata:AddMoneyToCharacterOnce(cid, account, amount, reference, meta?)` | same | same (the refund payer credit) |
| `cm-playerdata:GetCharacterMoneyOperation(reference)` | same | `{ status='committed', direction, characterId, account, amount }`, `false` (never applied) or `nil, 'unavailable'` (unknown: never assume "not applied") |
| `cm-family:DebitFamilyTreasuryAtomic(familyId, amount, { reason = reference, category? })` | `cm_family_treasury_operations` | `true, { replayed }` or `false, reason` |
| `cm-family:HasFamilyTreasuryEntry(familyId, 'debit', reference)` | same | `true/false`; raises when the journal cannot answer |
| `cm-family:CreditFamilyTreasuryOnce(familyId, amount, { reference, category? })` | same | `true, { requested, accepted, balance, replayed }` or `false, reason`; the journal stores the ACCEPTED amount (capacity) |
| `cm-family:GetFamilyTreasuryOperation(reference)` | same | `{ direction, familyId, amount }`, `false` (never applied) or raises when the journal cannot answer |

Both journals are created additively (`cm-playerdata` migration 009, `cm-family` schema). They cover **every** money movement billing performs through a
character or family owner, with distinct reference namespaces (the fingerprint includes direction, so one reference can never be both a credit and a debit):
`cm-billing-pay-debit:<invoice>` (payer), `cm-billing-pay-credit:<invoice>` (destination credit), `cm-billing-pay-refund:<invoice>` (payer refunded after a
definitive destination failure), `cm-billing-pay-remainder:<invoice>` (capacity remainder), `cm-billing-rfd-debit:<invoice>:<journal id>` and
`cm-billing-rfd-credit:<invoice>:<journal id>` (refunds). Business keeps its own idempotency key (`billing-credit:<invoice>`); city is a sink.

**Settlement recovery** (`settling` -> `paid`): the payer debit, destination credit and any returns are exactly-once by those references, so recovery asks the
owner's durable status (never `economy_transactions` / `cm_family_bank_log`) and re-issues the SAME reference. An owner that cannot answer, or an outcome that
is unknown (error, timeout, `unavailable`/`busy`), leaves the invoice `settling` and is retried by the sweep; **it is never read as "not applied" and never
refunds the payer**. Only a definitive owner refusal refunds the payer (once) and returns the invoice to `pending`. The destination's accepted amount is the
authoritative paid amount (`settlement_note = partial_refund_<remainder>` when it accepted less). Correctness does not depend on
`Config.Money.TransactionLog` or on the family bank log. Invoices that were `settling` under the pre-journal build must be reconciled before deploying it.
`cm-commercial-ownership` `Config.BalanceCallers.debit` includes `cm-billing` (idempotency key `cm-billing-rfd-debit:<invoice>:<journal id>`).
Tests: `cm_billing_selftest` (refund, policy, owner and journal suites), `python tests/refund_mysql_smoke.py` and `python tests/owner_journal_mysql_smoke.py` (scratch database).

## Player callbacks (ox_lib, client → server)

`cm-billing:list` → `{ pending, history, balances = { cash, bank } }` (caller's own invoices only).
`cm-billing:pay { reference, account = 'cash'|'bank' }` → refreshed snapshot + `paid`, or an error code
(`not_found, not_pending, invalid_account, insufficient_funds, destination_unavailable, settlement_failed, busy, rate_limited`).

## Events

Client: `cm-billing:client:changed` (targeted hint to refresh; no data). There are no server net events and no create/void event.

## Consumed contracts

cm-playerdata (`GetCharacterId`, `RemoveCash/RemoveBank`, `AddMoneyToCharacter`, `RemoveMoneyFromCharacter`, `GetCash/GetBank`), cm-family (`CreditFamilyTreasuryAtomic`, `DebitFamilyTreasuryAtomic`, `HasFamilyTreasuryEntry`, optional),
cm-commercial-ownership (`GetBusiness`, `CreditBusinessAtomic`, `DebitBusinessAtomic`, `HasBusinessTransaction`; business destinations), cm-phone (`SendSystemMessage`, optional), cm-hud (`cm-hud:client:notify`, optional), cm-admin (`cm-admin:server:addLog`, optional), tables `characters`, `economy_transactions`.

## Not in scope (by design)

Fines/citations remain owned by cm-law (`cm_police_citations`); law may later create an invoice for settlement. EMS/doctor charges are unchanged.
No interest, loans, credit scores, subscriptions, taxes or processing fees.
