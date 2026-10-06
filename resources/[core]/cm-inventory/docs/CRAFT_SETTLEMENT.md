# Craft settlement (cm-inventory, additive)

Atomic **single-character** item transformation for `cm-crafting` (`server/craft.lua`). Not a two-party exchange: it must not be used for player trading
(`cm-trade` still needs its own two-character atomic primitive; this ledger/locking design may be extended for it later, nothing here enables it).

## Exports (server only, caller must be `cm-crafting`; anything else -> `false, 'forbidden'`)

```lua
ValidateCraftTransaction(characterId, tx)          -> true | false, reason                 -- read-only, advisory
ExecuteCraftTransaction(reference, characterId, tx)
    -> true, { replayed = bool, outputs = { {item, amount}... } }                           -- committed now, or earlier under this reference
    |  false, reason                                                                        -- DEFINITE failure, nothing applied
    |  false, 'unavailable'                                                                 -- unknown: reconcile via GetCraftTransactionStatus
GetCraftTransactionStatus(reference)               -> 'committed' | 'not_applied' | 'unknown' (DB error) ; false,'invalid_reference'
```

Reasons: `insufficient_input`, `tool_missing`, `tool_durability`, `no_capacity`, `invalid_item`, `invalid_metadata`, `invalid_transaction`,
`reference_conflict`, `forbidden`, `unavailable`. There is no client event; `characterId` is a database character id (works offline).

`tx = { inputs = {{item, amount}}, outputs = {{item, amount, metadata?}}, tools = {{item, durabilityUse?}} }`. Unknown fields are rejected.
Limits: 8 input / 8 output / 4 tool lines, amount 1..10000 per line, 50000 total, `durabilityUse` 1..100, output metadata plain data <= 1024 bytes, depth 4, 64 nodes.

## Atomic sequence (one `MySQL.startTransaction`)
1. per-character in-process lock (re-entrant per coroutine; also taken by the legacy Add/Remove/Move/Split/Drop/ConsumeSlot internals)
2. `SELECT ... FOR UPDATE` on the character's `inventory_items` rows (the row-lock serialization point)
3. ledger lookup (`cm_inventory_transactions` by reference): replay or `reference_conflict`
4. plan on the in-memory rows: tools -> inputs -> outputs -> **post-transaction** slot/weight check (inputs free slots/weight first)
5. guarded writes (`... AND quantity = ?`, `metadata <=> ?`): tool durability, input updates/deletes, output updates/inserts, audit rows
6. `INSERT` the ledger row (UNIQUE `reference`) as the last write, then commit. Any error returns `false` -> full rollback.
After a non-confirmed result the ledger is consulted; the DB, not the caller, decides committed vs not applied.

## Item policy (V1, deliberate)
* inputs: stackable, plain items; matched only against rows whose stack-metadata signature equals a metadata-free item; across stacks, largest first. Items with a default
  `durability` cannot be inputs. Equipment slots are never consumed. **Metadata-matched inputs are not supported.**
* outputs: stackable, non-clothing, non-weapon/armor. Unique/serial outputs are rejected (`invalid_item`): serial generation cannot join this transaction safely.
  Existing compatible stack first (pocket, backpack, quickaccess), then an empty pocket/unlocked backpack slot; matching stack metadata is left unchanged.
* tools: kept; `durabilityUse` is applied to `metadata.durability` (falls back to the item definition) in the same transaction. A durability tool must be a
  single-quantity row; the most worn sufficient tool is used.

## Table
`cm_inventory_transactions(id, reference UNIQUE, tx_type, character_id, payload_hash, payload, status, result_json, created_at, committed_at, INDEX(character_id,id))`
created idempotently (`CREATE TABLE IF NOT EXISTS`) on start. Rows exist only for committed transactions. `payload` is the canonical normalized tx (<= 8000 bytes);
no inventory snapshots, no account identifiers.

## Known limits
* The lock is in-process; legacy inventory paths that do not go through the wrapped internals (external/trunk moves, robbery, tier2 SQL) are only protected by the InnoDB row
  locks and the guarded writes (a conflicting write makes the craft roll back with `unavailable` and retry; it cannot double-spend).
* The reference and ledger are not purged; retention is a future ops decision.

## Tests
`lua tests/craft_selftest.lua` (real inventory code + SQL double), `python tests/craft_mysql_smoke.py` (isolated scratch database, real MySQL),
`cm-crafting/tests/integration_inventory.lua` (production crafting adapter against the real inventory code).

## Item sink (consume-only) - added for business material delivery

The same atomic engine without outputs or tools. Trusted caller `Cfg.sinkTrusted` = `cm-commercial-ownership` (`cm-crafting` cannot use it, and the sink owner cannot run craft transactions, so there is no minting path).

```lua
ValidateItemSinkTransaction(characterId, items)             -> true | false, reason                      -- read-only
ExecuteItemSinkTransaction(reference, characterId, items)   -> true, { replayed } | false, reason | false, 'unavailable'
GetItemSinkTransactionStatus(reference)                     -> 'committed' | 'not_applied' | 'unknown' ; false,'reference_conflict' if the reference belongs to a craft
```
`items = { { item, amount } ... }` (same bounds/limits and the same input policy as craft inputs: stackable, metadata-free stacks, carry slots only). The ledger row has `tx_type = 'item_sink'`; the payload identity includes
the transaction type, so a reference can never be replayed as the other kind. The destination owner must treat a committed sink as irreversible (retry its own credit; no refund path).
New construction/city-project owners reuse it by being added to `Cfg.sinkTrusted` (documented contract in `cm-commercial-ownership/docs/MATERIALS.md`).
