# Resource Summary — Phase 1 (static manifest + server.cfg evidence)

Generated from every `fxmanifest.lua` under `resources/` (49 files; zero
`__resource.lua` files exist in this repository) plus every `ensure`/`start`
line in `server.cfg` (active and commented). Full detail and evidence paths are
in `resource-registry.yaml`. See `README.md` for what this phase does and does
not cover, and for definitions of the terms used below (inventory row,
manifest candidate directory, non-nested resource candidate, nested manifest
candidate, configured manifest-missing folder).

## Total resource count — corrected classification

Earlier drafts of this file used a flat "50 resources" framing. That blurred
together three different kinds of evidence. The precise breakdown, per
`resource-registry.yaml`'s `entry_kind` field:

- **50** total inventory rows.
- **49** manifest candidate directories (a `fxmanifest.lua` was physically
  found).
- **47** non-nested manifest-backed resource candidates (`entry_kind:
  resource`) — ordinary resources not physically nested inside another
  manifest-backed resource's own directory.
- **2** nested manifest candidates (`entry_kind: nested_manifest_candidate`):
  `resources/[core]/bcrypt/dist` (inside `resources/[core]/bcrypt`) and
  `resources/[core]/nv_cloth/nv_cloth` (inside `resources/[core]/nv_cloth`).
- **1** configured folder missing a FiveM manifest (`entry_kind:
  configured_manifest_missing`): `gn_dual_mediccenter`.

The two nested candidates are retained in the registry for evidence and
completeness, not because they are confirmed to run. **Their independent
loadability by FXServer is not proven** — no server was started or restarted
to check (this project's safety rules disallow it in this phase). Both are
marked `loadability_confidence: inferred_platform_behavior` rather than
`extracted` for exactly this reason. See "Nested manifest candidates" below
for the supporting evidence.

`gn_dual_mediccenter` is `ensure`d in `server.cfg` but **cannot be treated as a
valid manifest-backed resource in its current state** — see "Configured
manifest-missing folder" below.

No deletion or relocation of any file was performed or recommended as an
automatic action anywhere in this document.

## Count by category

Two counts are given per category: all inventory rows (including nested
candidates and the manifest-missing folder), and non-nested manifest-backed
resource candidates only (`entry_kind: resource`) — the count that should be
used when reasoning about "how many resources does this category actually
run."

| Category | Inventory rows | Non-nested resource candidates |
|---|---|---|
| core | 31 | 29 (excludes `dist` and `nv_cloth/nv_cloth`, both `entry_kind: nested_manifest_candidate`) |
| system | 8 | 8 |
| mlo | 6 | 5 (excludes `gn_dual_mediccenter`, `entry_kind: configured_manifest_missing`) |
| standalone | 4 | 4 |
| clothes | 1 | 1 |
| **Total** | **50** | **47** |

Category was taken from the outermost bracketed folder directly under
`resources/` (`[core]`, `[standalone]`, `[mlo]`, `[clothes]`, `[system]`).
Bracketed directory names themselves were never counted as resources.

## Count explicitly ensured/started

**41 registry rows** have `ensured_in_server_cfg: true`, covering **40 distinct
active `ensure` lines** in `server.cfg`. The count of rows is one higher than
the count of distinct lines because both `nv_cloth` folders (the non-nested
resource candidate and the nested manifest candidate inside it) match the
single `ensure nv_cloth` line by name — see "Nested manifest candidates".

## Resources present but not explicitly started (9)

| Name | Category | Note |
|---|---|---|
| `cm-storebase` | core | Not referenced anywhere in `server.cfg` (active or commented). Has a full manifest and depends on `ox_lib`. |
| `dist` (`resources/[core]/bcrypt/dist`) | core | Nested manifest candidate, not itself referenced by any `ensure` line — see "Nested manifest candidates". |
| `baseevents` | system | Standard Cfx system resource; not referenced by any `ensure`/`start` line found in `server.cfg`. |
| `rconlog` | system | Same as above. |
| `runcode` | system | Same as above. |
| `sessionmanager-rdr3` | system | Same as above; depends on `yarn`. |
| `webpack` | system | Referenced only via manifest `dependencies` (by `screenshot-basic`), never `ensure`d. |
| `yarn` | system | Referenced only via manifest `dependencies` (by `screenshot-basic`, `sessionmanager-rdr3`, `webpack`), never `ensure`d. |
| `zpack_1` | clothes | `ensure zpack_1` exists in `server.cfg` but is **commented out**. |

## Resources referenced in server.cfg but missing from resources/

None of the **active** `ensure`/`start` lines reference a name with no
matching folder anywhere under `resources/`.

Three **commented-out** `ensure` lines reference names with no matching folder
at all (distinct from `zpack_1`, whose folder does exist):

- `#ensure cm-clothstore`
- `#ensure cm-clothingadmin`
- `#ensure cm-vehiclestore`

These are inactive references; flagged for visibility only, not treated as a
currently-broken start.

## Nested manifest candidates (2)

Two manifest candidate directories are physically nested inside another
manifest-backed resource's own directory tree. They are **not** counted among
the 47 non-nested resource candidates, and their `name` values collide with
their container in one case — but that name collision is a side effect of the
nesting, not an independent duplication event; see below for why these are
classified as `nested_manifest_candidate` rather than a second free-standing
resource.

- **`resources/[core]/bcrypt/dist`** (contained by `resources/[core]/bcrypt`)
  — its `fxmanifest.lua` is byte-identical to the outer `bcrypt` manifest, but
  `dist/server.lua` is **missing** even though that same manifest declares
  `server_script 'server.lua'`. Its directory contains only compiled
  Client/Server publish-output DLLs plus the manifest — it resembles build
  distribution output copied alongside the source tree, not a second
  hand-authored resource. The outer `bcrypt` resource's own manifest
  declarations resolve entirely within its own folder and never reference
  `dist/`.
- **`resources/[core]/nv_cloth/nv_cloth`** (contained by
  `resources/[core]/nv_cloth`) — `fxmanifest.lua` and all Lua source are
  byte-identical to the outer `nv_cloth`, but the inner copy's web UI
  identifies itself as `v3` (`app.js?v=manual-pose-v3`) while the outer
  resource identifies as `v5` (`app.js?v=manual-pose-v5`), and the inner
  `stream/` folder is missing seven binary assets that exist in the outer
  resource. This is an older, incomplete copy, not a byte-for-byte complete
  duplicate.

For both: **whether FXServer's resource scanner independently discovers and
registers these nested folders as their own resources was not runtime-verified
in this phase** (no server start/restart was performed, per this phase's
safety rules). General FiveM platform convention is that resource discovery
does not typically recurse into an already-discovered resource's own
subdirectories looking for further manifests — if that holds here, neither
nested folder is ever independently loaded, and each sits inert inside its
container's own tree. This is recorded as `loadability_confidence:
inferred_platform_behavior`, explicitly distinct from `extracted` fact, in
both entries.

**No deletion or relocation was performed or recommended as an automatic
action** for either nested candidate — both remain exactly where they were
found, and a decision on what to do with them is left to you.

No other resource name collides outside of this nesting relationship.

## Configured manifest-missing folder (1)

- **`gn_dual_mediccenter`** (`resources/[mlo]/gn_dual_mediccenter`) — directory
  exists and is `ensure`d in `server.cfg` (order 38), but contains **no
  `fxmanifest.lua` or `__resource.lua`** anywhere (recursive search, all
  common casings) — only raw streamed GTA assets (119 `.ydr`, 9 `.ybn`, 8
  `.ymap`, 3 `.ytyp`, 2 `.ytd`, 2 `.gfx`, 1 `.ydd`) and a readme `.txt`. A
  `stream/_manifest.ymf` file is present, but this is a binary RAGE/game-asset
  manifest format unrelated to FiveM's resource manifest system — **it is not
  treated as a substitute for `fxmanifest.lua`/`__resource.lua`** anywhere in
  this registry. As configured, this `ensure` line cannot start a resource,
  and `gn_dual_mediccenter` cannot be treated as a valid manifest-backed
  resource in its current state.

  The entire `resources/[mlo]/` collection is intentionally excluded from git
  (`.gitignore: resources/\[mlo\]/`), consistent with this repository's
  earlier history of deliberately not tracking heavy MLO/clothing asset
  folders. `gn_dual_mediccenter` being untracked by git is therefore **not
  unique to it** — every other `[mlo]` resource (`Relax_muatininV4`,
  `bob74_ipl`, `showcasecars`, `showcasecars2`,
  `vStudios_PacificBluffsDealership_Ultimate`) is equally untracked, even
  though those do have a working manifest. The missing manifest is a distinct
  problem from the git-tracking status.

No other manifest failed to parse; all 49 discovered `fxmanifest.lua` files
were read successfully with `fx_version`, `game`, and script/dependency data
recovered (see Validation below for how "recovered" was checked).

## Resources with NUI (`ui_page` declared)

30 rows (29 distinct names — the outer `nv_cloth` and its nested manifest
candidate both declare the same `ui_page`):

`cm-admin`, `cm-auth`, `cm-carwash`, `cm-characters`, `cm-chat`,
`cm-climatime`, `cm-core`, `cm-family`, `cm-gasstations`, `cm-gunstore`,
`cm-house`, `cm-hud`, `cm-inventory`, `cm-items`, `cm-parking`,
`cm-playerdata`, `cm-spawn`, `cm-store`, `cm-storebase`, `cm-tuning`,
`cm-vehicles`, `cm-weapons`, `nv_cloth` (×2 folders), `ox_lib`, `ox_target`,
`oxmysql`, `rn-vehicleshop`, `runcode`, `screenshot-basic`

## Resources with database-related declared dependencies (`oxmysql`)

12: `cm-auth`, `cm-core`, `cm-family`, `cm-gunstore`, `cm-house`,
`cm-inventory`, `cm-items`, `cm-playerdata`, `cm-store`, `cm-tuning`,
`cm-weapons`, `rn-vehicleshop`.

(Several other resources load `@oxmysql/lib/MySQL.lua` as a `server_script`
without declaring `oxmysql` in `dependencies` — e.g. `cm-admin`,
`cm-characters`, `cm-climatime`, `cm-parking`, `cm-spawn`, `cm-vehicles`. That
script include is recorded verbatim in each resource's `server_scripts` list in
the registry, but is **not** counted here since the question asked about
*declared dependencies* specifically, not script includes. Worth a look before
assuming these are fully decoupled from the database.)

## Declared dependency edges

69 edges extracted (excluding FiveM's special non-resource dependency markers
— see below). Full list lives in `resource-registry.yaml` per-resource
`declared_dependencies`; the graph (`A -> B` meaning "A declares a dependency
on B"):

```
cm-admin -> cm-ui
cm-auth -> cm-core, cm-ui, oxmysql
cm-characters -> cm-auth, cm-core, cm-playerdata, cm-ui
cm-climatime -> cm-ui
cm-core -> oxmysql
cm-family -> cm-house, cm-playerdata, cm-vehiclekeys, ox_lib, oxmysql
cm-gunstore -> cm-core, cm-inventory, cm-items, cm-playerdata, cm-weapons, oxmysql
cm-house -> cm-inventory, cm-playerdata, cm-vehicles, ox_lib, oxmysql
cm-hud -> cm-core, cm-playerdata, cm-ui
cm-inventory -> cm-items, oxmysql
cm-itemactions -> cm-inventory
cm-items -> oxmysql
cm-parking -> cm-vehicles
cm-playerdata -> cm-ui, oxmysql
cm-spawn -> cm-characters, cm-core, cm-playerdata, cm-ui
cm-store -> cm-core, cm-inventory, cm-items, cm-playerdata, oxmysql
cm-storebase -> ox_lib
cm-tuning -> cm-playerdata, cm-vehicles, oxmysql
cm-vehiclekeys -> cm-playerdata
cm-vehicles -> cm-inventory, cm-playerdata, cm-vehiclekeys
cm-weapons -> cm-items, oxmysql
nv_cloth (both folders) -> cm-items, screenshot-basic
rn-vehicleshop -> cm-core, cm-playerdata, cm-vehicles, oxmysql, screenshot-basic
ox_target -> ox_lib
screenshot-basic -> webpack, yarn
sessionmanager-rdr3 -> yarn
webpack -> yarn
```

Every dependency target above resolves to a resource name present somewhere in
this registry — no resource declares a dependency on a name that doesn't exist
anywhere in `resources/`.

**Special non-resource dependency markers found** (recorded verbatim in the
registry but excluded from the edge list above, since they are FiveM-reserved
syntax, not resource names): `/assetpacks` (`zpack_1`, `showcasecars`,
`showcasecars2`, `vStudios_PacificBluffsDealership_Ultimate`), `/onesync` and
`/server:7290` (`ox_lib`), `/server:12913` (`oxmysql`).

## Potential start-order problems

Checked every declared dependency edge against each resource's own
`ensure_order` (explicit `server.cfg` order only — no assumption about load
order beyond that). **No active, started resource depends on something that
starts later than itself** — all `cm-*` dependency chains are internally
consistent with their `ensure` order.

One finding:

- **`screenshot-basic`** (ensure order 8) declares dependencies on `webpack`
  and `yarn`, **neither of which is ever `ensure`d in `server.cfg`**. Static
  evidence alone can't say whether this is a real problem — `webpack`/`yarn`
  look like build-time tooling pseudo-resources (their manifests declare no
  scripts of substance beyond a builder `.js` file) rather than resources
  meant to run at server start, but that is an inference, not an extracted
  fact, so it is flagged rather than dismissed.

## Custom `cm-*` resources (26)

`cm-admin`, `cm-auth`, `cm-carwash`, `cm-characters`, `cm-chat`,
`cm-climatime`, `cm-core`, `cm-family`, `cm-gasstations`, `cm-gunstore`,
`cm-house`, `cm-hud`, `cm-inventory`, `cm-itemactions`, `cm-items`,
`cm-parking`, `cm-playerdata`, `cm-population`, `cm-spawn`, `cm-store`,
`cm-storebase`, `cm-tuning`, `cm-ui`, `cm-vehiclekeys`, `cm-vehicles`,
`cm-weapons`

## Other nesting note (not a duplicate/ambiguity case)

- `webpack` / `yarn` live inside a doubly-bracketed path
  (`resources/[system]/[builders]/webpack`), which this phase's flat category
  scheme (core/standalone/mlo/clothes/system) doesn't fully represent. Category
  was assigned as `system` from the outermost bracket; the nested grouping
  itself is preserved only in each entry's `unresolved` notes.

## Unresolved — requires runtime source scan

Nothing below was inspected in this phase. Recorded here as the explicit scope
for the next phase, not as a claim about what these resources do or don't do:

- **events** — every `RegisterNetEvent`, `AddEventHandler`,
  `TriggerEvent`/`TriggerServerEvent`/`TriggerClientEvent` call, and which
  resource produces vs. consumes each event name.
- **exports** — every `exports(...)`/`exports['x']:fn()` definition and call
  site, beyond what's declared as a manifest `dependency`.
- **callbacks** — every `lib.callback.register` / NUI `RegisterNUICallback`
  and its message contract (what payload shape each side expects).
- **SQL tables** — every table read or written per resource, and which tables
  are shared across resource boundaries (e.g. `cm-house` and `cm-family`'s
  house/family linkage, already known qualitatively from the earlier security
  audit in this conversation but not yet captured here as structured evidence).
- **permissions** — every ACE/permission identifier actually checked in code
  (e.g. `cm-house.create`, `family.manage_vehicles` from the earlier audit),
  cross-referenced against what `server.cfg`'s `add_ace`/`add_principal` lines
  grant.
- **cross-resource runtime calls** — any place one resource calls into another
  by name (export call, `TriggerEvent` with a namespaced event, hard-coded
  resource-name string) that isn't already captured as a manifest
  `dependency`.

## Validation

1. **Every discovered manifest was parsed.** All 49 `fxmanifest.lua` files
   under `resources/` were located and read; 0 raised a parse exception. Static
   checks for `fx_version`/`game` presence and brace balance were run against
   every file; 0 remained flagged after fixing two parser gaps found along the
   way (a `games { ... }` plural-table form, and singular `file '...'`
   declarations, both now handled).
2. **YAML validity — partial, with a stated limitation.** `PyYAML` is **not**
   installed in this environment and was **not** installed for this task, per
   the safety requirements. No other YAML parser (Node `js-yaml`, PowerShell
   cmdlet, etc.) was found already present either. Instead, a small
   purpose-built structural parser was written (recognising only the exact
   block-mapping/block-sequence/quoted-scalar subset this file uses) and run
   against `resource-registry.yaml`. It parsed the file successfully end to
   end, confirmed the top-level keys (`schema_version: 2`, `generated_from`,
   `resources`), confirmed exactly 50 resource entries, confirmed every entry
   has all 21 expected fields (including the four classification fields added
   in this revision: `entry_kind`, `containing_resource`,
   `expected_loadability`, `loadability_confidence`), confirmed the
   `entry_kind` counts are exactly 47 `resource` / 2 `nested_manifest_candidate`
   / 1 `configured_manifest_missing`, confirmed every non-nested `resource` row
   has `containing_resource: null`, and confirmed the two nested rows'
   `containing_resource` values point at the correct parent paths. This is
   **not** equivalent to full PyYAML/YAML-1.1-spec validation (edge cases like
   flow-style collections, anchors, or multi-document streams were never
   exercised, because this file doesn't use them) — treat it as strong
   evidence of well-formedness for this specific file, not a general-purpose
   guarantee.
3. **Every registry path exists.** Checked with `os.path.isdir` against all 50
   `path` values — 0 missing.
4. **Every non-nested resource candidate appears exactly once; nesting is
   explicit rather than hidden.** All 47 `entry_kind: resource` rows have a
   unique `name`. `nv_cloth` as a bare folder name occurs twice across the
   full registry, but the second occurrence is explicitly classified
   `entry_kind: nested_manifest_candidate` with `containing_resource:
   resources/[core]/nv_cloth` — it is not presented as a second, independent
   `nv_cloth` resource. `gn_dual_mediccenter` is confirmed **not** reported as
   manifest-backed (`entry_kind: configured_manifest_missing`, `manifest:
   null`).
5. **Square-bracket collection directories were not counted as resources.**
   Verified — no registry `name` is itself a bracketed string; `[core]`,
   `[standalone]`, `[mlo]`, `[clothes]`, `[system]`, and the nested
   `[builders]` were all used only to derive `category`/note nesting, never as
   a resource entry.
6. **No secret values appear in `agent-docs/`.** Neither manifests nor
   `server.cfg`'s `ensure` lines contain credentials — the only place secrets
   ever existed in this repository (`server.cfg`'s license key / Steam API key
   / MySQL connection string) was already relocated to `server.local.cfg` in
   an earlier session and is untouched by this phase. Manifest `dependencies`
   and script paths were the only content copied into this registry.
7. **No files outside `agent-docs/` were modified.** Confirmed via `git
   status` — only new, untracked files under `agent-docs/` appear; nothing
   under `resources/`, `server.cfg`, or elsewhere changed.
8. **cm-family and cm-house working-tree changes are unchanged.** Confirmed
   byte-for-byte identical (`git diff` hash match) against the same baseline
   established earlier in this session, both before and after this phase's
   work.
