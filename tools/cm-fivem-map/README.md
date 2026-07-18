# cm-fivem-map — portable CM FiveM contract scanner (Phase 1)

A dependency-free, Python-3.11-standard-library-only scanner that extracts
the FiveM-specific relationships a generic code-graph tool does not
understand: network/local events, cross-resource exports, NUI callbacks,
`ox_lib` callbacks, `MySQL`/`oxmysql` operations and the SQL tables they
touch, commands, and ACE permissions.

## What Graphify covers

[Graphify](../../.agents/skills/graphify/) builds a generic AST call graph
(functions, files, `calls`/`contains`/`imports` edges) across the whole
repository, offline, using tree-sitter. It is good at intra-file and
intra-resource call graphs. It has **no model of FiveM's runtime**: natives
like `RegisterNetEvent`, `TriggerServerEvent`, `TriggerClientEvent`,
`RegisterNUICallback` etc. have no local Lua definition, so AST-based
call-resolution silently drops them — the single most important
architectural relationship in a FiveM codebase (which resource talks to
which, over which event/export/callback) is invisible to it. Cross-resource
`exports.resourceName:fn()` calls and `MySQL.*`/`oxmysql` table usage are
likewise not resolved across resource boundaries. (See the evaluation that
motivated this tool for the concrete counts.)

## What this scanner adds

A separate, authoritative **evidence map** for exactly those FiveM
contracts:

- Network/local events: `RegisterNetEvent`, `RegisterServerEvent`,
  `AddEventHandler`, `TriggerServerEvent`, `TriggerClientEvent`,
  `TriggerEvent`, `TriggerLatentServerEvent`, `TriggerLatentClientEvent` —
  matched by exact literal event name into producer→consumer relationships,
  with direction (client→server / server→client / local), handler counts,
  and unresolved/dynamic flags.
- Cross-resource exports: `exports("Name", fn)`, `exports.Name = ...`,
  manifest `exports {}` / `server_exports {}`, and consumer syntax
  `exports.res:Fn()` / `exports['res']:Fn()` / `exports[var]:Fn()` (the last
  reported dynamic/unresolved, never guessed).
- NUI: Lua-side `RegisterNUICallback`/`RegisterNuiCallbackType`/
  `SendNUIMessage`, browser-side `fetch()` calls (literal URL or the
  `` `https://${GetParentResourceName()}/name`` `` template idiom), matched
  by callback name within the owning resource.
- `ox_lib` callbacks: `lib.callback.register`/`lib.callback.await`/
  `lib.callback`, matched by exact name.
- Database usage: `MySQL.query/single/scalar/insert/update/transaction`
  (with or without `.await`) and `exports.oxmysql:*`, with static SQL
  extracted from string literals, Lua long-bracket strings, and simple
  same-file local-variable resolution, plus table names pulled from
  `SELECT/JOIN/INSERT/UPDATE/DELETE/CREATE/ALTER/DROP/REFERENCES/TRUNCATE`.
  Also scans `.sql` schema files directly.
- Commands and permissions: `RegisterCommand`, `lib.addCommand`,
  `IsPlayerAceAllowed(source, "perm")`, a best-effort heuristic for
  rank/permission-check-style function calls (`*Permission*`, `*HasAccess*`,
  `*AceAllowed*`), and `add_ace`/`add_principal` lines from the tracked
  `server.cfg` (never `server.local.cfg`, and `add_principal` identifier
  values — FiveM/license IDs — are intentionally never captured, only the
  group they bind to).
- Resource ownership derived from repository-relative paths and
  `fxmanifest.lua`/`__resource.lua`, honouring `.gitignore` and
  `.graphifyignore`.

## Architecture

Graphify remains responsible for the generic AST call graph. This scanner
is a **separate, standalone evidence map** — it does not modify
`graphify-out/` and does not inject data into Graphify's schema. Its own
output lives entirely under `cm-agent-out/` (git-ignored, generated).

## How any AI coding assistant can invoke it

No dependency on Codex, Claude, Cursor, Hermes, or Graphify internals — it
is a plain Python 3.11 script using only the standard library:

```bash
python tools/cm-fivem-map/scan.py --root . --out cm-agent-out
```

Any assistant (or a human) can run this directly in a terminal, on any OS
with Python 3.11+, with no `pip install` step.

## Commands

```bash
# full scan, writes cm-agent-out/
python tools/cm-fivem-map/scan.py --root . --out cm-agent-out

# validate existing output is current without rewriting it (CI-friendly)
python tools/cm-fivem-map/scan.py --check

# scan one resource plus everything referenced by a relationship touching it
python tools/cm-fivem-map/scan.py --resource cm-house

# scan changed git files -- see the Phase 1 note below
python tools/cm-fivem-map/scan.py --changed

# operate without git
python tools/cm-fivem-map/scan.py --no-git

# diagnostic progress output (no secret contents)
python tools/cm-fivem-map/scan.py --verbose

# non-zero exit if any file failed to parse/read
python tools/cm-fivem-map/scan.py --fail-on-errors
```

**Phase 1 honesty note on `--changed`:** this flag does **not** perform an
incremental scan. It still walks and re-parses the entire repository; the
only difference is that the changed-file list from `git diff`/`git status`
is recorded in `working_tree.changed_files` as informational metadata. A
true incremental scanner (only re-parsing changed files and their
relationship neighbourhood) is future work, not Phase 1.

Similarly, `--resource <name>` performs a **full internal scan** and then
filters the *output* to the named resource plus anything a relationship
connects it to. It does not skip file I/O. Both simplifications are
intentional and documented rather than pretended away, per the Phase 1
scope for this tool.

## Output files

Written to `cm-agent-out/` (git-ignored, generated — never commit it):

- `fivem-contracts.json` — the full evidence map. See
  [`agent-docs/fivem-contract-schema.md`](../../agent-docs/fivem-contract-schema.md)
  for every field and confidence value.
- `fivem-contracts-summary.md` — human-readable counts, cross-resource
  relationships, unresolved/dynamic entries, missing handlers/exports, NUI
  and callback mismatches, direction-error suspects, top cross-resource
  dependencies, and parse/read errors.
- `scan-metadata.json` — a small summary (schema/scanner version,
  timestamp, mode, statistics, working-tree state) suitable for a CI
  artifact or a quick `--check` reference.

Output is deterministic: two scans of an unchanged tree produce identical
JSON except for `generated_at`.

## Limitations

- **Not a parser, a lexer.** Calls are recognised by regex over a
  comment/string-masked source (Lua and JS/TS tokenized; HTML via extracted
  `<script>` blocks; SQL via comment-stripped text). It does not build an
  AST and does not evaluate control flow.
- **No JS regex-literal awareness.** A `/pattern/` regex literal isn't
  tokenized as a unit; embedded quotes or backticks inside one can (rarely)
  desync string/template tracking for the rest of a file. Observed once in
  this repository, in a large third-party *minified/bundled* distribution
  file (`resources/[standalone]/oxmysql/dist/build.js`) — two
  `RegisterCommand` calls there were missed as a result. Authored,
  non-bundled FiveM source was not affected (see the validation report for
  the full source-count comparison).
- **String concatenation is treated as dynamic, not truncated.** A literal
  immediately followed by Lua `..` or JS `+` is reported `dynamic_name` with
  `unresolved_reason: string_concatenation` rather than silently resolved to
  its static prefix.
- **Same-file local-variable SQL resolution only.** `local q = "SELECT..."`
  then `MySQL.query(q)` resolves; a value assigned in a different file, or
  built across multiple statements/branches, does not.
- **`.sql` schema files are attributed without per-statement line
  numbers** (reported as line 1) — table names are still extracted
  correctly, just not pinpointed to an exact line within the file.
- **Permission-check heuristics are best-effort.** Functions matching
  `*Permission*`/`*HasAccess*`/`*AceAllowed*` are treated as permission
  checks; this will miss project-specific naming that doesn't match, and
  will not fire on patterns that don't look like a function call.
- **No cross-file event-declaration merging beyond exact literal name
  match.** `RegisterNetEvent` is treated as a declaration; only
  `AddEventHandler` counts as an actual handler for relationship purposes
  (so the idiomatic `RegisterNetEvent(x); AddEventHandler(x, fn)` pair isn't
  double-counted as two handlers).
- **Both bracket-consumer call forms are recognised** —
  `exports['res']:Fn()` (colon) and `exports['res'].Fn()` (dot property
  access), both seen in this codebase — but a stored/indirect reference like
  `local h = exports['res']; ...; h:Fn()` is not traced across lines; it has
  no function name at the point of the `exports[...]` expression itself and
  is reported as an unnamed (`<unknown>`) consumer rather than guessed.

## Security / exclusions

- Always excludes (regardless of `.gitignore`/`.graphifyignore`, matched as
  literal path components — no glob/escaping ambiguity):
  `.git/`, `graphify-out/`, `cm-agent-out/`, `cache/`, `logs/`,
  `node_modules/`, `stream/`, `local-security-backup/`, `server.local.cfg`,
  `resources/[mlo]/`, `resources/[clothes]/`,
  `resources/[core]/bcrypt/dist/`, `resources/[core]/nv_cloth/nv_cloth/`,
  `resources/[system]/[builders]/yarn/`, and `tools/` (this scanner's own
  tree).
- Additionally honours `.gitignore` and `.graphifyignore`, via an
  independent gitignore-glob reimplementation (not Graphify's matcher —
  this tool has no dependency on Graphify internals). Backslash-escaped
  brackets (`\[mlo\]`, as `.gitignore` uses) and fnmatch-style bracket
  classes (`[[]mlo[]]`, as `.graphifyignore` uses for Graphify's own
  matcher) are both understood correctly.
- `server.local.cfg` is refused even by a direct call into the file loader
  — a hardcoded basename guard, independent of the ignore engine, as
  defense in depth for the one file that must never be opened.
- `add_principal` identifier values (FiveM/license platform IDs) are never
  captured, even though they appear in the tracked (non-`.gitignore`d)
  `server.cfg` — only the *group* they bind to is recorded, to avoid
  embedding a real player's platform identifier in a generated,
  potentially-shared JSON artifact.
- No secret values, full source files, or file contents beyond short
  extracted identifiers (event names, table names, permission strings) are
  ever stored.

## No database/network behaviour

This tool **never connects to a database** and **never makes a network
request**. SQL table names are extracted from source text only. `.sql`
files are read as plain text. `MySQL.*`/`exports.oxmysql:*` calls are
recognised syntactically; nothing is executed.

## Tests

```bash
python -m unittest discover -s tools/cm-fivem-map/tests -v
```
