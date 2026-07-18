# Security review

This is a review *procedure* and checklist for FiveM-specific risk. It does
not restate root `AGENTS.md`'s permanent security rules (server authority,
identity, database, secrets) — read that first; this file is what to
actually check, line by line, when a change touches anything privileged.

## When to run this

Any change touching: a network event handler, an export consumed by
another resource, a database write, an NUI callback, an ACE/permission
check, vehicle spawning/ownership, house/family access, or an admin-only
action.

## Checklist

For each touched call site, confirm:

- **Network event exposure** — is the event name predictable/guessable in
  a way that matters? Does the handler validate its arguments as untrusted
  input regardless of the sender?
- **Source/session vs. character identity** — does the code use the
  authoritative character ID for game-state decisions, or does it leak/use
  the raw FiveM `source`/session ID as if it were persistent identity?
- **Permission and rank checks** — is there a check at all, and does it run
  server-side? Confirm it uses a real permission-check context (ACE,
  rank/permission function), not an incidental string comparison.
- **Ownership** — does the operation verify the acting player actually owns
  or has been granted access to the target (vehicle, house, item, family)
  before acting on it?
- **Distance** — for physical-world interactions, is there a server-side
  distance/proximity check, not just a client-side one?
- **Routing bucket** — could cross-bucket/cross-instance interaction leak
  state or bypass isolation?
- **Entity existence and persistent identity** — does the code verify the
  entity/vehicle/network ID still exists and matches the expected
  persistent ID before acting, rather than trusting a stale reference?
- **Price/money/item authority** — are price, currency amount, and item
  identity/quantity always computed or validated server-side, never taken
  verbatim from the client?
- **Request replay / rate limiting** — can the same privileged request be
  fired repeatedly to duplicate an effect (money, items, vehicles)? Is
  there a cooldown, lock, or idempotency check where it matters?
- **Transaction / idempotency / operation locks** — for multi-step
  state changes (e.g. buy, transfer, withdraw), is there a lock or
  transaction preventing a race between two near-simultaneous requests?
- **Dynamic SQL** — is any table/column name or clause built from
  unsanitised input rather than a fixed, code-controlled string? (Values
  should be parameterised; identifiers should never come from client
  input at all.)
- **NUI trust** — does the Lua side treat every NUI callback payload as
  untrusted, validating shape and values before acting on them?
- **Callback response data** — does a callback (ox_lib or NUI) response
  avoid leaking data the requesting client/player isn't entitled to see?
- **Vehicle spawning/duplication** — is there a single authoritative path
  for creating/registering a persistent vehicle record, preventing two
  code paths from both minting a "new" vehicle for the same logical car?
- **House/family access** — does the change respect existing
  membership/rank/ownership boundaries for house and family features
  rather than widening access implicitly?
- **Admin actions** — are admin-only code paths gated by a real permission
  check on every entry point, not just the primary one?
- **Secret/log exposure** — does any log line, error message, or report
  include a credential, token, or other secret value?
- **High-risk activity logging** — are privileged actions (money changes,
  admin actions, ownership transfers) recorded through the project's
  existing logging/audit mechanism, without exposing secrets in the log?

## Reporting

List each checked item that is **relevant to the change** with a pass/fail/
not-applicable note and a one-line reason. Do not report on items the
change doesn't touch. Flag anything unresolved as a remaining risk in the
completion report rather than silently accepting it.
