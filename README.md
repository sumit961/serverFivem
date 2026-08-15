# CM FiveM Framework

CM is a complete FiveM roleplay server built from cooperating resources. Resource contracts, persistent identities, permissions, and startup order are repository-wide concerns; individual resources should not be treated as standalone scripts.

## Repository layout

- `resources/[core]/` — CM gameplay and framework resources.
- `resources/[standalone]/` and Cfx default groups — third-party/runtime dependencies.
- `resources/[mlo]/` and `resources/[clothes]/` — private assets intentionally excluded from Git.
- `tools/cm-fivem-map/` — FiveM contract scanner.
- `tools/cm-validate/` — static repository validator.
- `agent-docs/` — tracked architecture documentation.

## Prerequisites

- A current FiveM/FXServer artifact and valid Cfx.re license.
- MySQL/MariaDB reachable by `oxmysql`.
- The required private assets documented in [PRIVATE_ASSETS.md](PRIVATE_ASSETS.md).
- Node.js only when rebuilding a resource's NUI source; built NUI files are normally loaded by FXServer.

## Installation and startup

1. Clone the repository and install the required private resources.
2. Import the repository SQL migrations into a dedicated database. Never point a development checkout at production without a backup.
3. Copy `server.local.example.cfg` to `server.local.cfg` and replace the placeholders locally.
4. Keep `server.local.cfg` untracked. `server.cfg` loads it with `exec server.local.cfg`.
5. Review the active `ensure` list and confirm every external/private resource is installed.
6. Start FXServer using `server.cfg` (or select this recipe in txAdmin).

Do not put credentials in `server.cfg`, documentation, commits, or issue logs.

## Resource ownership

- `cm-core`: framework lifecycle and shared services.
- `cm-playerdata`: character identity and player relationship data.
- `cm-items`: authoritative shared item definitions.
- `cm-inventory`: player/container inventory behavior.
- `cm-weapons`: weapon and ammunition definitions.
- `cm-vehicles`: persistent vehicle identity and physical vehicle state.
- `cm-house`: properties, interiors, garages, and house access.
- `cm-family`: family membership, ranks, and family-scoped access.
- `cm-admin`: privileged administration and audit visibility.
- `cm-ui`: shared UI primitives and CM design tokens.
- `cm-law`: shared legal-organization services.
- `cm-police`: police-specific gameplay.
- `cm-ems`: EMS organization and medical-response gameplay.
- `cm-doctor`: doctor/NPC medical services built on EMS contracts.
- `cm-prison`: shared jail sentence and prison state.

`cm-gunstore` owns the public weapons/armor store. Its armory catalog enrichment is an optional runtime integration for `cm-law`; weapon definitions still come from `cm-weapons`.

## Validation

From the repository root:

```powershell
python tools/cm-validate/validate.py
python tools/cm-fivem-map/scan.py --root . --out cm-agent-out --check
```

Refresh generated contract intelligence with:

```powershell
python tools/cm-fivem-map/scan.py --root . --out cm-agent-out
graphify extract . --code-only
graphify cluster-only . --no-label --no-viz
```

Generated `cm-agent-out/` and `graphify-out/` directories are intentionally ignored.

## Troubleshooting

- A missing-resource/start-order error usually means an active `ensure` or hard manifest dependency is unavailable or starts too late. Run `tools/cm-validate/validate.py`.
- Database errors should be checked against the relevant resource migration and the oxmysql connection string. Never reset production tables to silence an error.
- Missing maps, interiors, or clothing generally indicate an unavailable private asset; see `PRIVATE_ASSETS.md`.
- Static validation cannot prove runtime behavior. Test affected flows on a non-production FiveM server after every integration change.
