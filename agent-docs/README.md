# agent-docs

## Why this directory exists

This repository is a complete FiveM server made of many interdependent resources
(see the root `AGENTS.md`). Before Codex or any other agent changes a resource, it
needs an accurate picture of what actually exists and how it is actually wired
together — not an assumption. `agent-docs/` is where that repository-derived
evidence lives, built up in phases as runtime facts are extracted alongside the
static ones.

## Division of responsibility with AGENTS.md

- **`AGENTS.md`** (repository root) contains **permanent behaviour rules** —
  durable instructions about ownership, security, database safety, UI
  conventions, and working procedure. It rarely changes and is not regenerated
  from the codebase; it is written and maintained deliberately.
- **`agent-docs/`** contains **repository architecture evidence** — data
  extracted from the resources themselves (manifests, and in later phases,
  runtime source). It changes whenever the resources change, and is intended to
  be regenerated, not hand-maintained.

Do not duplicate AGENTS.md's rules here, and do not put architecture evidence
into AGENTS.md. They serve different purposes and update on different cadences.

## Phase 1 scope: `resource-registry.yaml`

`resource-registry.yaml` is, at this stage, built **only** from static,
declarative evidence:

- every `fxmanifest.lua` (no `__resource.lua` files exist in this repository)
  found under `resources/`
- `server.cfg`'s `ensure`/`start` lines (including commented-out ones, which are
  recorded but marked inactive)

It records what each resource *declares* — its manifest metadata, declared
`dependencies`, declared script/`ui_page`/`files`/`data_file` entries, and
whether/where it is started in `server.cfg`. It does **not** yet know anything
about what happens at runtime.

## Terminology

`resource-registry.yaml` (schema version 2) classifies every row with an
`entry_kind`, so that a raw manifest count is never confused with a count of
resources actually expected to run. These terms are used consistently across
`README.md`, `resource-registry.yaml`, and `resource-summary.md`:

- **Inventory row** — any single entry in `resource-registry.yaml`'s
  `resources` list. There are 50 in this phase. This is the broadest,
  least-specific count and should rarely be quoted on its own.
- **Manifest candidate directory** — any directory under `resources/` where a
  `fxmanifest.lua` (or `__resource.lua`) was physically found, regardless of
  where that directory sits or whether FXServer is expected to load it. There
  are 49 in this phase.
- **Non-nested resource candidate** (`entry_kind: resource`) — a manifest
  candidate directory that is *not* physically inside another manifest
  candidate directory's own tree. This is the count to use when reasoning
  about "how many resources does this repository actually run." There are 47
  in this phase.
- **Nested manifest candidate** (`entry_kind: nested_manifest_candidate`) — a
  manifest candidate directory found physically inside another manifest
  candidate directory. Retained in the registry as evidence, but excluded from
  the non-nested resource candidate count. There are 2 in this phase
  (`resources/[core]/bcrypt/dist`, `resources/[core]/nv_cloth/nv_cloth`) —
  see `resource-summary.md` for the evidence behind each.
- **Configured manifest-missing folder** (`entry_kind:
  configured_manifest_missing`) — a folder referenced by an `ensure`/`start`
  line in `server.cfg` whose directory exists but contains no FiveM resource
  manifest of any kind. There is 1 in this phase (`gn_dual_mediccenter`).

Each row also carries `expected_loadability` (`expected` /
`unlikely_nested` / `unavailable_no_manifest`) and `loadability_confidence`
(`extracted` / `inferred_platform_behavior`), so a reader can tell at a glance
whether a loadability claim was read directly from a file or reasoned about
FXServer's general behaviour.

### Extracted fact vs. inferred platform behaviour

An **extracted fact** was read directly out of a manifest, `server.cfg` line,
or the filesystem — it has an `evidence` path and does not depend on any
assumption about how FXServer behaves at runtime. An **inferred platform
behaviour** is a conclusion that depends on how FXServer's resource discovery
is generally understood to work (e.g. "resource discovery does not typically
recurse into an already-discovered resource's own subdirectories"), which has
**not** been runtime-verified against this specific repository — no server was
started or restarted to confirm it, by design (see the safety rules each
phase operates under). Both `expected_loadability: unlikely_nested` rows in
this phase carry `loadability_confidence: inferred_platform_behavior` for
exactly this reason — treat that classification as a reasoned hypothesis, not
a proven fact, until a later phase can check it against real FXServer output.

## What is deliberately not in Phase 1

The following are **not** covered yet and are explicitly reserved for later
phases, once a runtime source scan is performed:

- events (`RegisterNetEvent`, `AddEventHandler`, `TriggerEvent`/`TriggerServerEvent`)
- exports and their actual call sites
- NUI callbacks (`RegisterNUICallback`) and their message contracts
- SQL table reads/writes and cross-resource database relationships
- permission/ACE identifiers actually checked in code
- any other cross-resource runtime call that isn't a declared manifest
  dependency

`resource-summary.md` has a section titled **"Unresolved — requires runtime
source scan"** that exists specifically to hold the placeholder list for this
future work, so nothing here is silently assumed complete.

## Extracted vs. inferred — do not confuse the two

Every fact in `resource-registry.yaml` is an **extracted** fact: it was read
directly out of a manifest or `server.cfg` line, with an `evidence` path
pointing at the source. Nothing in this file is a guess about what a resource
*probably* does based on its name, its neighbours, or common FiveM conventions.

Where the repository itself contains an ambiguity — a nested manifest
candidate, a special engine dependency marker (like `/assetpacks` or
`/onesync`) that isn't actually a resource, a folder referenced in
`server.cfg` with no matching manifest — that ambiguity is recorded in the
resource's own `unresolved` list, and classified via `entry_kind` /
`expected_loadability` / `loadability_confidence` (see Terminology above),
rather than silently resolved one way or the other. Treat every `unresolved`
entry, and every row with `loadability_confidence:
inferred_platform_behavior`, as something that still needs a human or a later
phase to confirm before being relied on for a high-risk change.

## Keeping this current

`resource-registry.yaml` and `resource-summary.md` are generated data, not
hand-authored documentation. Whenever a resource is added, removed, renamed, or
has its `fxmanifest.lua` or `server.cfg` `ensure` line changed, this phase's
extraction should be re-run and these two files regenerated. Treat a stale
registry as untrustworthy — check its evidence paths still resolve before
trusting it for a non-trivial change.
