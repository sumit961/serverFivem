status = approved

# Complete CM gang system implementation plan

## Goal

Create one authoritative `resources/[core]/cm-gang` framework serving exactly four fixed IDs (`gang_1`â€“`gang_4`). Membership is character-based, independent of family/Police/EMS/`cm-law`, and has no duty state. Deliver secure ranks, G-menu invitations and robbery, dashboard, NPC/facilities, chat, stash, armory, persistent fleet, `cm-admin` configuration, recovery, and auditing by extending existing owner APIs rather than duplicating them. Implementation starts only after explicit approval.

## Audited architecture decisions

- `cm-family` is the closest rank/hierarchy/invite/activity/G-menu/NPC/chat/dashboard reference, but gangs receive separate schema, state and APIs. No family or legal membership mutation is involved.
- Existing organization memberships use their own character-keyed tables. `cm_gang_members.character_id` will be unique; it will neither query nor remove family/job membership. No `on_duty` field/check will exist.
- `cm-playerdata` owns G via its interaction registry and supplies character/source lookup, target validation, death state and wallet APIs. Gang registers conditional options there; no second targeting system.
- Server-observable robbery states currently available are `Player(target).state.cmCuffed` and `cm-playerdata:IsDead`. Core accepts only those. No client-only hands-up flag.
- `cm-inventory` owns inventory rows, external storage and metadata. It lacks an atomic player-to-player exact-row transfer, so a minimal trusted export is required; never compose Remove+Add.
- `cm-items` has no robbery-protection property today; add an authoritative `robberyProtected` definition/config field. Ordinary items default stealable; protect only verified system/identity/admin/dev/quest items.
- `cm-weapons` owns database weapon/ammo definitions. Armory stores catalog IDs and issues through inventory metadata/serial rules, without firearms-license checks.
- `cm-vehicles` owns `vehicle_id`, entity registry, operations, location, condition, recall and duplicate cleanup. `rn-vehicleshop` owns catalog metadata. Gang stores fleet authorization/config references only.
- `cm-chat` exposes channel/group/message APIs and an owner-authoritative family precedent. Gang follows that pattern; `/g` is registered only if still free.
- F6/F9/TAB/J are organization controls, G is interaction, and F7 is HUD. Repository audit found F8 unclaimed; use `/gang` plus configurable F8 without editing F6 routing.
- `cm-admin` owns F11/permissions/configuration. Its Gangs page shows exactly four rows; every NUI action is reauthorized server-side.
- `cm-ui` supplies the cyan foundation; gang accents/local allowlisted art are permitted. No arbitrary URLs, purple primary accent, or `backdrop-filter`.
- The dirty tree contains extensive unrelated Police/EMS/legal/admin work. Re-read overlapping files and patch surgically; never revert it.
- Graphify matches HEAD and was used only for generic paths. The CM map was queried, but `scan.py --check` could not execute because this environment only exposes a broken Windows Store Python shim. Establish a working baseline before code edits.

## Scope exclusions

- No fifth/dynamic gang, player create/delete, dashboard/offline/ID recruitment, NPC recruitment, duty, gang bank/dirty money, reputation, missions, territories, graffiti, wars, safehouses, drug systems, businesses, chop operations, or contracts.
- No redesign of family, Police, EMS, `cm-law`, houses, inventory/weapons/vehicle persistence, Spike/Barricade, or F6/F9/TAB/J/G mappings.
- No protected `server.local.cfg`, `db/`, credentials/backups/private MLO/clothing/assets; no destructive migration, production data, commit, push, or deploy.

## Ordered plan

### GANG-001 â€” Baseline and contracts

1. Snapshot dirty status/diff and generated-map unresolved counts without reading/logging protected content.
2. With a working interpreter run validator and scanner `--check`; query affected events, exports, NUI/callbacks, commands, permissions and tables. Separate pre-existing failures.
3. Reconfirm `/g`, F8, manifests/start order and actual API signatures. Stop on incompatible contracts or overlapping edits that cannot be preserved.

### GANG-002 â€” Resource and fixed schema

1. Create one `cm-gang` manifest/config/server/client/NUI/docs/resource-local SQL package; hard-depend only on essential owners and use guarded soft integrations to prevent cycles.
2. Define the immutable four-ID allowlist, permissions, rate/proximity/expiry limits, facility types, restricted asset keys and configurable `/gang`/F8.
3. Add idempotent `cm_gangs`, `cm_gang_members`, `cm_gang_ranks`, `cm_gang_invites`, `cm_gang_activity`, `cm_gang_facilities`, `cm_gang_fleet_vehicles`, `cm_gang_armory_config`, plus migration/journal metadata where needed.
4. Constrain IDs to four, unique membership character, gang+tier, invite, facility, fleet `vehicle_id`, and activity indexes. Seed four gangs with INSERT IGNORE and Leader/Underboss/Enforcer/Member/Recruit once only; never overwrite customization on restart.
5. Keep one highest leader per enabled gang through serialized transactions and diagnostics. Zero/multiple-leader states require explicit logged admin recovery, never silent selection.

### GANG-003 â€” Owner domain, state, ranks and members

1. Load/cache database authority; resolve sessions through `cm-playerdata` but persist/log CIDs. Replicate only privacy-safe `cmGang` identity/rank presentation.
2. Implement fixed-ID, membership, permission/tier, enabled-feature and hierarchy decisions; publish documented server exports and server-only integration events, not generic client mutations.
3. Implement permission catalog: `gang.view_members`, `manage_members`, `manage_ranks`, `manage_permissions`, `chat`, `vehicle`, `manage_vehicles`, `armory`, `manage_armory`, `stash`, `manage_stash`, `invite`, `search`, `rob_cash`, `rob_items`, `view_logs` (all `gang.*`).
4. Implement rank CRUD/re-tier/permission edits and existing-member promote/demote/assign/remove. Actor must outrank target and destination; normal UI cannot demote/remove leader or modify equal/higher members.
5. Leader replacement atomically changes leader/member/rank state. Apply mutation locks/rates and log all high-value actions. Load/unload/restart clears stale state without touching other membership domains.

### GANG-004 â€” G-only invitations

1. Register a conditional Gang page/options through `cm-playerdata`; civilians see none. Dashboard/admin/NPC offer no ordinary recruitment.
2. Server validates actor/target CIDs, distinct and online, same bucket, server ped distance, actor gang/`gang.invite`, enabled gang, target no gang, duplicate/rate/expiry; server chooses gang and lowest rank.
3. Persist ~60-second invite and Accept/Decline prompt. Acceptance revalidates everything and transactionally inserts membership/deletes invite. Expiry/decline/disconnect/restart clean up and log safely.

### GANG-005 â€” Robbery authority and cash

1. Show Search/Rob Cash/Rob Items only for locally eligible members, with server authority decisive.
2. Central guard validates enabled gang, current permission, actorâ‰ target, loaded/online, same bucket, server distance/entity, and target `cmCuffed` or authoritative dead/downed state.
3. Add per-actor throttles and one per-target lock shared across search/cash/items; clear it on every failure/disconnect/timeout/stop.
4. Cash UI requests an amount, but server resolves wallet balance. Reuse or add a trusted `cm-playerdata` two-character atomic transfer/journal contract: bounded integer, debit-before-credit transaction/rollback, idempotency, no negative/creation, bank untouched, logged CIDs.

### GANG-006 â€” Search and atomic item robbery

1. Add a trusted-resource `cm-inventory` exact-row player-to-player transfer export. It resolves both character owners, locks/re-reads the victim row, validates quantity/protection and destination capacity/stack/unique rules, and transactionally transfers while preserving metadata, durability, serials and unique IDs.
2. If destination cannot accept, remove nothing. Verify invoking resource, refresh both inventories/equipment, audit safe summary, and release locks. `cm-gang` retains robbery authorization.
3. Add `cm-items` robbery protection. Search returns a sanitized authorized inventory view; opaque slot/row tokens are revalidated on transfer.
4. Weapons/ammo use the same transfer. If unique weapon metadata cannot safely validate, deny and record a runtime decision rather than minting/reconstructing it.

### GANG-007 â€” Chat, dashboard, NPC and facilities

1. Register gang channel/group state with `cm-chat`; owner path checks `gang.chat` and rebuilds current same-gang recipients each message. Use character identity, safe accent, sanitization/cooldown/logging. `/g` uses the identical path.
2. Build NUI sections Overview, Members, Ranks & Access, Vehicles, Armory, Stash, Activity using `cm-ui`; no duty/recruitment/card wall. Permission-filter payloads and validate every callback.
3. `/gang` and F8 open only for members, do not change organization mappings, and handle missing local art cleanly.
4. Spawn one configurable NPC per enabled gang (allowlisted model, safe name/role, stored coords/heading/bucket). Services are Dashboard/Vehicles/Armory/Stash only when configured/permitted; hide prompts while UI/inventory is open.
5. Store headquarters/armory/stash/fleet facility records and validate server proximity/bucket for use.

### GANG-008 â€” Stash and armory

1. Open `cm-inventory` external storage after membership, `gang.stash`, enabled facility, distance/bucket checks using `owner_type=gang_stash`, `owner_id=<gang_id>` (conceptually `gang_stash:<gang_id>`), unique slots. `manage_stash` controls configuration/recovery.
2. Add narrow deposit/withdraw hooks so gang activity records actor CID, direction, item ID/quantity and safe identifiers, never full contents.
3. Armory config stores authoritative item ID, enabled, min tier, quantity and issue/limit fields. Resolve through `cm-weapons`/`cm-items`; client cannot supply label/price/hash/metadata/ammo.
4. At configured proximity validate membership, `gang.armory`, tier, item and cooldown/limits/capacity; issue through inventory serial/metadata conventions with gang issuer and idempotent locks/journal. Never check firearms license.

### GANG-009 â€” Persistent fleet and keys

1. Follow current Police/EMS/legal fleet lifecycle: catalog model, persistent `vehicle_id`, min tier, enabled/status, fixed coords/heading/bucket and availability.
2. Resolve catalog via `rn-vehicleshop`; create/associate records only through `cm-vehicles`. Add a narrow generic gang authorization seam there only if existing organization APIs cannot represent gangs without coupling.
3. Call/store/recall validates gang, `gang.vehicle`, tier, fleet match, location/bucket/entity/vehicle ID and operation lock. Reuse live entity; never duplicate or use plate/net ID as database identity.
4. Add narrow session-key grant/revoke through `cm-vehiclekeys`/`cm-vehicles`; revoke on permission/rank/member/disable/return/disconnect/reassignment and never grant personal ownership.
5. Admin placement tracks a server-authorized dummy/session, reads authoritative entity/admin coordinates at confirm, saves through owner, and cleans on cancel/timeout/disconnect/stop. Members cannot place.
6. Preserve actual engine/body/tank/fuel/mod state, including zero health, through current persistence/location APIs.

### GANG-010 â€” `cm-admin` management and recovery

1. Add F11 Gangs page with exactly four rows and no Create/Delete: Overview, Identity, Leader, NPC/HQ, Facilities, Ranks, Permissions, Vehicles, Armory, Stash, Activity/Recovery.
2. Add dedicated admin permission(s). Each NUI action is checked by `cm-admin` then revalidated by trusted `cm-gang` exports.
3. Validate identity lengths/color/local asset key/enabled state. Location actions read authorized admin ped/entity/bucket server-side; reject NUI coordinates.
4. Recovery reports/repairs missing/multiple leader, orphan rank/member/fleet references, stale invites/locks and vehicle inconsistencies via bounded explicit logged actions.

### GANG-011 â€” Security, compatibility and cleanup review

1. Review every event/callback/NUI/export/write/mutation for source/CID, permission/hierarchy, ownership, distance/bucket, entity/persistent ID, amount/catalog authority, replay/rate/lock, transaction, SQL parameters, exposure and logging.
2. Confirm no duty read, other-domain mutation, source/account leak, external URL, fifth gang or hard dependency cycle.
3. Document permissions, APIs, tables/migration/start order, admin setup, recovery/failures. Clean invitations, locks, NUI/storage, NPCs, placement, keys and cached state on disconnect/stop.

## Validation and review gates

### GATE-V1 â€” Incremental

- After each item: diff review, Lua syntax, `node --check` for JS, HTML/CSS asset/NUI callback checks, fxmanifest paths and targeted contract searches.
- Review migrations for idempotency, constraints, parameterization and transactions; execute only on a disposable non-production database.

### GATE-V2 â€” Contracts/dependencies

- Run scanner refresh then `--check`; compare new unresolved/missing/context-mismatch relationships against baseline. Refresh Graphify code-only after material call-graph changes and run scoped queries.
- Validate resource start order and dependency graph; no new hard cycle.

### GATE-V3 â€” Final static

- `python tools/cm-validate/validate.py` has zero errors; scanner check passes; all changed Lua/JS/manifests/migrations pass; `git diff --check` passes.
- Final diff/security review confirms protected/unrelated work untouched, no client authority, duty/cross-membership coupling, dynamic gangs, plate/net persistence, secret/debug leak, or unbounded payload/query.
- Static checks do not prove FiveM runtime behavior.

### GATE-V4 â€” Manual FiveM runtime suite

Record exact results in `RUNTIME_TESTS.md`:

1. Boot/migrate twice: exactly four rows, one-time ranks, custom config preserved, restart/state/start-order clean.
2. Same character in family+gang+Police/EMS/legal; one-gang-only and no duty.
3. G invite accept/decline/expiry/duplicate/self/occupied/distance/bucket/disconnect/simultaneous accept; no dashboard recruitment.
4. Rank/member/leader actions as leader/lower/equal/unauthorized/admin recovery.
5. `/gang`, F8, all tabs/art fallback/NUI reopen and unchanged F6/F9/TAB/J/G.
6. NPC/facilities as member/nonmember/unauthorized/distant/wrong bucket/disabled/restart.
7. Chat tab and `/g`: same gang only, cross-gang denial, identity/cooldown/restart.
8. Stash: four unique owners, deposit/withdraw/capacity/stack/metadata/concurrency/auth/log/restart.
9. Armory: tier/permission/item/quantity/limit/full inventory/concurrency/serial/no-license/disabled/log.
10. Fleet: catalog/placement cancel/disconnect/call/store/recall/tier/keys/live concurrency/restart/same `vehicle_id`/no duplicate/damage and zero-health preservation.
11. Search/cash/items: cuffed/dead allowed; standing denied; self/distance/bucket/disconnect/permission loss/disabled/rate/two robbers/stale slot/partial/protected/full destination/weapon serial/cash bounds; bank unchanged.
12. Audit visibility and safe details for every high-value action without full inventory/account/session leaks.

## Risks

- Dirty admin/org overlap: surgical patches; stop rather than overwrite.
- Inventory/cash race gaps: add owner-controlled atomic contracts, never multi-export emulation.
- No authoritative hands-up: cuffed/dead only.
- Vehicle API not gang-generic: narrow owner seam; never duplicate persistence.
- Leader concurrency: serialized transactional mutation and diagnostics.
- Cycles: gang calls owner APIs; owners expose generic seams without depending on gang.
- OneSync/NUI/runtime-only failures: after three identical failed repairs record runtime blocker instead of guessing.
- Scanner baseline: GANG-001 blocks edits until working Python establishes it.

## Exact acceptance criteria

1. Exactly four fixed gangs exist; no fifth/create/delete path.
2. Unique CID gang membership coexists with family/jobs; no duty schema/check/UI.
3. Database-authoritative ranks/permissions seed once; one protected leader with recovery.
4. Recruitment is G-only and passes all identity/online/gang/permission/distance/bucket/expiry/rate/revalidation rules.
5. Dashboard/NPC/admin cannot remotely recruit.
6. `/gang`+F8 dashboard works without changing F6/F9/TAB/J/G and meets UI restrictions.
7. One configurable NPC/HQ per gang exposes authorized services.
8. Gang chat uses `cm-chat` and current same-gang recipients only.
9. Search/robbery requires current permission and authoritative cuffed/dead, proximity, bucket and distinct online target.
10. Cash transfers wallet only atomically, bank unchanged, no negative/creation/duplication.
11. Item transfer is atomic through inventory, preserves exact metadata/serial/unique state, protects configured items and removes nothing on capacity failure.
12. Stash uses four unique `cm-inventory` external owners with server auth.
13. Armory uses authoritative weapon/item IDs, gang/tier/limit checks, serial metadata, and no firearms license.
14. Fleet uses shop catalog plus `cm-vehicles`; fixed locations and condition persist under authoritative `vehicle_id`, without duplicates.
15. Keys derive from current gang authority and never personal ownership.
16. `cm-admin` securely configures all four gangs and has no Create/Delete button.
17. Safe activity rows record gang/action/time/actor CID and optional target CID/vehicle ID for all required high-value actions.
18. Direct event/callback/NUI invocation fails closed with relevant server checks/locks/rates.
19. Disconnect/restart leaves no stale invite/lock/key/placement/entity/state.
20. Validator zero errors, syntax/manifests/migrations/scanner and `git diff --check` pass; no new contract mismatch or dependency cycle.
21. Protected paths and unrelated dirty work remain untouched; no commit/push/deploy.
22. Every GATE-V4 result is honestly recorded before declaring runtime completion.

## NEXT IDEAS (not core scope)

Separate future proposals: reputation, missions/contracts, territory, graffiti, rivalry/war, safehouses, drug runs, illegal businesses, shared dirty money, chop operations, and criminal contracts.
