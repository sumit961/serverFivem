# cm-core shared item-purchase settlement

`shared/item_purchase.lua` — server-only helper included by consumers with `server_scripts { '@cm-core/shared/item_purchase.lua', ... }`
(not a resource export, not loaded by cm-core itself). Consumers: **cm-store** (journal `cm_store_purchases`, refs `STORE-PUR-`) and
**nv_cloth** (journal `nv_cloth_purchases`, refs `CLOTH-PUR-`). cm-gasstations has its own fuel-aware variant (`server/settlement.lua`).

One order terminates in exactly one result. Journal row first (identity = character id), then:

| step | owner / idempotency | unknown / failure |
|---|---|---|
| reserve all cart units | one guarded UPDATE joined to the journal row | fails → journal closed, no charge |
| debit | cm-playerdata `RemoveMoneyFromCharacter`, ref `<ref>:debit` (cash or bank) | definite refusal → compensate; unknown → `GetCharacterMoneyOperation` |
| deliver | cm-inventory `ExecuteItemGrant`, whole cart, all-or-nothing, ref `<ref>` | unknown → `GetItemGrantStatus`; `CancelItemGrant` fence before any refund |
| refund | cm-playerdata `AddMoneyToCharacterOnce`, ref `<ref>:refund`, full amount | unavailable → stays `pending`, retried |
| terminal | ONE UPDATE: state + undelivered-stock release (capped) + owner revenue (success only) | only the first caller matches `state='pending'` |

There is no partial delivery: a cart is delivered whole or refunded whole, so stock can never be restored for items the player kept.
Revenue is credited only by the terminal statement, after delivery is proven, so compensation never reverses a business credit.
`recover()` (20 s after start, then every 60 s) resolves `pending` rows older than 60 s that the resource is not currently processing.

## Public surface (Lua, per consumer)

`CMItemPurchase.sqlFor(cfg)`, `.mysqlDb(MySQL, cfg)`, `.ownerDeps(exports, GetResourceState)`, `.new({ db, money, items, log })` →
`run(order)`, `resolve(ref)`, `recover(seconds)`. `cfg = { journal, stockTable, stockKey, ownerColumn, ownedOnly, capacity }`.
`order = { reference, character_id, scope_id, account ('cash'|'bank'), total, units, owner_pct, items = {{ item, amount [, metadata] }} }`
is built by the CALLER from server-side catalog/price data only.

## Trust

* cm-playerdata `MONEY_OP_CALLERS`: `cm-store` → `STORE-PUR-*` on cash/bank; `nv_cloth` → `CLOTH-PUR-*` on cash/bank; `cm-gasstations` →
  `GAS-PUR-*` on cash; `cm-billing` unchanged.
* cm-inventory `grantTrusted`: `cm-gasstations`, `cm-store` (carts up to 24 lines), `nv_cloth` (clothing garments, large metadata, 24 lines).

## Tests

`tests/item_purchase_selftest.lua`, `tests/purchase_integration.lua` (REAL playerdata money ops + REAL inventory grant), `tests/consumer_wiring_test.lua`,
`tests/item_purchase_mysql_smoke.py` (`CM_TEST_MYSQL=host:port:user` for a throwaway MariaDB/MySQL).

## Residual risks

* The journal joins `scope_id` (VARCHAR) to the store key; the journal and store tables must share a collation (they do on a default database).
* Client-visual application of purchased clothing is not part of economic delivery: persistence in the inventory is. A purchase whose visuals fail
  is never refunded; the garment is in the inventory.
