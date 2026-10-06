# cm-inventory paid-goods grant (server exports)

Same atomic engine and `cm_inventory_transactions` ledger as craft settlement (`server/craft.lua`), outputs only, for a trusted caller that
has already taken payment under the same reference and must deliver exactly once. Trusted callers (`Cfg.grantTrusted`, per-caller policy): `cm-gasstations` (default limits), `cm-store` (carts up to 24 lines), `nv_cloth` (may also grant `clothing_*` garments; 24 lines, metadata up to 8 KB / 256 nodes, payload up to 60 KB). Clothing items are refused for every other caller; weapons/armor/unique items for all.
Any other resource gets `false, 'forbidden'`. Outputs follow the craft output policy (stackable, non-clothing, non-weapon, definition known).

| export | result |
|---|---|
| `ExecuteItemGrant(reference, characterId, items)` — `items = { { item, amount [, metadata] } }`, all-or-nothing | `true, { replayed }` delivered (now or earlier) · `false, 'cancelled'` fenced, definitely never delivered · `false, reason` definite failure, nothing applied (`no_capacity`, `invalid_item`, `reference_conflict`, …) · `false, 'unavailable'` **unknown** — ask the status |
| `GetItemGrantStatus(reference)` | `'committed'` · `'not_applied'` · `'cancelled'` · `'unknown'` (ledger unreachable) |
| `CancelItemGrant(reference, characterId)` | `true, 'cancelled'` permanently fenced (a later `ExecuteItemGrant` can never deliver) · `false, 'already_committed'` it WAS delivered · `false, 'unavailable'` retry |

Contract for callers: refund only after `GetItemGrantStatus` says `cancelled`, or after a successful `CancelItemGrant`. `unavailable`,
timeouts and exceptions are never evidence of non-delivery. Same reference + different payload/character → `reference_conflict`.
`CancelItemGrant` and `ExecuteItemGrant` serialize on the character's inventory lock and the UNIQUE(reference) ledger row, so exactly one wins.
