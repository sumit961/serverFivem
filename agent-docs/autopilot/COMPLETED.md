# COMPLETED

## Cycle 29 - GANG-004 invite decline race repair

- Made invitation decline consume exactly one matching pending, unexpired row
  before activity logging or success notification. The update also binds the
  target character, preserving the existing invite ownership boundary.
- A periodic expiry or competing response that wins first now produces a
  zero-row decline update, returns the existing expired failure, and cannot
  create an `invite_declined` activity row or false success message.
- Preserved the public response event, schema, response lock and acceptance
  transaction. No migration or cross-resource contract change was required.
- Lua and JavaScript syntax passed. Validator reported 0 errors and the same 3
  baseline warnings. The CM scanner refreshed with 0 errors and reports
  current. `git diff --check` passed with line-ending notices only. Real MySQL
  decline/expiry and simultaneous-response behavior remains a manual FXServer
  test.

## Cycle 26 - GANG-004 invite expiry race repair

- Made invite acceptance consume the pending, unexpired invite before member
  creation in the same transaction. The membership insert is gated by the
  invite update's `ROW_COUNT() = 1`, so an expiry worker that wins the row race
  cannot leave a membership behind.
- Added an accepted-invite/member postcondition before state refresh, activity
  logging and the success response. Losing expiry or duplicate response paths
  therefore cannot report a successful join.
- Preserved the existing unique character membership constraint, server-chosen
  gang/rank, response lock, physical revalidation and public event contract.
- Lua and JavaScript syntax passed. Validator reported 0 errors and the same 3
  baseline warnings. The CM scanner refreshed with 0 errors and `--check`
  reports current. `git diff --check` passed with line-ending notices only.
  Real MySQL expiry-boundary and simultaneous-response behavior remains a
  manual FXServer test.

## Cycle 22 - GANG-008 armory lock cleanup repair

- Wrapped the locked armory checkout in protected execution and guaranteed
  removal of both the operation lock and its ownership record on success,
  handled failure, or thrown error.
- Added safe exception compensation for issue journals created before item
  delivery, while treating post-delivery activity-log failure as a logging
  failure instead of inviting a duplicate checkout retry.
- Tracked lock ownership by persistent character ID and current source so
  disconnect cleanup removes every matching lock and cooldown even after the
  playerdata session has already unloaded. Resource stop resets all related
  lock, owner, source and cooldown state.
- Lua syntax passed for all 13 `cm-gang` Lua files and JavaScript syntax passed
  for its one JavaScript file. Validator reported 0 errors and the same 3
  baseline warnings. The CM scanner refreshed with 0 errors and `--check`
  reports current. `git diff --check` passed with line-ending notices only.
  FXServer exception/disconnect concurrency remains a manual runtime test.

## Cycle 18 - GANG-011 security, compatibility and cleanup review

- Reviewed the gang network events, ox callbacks, NUI/admin bridge, exports,
  database mutations, permission/hierarchy checks, proximity/bucket/entity
  guards, mutation locks, rate limits, persistent vehicle identity and cleanup
  handlers against the approved security checklist.
- Confirmed exactly four fixed gang IDs, character-based one-gang membership,
  no duty/cross-domain membership mutation, G-only recruitment, local asset
  allowlists, wallet-only cash robbery, inventory-owned exact-row transfer,
  and owner-controlled stash/armory/fleet integrations.
- Confirmed optional owner resources remain guarded soft integrations and the
  final manifest adds no hard dependency cycle. Updated stale resource docs to
  describe the completed fleet/admin/NPC/service integrations.
- Repaired the fleet return path so requests are rate-limited and serialized by
  gang/catalog vehicle, with guaranteed lock release after owner errors. This
  prevents concurrent return callbacks from repeating persistent transitions,
  organization-key cleanup or activity writes for one `vehicle_id`.
- Lua and JavaScript syntax passed. Validator reported 0 errors and the same 3
  baseline warnings. Scanner refreshed with 0 errors and reports current.
  `git diff --check` passed with line-ending notices only. Runtime FiveM,
  OneSync, NUI and disposable-database testing remains required.

## Cycle 15 - GANG-010 central administration and recovery

- Added a dedicated F11 Gangs page showing exactly `gang_1` through `gang_4`
  with no create, delete, duty or recruitment controls.
- Added separate `gang.admin.view` and `gang.admin.manage` permissions. Every
  browser action is reauthorized by `cm-admin` and again by the `cm-gang`
  owner export; direct calls from other resources fail closed.
- Added identity/enablement, allowlisted local art keys, leader assignment and
  removal, server-captured NPC/facility locations, database-authoritative rank
  permission editing, armory catalog configuration, fleet placement, recent
  activity and bounded recovery controls.
- Leader replacement is transactional, respects the one-gang-per-character
  constraint, and demotes the previous leader to the highest non-leader rank.
  Removing a leader retains that character as a member and leaves the explicit
  leader vacancy visible for recovery.
- Cycle 16 follow-up repaired the view/manage split in the owner payload and
  replaced partial state refreshes with a complete database-domain reload plus
  online state resynchronization after identity, leader and rank mutations.
  The page now also shows configured armory/fleet rows and bounded leader/stale
  invite diagnostics.
- Lua and JavaScript syntax passed. Validator remained at 0 errors and 3
  baseline warnings. Scanner refreshed with 0 errors and reports current.
  Graphify refreshed code-only. `git diff --check` passed with line-ending
  notices only. FiveM/NUI/database behavior remains manual testing.

## Cycle 14 - GANG-009 persistent fleet

- Added a `cm-gang` fleet owner using the existing `rn-vehicleshop` catalog
  and `cm-vehicles` persistent/entity lifecycle. Every configured fleet row
  retains one authoritative `vehicle_id`; model remains only its catalog key.
- Added permission/tier/enabled/facility/distance/bucket/entity checks,
  per-vehicle operation locks and request throttles for dashboard call/return.
- Added current-authority vehicle access routing in `cm-vehicles` for the four
  immutable gang owner IDs. Gang access never creates personal ownership and
  sell/delete/key-management/family-sharing operations remain protected.
- Added revocable organization session-key records for active callers. Every
  key action delegates back to `cm-gang:GetVehicleAccessDecision`; records are
  removed on return, character/disconnect cleanup, access loss or resource stop
  and never represent personal ownership.
- Added `cm-admin`-only placement/configuration exports. Placement uses a
  temporary server-tracked vehicle, reads its server entity coordinates on
  confirmation, preserves an existing persistent identity, and cleans up on
  cancel, timeout, disconnect and resource stop.
- Gang recall deliberately does not copy legal-fleet repair/refuel behavior;
  genuine saved fuel and engine/body/tank condition, including zero health,
  remain under `cm-vehicles` authority.
- Lua and JavaScript syntax passed. Validator remained at 0 errors and 3
  baseline warnings. Scanner refreshed with 0 errors and reports current.
  Graphify refreshed code-only. `git diff --check` passed with line-ending
  notices only. FiveM/OneSync entity behavior remains manual testing.

## Cycle 12 - GANG-008 stash and armory

- Added shared gang stashes through the existing `cm-inventory` external
  storage owner, isolated by fixed gang ID.
- Added a generic owner-validator seam in `cm-inventory`; membership,
  `gang.stash`, enabled facility, distance and routing bucket are rechecked on
  open and every deposit/withdraw. Safe stash activity is recorded.
- Added authoritative gang armory listing/checkout from enabled `cm-weapons`
  weapon/ammunition IDs with tier, facility, cooldown, capacity and issue-limit
  checks. Weapon serial/durability/hash metadata is server-created and no
  firearms-license or duty rule exists.
- Added idempotent `002_cm_gang_armory_issues.sql`; schema readiness now requires
  its issue journal. Lua/JavaScript syntax passed. Validator remained at 0
  errors and 3 baseline warnings. Scanner refreshed with 0 errors and reports
  current. Graphify was refreshed code-only. `git diff --check` passed with
  line-ending notices only. Database/FiveM behavior remains manual testing.

## Cycle 11 - GANG-007 chat, dashboard, NPC and facilities

- Added authoritative `/g` and CM Chat GANG-tab routing with current
  membership, `gang.chat`, cooldown and same-gang recipient rebuilding.
- Added `/gang` plus F8 NUI with Overview, Members, Ranks & Access, Vehicles,
  Armory, Stash and Activity. Payloads are server-built and permission-filtered;
  there is no recruitment control.
- Added existing-member rank assignment/removal through the GANG-003
  hierarchy-safe owner APIs.
- Added one member-specific headquarters NPC driven by stored facilities,
  allowlisted models and routing-bucket checks, with dashboard service and
  resource cleanup.
- Lua/JavaScript syntax and repository validation passed. Validator remained
  at 0 errors and 3 baseline warnings. Scanner refreshed with 0 errors and
  reports current. Graphify refreshed code-only. `git diff --check` passed
  with line-ending notices only.
- FiveM NUI, state-bag, NPC/OneSync and multiplayer chat behavior remains an
  explicit manual runtime suite. No production database was touched.

## Cycle 10 - GANG-006 search and atomic item robbery

- Added conditional Search Player and Rob Items actions to the existing
  `cm-playerdata` G-menu registry with authoritative robbery-state checks.
- Added rate-limited search using sanitized item data and short-lived,
  single-use opaque tokens; clients never receive row IDs or full metadata.
- Added `cm-items` `robberyProtected` authority and protected `id_card` and
  `driver_license` by default.
- Added a `cm-gang`-only `cm-inventory` exact-row transfer with protection,
  bag, weight, slot, stack and unique-item enforcement. Stored metadata moves
  through atomic SQL rather than Remove+Add/refund composition.
- Added equipment/UI refresh, inventory audits, and `player_searched` and
  `item_stolen` gang activity records.
- Lua/JavaScript syntax passed. Validator: 0 errors and 3 baseline warnings.
  Scanner: 0 errors and current. Graphify refreshed code-only. `git diff
  --check` passed with line-ending notices only.
- Real MySQL concurrency and FiveM equipment behavior remain runtime tests.

## Cycle 9 - GANG-005 robbery authority and cash

- Added a reusable server-only robbery guard validating current character
  membership, feature permission, enabled gang, distinct online target,
  routing bucket, server entity distance, and authoritative cuffed/dead state.
- Added conditional G-menu Rob Cash visibility with no client-side permission
  map. The network handler independently repeats all authorization checks.
- Added per-actor throttling and one shared per-target robbery lock, with
  disconnect/resource-stop cleanup and a final validation inside the lock.
- Added a trusted `cm-playerdata` cash-only atomic transfer contract. It locks
  both live balances, flushes them, and conditionally debits/credits both
  character rows in one SQL statement; stale balances fail closed.
- Cash robbery affects wallet cash only, never bank, and records both economy
  transactions plus a safe `cash_stolen` gang activity entry.
- Lua and JavaScript syntax passed. Validator remained at 0 errors and 3
  baseline warnings. CM scanner refreshed with 0 errors and reports current.
  `git diff --check` passed with existing line-ending notices only.
- OneSync, disconnect timing, state bags and real database concurrency remain
  explicit manual runtime tests. No production database was touched.

## Cycle 8 - GANG-004 G-menu invitations

- Added a conditional Gang page to the existing `cm-playerdata` G interaction
  registry. The client requests only a server-derived eligibility boolean, so
  gang permission maps remain server-only and civilians/unauthorized ranks see
  no Gang page.
- Registered one `gang_invite` extension action through `cm-playerdata`; no
  second targeting system, dashboard recruitment, CID/server-ID search, offline
  invite, or client-selected gang/rank path was added.
- Added persisted approximately 60-second invitations. The server selects the
  actor's gang and current lowest non-leader rank, rejects self/occupied/
  duplicate/rate-limited targets, and validates loaded characters, current
  permission, enabled gang, online state, routing bucket, server entity and
  three-metre proximity.
- Added target Accept/Decline confirmation. Acceptance repeats actor, target,
  membership, gang, permission, entry-rank, bucket and proximity checks before
  transactionally inserting the unique character membership and resolving the
  invite. Decline, expiry, disconnect and resource-stop state are cleaned.
- Added safe invite/join/decline activity records and a trusted server-only
  owner refresh seam so accepted membership immediately refreshes `cmGang`.
- Lua syntax passed for all seven gang Lua files; gang JavaScript syntax passed.
  Validator remained at 0 errors and 3 baseline warnings. The CM scanner
  refreshed with 0 errors and `--check` reports current. Graphify refreshed
  code-only. `git diff --check` passed with existing line-ending notices only.
- OneSync/database/UI behavior remains an explicit manual runtime test. No
  production database was touched.

## Cycle 7 - GANG-003 owner domain, ranks and members

- Added the server-only `cm-gang` owner domain with database-backed fixed-gang,
  rank, member and permission caches. Online members receive only privacy-safe
  gang/rank presentation in replicated `cmGang` state; CIDs and permission maps
  are not replicated.
- Added documented read exports for membership, permission decisions, gang
  identity, authorized rank lists and authorized member lists. Returned values
  are copies and all identity arguments are persistent character IDs.
- Added per-gang mutation serialization and per-character throttling for rank
  create/rename/re-tier/delete, permission edits, existing-member rank changes,
  removal, and current-leader transfer.
- Enforced server-side permission and hierarchy rules: no self mutation, no
  equal/higher target mutation, no destination at/above the actor, no leader
  rank edit/delete, no leader removal, no unknown permission, and no granting a
  permission the actor lacks.
- Leadership transfer changes both member flags/ranks and
  `cm_gangs.leader_character_id` in one database transaction, then refreshes
  both online state bags. High-value mutations write safe gang activity rows.
- Added no network-safe mutation event, duty state, fifth-gang path, or family,
  Police, EMS, or legal-organization mutation.
- Lua syntax passed for all six resource Lua files. Validator remained at 0
  errors and 3 baseline warnings. The CM scanner refreshed with 0 errors and
  `--check` reports current. Graphify was refreshed code-only. `git diff
  --check` passed with pre-existing line-ending notices only.
- Database/FiveM behavior was not claimed from static checks. Exact cache,
  hierarchy, throttle, disconnect and leadership tests are recorded in
  `RUNTIME_TESTS.md`. No production database was touched.

## Cycle 6 - GANG-002 resource and fixed schema

- Created one `resources/[core]/cm-gang` resource with an immutable allowlist for `gang_1` through `gang_4`, `/gang`, `/g`, F8, security limits, facility types, local asset allowlists and the complete `gang.*` permission catalog.
- Added a fail-closed database readiness check. The resource exposes only fixed-ID/readiness scaffolding in this cycle and has no client mutation event, NUI callback, dynamic create/delete path or duty state.
- Added additive `sql/001_cm_gang.sql` defining gangs, ranks, members, invites, activity, facilities, fleet authorization, armory configuration and migration journal tables.
- The migration uses `INSERT IGNORE` for exactly four disabled fixed gang rows and seeds Leader/Underboss/Enforcer/Member/Recruit only when a gang has no ranks, so later customization is not overwritten on restart/rerun.
- Enforced one gang per character, one leader rank/member slot per gang, rank-to-gang consistency, indexed activity/invites, and `BIGINT UNSIGNED vehicle_id` fleet identity.
- Lua syntax, JavaScript syntax and manifest path checks passed. Validator: 0 errors and the same 3 baseline warnings. CM scanner refreshed with 0 errors and `--check` reports current. Graphify code-only graph refreshed. `git diff --check` passed with existing line-ending notices only.
- SQL received static schema/idempotency/security review but was not executed because no disposable database or MySQL/MariaDB client is available. No production data was touched.

## Cycle 5 - GANG-001 baseline and contracts

- Established a working repository interpreter at the installed Graphify tool environment; the Windows Store `python.exe` remains unusable.
- Ran `tools/cm-validate/validate.py`: 0 errors, 3 baseline warnings (two missing `map4all-pillbox` manifest paths and a potentially stale resource registry).
- Ran `tools/cm-fivem-map/scan.py --root . --out cm-agent-out --check`: output is current.
- Confirmed Graphify was built from current HEAD `e0a09b1f`; ran a scoped query over family, character/player interaction, inventory, vehicles, chat, ranks and permissions.
- Reconfirmed from Lua source that `/g`, `/gang`, and F8 are unclaimed. Existing mappings remain G=`cm-playerdata`, F6/F9/TAB/J=`cm-core`, and F7=`cm-hud`.
- Captured the dirty tree and preserved all unrelated Police/EMS/legal/admin work. No gameplay code, protected path, database content, commit, push, or deployment was performed.
- `git diff --check` passed; it emitted only existing LF-to-CRLF notices.
