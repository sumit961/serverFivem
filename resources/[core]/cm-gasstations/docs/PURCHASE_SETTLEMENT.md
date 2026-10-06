# cm-gasstations purchase settlement

One customer order (fuel and/or repair kit / jerry can / wash kit) terminates in exactly one economic result.
Implementation: `server/settlement.lua` (state machine + SQL), wired in `server/placeOrder` of `server/main.lua`.

## Journal

`cm_gas_purchases` — one row per order, keyed by a server-generated `GAS-PUR-<characterId>-<time>-<rand>` reference, written
**before** any side effect. Identity is the character id (never the FiveM source), so settlement survives disconnects and restarts.

| column | meaning |
|---|---|
| `state` | `pending` → `completed` \| `compensated` (single atomic terminal statement) |
| `items_state`, `fuel_state` | `none` \| `pending` → `delivered` \| `failed` (fuel also `applying` = live flow's claim) |
| `reserved_units` | stock taken from the station, set in the same statement as the decrement |
| `fuel_before`, `fuel_target` | persisted vehicle fuel before the order / target (crash-window evidence) |

## Sequence and recovery

| phase | owner / idempotency | failure → recovery |
|---|---|---|
| journal insert | `cm_gas_purchases` PK | fails → nothing happened |
| stock reserve | one guarded UPDATE joined to the journal row | fails → journal closed, no charge |
| cash debit | cm-playerdata `RemoveMoneyFromCharacter`, ref `<ref>:debit` | definite refusal → compensate (nothing taken); unknown → `GetCharacterMoneyOperation` decides |
| item grant | cm-inventory `ExecuteItemGrant`, all-or-nothing, ref `<ref>` | definite no → refund; unknown → `GetItemGrantStatus`; `CancelItemGrant` fences before any refund |
| fuel apply | `ServiceVehicle` absolute set, claimed first (`claimFuel`) | unknown → persisted vehicle fuel is the evidence |
| refund | cm-playerdata `AddMoneyToCharacterOnce`, ref `<ref>:refund`, amount derived from persisted legs (stable) | unavailable → stays `pending`, retried |
| terminal | one `UPDATE` (journal + undelivered-stock release + owner revenue) | only the first caller matches `state='pending'` |

`resolve(ref)` is idempotent and is what the live flow, the exception path and recovery all call. `recover()` runs 20 s after start and
every 60 s for `pending` rows older than 60 s that this resource is not currently processing.

## Money / destination

Cash only. Owned station: owner share (80 %) is credited by the terminal statement on the **paid** amount only; nothing is credited
before delivery, so a compensation never has to reverse a business credit. Unowned station: money sink (no destination, nothing to reverse).

## Residual risks

* Fuel after a crash window is decided by persisted vehicle fuel (no ledger exists for it). If persisted fuel already equalled the target
  there is no evidence and the fuel leg is refunded.
* A debit issued by a resource instance killed mid-call can only land inside cm-playerdata's own call; the 60 s recovery grace covers it.
* `cm-store` and `nv_cloth` still use the old reserve → charge → deliver → unreferenced-refund sequence (see report: follow-up pattern).

## Tests

`tests/purchase_selftest.lua` (state machine, injected failures), `tests/purchase_mysql_smoke.py` and `tests/stock_mysql_smoke.py`
(real MySQL/MariaDB concurrency; `CM_TEST_MYSQL=host:port:user` targets a throwaway instance), `tests/money_gate_selftest.lua`.
