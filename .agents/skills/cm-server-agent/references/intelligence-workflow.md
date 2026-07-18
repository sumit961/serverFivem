# Intelligence workflow

How to use the two generated intelligence sources without loading either
whole into context, and how to interpret what each one actually knows.

## What each source provides

| Source | Provides | Does not provide |
|---|---|---|
| `AGENTS.md` | Permanent architectural rules, ownership map, security posture | Per-change contract detail |
| `agent-docs/resource-registry.yaml` | Manifest-backed resource inventory (supporting evidence) | Runtime relationships |
| `cm-agent-out/fivem-contracts.json` + `-summary.md` | FiveM events, exports, NUI callbacks, `ox_lib` callbacks, MySQL/oxmysql operations and tables, commands, ACE permissions — with producer/consumer resolution | Generic function-level call graphs; anything outside these syntax families |
| `graphify-out/graph.json` | Generic AST call/contains graph across all code (functions, files) | FiveM event/export/NUI/MySQL semantics (natives have no local definition, so Graphify drops them — see its own evaluation notes) |

Both `graphify-out/` and `cm-agent-out/` are **generated and git-ignored**.
Never commit them unless the user explicitly changes that policy.

## When to refresh

- Before a cross-resource change: check both are current.
- After a cross-resource change: refresh the CM map always; refresh
  Graphify only if generic call relationships materially changed (new
  files, renamed functions, restructured call chains) — not for every
  small edit.
- Before answering a question about "what calls/triggers/uses X": check
  freshness first, or say plainly that the answer may be stale.

## Stale-map detection

```bash
python tools/cm-fivem-map/scan.py --root . --out cm-agent-out --check
```
Exit code `0` and `output is current` means no rewrite happened and the map
matches the working tree. Exit code `1` means it drifted — the command
prints which statistics changed, without rewriting. Refresh with a plain
run (no `--check`) before relying on it.

For Graphify, there is no equivalent lightweight check in this repo's
verified command set. If in doubt, compare `graphify-out/GRAPH_REPORT.md`'s
"Built from commit" line against `git rev-parse HEAD`.

## Querying `fivem-contracts.json` without loading 3+ MB into context

Prefer, in order:

1. **`cm-agent-out/fivem-contracts-summary.md`** (tens of KB) — counts,
   cross-resource relationships, unresolved entries, missing
   handlers/exports, NUI/callback mismatches, top dependencies. Read this
   first for almost every question.
2. **Targeted Python queries** over the JSON (stdlib only, no `jq`
   dependency — this environment does not have `jq` and must not install
   it):

   ```bash
   python -c "
   import json
   doc = json.load(open('cm-agent-out/fivem-contracts.json', encoding='utf-8'))
   hits = [e for e in doc['event_relationships'] if e['event'] == 'cm-playerdata:server:characterLoaded']
   print(hits)
   "
   ```

   PowerShell equivalent:

   ```powershell
   $doc = Get-Content cm-agent-out\fivem-contracts.json -Raw | ConvertFrom-Json
   $doc.event_relationships | Where-Object { $_.event -eq 'cm-playerdata:server:characterLoaded' }
   ```

3. Only read the raw JSON file directly (via a normal file-read tool) when
   you need to inspect the schema itself or a small, already-known slice —
   never load the whole 3+ MB file into a prompt/context window
   speculatively.

Field meanings are documented in
[`agent-docs/fivem-contract-schema.md`](../../../../agent-docs/fivem-contract-schema.md).

## Graphify strengths and verified limitations

Strengths: fast, local, zero-cost intra-file/intra-resource call graphs;
respects `.gitignore`/`.graphifyignore`; honest about skipped/failed files.

Verified limitations (do not re-litigate these, they are established):
`RegisterNetEvent`/`AddEventHandler`/`TriggerServerEvent`/
`TriggerClientEvent`/`RegisterNUICallback` are FiveM natives with no local
Lua definition, so Graphify's AST resolver drops the call edge entirely —
it has **no concept of FiveM's event bus**. Cross-resource
`exports.resource:fn()` calls and `MySQL.*`/`oxmysql` table usage are not
resolved across resource boundaries either. HTML/CSS get no AST coverage
(no tree-sitter grammar installed for them). `.sql` files are unparsed
(missing `tree_sitter_sql`, an optional extra not installed by policy).

## Event / export / NUI / MySQL interpretation

- An event/export/callback is only "resolved" when the CM map's
  relationship `status` says so (`resolved`, `resolved_multiple`). A
  `missing_export_definition`, `missing_target_resource`,
  `missing_lua_handler`, or `unresolved_no_handler` status means exactly
  that — evidence of an absence, not proof of a bug (the counterpart may
  live in code the scanner didn't classify, e.g. a `.ts` build output, or
  be genuinely dead).
- `resolved_context_mismatch` on an export relationship is a real signal:
  exports do not cross the client/server realm boundary in FiveM. Treat it
  as a likely defect, not noise.
- MySQL/oxmysql table entries carry `category` (`read`/`write`/`schema`) —
  use this to reason about migration risk before assuming a table's shape.

## Dynamic/unresolved relationship handling

Every contract with `dynamic_name: true` has a `name` of exactly
`"<dynamic>"` and a specific `unresolved_reason` (see the schema doc for
the full list: `non_literal_argument`, `string_concatenation`,
`template_interpolation`, `dynamic_resource_name`, etc.). Never guess the
real value from context and report it as if extracted — if the map says
dynamic, treat it as dynamic and, if it matters to the task, verify by
reading the source directly.

## Source-verification procedure

1. Locate the relevant contract(s)/relationship(s) in the CM map.
2. Open the cited `file:line` and read the surrounding function.
3. If the map disagrees with what the source shows (stale map, scanner
   limitation, or a genuine gap in coverage), source code wins — say so
   explicitly in the report rather than silently preferring the map.
4. For anything Graphify surfaced, cross-check against the CM map or
   source before treating it as a FiveM-semantic fact.
