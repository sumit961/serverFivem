# cm-family v1.9.5

Family system for the CM Framework. Players create a family from a house they
own, invite members, manage up to 15 ranks with granular permissions, share
garage vehicles gated by rank tier, run a shared family treasury, and progress
a family through weekly objectives, an HQ upgrade tree, and an inter-family
event/reward engine — all through a full-screen `/family` menu.

This document is an architecture map, not a tutorial. Read the relevant
`server/sv_*.lua` file for exact behavior before integrating against an export.

## Core systems

- **Membership & ranks** (`sv_members.lua`, `sv_ranks.lua`). Invite by
  character id (5-minute expiry, accept/decline), promote/demote, kick, leave.
  Up to 15 ranks per family, reorderable by tier, each with its own permission
  set and daily bank withdrawal limit. Two rules are enforced server-side on
  every rank edit: you can never edit a rank at or above your own tier, and
  you can never grant a permission you don't hold yourself. Founder
  succession happens automatically if the founder leaves, or explicitly via
  "make head" (rank-hierarchy and DB updates commit together).
- **Permissions** (`shared/config.lua`, `Config.Permissions`). Every
  gameplay capability (invite, promote, kick, bank withdraw, weapon storage,
  vehicle sharing, HQ purchases, event actions, etc.) is an explicit named
  permission key, never a hard-coded rank name/number. All mutating actions
  resolve the acting character's rank from the database/live cache and check
  the specific permission key server-side; the client never supplies its own
  permission state for an authorization decision.
- **Family house integration** (`sv_core.lua`'s `HasHousePermission` seam,
  `sv_bridge.lua`). cm-house stays the property/vehicle authority; cm-family
  owns people and ranks. cm-house asks `HasHousePermission(cid, familyId,
  houseId, permissionKey, action)` for every house-side decision. cm-family
  never deletes or mutates a `cm_houses` row itself.
- **Family data ownership on disband** (`sv_schema.lua`'s
  `CMFamilyDeleteFamilyRows`, `sv_core.lua`'s `FinalizeHouseFamilyDeletion`
  export). cm-family is the only resource that deletes a `cm_family_*` row.
  When a house-lifecycle action (sale, eviction, admin deletion) disbands a
  linked family, cm-house calls the single authorized
  `FinalizeHouseFamilyDeletion(familyId, houseId, reason, actorCid)` export
  (invoker-restricted to cm-house), which atomically deletes every
  family-domain row, cancels any active event first, clears every runtime
  cache (member/rank/family tables, vehicle-key cache), and immediately
  clears online members' replicated state — no restart or reconnect
  required. The delete is idempotent: calling it twice is always safe.
- **Family vehicles** (`sv_vehicles.lua`). Every shared family vehicle has a
  required minimum rank tier; a member can spawn/use it only when their rank
  tier meets that level. Vehicle physical state/identity remains owned by
  cm-vehicles at all times.
- **Tracking** (`sv_members.lua`'s meeting broadcast in `sv_menu.lua`,
  `cl_tracking.lua`). Opt-in nearby-member minimap blips and a
  server-authoritative "set meeting point" broadcast (rate-limited,
  server-verified against the sender's actual position) that updates online
  members' GPS route without a database round trip.
- **Treasury / bank** (`sv_bank.lua`). Shared family balance with atomic
  deposit/withdraw (lock + conditional `UPDATE ... WHERE balance >= ?`),
  per-rank daily withdrawal limits, and a full transaction log.
  `FamilyBankCharge` is the external-spend seam other resources use.
- **HQ & progression** (`sv_hq.lua`, `sv_progression.lua`). Reputation-gated
  HQ upgrade tiers that raise weapon-storage capacity, shared-vehicle limits,
  and other modifiers. Purchases are atomic and re-validate the current
  reputation/treasury balance server-side.
- **Objectives & contributions** (`sv_objectives.lua`,
  `sv_contributions.lua`). Weekly objective definitions are global
  (`cm_family_objectives`); per-family weekly progress
  (`cm_family_objective_progress`) and per-member daily/weekly contribution
  ledgers (`cm_family_contribution_daily/weekly`, `cm_family_member_contributions`)
  use unique-key reservations so a concurrent or duplicate contribution call
  cannot double-count.
- **Event engine** (`sv_events.lua`, `sv_raid.lua`). Inter-family events
  (including house raids) go through a `forming → active → completed/cancelled`
  state machine backed by `cm_family_event_instances`, with cooldowns
  (`cm_family_event_cooldowns`) and participant rows
  (`cm_family_event_participants`) scoped per family so disbanding one side
  never deletes the other family's event history.
- **Reward lifecycle** (`sv_events.lua`, `sv_contributions.lua`,
  `sv_hardening_tests.lua`). Every reward-bearing row (event completion,
  objective completion) carries a `reward_state` of `not_applicable` (or
  `unclaimed`) → `processing` → `delivered` / `failed`, plus a unique reward
  id reserved in `cm_family_reward_history` before payout. A background
  recovery sweep reconciles rows left stuck in `processing`/`failed` after a
  crash. This design exists specifically to prevent duplicate or lost reward
  delivery under concurrency — do not bypass the state machine or the unique
  reward id when adding a new reward source.

## Public vs. private family state (security-relevant — read before touching `cmFamily`)

`BuildFamilyMemberState` (`sv_core.lua`) builds the payload replicated to
every connected client as `Player(src).state.cmFamily` (and mirrored again by
cm-playerdata's `SetFamily`/identity cache). Because it is broadcast to every
client, not just the family in question, **it must only ever contain public
identity fields**: family id/name/tag/color, overhead symbol, rank id/name/tier,
founder flag, custom title. It must never contain a member's permission map
or any other management-capability data — that was a real privacy bug fixed
in v1.9.4. A member's own or another member's effective permissions are only
ever delivered through a dedicated, server-validated request/response path
(see `sv_gmenu.lua`'s owner-only `family_permissions` action), never through
the replicated state bag. Every mutating action independently re-checks
permissions live and server-side regardless of what any client believes its
own permissions are.

## Install

1. Database setup is automatic by default. At startup, `server/sv_schema.lua`
   creates `cm_families` and its ~18 related tables, repairs additive schema
   drift (missing columns, legacy `grade`/`perms` layouts, id-less member
   tables), validates required columns/indexes, and only then enables
   callbacks. See `sql/` for the full migration history and
   `sql/000_OPTIONAL_reset.sql` (destructive, opt-in only) if you intend to
   wipe all family data.
   - Keep `Config.Database.autoInstall = true` for normal use.
   - If your database user has no `CREATE`/`ALTER` permission, apply the
     `sql/` files manually in order.
2. Ensure `cm-house`, `cm-playerdata`, `oxmysql`, and `ox_lib` are started
   before `cm-family`.
3. Add `ensure cm-family` to your server.cfg after cm-house.
4. cm-house already authorizes cm-family in its
   `Config.Integration.authorizedResources` (scopes: access, family, garage,
   weaponStorage). No cm-house config change is required for the base flow.

## Integration exports (for other resources)

Identity / permissions:
`HasHousePermission`, `GetHousePermissionDecision`, `HasPermission`,
`GetFamilyForCharacter`, `GetFamilyMemberCharacterIds`, `GetFamilyById`,
`GetMemberIdentity`, `GetFamilyMember`, `GetFamilyExportContract`.

House lifecycle:
`FinalizeHouseFamilyDeletion` (cm-house only), `RefreshFamilyHouseLink`.

Vehicles:
`CanUseFamilyVehicle`, `GetFamilyVehicleAccessDecision`, `GetFamilyVehicleLevel`,
`SetFamilyVehicleLevel`, `SetFamilyVehicleLevelFromGarage`,
`SetFamilyVehicleShared`, `RemoveFamilyVehicle`, `InvalidateVehicleCache`,
`RequestFamilyVehicleTrack`, `GetFamilyGarageRankContext`.

Treasury:
`FamilyBankCharge`, `BankDeposit`, `CreditFamilyTreasuryAtomic`,
`GetTreasuryOverview`.

HQ / progression:
`GetFamilyHQUpgrades`, `GetFamilyHQUpgradeLevel`, `GetFamilyHQModifiers`,
`GetFamilySharedVehicleLimit`, `PurchaseHQUpgrade`, `GetFamilyProgression`,
`AddFamilyReputation`, `RemoveFamilyReputation`, `CanAwardFamilyReputation`,
`AwardFamilyActivityReward`.

Objectives / contributions:
`GetFamilyWeeklyObjectives`, `AdvanceFamilyObjective`,
`RecoverStaleObjectiveProcessing`, `GetMemberContribution`,
`AddFamilyMemberContribution`, `RecordFinancialContribution`,
`GetFamilyContributionLeaderboard`.

Events / raids:
`GetEventDefinition`, `CanFamilyStartEvent`, `CreateFamilyEvent`,
`JoinFamilyEvent`, `LeaveFamilyEvent`, `CompleteFamilyEvent`,
`CancelFamilyEvent`, `GetFamilyEvent`, `GetActiveFamilyEventForFamily`,
`StartFamilyRaid`, `GetFamilyRaidDoorState`, `CanStartFamilyRaid`.

Chat / audit:
`SendFamilyChat`, `WriteFamilyActivity`, `LogFamilyChatModeration`,
`AdminGetFamilyActivity`, `AdminGetHighRiskFamilyActivity`.

Every export above re-validates the acting character/rank/permission
server-side; none of them trust a caller-supplied permission claim.

## Notes

- One family per character (enforced by a unique key on `character_id`).
- Disbanding a family removes every `cm_family_*` row for that family in one
  transaction via cm-family's own authoritative delete (see "Family data
  ownership on disband" above). The append-only activity history
  (`cm_family_activity_log`) is intentionally retained for the configured
  audit period, matching the append-only audit contract.
- The default ranks (Head / Officer / Member / Recruit) and all permission
  keys live in `shared/config.lua`.
- `audit_pending.json` is a runtime retry queue for failed audit writes. It
  is git-ignored (not committed) — treat its production contents as live
  server data, never source content.

## Family chat integration

With `cm-chat` running, members receive a dedicated FAMILY tab using the
family colour. Both the tab and `/f` / `/familychat` route through
`cm-family`. Every active family member can use family chat regardless of
rank, with cooldowns, authoritative online recipients, family tag, rank/custom
title, and character ID. The default GTA chat event is used only when
`cm-chat` is absent.
