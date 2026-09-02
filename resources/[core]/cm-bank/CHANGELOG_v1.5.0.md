# cm-bank v1.5.0 — Statements, Transfers & Banking UX

## Files changed

- `fxmanifest.lua` — version bumped to `1.5.0`.
- `shared/config.lua` — added `Config.TransferSecurity` and `Config.TransferLimits`.
- `server/main.lua` — schema additions, note sanitization, recipient lookup,
  offline transfer queue + delivery, transfer rate limiting + daily cap,
  paginated/filtered/searchable statements, today's dashboard aggregate.
- `client/main.lua` — passes the transfer note through, bridges two new NUI
  callbacks (`lookupRecipient`, `fetchStatements`) and two new server->client
  events (`recipientLookupResult`, `statementsResult`).
- `ui/index.html` — note field, Today In/Out/Fees tiles, expanded confirm
  modal (fee/note rows), new statements overlay (filters, search, pager).
- `ui/app.js` — confirm-first flow for deposit/withdraw/transfer, server-side
  recipient lookup before showing a transfer confirmation, statements
  rendering/pagination/filtering, full NUI-close/reopen state reset.
- `ui/style.css` — styling for the new tiles, statements overlay, and
  confirm-modal rows (existing cyan/blue palette, no `backdrop-filter`).
- `sql/006_statements_transfers_v1.5.0.sql` — new migration (see below).
- No other resource was modified. `cm-playerdata`, `cm-core`, `cm-admin` are
  untouched; cm-bank only *subscribes* to a `cm-playerdata` server event and
  reads (never writes) the `characters` table, exactly as v1.4 already did
  for offline owner-name lookups.

## SQL changes (`sql/006_statements_transfers_v1.5.0.sql`)

- `bank_transactions.status` (`VARCHAR(20) DEFAULT 'completed'`) — every
  pre-v1.5 row defaults to `completed`, which is accurate since only
  fully-committed operations were ever inserted.
- `bank_transactions.description` (`VARCHAR(120) NULL`) — sanitized transfer
  note.
- New indexes: `idx_transaction_id`, `idx_counterparty
  (counterparty_character_id, created_at)`, `idx_kind_created (kind,
  created_at)` — support the new statement filters/search without scanning
  full history.
- New table `bank_pending_transfers` — the offline-transfer queue (see
  below).
- All statements use `IF NOT EXISTS`; nothing is dropped or destructively
  altered. No transaction history is deleted. `server/main.lua` applies the
  same statements automatically at boot, so this file is safe to run by hand
  or skip.

## Security changes

- **Transfer rate limiting** (`Config.TransferSecurity`): a server-side
  sliding window (`maxTransfersPerMinute`, default 10) and a minimum
  cooldown (`cooldownMs`, default 1500ms) reject spam regardless of what the
  NUI submit button allows — enforced inside the same locked handler as the
  money movement, not just via a disabled button.
- **Transfer amount/day caps** (`Config.TransferLimits`): `minimum`,
  `maximumPerTransfer`, `dailyLimit` (default $1,000,000/day) are all
  config-driven, not hardcoded. The daily total is computed via an aggregate
  SQL query over today's `transfer_out` rows, excluding
  `rolled_back`/`failed` status — matching the spec's "successful outgoing
  transfers only" requirement. Exceeding it returns exactly "Daily transfer
  limit exceeded."
- **Recipient identity is never trusted from NUI.** A new
  `cm-bank:server:lookupRecipient` event resolves a Character ID's display
  name server-side (checking the online player first, falling back to the
  same read-only `characters` table query v1.4 already used for offline ATM
  owner names) before the transfer confirmation dialog shows anything. The
  transfer handler re-resolves this independently at execution time — the
  NUI-supplied name is never used to decide who gets paid.
- **Note sanitization.** `sanitizeNote()` strips all control characters
  (including newlines), collapses whitespace, and caps length at 120 chars
  server-side before storage. The NUI only ever assigns note/description
  text via `textContent`, never `innerHTML`, so stored notes cannot inject
  markup into any transaction row, statement row, or confirmation dialog.
- **All new SQL is parameterized.** The statement-search filter builds its
  `WHERE` clause from fixed literal fragments only; every user-supplied
  value (search term, Character ID, filter kind) is passed as a `?`
  placeholder, never concatenated into the query string.
- **Idempotency.** Every money-changing request still gets a single
  server-minted transaction ID (`newTransactionId`), inserted into the
  UNIQUE-constrained `cm_bank_operation_journal` — the client never supplies
  or can replay a reference. The offline-delivery path adds its own
  compare-and-set claim (`status: pending -> delivering`) so a duplicate
  `characterLoaded` fire can never credit the same pending transfer twice.
  All v1.4 locking (`money:<charId>` keys, ATM keys) is preserved unchanged;
  transfers still lock both the sender's and recipient's Character ID.
- **Startup gating preserved.** All new events (`lookupRecipient`,
  `fetchStatements`, the offline transfer path) check `bankReady` first and
  fail closed exactly like every v1.4 event.

## New statement features

- Full transaction history via `cm-bank:server:fetchStatements`, paginated
  20/page with total count, never sending the whole table at once.
- Filters: All / Deposits / Withdrawals / Transfers Sent / Transfers
  Received / ATM Earnings / ATM Purchase / ATM Sale — mapped 1:1 onto the
  existing `kind` values already used by every prior version
  (`deposit`, `withdraw`, `transfer_out`, `transfer_in`, `atm_purchase`,
  `atm_earnings`, `atm_sale`), so no historical row needs reclassifying.
  Search by transaction ID, Character ID, or note/description.
- Each row shows type, amount, fee, net total, counterparty Character ID +
  name, note, reference ID, status (when not `completed`), and date/time.
- Dashboard "Today" tile: Money In / Money Out / Fees Paid, computed via one
  aggregate SQL query per panel-open (not a full-history scan), and updated
  optimistically client-side after each successful action.

## Transfer changes

- Optional note (~120 chars), sanitized server-side, threaded through the
  confirm dialog and stored on both legs of an online transfer (and the
  sender's leg of an offline one).
- Confirmation dialog now always appears before deposit, withdrawal, *and*
  transfer submission (previously only transfers above a threshold showed
  one), each showing the exact breakdown (amount / fee / total), with
  deposits explicitly showing "Fee: $0" since deposits never carry an
  ATM-owner fee. For transfers, the dialog shows the server-resolved
  recipient name and Character ID, never a client-guessed name.
- Withdrawal ATM-fee display distinguishes "ATM #N (Your ATM)" / "ATM #N
  (Owned ATM)" / "ATM #N (Public ATM)" / "Bank Teller", sourced from the
  server-provided access context (never inferred from client coordinates).
- Withdrawal fee choices remain exactly 1% / 2% / 3% / 4% — unchanged.

## Offline transfer implementation choice

`cm-playerdata`'s exported money functions (`AddMoney`, `RemoveMoney`,
`TransferMoney`, `GetCash`, `GetBank`, etc.) all require an online `src`;
there is no exported function to credit an offline character. Per the
project's compatibility rules, cm-bank does **not** bypass this by writing
directly into `cm-playerdata`'s tables. Instead:

1. A transfer to an offline Character ID debits the sender immediately
   (server-authoritative, same locked path as an online transfer) and
   inserts a row into `bank_pending_transfers` with `status = 'pending'`.
2. cm-bank subscribes (read-only `AddEventHandler`, no modification to
   cm-playerdata) to the real, existing
   `cm-playerdata:server:characterLoaded` event, fired from `NotifyLoaded`
   in `cm-playerdata/server/main.lua`.
3. When that Character ID next loads, cm-bank claims the pending row via a
   compare-and-set (`pending -> delivering`), credits it through the same
   `AddMoney` export every other credit path uses, and marks it
   `delivered`. If the credit fails, the claim is released back to
   `pending` for retry on the next load — money is never marked delivered
   without a successful credit, and a claim that already credited but
   failed to finalize its status is flagged `recovery_required` and logged
   via `adminLog`, never silently retried (which would double-pay).

This is the "safe pending-transfer mechanism inside cm-bank" path described
in the spec, chosen because cm-playerdata does not provide a safe supported
way to credit an offline character directly.

## Compatibility notes

- Existing transaction-ID prefixes (`BUYATM`, `SELLATM`, `ATMEARN`) are kept
  as-is rather than renamed to the spec's example (`ATMBUY`/`ATMSELL`), to
  avoid fragmenting historical transaction references already stored in
  `bank_transactions` and `cm_bank_operation_journal`.
- No existing network event was renamed. `cm-bank:server:transfer` gained a
  third, optional `note` argument — old client payloads that omit it still
  work (`note` is nilable and sanitizes to `nil`).
- `Config.Limits.maxTransfer` / `Config.Limits.minAmount` are left in place
  for deposit/withdraw; transfers now read their limits exclusively from the
  new `Config.TransferLimits` block instead, per the spec's explicit
  "do not hardcode these values" requirement.
- Character ID remains the only identifier ever used for transfers; the
  FiveM server ID is never exposed in the banking UI.

## Testing checklist

- [ ] `luac -p` passes on `server/main.lua`, `client/main.lua`,
      `shared/config.lua`.
- [ ] `node --check` passes on `ui/app.js`.
- [ ] Resource starts cleanly; console shows no `[CM-BANK]` init errors;
      `bankReady` reaches `true`.
- [ ] Existing v1.4 flows still work: deposit, withdraw (teller and ATM,
      owned/unowned fee), buy/sell/fee-choice/contact/earnings-withdraw ATM
      ownership, admin ATM commands, verified/unverified ATM discovery.
- [ ] Online transfer: send to an online Character ID, confirm dialog shows
      the server-resolved recipient name, sender debited, recipient
      credited, both statement rows recorded with the same reference.
- [ ] Offline transfer: send to a Character ID that is not online; sender is
      debited immediately; log in as that character and confirm the money
      arrives exactly once, with a toast/notification.
- [ ] Restart the server with a pending offline transfer still undelivered;
      confirm it still delivers exactly once on next login (no duplication,
      no loss).
- [ ] Attempt to transfer to a nonexistent Character ID — expect "Character
      ID not found."
- [ ] Attempt to transfer to your own Character ID — expect "You cannot
      transfer to yourself."
- [ ] Exceed `maxTransfersPerMinute` by sending transfers rapidly — expect
      rejection independent of NUI button state.
- [ ] Exceed `TransferLimits.dailyLimit` across multiple transfers in one
      day — expect "Daily transfer limit exceeded."; failed/rolled-back
      transfers must not count toward the total.
- [ ] Send a transfer with a note containing HTML/script-like text (e.g.
      `<img src=x onerror=alert(1)>`) — confirm it renders as inert plain
      text everywhere (confirm dialog, recent activity, statements).
- [ ] Open "View All" statements: pagination (prev/next/page count), each of
      the 8 filters, and search by transaction ID, Character ID, and note
      text all return correct, server-authoritative results.
- [ ] Today tile (Money In/Out/Fees) matches actual deposits/withdrawals/
      transfers made during the session.
- [ ] Close the NUI mid-transfer-entry (Character ID + amount + note typed
      but not submitted) and reopen — all fields, filters, and the confirm
      modal are reset; nothing resubmits.
- [ ] Confirm no other resource's files were modified (`git status` outside
      `resources/[core]/cm-bank/`).
