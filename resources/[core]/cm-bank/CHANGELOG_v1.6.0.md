# cm-bank v1.6.0 — ATM Business & Cash Reserve System

## Files changed

- `fxmanifest.lua` — version bumped to `1.6.0`.
- `shared/config.lua` — added `Config.ATMBusiness` and `Config.PublicATM`.
- `server/main.lua` — cash-reserve helpers, rewritten deposit/withdraw flows,
  new `restockAtm`/`fetchAtmAnalytics`/`fetchAtmHistory` events, rewritten
  `buyAtm`/`sellAtm` reserve accounting, a server-only public-ATM restock
  timer, ATM business activity logging, low-cash owner notification.
- `client/main.lua` — three new NUI callback bridges (`restockAtm`,
  `fetchAtmAnalytics`, `fetchAtmHistory`), three new server→NUI event
  forwards, and an `atmNotice` handler reusing the existing `notify()` helper.
- `ui/index.html` — cash-reserve bar + status badge + restock UI on the
  owner panel, capacity/starting-reserve rows on the purchase panel, a new
  ATM Business modal (analytics + paginated history).
- `ui/app.js` — reserve/status rendering, restock confirm flow, business
  analytics/history rendering and pagination, NUI-close state reset.
- `ui/style.css` — reserve bar, status badge, and business-metrics styling
  (existing cyan/blue palette, no `backdrop-filter`).
- `sql/007_atm_business_v1.6.0.sql` — new migration (see below).
- No other resource was modified.

## SQL changes (`sql/007_atm_business_v1.6.0.sql`)

- `bank_atm_locations.cash_reserve` (`INT DEFAULT 0`) — physical cash
  currently in the machine.
- `bank_atm_locations.cash_capacity` (`INT DEFAULT 0`) — per-ATM capacity;
  `0` is a one-time "never initialized" sentinel that `server/main.lua`
  replaces on first boot after migration (100000 for an owned ATM, a full
  250000 for a public one) and can never re-trigger once a real value is set.
- `bank_atm_locations.owner_reserve_contribution` (`INT DEFAULT 0`) — cash
  the current owner has personally restocked (see the sale formula below).
- New table `bank_atm_activity` — ATM-scoped business history/analytics,
  indexed on `(atm_id, created_at)`.
- Nothing is dropped, no history/ownership/pending-earnings/verified data is
  touched. Safe to run repeatedly.

## Cash-reserve architecture

Every ATM (owned or public) now has `cash_reserve` / `cash_capacity`.
Withdrawals consume `cash_reserve` by the *dispensed amount only* — the
withdrawal fee is untouched and still flows straight to
`pending_earnings`, exactly as in v1.4/v1.5. Deposits and owner restocks add
to `cash_reserve`, capped at `cash_capacity` (excess never overflows and
never fails the underlying bank deposit — see below).

- **Owned ATMs**: always reserve-limited. Never infinite.
- **Public/unowned ATMs**: reserve-limited by default, topped up by a
  server-only timer (`Config.PublicATM.automaticRestock`, every 5 minutes,
  never triggered by a client event) whenever a machine drops below
  `restockThreshold`. `Config.PublicATM.infiniteCash = true` (or
  `useCashReserve = false`) is available as a simpler escape hatch that skips
  reserve tracking for public ATMs entirely — owned ATMs can never use it.
- **Tellers**: never reserve-limited (no physical machine).

Concurrency: an ATM withdrawal claims its reserve via an atomic
compare-and-set UPDATE (`cash_reserve = cash_reserve - ? WHERE cash_reserve
>= ?`) *before* touching any player money, under the same `atm:<id>`
operation lock v1.4 already used for withdrawals. Two simultaneous
withdrawals against the last $5,000 can never both succeed — whichever
loses the lock gets "busy," and in the rarer case the compare-and-set itself
fails (a race the lock didn't already catch), the request fails cleanly with
"This ATM no longer has enough cash." before any player money moves. Every
rollback path (bank-debit failure, cash-credit failure) refunds a claimed
reserve amount before returning.

## Deposit reserve behavior

Deposits are never blocked or reversed by ATM capacity. The bank deposit
always succeeds first; only afterward does a best-effort, capped
contribution add to `cash_reserve` (`min(depositAmount, capacity -
reserve)`). If a $10,000 deposit happens at a machine with $2,000 of room
left, the deposit still fully succeeds and the player's bank balance
increases by $10,000 — the ATM's reserve only gains the $2,000 it had room
for. No money is created or destroyed by this process.

## ATM withdrawal flow (order of operations)

1. Pre-check reserve (informational, in-memory).
2. Begin operation journal entry.
3. **Claim the physical reserve first** (compare-and-set) — the contended
   resource, claimed before any player money moves.
4. Debit player bank.
5. Credit player cash.
6. Accrue the fee into the owner's `pending_earnings` (unchanged from v1.5).
7. Record the transaction, journal, and (for owned ATMs) the business
   activity row; notify the owner only if reserve status just got worse.

Any failure after step 3 refunds the claimed reserve before rolling back.
Any state that can't be safely unwound is marked `recovery_required` with
the transaction reference, logged via `adminLog`, and never silently
continued — matching the v1.4/v1.5 recovery architecture exactly.

## Owner-contribution accounting & ATM sale formula

Three distinct pools exist on every owned ATM, and they are never conflated:

1. **Government starting reserve** — set on purchase
   (`Config.ATMBusiness.purchaseStartingReserve`, default $25,000), not
   owner property.
2. **Player-deposited / public liquidity** — added to `cash_reserve` by
   deposits or the public auto-restock timer, not owner property.
3. **Owner-contributed reserve** (`owner_reserve_contribution`) — increases
   only when the *owner* restocks with their own cash via `restockAtm`.

On sale, the payout is:

```
payout = governmentBaseValue (purchasePrice * governmentSellPercent / 100)
       + pendingEarnings
       + recoverableContribution
```

where `recoverableContribution = min(owner_reserve_contribution,
cash_reserve)` — the owner is paid back for their own restocked cash, but
never more than they personally contributed, and never more than is
physically still in the machine (withdrawals since the last restock reduce
what's recoverable). Player deposits and the government starting reserve are
excluded from this term entirely, so `buy ATM -> receive player deposits ->
sell ATM` cannot convert public liquidity into owner profit. The recovered
amount is subtracted from `cash_reserve` (the owner takes their cash out);
whatever remains stays with the machine as it reverts to public. Buying an
ATM always resets `cash_reserve` to `purchaseStartingReserve` and
`owner_reserve_contribution` to `0` — a public machine's existing balance is
never inherited by a buyer (closes the "deposit into a public ATM then
immediately buy it" exploit).

## New UI

- Owner panel: reserve status badge (Operational/Low Cash/Critical
  Cash/Out of Cash), a reserve bar (`$X / $Y`, percentage), a Restock ATM
  control (inline amount input, confirmed through the existing confirm
  modal, debited from **cash** not bank), and a "View Business History"
  button.
- Purchase panel: shows Cash Capacity and Starting Reserve alongside the
  existing purchase price and fee choices.
- New ATM Business modal: Today / Last 7 Days / All Time analytics
  (transactions, withdrawal/deposit counts, cash withdrawn/deposited, fee
  revenue, average withdrawal — all from one aggregate SQL query per
  range/open, never per-frame) plus a 20-per-page paginated business history
  showing Character ID only (never a name) for the counterparty.
- Reserve status is also surfaced on the shared ATM status badge for every
  visitor (not just the owner) since "will my withdrawal work" is
  operational information, not private owner finance — pending earnings and
  owner-contribution figures remain owner-only.

## New network events

- `cm-bank:server:restockAtm(amount)` / `cm-bank:client:actionResult`
  (action `restockAtm`).
- `cm-bank:server:fetchAtmAnalytics(range)` →
  `cm-bank:client:atmAnalyticsResult`.
- `cm-bank:server:fetchAtmHistory({page})` →
  `cm-bank:client:atmHistoryResult`.
- `cm-bank:client:atmNotice(message)` — low-cash notification to an online
  owner, reusing the existing `notify()` client helper (no new notification
  system).
- New transaction-ID prefixes: `CB-ATMRESTOCK-...` (owner restock,
  `kind = 'atm_restock'` in `bank_transactions`). Reuses the existing
  `newTransactionId`/operation-journal architecture unchanged — no new
  reference system.

## Security changes

- Every ATM-business write (`restockAtm`) validates, in this order: bank
  ready → character loaded → ATM exists & is the one physically nearby
  (`currentAtmForPlayer`, re-resolved fresh inside the lock) → ATM verified
  (implicit in `currentAtmForPlayer`, which only matches verified machines)
  → not disabled → ownership → amount is a valid positive integer → owner
  has enough cash → remaining capacity → operation-locked (`money:<charId>`
  + `atm:<id>`) → server-minted, journal-unique transaction reference.
- `fetchAtmAnalytics`/`fetchAtmHistory` are read-only but still require
  proximity + ownership (resolved server-side, never trusting a
  client-claimed ATM ID) so business figures can't be scraped remotely.
- Never trusted from NUI: reserve, capacity, status, fee, owner, purchase
  price, sale price, coordinates, or transaction reference — every one of
  these is server-computed and sent to the client only for display.
- `claimAtmReserve`/`contributeAtmReserve` are compare-and-set/capacity-
  clamped SQL updates — negative reserve and over-capacity reserve are both
  structurally impossible, not just checked in Lua.
- Locks are released on every path via the existing `runLocked` pcall
  wrapper (unchanged from v1.4/v1.5); every new failure branch that claimed
  a reserve amount refunds it before returning.

## Compatibility

- All v1.4/v1.5 events, exports, transaction references, statements
  (pagination/filters/search), offline transfers + notes, daily transfer
  cap, transfer cooldown, ATM discovery/verification, teller flows, and
  dashboard totals are unchanged and still function exactly as before.
- No existing event was renamed; only new events were added.
- `Config.Limits`/`Config.TransferLimits`/`Config.TransferSecurity` from
  v1.5 are untouched.

## Manual testing checklist

- [ ] `luac -p` passes on all changed Lua files; `node --check` passes on
      `ui/app.js`.
- [ ] Resource restarts cleanly; `bankReady` reaches `true`; migration
      backfills capacity/reserve for pre-existing owned and public ATMs.
- [ ] Withdraw $5,000 from a $50,000/$100,000-capacity owned ATM → reserve
      becomes $45,000; deposit $10,000 → reserve becomes $55,000.
- [ ] Withdraw more than the reserve holds → rejected, exact "Available ATM
      cash: $X" message, no bank debit, no earnings change, no reserve change.
- [ ] Two players withdraw the last $5,000 simultaneously → exactly one
      succeeds, reserve never goes negative.
- [ ] Test all four fee choices (1/2/3/4%) on a $10,000 withdrawal; verify
      fee amounts ($100/$200/$300/$400), reserve reduction equals the
      dispensed amount (not amount+fee), and pending earnings increase by
      the fee only.
- [ ] Restock: sufficient cash, insufficient cash, zero/negative amount,
      amount above remaining capacity, double-click, owner leaves the ATM
      mid-confirmation, non-owner attempting the event manually.
- [ ] Deposit into a near-full ATM ($98,000/$100,000 + $10,000 deposit) →
      bank receives the full $10,000, reserve caps at $100,000, no
      duplication.
- [ ] Sell an ATM that has government starting reserve, owner-contributed
      restock cash, player-deposited cash, and pending earnings all mixed
      together — confirm the payout matches
      `governmentValue + pendingEarnings + min(contribution, reserve)`
      exactly, and that deposited/public cash is never paid to the owner.
- [ ] Regression: online/offline Character ID transfers, transfer notes,
      daily cap, transfer cooldown, statements + filters, teller
      deposit/withdraw/transfer, verified/unverified ATM, fake ATM report,
      ATM purchase/fee-change/earnings-withdraw/sale, admin ATM commands,
      startup failure, resource restart.
