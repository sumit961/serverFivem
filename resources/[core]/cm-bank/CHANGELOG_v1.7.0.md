# cm-bank v1.7.0 — Saved Payees, Banking UX & Financial Overview

## The deliberate behavioral change

**Gameplay transaction amount limits are removed.** cm-bank is a FiveM
gameplay banking system, not a realistic banking simulator. A player may
now deposit, withdraw, or transfer any amount, constrained only by:

- **Deposit**: the player actually has that much cash.
- **Withdrawal**: the player has that much bank balance, and — at an ATM —
  the ATM's physical cash reserve (unchanged from v1.6, still the only real
  ATM-side constraint).
- **Transfer**: the sender has that much bank balance, and the recipient
  Character ID is valid.

There is no longer a maximum deposit, maximum withdrawal, maximum transfer,
or daily/weekly/monthly transfer cap. Anti-spam protections (cooldowns,
per-minute rate limiting, operation locks, replay protection) are **not**
amount limits and are fully preserved — see Security below.

## Files changed

- `fxmanifest.lua` — version bumped to `1.7.0`.
- `shared/config.lua` — removed `Limits.maxDeposit/maxWithdraw/maxTransfer`
  and `TransferLimits.maximumPerTransfer/dailyLimit`; added
  `TransferSecurity.largeTransferWarning` and `Config.Payees`.
- `server/main.lua` — removed all amount-cap checks from deposit/withdraw/
  transfer; removed the now-dead `transferredTodayTotal`; added saved-payee
  CRUD events, statement date-range filtering, This Month + Monthly
  Transfers aggregate queries, and a nickname sanitizer.
- `client/main.lua` — five new NUI callback bridges for payee CRUD, one new
  server→client forward (`payeesResult`), `dateRange` threaded through the
  statements callback.
- `ui/index.html` — new Payees tab/panel, Quick Transfer chips on the
  Transfer tab, Financial Summary section (This Month / Cash Flow /
  Monthly Transfers), Large Transfer / Receipt / Transaction Detail modals,
  statement date-range filter row, itemized breakdown container on the
  confirm modal (buy/sell ATM previews).
- `ui/app.js` — payee rendering/CRUD (inline rename, never `window.prompt`,
  which doesn't work in FiveM's NUI), quick-transfer prefill (never
  auto-submits), large-transfer confirmation step, post-action receipts,
  clickable statement rows opening transaction details, financial-summary
  rendering, buy/sell ATM itemized confirm previews.
- `ui/style.css` — styling for all of the above (existing cyan/blue
  palette, no `backdrop-filter`).
- `sql/008_saved_payees_financial_ux_v1.7.0.sql` — new migration.
- No other resource was modified.

## SQL changes (`sql/008_saved_payees_financial_ux_v1.7.0.sql`)

- New table `bank_saved_payees` (`owner_character_id`,
  `recipient_character_id`, `nickname`, `is_favourite`, `created_at`,
  `updated_at`), with `UNIQUE(owner_character_id, recipient_character_id)`
  preventing a duplicate saved payee at the database level, and an index on
  `(owner_character_id, is_favourite)` for the favourites/quick-transfer
  query. `CREATE TABLE IF NOT EXISTS`; nothing else is touched, no
  transaction or ATM data is deleted.

## Saved Payees

- Store a personal `nickname` + `is_favourite` flag over an existing
  `recipient_character_id`. The nickname is cosmetic only — every transfer
  still resolves and debits/credits by Character ID, exactly as v1.4-v1.6.
- Server validates on every mutation: bank ready, character loaded,
  recipient Character ID exists (reuses `resolveCharacterIdentity`), not
  your own Character ID, nickname non-empty and sanitized (control
  characters stripped, capped at `Config.Payees.nicknameMaxLength`),
  `maxPayees`/`maxFavourites` enforced, and ownership checked on every
  rename/favourite/delete (`WHERE id = ? AND owner_character_id = ?`).
- The Character ID cannot be edited on an existing payee — the UI only
  offers delete-and-re-add, per spec.
- Quick Transfer: favourite payees appear as chips at the top of the
  Transfer tab (and are reachable from the ATM transfer UI, not just
  tellers). Selecting one only pre-fills the Character ID field — it never
  submits a transfer. The normal server-side recipient lookup and
  confirmation dialog still run afterward.
- Full payee management (add/rename/favourite/delete) lives on a
  teller-only "Payees" tab, hidden while at an ATM; Quick Transfer chips
  remain available at both.

## Receipts

Deposit, withdrawal, and transfer now show a dedicated receipt screen
instead of only a toast (built entirely from data the server already
returns — no new server round-trip): deposited/withdrawn/transferred
amount, fee, resulting total, new bank balance where relevant, and the
transaction reference. Transfer receipts include the note (read from the
NUI's own input, never echoed back by the server) and a "Transfer Again"
button that pre-fills the same Character ID — it never resubmits
automatically.

## Large Transfer confirmation

`Config.TransferSecurity.largeTransferWarning` (default $100,000) shows an
extra "please verify the recipient" step before the normal transfer
confirmation for transfers at or above the threshold. This is purely a
client-side UX nudge — it never rejects or reduces a transfer, and setting
it to `0` disables it entirely. The server has no knowledge of this
threshold and never enforces it.

## Statements & transaction details

- New date filter: Today / Last 7 Days / Last 30 Days / This Month /
  All Time, applied server-side via a fixed literal SQL fragment selected
  from an internal map (never interpolated from client input) — stays just
  as parameterized-safe as the existing kind filter and search.
- Statement rows now show the amount on the header line (right-aligned,
  signed) next to the transaction type, with note/description shown
  inline and clutter (redundant Amount/Fee/Total lines) trimmed.
- Clicking a row opens a Transaction Details view built entirely from that
  row's already-fetched data (Character ID, amount, fee, total, note,
  reference, date, time) — no per-click query. Never shows server ID,
  database row ID, lock state, or journal internals.

## Financial dashboard

- "This Month" tile (Money In / Money Out / Fees Paid) alongside the
  existing "Today" tile, plus a Monthly Cash Flow figure and a Monthly
  Transfer Summary (sent/received counts and amounts) — all from small,
  targeted aggregate `SUM`/`COUNT` queries at panel-open time, never a full
  history scan. Only `completed` transactions count — `failed`,
  `rolled_back`, and `recovery_required` rows are excluded from every
  aggregate (Today, This Month, and Monthly Transfers alike; this also
  fixed a v1.6 gap where the Today tile didn't yet exclude
  `recovery_required`).
- Collapsed by default behind a "Financial Summary" toggle to keep the
  default dashboard uncluttered.

## ATM purchase/sale previews

- Buying an ATM now opens a confirm step (previously immediate) showing
  Price, Cash Capacity, Starting Reserve, and the fixed 1/2/3/4% fee
  options, all server-provided.
- Selling now shows itemized rows — Government Value, Pending Earnings,
  Recoverable Owner Contribution, and TOTAL PAYOUT — using the unchanged
  v1.6 formula: `governmentValue + pendingEarnings +
  min(ownerContribution, currentReserve)`. Player-deposited reserve and the
  government starting reserve still can never become owner profit.

## Security

- **No amount limits were security controls, so none of their removal
  affects security.** Everything that WAS a security/anti-abuse control is
  unchanged: `Config.Security.actionCooldownMs`/`transferCooldownMs`,
  `Config.TransferSecurity.cooldownMs`/`maxTransfersPerMinute`
  (server-side sliding window), server-minted transaction references with
  UNIQUE journal constraints (replay-proof), `runLocked` operation locks
  (`money:<charId>`, `atm:<id>`), proximity/ownership re-validation inside
  every lock, and fail-closed `bankReady` gating.
- Character ID transfers remain fully server-authoritative: recipient
  existence, self-transfer rejection, balance checks, debit/credit,
  offline delivery, and the transaction reference are all resolved and
  enforced server-side — never trusted from NUI.
- ATM reserve remains fully server-authoritative and is now the *only*
  meaningful constraint on withdrawal size at an ATM: claimed via the same
  v1.6 compare-and-set (`cash_reserve >= ?`), under the same `atm:<id>`
  lock, with the same refund-on-failure paths.
- Payee mutations validate ownership server-side on every single request
  (never trust a client-supplied `owner_character_id`) and are rate-limited
  via the existing lightweight cooldown table.
- XSS: audited every user-controlled value rendered in the NUI — payee
  nickname, transfer note, transaction description/note — confirmed all
  are assigned via `textContent`/`document.createElement`, never
  `innerHTML` (a full search of `ui/app.js` for `innerHTML` returns zero
  matches). Nicknames are sanitized server-side the same way notes already
  were (control characters stripped, length-capped).

## Compatibility

Preserved and unregressed: deposit, withdraw, Character ID transfers,
offline transfers + notes, statements (pagination/filtering/search),
transaction references, the operation journal, ATM discovery/verification/
purchase/ownership, the fixed 1/2/3/4% ATM fees, ATM cash reserve/capacity,
owner restocking/contribution/analytics/history, ATM earnings, ATM sale,
public-ATM auto-restock, ATM disable/for-sale controls, tellers, fail-closed
startup readiness, and cm-admin logging. No existing network event was
renamed; only new events were added.

## Manual testing checklist

- [ ] `luac -p` passes on all changed Lua files; `node --check` passes on
      `ui/app.js`.
- [ ] Transfer $1, $10,000, $100,000 (large-transfer warning should
      appear), $500,000, and $1,000,000+ — all succeed with sufficient
      balance, none rejected for being "too large."
- [ ] Transfer to: a valid online Character ID, a valid offline Character
      ID, an invalid Character ID, your own Character ID, with insufficient
      balance, via double-click, via rapid repeated submission (rate
      limit should trigger), with a replayed/duplicate reference (should
      never double-charge).
- [ ] ATM withdrawal: $100,000 against a $150,000 reserve succeeds; the
      same withdrawal against a $50,000 reserve is rejected with the exact
      "not enough cash" / available-amount message, not a generic limit
      error.
- [ ] Saved payees: add, rename (inline edit, not a browser prompt),
      favourite, unfavourite, transfer via Quick Transfer chip (confirm it
      only pre-fills, never auto-submits), delete, invalid Character ID,
      own Character ID, duplicate Character ID, and a nickname containing
      `<script>`/HTML — confirm it renders as inert plain text everywhere
      (payee list, quick-transfer chip, receipts).
- [ ] Statements: each date-range filter, each kind filter, search by
      Character ID/reference/note, and click a row to confirm the
      transaction-detail view matches the row exactly with no internal
      fields exposed.
- [ ] Financial Summary toggle shows correct This Month / Cash Flow /
      Monthly Transfer figures matching manual transactions performed
      during testing.
- [ ] Regression: ATM 1/2/3/4% fees, concurrent withdrawal race (reserve
      never negative), owner restock, owner earnings withdrawal, ATM sale
      payout formula, ATM purchase preview, offline transfer delivery,
      statement pagination, startup with an intentionally broken DB
      connection (banking should stay unavailable, not partially enable).
- [ ] Confirm no other resource's files changed (`git status` outside
      `resources/[core]/cm-bank/`).
