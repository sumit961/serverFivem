# Item settlement: shared integration (RESOLVED 2026-10-03)

`cm-trade` now settles **items** (item-only and mixed cash + items) through the authoritative `cm-inventory` two-character exchange. Cash-only trades are unchanged.
`Config.Items.Enabled = 'auto'` resolves to **on** whenever `cm-inventory` answers `GetItemExchangeStatus('cm-trade-probe')`; set it to `false` to force cash-only.

## Contract implemented by cm-inventory (`server/exchange.lua`; caller allowlist `cm-trade`; documented in `cm-inventory/docs/ITEM_EXCHANGE.md`)

| Export | Contract |
|---|---|
| `GetTradeSnapshot(characterId)` | `{ { ref, item, label, image, quantity, tradeable, summary, fp } }`, carry slots only. `ref` = inventory row id (string). `tradeable` comes from the authoritative cm-items policy. `fp` is a server-side row fingerprint (item + exact metadata); cm-trade never sends it to the client. |
| `ValidateItemExchange(tradeRef, a, b)` | read-only dry run (rows exist and belong to that character, eligible, quantity, fingerprint unchanged, **final-state capacity for both sides**). |
| `ExecuteItemExchange(tradeRef, a, b)` | one SQL transaction, idempotent per `tradeRef` (UNIQUE ledger row, `tx_type = trade_exchange`). `true, { replayed }` or `false, reason` (nothing applied) or `false, 'unavailable'` (ask the status). |
| `GetItemExchangeStatus(tradeRef)` | `committed` / `pending` / `not_applied` (terminal) / `not_submitted` / `unknown`. cm-trade maps `committed` -> `applied`; `pending`, `not_submitted` and anything unreadable are **never** grounds for a refund. |
| `FenceItemExchange(tradeRef)` | makes `not_applied` permanent for a never-submitted reference or a provably dead executor (`pending` while a live lease exists). |

`a`/`b` = `{ characterId, lines = { { ref, quantity, fp } } }`.

## Eligibility (cm-items, fail closed)

`CMItems.CanTradeItem(name, metadata)` / export `CanTradeItem`: a definition must carry an explicit `tradeable = true` (default **false**), outside the hard-blocked classes
(weapons, ammo, keys, identity/licence/documents, robbery-protected, singleton, characterId-bound, admin/dev/test names), and the instance must not be `bound`/`soulbound`/`nonTransferable`.
Approved today: `water, sandwich, bandage, medkit, painkillers, repairkit`. The new commodity **materials are deliberately NOT tradeable** until their sources go live (flip `tradeable = true` on the definition).
cm-trade keeps its own `Config.Items.DenyPatterns` as defence in depth.

## cm-trade changes (minimal)

* the offer line freezes the server-side row fingerprint (`fp`) from the inventory snapshot and passes it to validate/execute (so an item swapped or changed after the offer is refused);
* `P.items.status` accepts the inventory vocabulary (`committed` -> `applied`, `not_applied`, `pending`, `not_submitted`; anything else is nil = decide later). `P.items.fence` wraps `FenceItemExchange`.
The state machine, journal, recovery, UI and G-menu are unchanged. The item picker UI already existed (it appears when `caps.items` is true).

## Settlement order (unchanged saga, now with real items)

Revalidate (incl. `ValidateItemExchange`) -> journal `debiting` -> debit both cash legs -> **pivot: `ExecuteItemExchange`** -> credit both legs. Before the pivot a crash/failure rolls back (refund debits);
after it only forward. An exchange whose response is lost is detected through `GetItemExchangeStatus`. Tested at every boundary in `tests/exchange_integration.lua`.

Tests: `lua tests/exchange_integration.lua` (cm-trade core + REAL inventory exchange), `cm-inventory/tests/exchange_selftest.lua`, `exchange_mysql_smoke.py`, `cm-items/tests/trade_policy_selftest.lua`,
in-game `cm_trade_selftest`, `node tests/nui-smoke.js`. Live two-player trading is untested by instruction.

## Recovery rules (cash is refunded ONLY when the owner proves `not_applied`)

| Owner status | cm-trade action |
|---|---|
| `committed` | forward only: credits settle idempotently, trade `completed` (`forward_settlement_resumed` event when it was pending) |
| `not_applied` | terminal proof: refund both debits (`compensation_started` event), `rolled_back` |
| `not_submitted` | fence (`FenceItemExchange`); `not_applied` -> refund (`items_fenced_not_applied`); `pending`/`committed` follow their rows |
| `pending` | never refund. Re-submit the SAME reference from the journal's `items_json` (the owner reclaims a stale lease or answers pending); journal `needs_reconciliation/items_pending`, retried each reconcile interval, logged once |
| unreadable / inventory stopped | no change, retry later (no refund on downtime) |

During settlement an unresolved exchange (`pending`/unreachable) leaves the cash debited, sets `needs_reconciliation/items_pending`, and tells the players the trade is being finalised. Disconnects never influence the outcome. The 20 s `StaleSeconds` is only a liveness delay, not correctness.
Events (`cm_trade_events.kind`): `items_submitted`, `items_pending`, `items_fenced_not_applied`, `items_reexecuted`, `compensation_started`, `forward_settlement_resumed`, plus the existing ones.
