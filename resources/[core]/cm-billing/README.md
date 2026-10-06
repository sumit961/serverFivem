# cm-billing

The single authoritative invoice platform. Owner resources (law, EMS, mechanic, businesses, government) decide **what** is owed
and **who** may bill; `cm-billing` stores the invoice, lets the recipient pay it, and moves **existing** money to a validated destination.
It never mints money, has no client-callable create path and persists only character IDs (never FiveM sources).

```
OWNER RESOURCE  --validates gameplay, role, amount-->  exports['cm-billing']:CreateInvoice(data)
cm-billing      --stores invoice, notifies recipient (cm-phone / cm-hud, best effort)-->
RECIPIENT       --/bills, picks cash or bank, confirms-->  cm-billing:pay
cm-billing      --debit payer (cm-playerdata)  -->  destination credit (city sink / character / family treasury)
```

## Trust model

- Callers are identified with `GetInvokingResource()` and must be an **enabled** entry in `Config.Providers` (fail closed; cm-law, cm-ems and cm-doctor
  are present but disabled until they integrate). A provider is limited by its own `maxAmount` (per provider, never shared), `issuerTypes`, `destinations` (+ optional `destinationIdPrefixes`), `allowOffline`, `metadataNamespace`, `canVoid`, `canRefund`.
- Platform ceiling `Config.HardMaxAmount` (5,000,000) applies to every provider; the effective creation limit is `min(provider.maxAmount, HardMaxAmount)` and applies to NEW invoices only (existing invoices stay payable/refundable). Amounts must be whole numbers >= 1. `GetProviderPolicy()` shows a provider its own limit.
- The client can only list **its own** invoices and pay **its own** invoice. There is no client event to create, void or read others.
- `CreateInvoice` is a server export; the amount/label/destination come from the owner resource, never from NUI input.
- Recipients never see internal IDs, the issuing resource, the destination or metadata.

## Lifecycle

`pending → paid`, `pending → voided`, `pending → expired`, plus the internal transient `settling` (shown to the player as `processing`).
`paid` never returns to `pending`. Nothing is deleted; `cm_billing_events` is an append-only journal.

## Payment safety

1. Process lock per invoice (double clicks), then an atomic DB claim `pending → settling` guarded by recipient, amount and expiry (cross-instance safe).
2. Debit payer from `cash` or `bank` via cm-playerdata (server resolves balances; client balances are never trusted).
3. Credit destination, then `settling → paid` (token-guarded).
4. **Partial failure:** destination credit fails → payer is refunded and the invoice returns to `pending`. If the refund also fails the invoice stays `settling`
   with `manual_review_refund_failed`, an audit alert is raised, and the next sweep reconciles it from `economy_transactions` evidence
   (no charge → pending; charged and credited → paid; charged, uncredited → complete the credit once, otherwise refund).
   A family treasury that accepts less than requested has the remainder refunded to the payer.

## Destinations

| Type | Settlement | Status |
|---|---|---|
| `city` | money leaves circulation (sink) | available |
| `character` | `cm-playerdata:AddMoneyToCharacter` (offline-safe); must be allowed per provider; never the recipient | available |
| `family` | `cm-family:CreditFamilyTreasuryAtomic` | available (requires cm-family) |
| `business` | `cm-commercial-ownership:CreditBusinessAtomic` (id `<type>:<id>`, owned businesses only, ledger-idempotent per invoice) | available (requires cm-commercial-ownership) |
| `organization` | no authoritative credit contract exists | rejected at creation until an owner provides one |

## Operations

- Player UI: `/bills` (no default key; every common key is taken). ESC closes the confirmation first, then the panel; focus is released on every close path.
- Expiry and stuck-settlement sweeps run every `Config.DefaultExpiryCheckSeconds`.
- Audit: `cm-admin:server:addLog` category `billing` (created, paid, voided, settlement-critical). No descriptions are logged.
- Notifications: `cm-phone:SendSystemMessage` ("New invoice received - $X", no description or reference) + cm-hud toast; failures never affect invoice state.
  `cm-billing` must stay in `cm-phone` `Config.TrustedResources`.

## Tests

- Server console: `cm_billing_selftest` (needs `cm_environment=development`; synthetic `qa-bill-*` characters, in-memory money, injected failures, cleans up).
- NUI: `node resources/[core]/cm-billing/tests/nui-smoke.js` (headless Chrome/Edge against `ui/` + `ui/dev-mock.js`).

See `docs/CONTRACTS.md` for the exports and the integration recipe for owner resources.
