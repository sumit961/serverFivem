# cm-bank v1.8.0 — Banking Polish, ATM Business Improvements & Final Security Pass

## Scope

This release is **polish, not a redesign**. Every system already built in
v1.4-v1.7 (deposit, withdraw, Character ID transfer, saved payees, ATM
ownership/business, statements, financial dashboard) keeps its existing
UI structure and existing behavior. Nothing here is a new feature category
— it makes the existing systems feel more complete, clearer, and safer.

## Abandoned "Payment Requests" feature — fully removed

An earlier, unreleased v1.8 development pass began a Request Money /
Payment Request system (`bank_payment_requests`, `request_reference`,
`CB-REQ-` references, five request-lifecycle events, a Requests tab/modal
in the NUI). **This feature is not part of v1.8.0.** All of the unfinished
work for it has been cleanly removed:

- `shared/config.lua` — `Config.PaymentRequests` block removed entirely.
- `server/main.lua` — the `bank_payment_requests` table-creation block, the
  boot-time stale-`processing`-row recovery pass, the periodic expiry
  thread, and all five `RegisterNetEvent` request handlers removed;
  `request_reference` dropped from `bank_transactions`/
  `bank_pending_transfers` write paths and from `fetchStatements`; the
  temporarily-introduced `performCharacterTransfer` helper (which existed
  only to be shared with the request-acceptance path) was reverted back
  into a single self-contained `cm-bank:server:transfer` handler, matching
  v1.7 structure exactly.
- `client/main.lua` — the five request NUI callback bridges and three
  request server→client forwards removed.
- `ui/index.html` / `ui/style.css` / `ui/app.js` — the Requests tab,
  `#requestsPanel`, `#requestMoneyModal`, and all request-specific styling
  and state removed.
- **No database table was dropped.** If `bank_payment_requests` already
  exists in a live database from the interrupted prior work, it is left
  alone — see `sql/009_banking_polish_v1.8.0.sql` for a manual, optional
  cleanup snippet. cm-bank has zero runtime code that reads or writes it.

Confirmed via full-resource grep: zero references to
`PaymentRequest`/`payment_request`/`CB-REQ`/`request_reference` remain
anywhere in `cm-bank`, and the plain English word "request" only appears
in unrelated, legitimate contexts (recipient lookup requests, generic
error toasts).

## Files changed

- `fxmanifest.lua` — version bumped to `1.8.0`.
- `shared/config.lua` — `Config.PaymentRequests` removed; no other change.
- `server/main.lua` — payment-request removal (above); numeric-safety
  hardening (`sanitizeAmount`); recent-payees query
  (`fetchRecentPayees`); access-context teller name threading; ATM
  reserve-recovery owner notification (`notifyOwnerIfReserveRecovered`);
  ATM analytics extended with current reserve + reserve utilisation %;
  standardized `recovery_required` player-facing messaging.
- `client/main.lua` — payment-request removal (above); `atmNotice` now
  accepts a notification-kind argument (success/error) so the new
  reserve-recovery notice can render as a positive toast instead of an
  error.
- `ui/index.html` — Requests UI removed; new access-context header;
  recent-payees chip row; live comma-formatted amount preview; quick
  amount buttons redesigned as fixed dollar increments + MAX; a
  session-remembered "last amount" chip; ATM restock MAX button; ATM fee
  example copy.
- `ui/app.js` — payment-request removal (above); access-context
  rendering; recent-payees chips; comma-formatted live amount preview;
  redesigned quick-amount buttons (+$1,000/+$5,000/+$10,000/+$50,000/MAX,
  server-authoritative MAX derived from cash/bank/ATM reserve, never a
  client-invented limit); last-amount memory for deposit/withdraw
  (session-only, never persisted, never restored across a character
  change, never auto-submits); copyable transaction reference on receipts
  and transaction details (clipboard, with a visible selectable-text
  fallback); ATM restock MAX button; ATM sale-warning copy clarified;
  ATM fee-choice example text; **Enter-key support** on the active
  deposit/withdraw/transfer form (submits only when not already
  submitting, never fires twice on a held key); **double-submit
  protection** added to payee Add/Rename/Favourite/Delete (these post
  through a fire-and-forget NUI callback, so the guard spans until the
  server's `payeesResult` reply, not just the initial callback).
- `ui/style.css` — access-context header styling; quick-amount button
  layout (5-across); last-amount chip; live amount preview text. Existing
  CM cyan/blue palette kept throughout; no `backdrop-filter` used.
- `sql/009_banking_polish_v1.8.0.sql` — new migration file. Contains no
  schema changes (documented, not silently omitted) plus the
  payment-request cleanup note above.
- No other resource was modified.

## SQL changes (`sql/009_banking_polish_v1.8.0.sql`)

None. v1.8.0 requires no destructive schema changes — recent payees, the
access-context header, and ATM reserve utilisation are all computed from
existing `bank_transactions`/`bank_atm_locations`/`bank_saved_payees`
columns at query time. The file exists purely to document that and to
record the optional, manual, non-destructive cleanup path for a
leftover `bank_payment_requests` table if one exists.

## Numeric safety (technical, not a gameplay limit)

`sanitizeAmount()` rejects NaN, Infinity, negative values, and clamps to
a `SAFE_MAX_AMOUNT` of 2,000,000,000 before any amount reaches balance
math — applied to every amount/Character-ID-shaped input from the NUI
(deposit, withdraw, transfer amount + target, ATM restock, payee
add/rename/favourite/delete, recipient lookup). This is the same
gameplay-unlimited model from v1.7 — it stops overflow/decimal/
scientific-notation abuse, it does not introduce a transaction cap.

## Amount entry & previews

- Quick amount buttons are now fixed dollar increments
  (+$1,000/+$5,000/+$10,000/+$50,000) plus a MAX button, replacing the old
  percentage-of-something buttons. MAX is computed per tab:
  deposit = cash on hand; withdraw = bank balance, further capped by ATM
  reserve when at an unowned/other-owned ATM; transfer = bank balance.
- A "Use last amount" chip appears after your first deposit or withdrawal
  this session, letting you repeat the same amount in one click. It is
  session memory only — never written to disk, never restored after a
  character switch, never submits by itself.
- The amount input gets a live, read-only comma-formatted preview
  underneath it as you type (the actual `<input type="number">` element
  itself is untouched, so no risk of corrupting what you're typing).
- **Withdrawal fee model is unchanged from v1.4-v1.7 by deliberate
  decision**: the typed amount is always the bank debit; the fee is
  subtracted from it to produce the cash you receive. No server money-math
  changed in this release.

## Access context header

The panel header now states plainly where you are: a teller shows
"CM BANK — <Teller Name> — Full Service — No withdrawal fee"; an ATM shows
"ATM #N — X% withdrawal fee — <status>" (or "No fee for you" if you own
it). A "YOUR ATM" badge appears only to the owner, only on their own
machine — no other player's ownership, contact, or reserve is ever shown
beyond what v1.7 already displayed generically.

## Recent payees & saved payees

- The Transfer tab now shows up to 5 recent unique recipients (most
  recent transfer to each), pulled from existing `bank_transactions`
  history via a portable self-join query (no window functions, so it
  works on older MariaDB/MySQL) — no new table. Clicking one only
  pre-fills the Character ID, exactly like an existing saved-payee chip.
- Saved payee add/rename/favourite/delete now disable their buttons while
  a request is in flight and re-enable on the server's reply, preventing
  a double-click from firing the same mutation twice.

## ATM owner improvements

- ATM analytics now also reports current reserve and reserve utilisation
  percentage, alongside the existing Today/7 Days/All Time figures.
- Restock gets a MAX button: client suggests
  `min(your cash, remaining ATM capacity)`; the server independently
  recalculates and is the only source of truth for what actually gets
  deposited.
- When an ATM's reserve recovers from Low/Critical/Out of Cash back to
  Operational, the owner now gets a one-time "ATM #N is operational
  again." notification (mirroring the existing low-cash warning, which
  already fired once per threshold transition and still does).
- Fee-choice buttons now show a worked example ("At 2%: $1,000 withdrawal
  = $20 fee") next to the existing fixed 1/2/3/4% choices — explanation
  only, the fee logic itself is unchanged.
- The sale confirmation now spells out in one message that selling is
  permanent and that pending earnings + recoverable contribution are
  included in the payout shown below, replacing a terser prior notice.

## Receipts & transaction details

Reference numbers on receipts and transaction-detail views now have a
Copy button (clipboard write with a visible selectable-text fallback for
environments without clipboard access) instead of only being shown as
plain text.

## Keyboard UX

- **Enter** now submits the active deposit/withdraw/transfer form when
  focus is in the amount/target/note field — guarded against firing twice
  on a held key (`event.repeat`) and against firing while a submission is
  already in flight (respects the existing `submitting`/disabled state on
  the submit button).
- **Escape** behavior is unchanged and was already correct: it closes the
  topmost open modal first (statements/ATM business/transaction
  detail/receipt/large-transfer/confirm), and only closes the whole panel
  once no modal is open.

## Security / recovery visibility

- Every `recovery_required` outcome across withdraw, transfer (online and
  offline-pending), ATM restock, ATM earnings withdrawal, and ATM sale now
  returns the same standardized player-facing message: *"The banking
  operation could not be completed safely. Reference: CB-...".* Previously
  each path had its own slightly different phrasing. The reference is
  real and traceable through `cm_bank_operation_journal`; no internal
  failure reason is ever exposed to the player (that detail stays in
  `adminLog`/cm-admin only).
- Re-confirmed zero `innerHTML`/`outerHTML`/`insertAdjacentHTML` usage
  anywhere in `ui/app.js` — every user-influenced value (payee nickname,
  transfer note, transaction description, recipient name, recent-payee
  entries, copyable references) is rendered via `textContent`/
  `document.createElement` only.
- Re-confirmed the ATM cache-vs-database consistency pattern used
  throughout v1.6/v1.7 is unchanged and was not weakened by any v1.8.0
  addition: every mutation path (withdraw, restock, fee change, earnings
  withdrawal, purchase, sale) only updates the in-memory ATM cache after
  its corresponding DB write reports success; a failed write is either
  refunded/rolled back or explicitly marked `recovery_required` and
  logged, never silently treated as if it had committed.
- Re-confirmed non-owner ATM customers never see an exact cash-reserve
  number — only the generic Operational/Low Cash/Critical/Out of Cash
  status — except in the existing insufficient-reserve rejection message,
  which has always named the exact amount available for that specific
  withdrawal attempt (unchanged from v1.6/v1.7, and required so the
  player knows what amount would actually succeed).

## Compatibility

Preserved and unregressed: deposit, withdraw, Character ID transfer
(fully server-authoritative), offline transfer + idempotent delivery,
transfer notes, saved payees, favourite payees, quick transfer, large
transfer warning, receipts, unlimited transaction amounts, statements
(pagination/filters/date filters/search/details), the financial
dashboard, the operation journal + transaction references, ATM discovery/
verification/ownership/purchase/sale, the fixed 1/2/3/4% ATM fees, ATM
reserve/capacity/restock/owner contribution/earnings/analytics/business
history, public ATM auto-restock (`Config.PublicATM.infiniteCash`
untouched; owned ATMs are never infinite), ATM admin controls, tellers,
fail-closed startup readiness, and cm-admin logging. No existing network
event was renamed; only new events/fields were added. No transaction
amount limit, scheduled/recurring payment, card/PIN system, loan,
interest, or overdraft was introduced — none of those exist in cm-bank.

## Manual testing checklist

- [ ] `luac -p` passes on `server/main.lua`, `client/main.lua`,
      `shared/config.lua`; `node --check` passes on `ui/app.js`.
- [ ] Deposit $1, $10,000, $500,000, $1,000,000+, and MAX — all succeed,
      none rejected for being "too large."
- [ ] Withdraw at a teller (large amount, MAX) and at an ATM (sufficient
      reserve, insufficient reserve — exact available amount shown, MAX,
      each of the 1/2/3/4% fees) — MAX correctly reflects the preserved
      fee model (typed amount is the bank debit, fee only reduces cash
      received).
- [ ] Transfer online, offline, via a saved payee, via a recent-payee
      chip, $1, $100,000, $1,000,000+, the large-transfer warning at
      threshold, double-submit (only one transfer should occur), an
      invalid Character ID, and your own Character ID.
- [ ] Payees: add, rename, favourite, unfavourite, delete, quick-transfer
      from a chip, click a recent-payee chip, and a nickname containing
      `<script>`/HTML (must render as inert plain text everywhere) —
      confirm the button being clicked visibly disables until the
      server responds and a rapid double-click never double-fires.
- [ ] Statements: pagination, filters, date filters, search by Character
      ID/reference/note, transaction details, copy-reference button
      (falls back to selectable text if clipboard is unavailable).
- [ ] ATM owner: purchase, each fee tier, restock (including MAX),
      withdraw earnings, analytics (confirm reserve/utilisation figures),
      business history, low-cash/critical/out-of-cash warnings (each
      fires once, not every transaction), the operational-recovery
      notice (fires once on recovery), and sale (payout formula
      unchanged, one clear confirmation).
- [ ] ATM reserve race: set a $5,000 reserve, fire two simultaneous
      $5,000 withdrawal requests, confirm exactly one succeeds and the
      reserve never goes negative.
- [ ] Cache consistency: after withdraw/deposit/restock/fee-change/
      earnings-withdrawal/purchase/sale, confirm the NUI's displayed ATM
      state always matches the database.
- [ ] Offline transfer: send to an offline recipient, have them reconnect,
      confirm the credit is delivered exactly once.
- [ ] Keyboard: Enter submits the active form once (not twice on a held
      key); Escape closes a modal first, then the panel; Tab moves
      through inputs normally.
- [ ] Confirm zero active Request Money / Payment Request UI, server
      events, or NUI state anywhere in the resource (search for
      `request money`, `payment request`, `CB-REQ`, `fetchRequests`,
      `acceptRequest`, `declineRequest`, `bank_payment_requests` — all
      should return nothing except this changelog and the SQL migration's
      documentation comment).
- [ ] Confirm no other resource's files changed
      (`git status` outside `resources/[core]/cm-bank/`).
