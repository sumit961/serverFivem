# CM Climatime v1.6.1 Sync Hotfix

Fixes large `cm-climatime:client:sync` payloads and server hitch warnings.

Changes:
- Public sync now sends a compact snapshot, not the raw live state table.
- Raw history undo snapshots are no longer sent to every client.
- History no longer stores history inside history.
- Large syncs use latent events as a fallback.
