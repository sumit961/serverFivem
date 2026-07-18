# FiveM contract scan schema

Documents every field written to `cm-agent-out/fivem-contracts.json` by
[`tools/cm-fivem-map/scan.py`](../tools/cm-fivem-map/README.md) (schema
version `1.0.0`). This file is generated and git-ignored; this document
describes its shape so any AI assistant or developer can consume it without
reading the scanner source.

## Top-level document

| Field | Type | Description |
|---|---|---|
| `schema_version` | string | Semantic version of this document's shape. |
| `generated_at` | string (UTC ISO-8601) | Scan timestamp. The only field that legitimately differs between two scans of an unchanged tree. |
| `scanner_version` | string | `scan.py`'s own version. |
| `repository_root` | string | Always `"."` — never an absolute path. |
| `working_tree` | object | See below. |
| `resources` | array | See **Resource**. |
| `events` | array | Raw event registration/trigger contracts. See **Event contract**. |
| `event_relationships` | array | Trigger↔handler links built from `events`. See **Event relationship**. |
| `exports` | array | Raw export definition/consumer contracts. See **Export contract**. |
| `export_relationships` | array | Consumer↔definition links. See **Export relationship**. |
| `nui_callbacks` | array | Raw NUI registration/browser-call contracts. See **NUI contract**. |
| `nui_relationships` | array | Browser-call↔Lua-handler links. See **NUI relationship**. |
| `ox_callbacks` | array | Raw `ox_lib` callback register/call contracts. |
| `callback_relationships` | array | Call↔registration links. See **ox callback relationship**. |
| `database_operations` | array | Raw `MySQL.*`/`oxmysql` call contracts. See **Database operation**. |
| `database_tables` | array | Table names extracted from SQL text (both from Lua/JS calls and `.sql` files). See **Database table entry**. |
| `commands` | array | `RegisterCommand`/`lib.addCommand` contracts. |
| `permissions` | array | `IsPlayerAceAllowed` checks, the rank-permission heuristic, and `add_ace`/`add_principal` entries from `server.cfg`. |
| `unresolved` | array | Flat index of every contract with `dynamic_name: true` or a non-null `unresolved_reason`, for quick triage. |
| `diagnostics` | object | `{errors: [...], warnings: [...], files_scanned: N, files_skipped: N}`. |
| `statistics` | object | Counts per section, used by `--check`'s drift summary and the Markdown report header. |

### `working_tree`

| Field | Type | Description |
|---|---|---|
| `git_available` | bool | Whether `git` could be invoked. |
| `head_commit` | string \| null | `git rev-parse HEAD`, or null if unavailable/`--no-git`. |
| `is_dirty` | bool \| null | Whether `git status --porcelain` was non-empty. |
| `mode` | string | `"full"`, `"changed"`, or `"resource:<name>"`. |
| `changed_files` | array \| null | Only present when `--changed` was used **and** git is available. Informational only — see the Phase 1 note in the README; the underlying scan is always full. |
| `changed_note` | string | Present alongside `changed_files`, states the informational-only caveat explicitly. |

## Resource

| Field | Description |
|---|---|
| `id` | Deterministic id, `res_<sha1[:12]>` of the resource's repo-relative path. |
| `name` | Directory name (e.g. `cm-house`). Never a bracket collection folder name (`[core]`, `[mlo]`, ...). |
| `path` | Repository-relative path (posix separators). |
| `owner_collection` | The bracket collection folder directly containing it (e.g. `"[core]"`), or `null`. |
| `manifest_path` | Path to its `fxmanifest.lua`/`__resource.lua`. |
| `manifest_kind` | `"fxmanifest.lua"` or `"__resource.lua"`. |
| `nested_manifest_candidate` | `true` if this manifest sits inside *another* discovered resource's directory tree (e.g. a vendored duplicate copy) — flagged for visibility, not silently merged or dropped. |

## Common contract fields

Every entry in `events`, `exports`, `nui_callbacks`, `ox_callbacks`,
`database_operations`, `commands`, and `permissions` carries at least:

| Field | Type | Description |
|---|---|---|
| `id` | string | Deterministic id (stable across unchanged re-scans). Prefix indicates kind (`evtreg_`, `evttrig_`, `expdef_`, `expuse_`, `nuireg_`, `nuicall_`, `oxcb_`, `dbop_`, `cmd_`, `perm_`, `ace_`, `principal_`). |
| `type` | string | Contract type, e.g. `event_registration`, `event_trigger`, `export_definition`, `export_consumer`, `nui_registration`, `nui_browser_call`, `ox_callback_register`, `ox_callback_call`, `database_operation`, `command`, `permission_check`, `ace_permission`, `principal_binding`. |
| `name` | string | The literal name (event/export/callback/table/command/permission), or `"<dynamic>"` when unresolved. |
| `resource` | string \| null | Owning resource name (source side). |
| `target_resource` | string \| null | Referenced resource, when known (export/NUI consumers; `"oxmysql"` for DB ops). |
| `file` | string | Repository-relative file path. |
| `line` | integer | 1-indexed line of the matched call/declaration. |
| `context` | string | `"client"`, `"server"`, `"shared"`, `"nui"`, or `"unknown"` — inferred from the file's path/name. |
| `operation` | string | The specific syntax family matched, e.g. `register_net_event`, `trigger_client_event`, `exports_dot`, `lib.callback.await`, `query`, `register_command`, `IsPlayerAceAllowed`. |
| `confidence` | `"EXTRACTED"` \| `"INFERRED"` | `EXTRACTED` = a literal value was read directly. `INFERRED` = the call/registration itself is certain but its name/argument could not be resolved to a literal (dynamic). |
| `syntax` | string | Human-readable label for the exact matched form, e.g. `"exports.resource:fn()"`, `"fetch(\`https://${GetParentResourceName()}/name\`)"`. |
| `dynamic_name` | bool | `true` when the name/value is not a compile-time literal. |
| `unresolved_reason` | string \| null | Why resolution failed, when `dynamic_name` is true (or a resolution otherwise couldn't complete). See **Unresolved reasons** below. |

Type-specific extra fields:

- **Database operations** additionally carry `await` (bool) and `dynamic_sql` (bool).
- **Commands** additionally carry `restricted` (bool \| null, from a trailing literal `true`/`false` argument if statically present).
- **ACE permissions** (`type: ace_permission`) carry `principal` (the group/principal string from `add_ace`). **Principal bindings** (`type: principal_binding`) carry `identifier_redacted: true` — the actual FiveM/license identifier value is never stored, only the group name (in `name`).

## Unresolved reasons

| Value | Meaning |
|---|---|
| `non_literal_argument` | The first argument is a variable/expression that isn't a simple same-file literal or resolvable local string. |
| `string_concatenation` | A literal was found but is immediately followed by `..` (Lua) or `+` (JS) — the real value depends on a variable; the static prefix is deliberately not reported as if it were complete. |
| `template_interpolation` | A JS template literal contains `${...}` and could not be reduced to a static string. |
| `dynamic_resource_name` | `exports[var]:fn()` where `var` is not a literal. |
| `no_argument_found` / `argument_too_far` / `eof` | No suitable literal token was found within the lookahead window. |
| `payload_not_a_callback_name` | `SendNUIMessage(...)` — its argument is a data payload, not a callback name; recorded for evidence but never treated as a resolvable name. |
| `non_literal_fetch_url` | A browser `fetch()` call whose URL could not be statically resolved at all. |

## Event relationship

| Field | Description |
|---|---|
| `event` | Literal event name. |
| `direction` | `client_to_server`, `server_to_client`, `local` (same-side `TriggerEvent`), or `unknown`. |
| `trigger` | `{resource, file, line, operation}` for the trigger site, or `null` for an untriggered-handler entry. |
| `handlers` | Array of `{resource, file, line, context, operation}` — every matching `AddEventHandler` site (only `AddEventHandler`, not the `RegisterNetEvent` declaration, counts as a "handler"). |
| `handler_count` | `len(handlers)`. |
| `status` | `resolved` (exactly one handler), `resolved_multiple` (more than one), `unresolved_no_handler` (trigger with zero matching handlers), `dynamic_unresolved` (trigger's event name wasn't a literal), or `untriggered_handler` (a handler with no corresponding trigger found anywhere in the scanned corpus — informational, not necessarily a bug: it may be triggered from an un-scanned source). |
| `direction_mismatch_note` | Present when a handler for a directional event also exists on the "wrong" side (e.g. a client handler for an event only ever triggered via `TriggerServerEvent`) — a hint, not a hard error. |

## Export relationship

| Field | Description |
|---|---|
| `export` | Export/function name. |
| `consumer` | `{resource, file, line, context}` of the `exports.res:fn()` call site. |
| `target_resource` | The resource name referenced by the consumer. |
| `definitions` | Matching `export_definition` sites `{file, line, context}`. |
| `status` | `resolved`, `resolved_context_mismatch` (definition and consumer are on opposite client/server realms — exports do not cross that boundary in FiveM, so this is a real correctness signal), `resolved_multiple_definitions`, `missing_export_definition` (target resource exists but never defines this export), `missing_target_resource` (no such resource discovered at all), or `dynamic_target_unresolved`. |

## NUI relationship

| Field | Description |
|---|---|
| `callback` | Callback name. |
| `browser_call` | `{resource, file, line}` of the `fetch()` site, or `null` for an orphaned-handler entry. |
| `target_resource` | Resource the browser call targets. |
| `handlers` | Matching `RegisterNUICallback`/`RegisterNuiCallbackType` sites `{file, line}`. |
| `status` | `resolved`, `resolved_multiple`, `missing_lua_handler` (browser call with no matching registration), `no_detected_browser_caller` (registration never referenced by any scanned `fetch()`), or `dynamic_unresolved`. |

## ox callback relationship

| Field | Description |
|---|---|
| `callback` | Callback name. |
| `caller` | `{resource, file, line, operation}` of the `lib.callback.await`/`lib.callback` site. |
| `registrations` | Matching `lib.callback.register` sites `{resource, file, line}`. |
| `status` | `resolved`, `resolved_multiple_registrations`, `missing_registration`, or `dynamic_unresolved`. |

## Database table entry

| Field | Description |
|---|---|
| `id` | Deterministic id. |
| `table` | Table name. |
| `clause` | Which SQL clause it was extracted from: `select_from`, `join`, `insert_into`, `update`, `delete_from`, `create_table`, `alter_table`, `drop_table`, `references`, `truncate_table`. |
| `category` | `read` (`select_from`, `join`), `write` (`insert_into`, `update`, `delete_from`, `truncate_table`), or `schema` (`create_table`, `alter_table`, `drop_table`, `references`). |
| `operation_id` | The `database_operations` entry this came from, or `null` for a table found directly in a `.sql` file. |
| `resource`, `file`, `line`, `await` | Provenance (line is always `1` for `.sql`-file entries — see the scanner's documented limitation). |

## Confidence values

Only two values appear anywhere in this schema:

- **`EXTRACTED`** — the name/value is a literal read directly from source (a quoted string, a Lua long-bracket string, or a same-file local-variable string resolved to its literal assignment).
- **`INFERRED`** — the contract itself (the call/registration) is certain, but its name/value could not be reduced to a literal, so `dynamic_name` is `true` and `unresolved_reason` explains why. `INFERRED` never means "the scanner guessed a value" — a dynamic entry's `name` is always exactly the string `"<dynamic>"`, never a fabricated guess.
