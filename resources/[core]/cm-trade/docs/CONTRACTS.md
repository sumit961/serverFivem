# cm-trade contracts

`cm-trade` is the single player-to-player trading platform: two **nearby, loaded, living** characters exchange wallet **cash** (and, once the inventory owner provides the
exchange contract, inventory items) in one server-authoritative session. It coordinates `cm-playerdata` (identity, money) and `cm-inventory` (items); it owns neither. It is
economy neutral: no fee, payout, XP or reward; it only moves existing value. Out of scope: bank transfers, offline trades, vehicles/houses/businesses, phone trading, marketplaces.

## Flow

`G menu -> Trade -> Offer a Trade` (or the `/trade` fallback, which invites the closest player within range) -> invite (45 s) -> target Accept/Decline -> both edit offers -> both Confirm
-> server settles. **Any change to either offer clears both confirmations**, and Confirm carries the revision the player saw (stale confirms are rejected).

States: `invited -> open -> committing -> completed | cancelled` (terminal states never reopen). One active session per character, exactly two participants.

## Server-side validation

* Invite and accept: both characters loaded and different, registered sources still map to the same characters, same routing bucket, within 3.0 m, neither already trading, not dead, rate limited.
* While open: cancelled on disconnect, death, bucket change, separation beyond 6 m, or 10 minutes of lifetime (1 s watcher).
* Cash: JSON number, integer, 0..1,000,000, <= wallet cash at offer time and again at settlement. Bank balance is never tradeable.
* Items (when enabled): opaque row `ref` must be in the caller's own safe snapshot, `tradeable`, not denied, quantity within the stack, max 8 lines, max 100 per line.
* Final revalidation right before settlement repeats presence, distance (3.0 m), cash and the inventory owner's `ValidateItemExchange`.
* Every net event proves `source` is one of the two registered participants (character AND source) before doing anything; no character id, owner, price or amount is taken from the client.

## Settlement (journaled saga with a pivot — not a single database transaction)

1. Revalidate. Nothing has moved; failure just cancels the session.
2. Insert the journal row `cm_trade_transactions` (`debiting`).
3. Debit each payer's cash (`cm-trade:<ref>:debit`). If the second debit fails the first payer is refunded (`cm-trade:<ref>:refund`) -> `rolled_back`.
4. **Pivot:** `ExecuteItemExchange(<ref>)` — one transaction inside cm-inventory, idempotent per `<ref>`. If it fails and the owner reports terminal `not_applied` (never merely pending/not_submitted/unreachable), both debits are refunded -> `rolled_back`.
5. Credit each recipient (`cm-trade:<ref>:credit`, offline-safe `AddMoneyToCharacter`), forward-only, 3 retries; if still failing the journal becomes `needs_reconciliation`.
6. `completed`, audit event, `cm-admin` log, both clients notified.

Before the pivot a failure or crash rolls **back**; after it only **forward**. Evidence for every decision comes from `economy_transactions` reasons and the inventory exchange status;
`Reconcile` (startup +6 s, then every 30 s, plus `AdminReconcileTrades`) re-derives the state, never repeats a leg that has ledger evidence and never guesses when the inventory owner is unavailable.
A cash-only trade has the same journal; the legs are separate ledger rows, so a crash mid-way is repaired, but cash movement itself is **not** a single atomic database operation.
Open/invited sessions are memory only and simply vanish on restart (nothing was moved).

## Database (additive, `sql/001_cm_trade.sql`, applied by `server/schema.lua`)

`cm_trade_transactions` (UNIQUE `reference`; status `debiting|debited|items_done|completed|rolled_back|needs_reconciliation`; indexes on status/updated_at and both characters) and
`cm_trade_events` (invited, accepted, confirmed, cancelled, settlement_rejected, rolled_back, completed, reconciled_*). Characters only, never FiveM source ids.

## Exports / events

Server exports: `IsTrading(src)`; admin recovery (caller must be `cm-admin`): `AdminListTrades({ open })`, `AdminInspectTrade(ref)`, `AdminReconcileTrades()`.
Net events (all re-validated): `cm-trade:server:respond|cancel|offer|confirm|inventory`. Client events: `cm-trade:client:invite|open|state|inventory|result|ended`.
Registered interaction action: `trade_invite` (cm-playerdata `RegisterInteractionAction`, local event `cm-trade:server:interactionInvite`, not network-callable).

## Privacy

Players see only `Stranger #<characterId>` unless the other character is in their known identities (then the full name). Server ids, accounts and license data never reach the NUI.

## Manual two-player test (MANUAL FIVEM TEST REQUIRED)

1. A and B stand together; A uses G -> Trade -> Offer a Trade (or `/trade`). B accepts (also try decline and 45 s expiry).
2. A offers cash, B offers a different amount. Both confirm: balances change exactly once; `cm_trade_transactions` row is `completed`.
3. Change an offer after one player confirmed: both confirmations clear.
4. Walk apart (> 6 m) before the final confirm: the trade cancels, nothing moves. Disconnect one player mid-session: the other is told, no stale lock after reconnect.
5. Offer more cash than the wallet: refused. Start a second trade while in one: refused.
6. Restart `cm-trade` mid-session: both windows close, nothing moved, both can trade again.
7. **After the inventory contract exists:** trade a normal item, a partial stack and a unique-metadata item (serial/durability must survive), fill the recipient's inventory (trade refuses, nothing lost),
   try a protected item, and (only if enabled) a weapon with serial/ammo.
