# CM LAW v3.5.1 — CM Admin Organization Registration

- Keep `cm-law` and its required `cm-prison` service running independently of `cm-admin` so Law's start handler can restore organizations after an Admin restart; Admin-dependent actions remain fail-closed while Admin is unavailable.
- Re-register Generic Law organizations after `cm-admin` starts, gated on the Law schema being ready; registration remains idempotent and uses the configured canonical IDs.
- Re-register embedded Police after `cm-admin` starts, retaining the `police` ID and explicit Police-specific admin export mapping.
- Report organization registration failures and add a server-only CM Admin registry snapshot export for diagnostics.
- Normalize organization IDs consistently in the CM Admin registry, and return one clear message when an organization is not registered.
- Make the organization leader assignment result event the sole UI feedback path so duplicate or stale request results are ignored.
- No database migration. No organization UI or Vehicle G-menu visual changes.
