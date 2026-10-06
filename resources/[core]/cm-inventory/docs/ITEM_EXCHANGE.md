# Two-character item exchange (cm-inventory `server/exchange.lua`)

Atomic player <-> player item exchange for `cm-trade`, on the same engine as the craft transaction and the item sink (`craft.lua`: per-character locks, `SELECT ... FOR UPDATE`, guarded writes, the UNIQUE-reference ledger `cm_inventory_transactions`).
Server-only; allowlist `Cfg.exchangeTrusted` = `cm-trade`. cm-trade orchestrates cash and sessions; this file only moves custody. It creates 0 items, 0 money.

```lua
GetTradeSnapshot(characterId)             -> { { ref, item, label, image, quantity, tradeable, summary, fp } ... }   -- carry slots only
ValidateItemExchange(tradeRef, a, b)      -> true | false, reason                                                    -- read-only
ExecuteItemExchange(tradeRef, a, b)       -> true, { replayed, pieces } | false, reason (nothing applied) | false, 'unavailable'
GetItemExchangeStatus(tradeRef)           -> 'committed' | 'pending' | 'not_applied' | 'not_submitted' | 'unknown'   (not_applied is terminal)
FenceItemExchange(tradeRef)               -> 'committed' | 'not_applied' | 'pending' | false,reason    ; false,'reference_conflict' if the reference belongs to another transaction kind
-- a / b = { characterId, lines = { { ref = '<row id>', quantity = n, fp = '<snapshot fingerprint>' } } }   (<= 8 lines per side, quantity 1..1000, no other fields)
```
Reasons: `forbidden, invalid_transaction, invalid_item, not_tradeable, insufficient_quantity, invalid_quantity, item_changed, singleton_conflict, no_capacity, reference_conflict, unavailable`.

## Atomic sequence (one `MySQL.startTransaction`)
1. in-process locks, **lowest character id first**; then `FOR UPDATE` on both characters' rows, **lowest id first** (A<->B and B<->A can never deadlock; proven against real MySQL in `exchange_mysql_smoke.py`)
2. ledger lookup (replay / conflict), characters exist
3. plan in memory on the locked rows: each offered row must belong to its character, be in a carry slot, be tradeable (**cm-items `CanTradeItem`**), match its `fp` and have the quantity; place every incoming piece
   into the receiver's post-removal state; **final-state capacity per side** = current - own offer + counterpart offer (stack merges, free pocket/unlocked backpack slots, singleton rule, weight)
4. writes: quantity updates/deletes (lowest id first), whole rows leave to unique temporary slots (`xfer-<rowid>`), inserts for partial pieces, then final slots; audit rows; ledger row last; commit. Any error returns `false` -> full rollback.

## Transfer semantics
* **Whole row** -> the same row id moves by `UPDATE` (metadata, serial, durability, custom labels preserved; never destroyed and recreated). Two rows swapping owners in place use the two-phase move (a direct swap collides with the UNIQUE `(owner_type, owner_id, slot)` key).
* **Partial quantity** (stackable items only) -> the source keeps the rest; the receiver merges into a compatible stack (`rowCanStackWithMetadata`, the normal rule) or gets a new row with the exact same metadata. Non-stackable rows move whole or not at all (`invalid_quantity`).
* Equipment slots are never offered. Eligibility is the authoritative cm-items policy (fail closed; weapons, ammo, keys, documents, bound items blocked).
* The offer is **not escrowed**: items stay in the player's inventory until the atomic exchange, which re-reads everything. An item that was used, moved to equipment, dropped or changed (`fp`) makes the exchange refuse with nothing applied.

## Idempotency / recovery
Unique `tradeRef`; payload = canonical (sides sorted by character id, lines sorted, quantities, fingerprints), so the same trade with sides swapped replays; any other change under the same reference is `reference_conflict`.
A response lost after commit is answered by `GetItemExchangeStatus` (`committed`); the ledger survives restarts. A committed reference is never re-executed (replay only).

Tests: `lua tests/exchange_selftest.lua` (108), `python tests/exchange_mysql_smoke.py` (15), `cm-trade/tests/exchange_integration.lua` (45), `cm-items/tests/trade_policy_selftest.lua` (22).

## Durable lifecycle, status contract and crash recovery (settlement hardening)

The ledger row of a `trade_exchange` reference is the only authority on what happened:

```
(none) --prepare/claim--> prepared --item transaction--> committed
   |                         |  \--lease expired + fence--> not_applied (TERMINAL)
   \--FenceItemExchange------+--definite rejection--------> not_applied (TERMINAL)
```

* `prepared`: an executor holds a lease (`result_json = {"lease":token,"exp":epoch}`) taken BEFORE any item row is touched. Outcome pending.
* `committed`: written inside the item transaction by `UPDATE ... SET status='committed' WHERE reference=? AND status='prepared' AND result_json=<our lease>`; 0 rows rolls the whole transaction back.
* `not_applied`: terminal. Written by a definite rejection (item_changed, not_tradeable, no_capacity ...) or by `FenceItemExchange`. Every later `ExecuteItemExchange` for that reference answers `false, 'not_applied'` (the UNIQUE reference makes a fresh claim impossible).
* Every transition is a compare-and-set on `(status, result_json)` and the transaction re-reads the ledger row `FOR UPDATE`, so exactly one of {commit, fence/reclaim} wins and the loser changes nothing. Correctness does **not** depend on the lease length: a slow or zombie executor can only commit while its own lease token is still in the row.

| Call | Returns |
|---|---|
| `GetItemExchangeStatus(ref)` | `committed` (items moved, forward only) · `not_applied` (terminal: no mutation can ever commit) · `pending` (claimed / possibly in flight: never compensate) · `not_submitted` (owner never saw it: **not a proof**, fence first) · `unknown` (database unavailable) · `false, reason` |
| `FenceItemExchange(ref)` | makes `not_applied` permanent when provable: no row -> tombstone; stale lease -> CAS to terminal. `pending` while a live lease exists; `committed` if it committed. |
| `ExecuteItemExchange(ref, a, b)` | `true,{replayed}` · definite `false, reason` (terminal) · `false,'pending'` (a live executor owns the reference) · `false,'not_applied'` (fenced/terminal) · `false,'unavailable'` (unknown: ask the status). A stale lease is reclaimed by CAS and the SAME reference re-executes. |

Only `cm-trade` may call any of them. `unavailable` from `cm-items` during planning is not terminal (the lease is released and a retry may commit); an error inside the transaction leaves the row `prepared` (or releases the lease when the rollback is confirmed) and is resolved by re-execute or fence, never by time alone.
Tests: `tests/exchange_recovery_selftest.lua`, `tests/exchange_mysql_smoke.py` (real InnoDB), `cm-trade/tests/exchange_integration.lua`.
