# CM FiveM Development

Read `AGENTS.md` before making changes; it is the authoritative project governance document.

- Inspect the existing implementation before editing.
- Identify authoritative resource ownership and preserve character ID/CID and `vehicle_id` as persistent identities.
- Reuse existing events, exports, callbacks, database contracts, inventory and vehicle APIs, shared UI, and framework services.
- Do not duplicate systems across `cm-*` resources.
- Treat clients and NUI as untrusted; keep sensitive operations server-authoritative and fail closed.
- Preserve unrelated working-tree changes. Do not commit, push, deploy, or modify protected secrets.
- Use `tools/cm-validate/`, `tools/cm-fivem-map/`, and `tools/cm-runtime/` for validation and runtime checks.
- After the affected-resource restart and fresh console check, run
  `tools/cm-qa/run.ps1 -Resource <resource>` (or `-Changed`) when relevant.
  Read `cm-agent-out/qa/latest.json`; do not claim automated coverage when a
  layer is `BLOCKED`, and leave only the manual remainder that cm-qa reports.
  UI changes also require the UI layer when a fixture exists.
