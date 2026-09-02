# CM Bank v1.4.0 — Security & Transactions

## Required behavior kept

- Player-to-player bank transfers still use **Character ID**.
- ATM owner withdrawal fee choices are exactly **1%, 2%, 3%, 4%**.
- Bank tellers do not charge an ATM withdrawal fee.
- Deposits and character-ID transfers do not pay an ATM-owner fee; ATM business fees apply to withdrawals only.

## Security fixes

- Deposit, withdrawal and transfer requests now fail closed unless the server confirms the player is physically at a verified ATM or a bank teller.
- Every sensitive money action re-checks position immediately before moving money.
- Newly client-discovered ATM coordinates are advisory only and are inserted as `verified = 0`, `for_sale = 0`.
- Unverified ATM reports cannot authorize banking, ownership, fees or map blips.
- Existing ATM rows from pre-v1.4 installs are retained as verified during migration.
- New ATM verification commands:
  - `/atmpending`
  - `/atmverify [atmNumber]` (in game, the number is optional if standing beside the pending ATM)
  - `/atmreject <atmNumber>`
- Client ATM reports are distance-checked against the server-known player position and rate-limited.

## Transaction safety

- Added non-blocking per-account and per-ATM operation locks.
- Character-ID transfers lock both sender and recipient character accounts in a deterministic order.
- ATM purchase locks the player account, owner slot and ATM.
- ATM earnings withdrawal and ATM sale lock the relevant account/ATM before mutation.
- Admin ATM ownership/state mutations respect the same ATM locks.
- Purchase uses a conditional SQL claim before debit and rolls ownership back if debit fails.
- Earnings withdrawal clears the exact persisted business balance first, then credits the player; failed credit restores the earnings.
- ATM sale clears ownership first, then pays the owner; failed payout restores the previous owner state.
- Cross-character transfers use sender debit + recipient credit with compensating sender refund if recipient credit fails.
- Any compensation failure is marked `recovery_required` and logged with a transaction reference instead of being silently ignored.

## Transaction IDs and audit journal

- Added transaction references such as `CB-XFR-...`, `CB-WDR-...`, `CB-BUYATM-...`.
- Added `transaction_id` and `fee_amount` to `bank_transactions`.
- Added `cm_bank_operation_journal` with `started`, `committed`, `rolled_back`, and `recovery_required` states.
- Sender/recipient ledger rows for a transfer share the same transaction reference.
- Recent activity UI now shows transaction references; withdrawals also show their actual fee.

## Startup/readiness

- Database schema setup, settings load, ATM cache load, teller load and branch seeding are now one ordered initialization sequence.
- Banking remains fail-closed until initialization completes.
- Client ATM/teller sync waits for readiness instead of receiving a partially loaded cache.

## ATM fee rules

- Unowned ATM withdrawal fee: **2%** by default (`Ownership.unownedFeePercent`).
- Owned ATM selectable withdrawal fees: **1%, 2%, 3%, 4%**.
- ATM owner using their own ATM: **0%** withdrawal fee.
- Teller withdrawal: **0%** ATM fee.
- Character-ID transfer fee remains controlled separately by `Limits.transferFeePercent` (default `0`).

## Database migration

`sql/005_security_transactions_v1.4.0.sql` documents the v1.4 schema changes. The resource also self-ensures the required schema at startup.

## Recommended test checklist

1. Restart `cm-bank` and confirm the server reports v1.4 ready with no DB error.
2. Stand nowhere near a teller/verified ATM and manually trigger deposit/withdraw/transfer events; all must be rejected.
3. Use a bank teller: deposit, withdraw and Character-ID transfer should work; ATM withdrawal fee must be 0%.
4. Use an unowned verified ATM: withdrawal should charge 2%; deposit and transfer should not charge ATM-owner fees.
5. Buy a verified ATM and test each owner fee button: 1%, 2%, 3%, 4%.
6. Withdraw from that ATM using another character and confirm the fee enters `pending_earnings` exactly once.
7. Withdraw ATM earnings twice quickly; only one request should succeed.
8. Attempt two simultaneous purchases of one ATM; only one character should acquire it/pay.
9. Sell an ATM and confirm ownership, pending earnings and payout are consistent after resource restart.
10. Transfer to an online Character ID and verify sender/recipient history share one `CB-XFR-...` reference.
11. Discover a brand-new ATM coordinate: it must not work until `/atmverify` approves it.
12. Run `/atmpending`, `/atmverify`, `/atmreject`, and confirm unverified ATM coordinates never become usable automatically.
