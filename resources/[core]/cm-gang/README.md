# cm-gang

## v0.5.0 — Supply War v2

Supply War uses server-ticked `AVAILABLE`, `CAPTURING`, `CONTESTED`, and
`SECURED` objectives. Supply crates appear immediately at configured world
locations with a server-timed parachute descent, landing smoke, and no map blip. Every secured crate
adds the same configured, idempotent package to the winning gang armory.

The server owns membership, proximity, routing bucket, alive-state, capture,
score, cooldown and rewards. Valid opposing-gang kills score; suicides and
environment deaths appear in the feed but do not score. Death immediately uses
the normal hospital flow and applies the configured re-entry cooldown. There
are no event tickets or event respawns. The admin page owns the aligned auto
schedule, circle, drop timings, reward package, scoring and cooldown values.

The consolidated internal combat contract is `cm-gang:server:eventCombatHit`
(throttled client hint plus independent server validation). Compatibility
wrappers remain for `eventDamage` and `eventCombat`. Other contracts include
`cm-gang:client:dropState` (authoritative objective snapshot). Existing
`eventJoin`, `eventBoundary`, `eventCombat`, `beginDropClaim`, event admin
exports, runtime exports, and armory exports are preserved.

Supply War entry-point rows are deprecated and ignored. Players intentionally
join with E from the configurable outer ring of the server-validated event circle and
remain at that position during the bucket transition. Event death removes the
participant from the private bucket and immediately uses cm-playerdata's
existing hospital-bed respawn, without the normal death screen or weapon drop.
No client event accepts join or respawn coordinates.

Supply-drop entities are participant-local ground visuals keyed by authoritative
drop ID. They are resynchronised for late joiners and destroyed immediately on leave,
secure, event cleanup, or resource stop. Supply objectives create no minimap or
full-map blips; the main event circle remains available.

Authoritative gang domain for exactly five canonical gangs: `marabunta`,
`bloods`, `ballas`, `families`, and `vagos`. The IDs are immutable and no
create/delete API exists. Retired `gang_1` through `gang_4` rows remain visible
only to the explicit cm-admin migration workflow.

## Ownership

`cm-gang` owns gang membership, ranks, permissions, invites, activity,
facilities, armory authorization and fleet authorization. Character identity,
inventory, items, weapons, persistent vehicles, vehicle catalog, chat and admin
presentation remain with their existing CM owners.

Gang membership is character-based, limited to one gang per character, and is
independent from family and legal/job organization membership. There is no duty
state.

## Install

Apply the numbered files in `sql/` in order to a disposable/non-production database first, then
start `cm-gang`. The resource validates the schema and fails closed when the
migration or any of the five canonical rows is missing. It never rewrites customized
gang/rank rows on restart.

Do not apply migrations to production without a backup and an approved rollout.

## Server owner API

These exports are server-only. Character IDs are persistent identities; callers
must never substitute a FiveM source. Read exports return copies so consumers
cannot mutate the owner cache.

- `IsDomainReady()`
- `GetGangForCharacter(characterId)`
- `HasPermission(characterId, permissionKey)`
- `GetPermissionDecision(characterId, permissionKey)`
- `GetGang(gangId)`
- `GetGangRanks(actorCharacterId)`
- `GetGangMembers(actorCharacterId)`
- `CreateRank(actorCharacterId, name, tier, permissions)`
- `RenameRank(actorCharacterId, rankId, name)`
- `SetRankTier(actorCharacterId, rankId, tier)`
- `SetRankPermission(actorCharacterId, rankId, permissionKey, enabled)`
- `UpdateRank(actorCharacterId, rankId, name, tier, permissions)`
- `DeleteRank(actorCharacterId, rankId)`
- `AssignMemberRank(actorCharacterId, targetCharacterId, rankId)`
- `RemoveMember(actorCharacterId, targetCharacterId)`
- `TransferLeadership(...)` (compatibility stub; always rejects because leadership is cm-admin-only)
- `RefreshCharacters(characterIds)` (trusted owner integrations after a
  committed membership/recovery transaction)
- `ValidateRobberyTarget(actorSource, targetSource, permissionKey)` (trusted
  server integration guard for `gang.search`, `gang.rob_cash`, or
  `gang.rob_items`; returns character-based context only after full validation)

Normal mutations re-resolve the actor's current membership and permission,
serialize per gang, apply a per-character throttle, enforce tier hierarchy, and
write an activity row. The leader rank cannot be edited or deleted through
these APIs; only the current leader can transfer leadership. Explicit
recovery/configuration is available only through the guarded `cm-admin`
integration and its dedicated gang permissions.

## G-menu invitations

`cm-gang` registers `gang_invite` with the existing `cm-playerdata` interaction
registry. The Gang page is shown only after the server returns an eligible
decision for the current looked-at player. The server selects the fixed gang
and current lowest non-leader rank; clients cannot submit either value.

Invitations expire after approximately 60 seconds. Send and acceptance both
validate loaded character identities, distinct online players, current gang
membership and `gang.invite`, enabled gang, routing-bucket equality, server
entity existence, and configured proximity. Acceptance inserts membership and
resolves the invite in one database transaction. No dashboard, NPC, offline,
character-ID, or server-ID recruitment API exists.

## Robbery authority and cash

The existing G menu conditionally exposes Rob Cash only when the actor has
`gang.rob_cash` and the target is currently cuffed (`cmCuffed`) or dead through
`cm-playerdata`. The network handler repeats all membership, permission,
enabled-gang, online identity, routing-bucket, entity, distance, and robbable
state checks. It applies per-actor throttling and a shared per-target robbery
lock.

Cash robbery transfers wallet cash only. `cm-playerdata` owns the trusted
cash-only atomic transfer: it locks both live balances, flushes them, and uses
one conditional database update for debit and credit. Bank balances are never
read or changed. Successful transfers write economy transactions and a safe
activity record.

Item search and robbery reuse `cm-inventory`. Search results contain short-lived
opaque tokens rather than inventory row IDs. `cm-inventory` re-reads the exact
row, applies `cm-items` `robberyProtected`, capacity, stack, bag and unique-item
rules, and transfers in one database transaction while preserving metadata.
Physical identity documents are protected by default.

## Chat, dashboard and headquarters

`/g` and the GANG tab in `cm-chat` use the same `SendGangChat` owner export.
The owner resolves the current character, enabled membership and `gang.chat`
permission, rate-limits the message, and `cm-chat` rebuilds recipients from
current same-gang state. Clients cannot submit a gang ID or recipient list.

`/gang` and F8 open the gang NUI without changing F6/F9/TAB/J/G mappings. The
dashboard payload is rebuilt server-side and includes only the member's fixed
gang, effective feature permissions, authorized member/rank data, facilities,
and up to 20 recent activity rows when `gang.view_logs` is granted. Existing
member rank assignment/removal calls the hierarchy-safe owner APIs; there is no
recruitment control in the dashboard.

Each member can receive only their own enabled headquarters configuration.
NPC models must exist in `Config.NpcModels`, coordinates come from the stored
owner facility row, and the player's current routing bucket must match. The NPC
and dashboard expose dashboard, armory, stash and fleet services only when the
corresponding facility, owner resource and current permission are available.
Missing soft integrations fail closed.

## Stash and armory

The stash uses `cm-inventory` external storage with `owner_type=gang_stash`
and the fixed gang ID as `owner_id`. Inventory calls the gang access export on
open and every movement, rechecking membership, `gang.stash`, facility
distance, and routing bucket.

The armory resolves enabled weapon/ammunition IDs through `cm-weapons`, checks
membership, `gang.armory`, tier, facility proximity, cooldown, issue limit and
inventory capacity, then journals the issue before delivery. Weapon metadata
and serials are server-created. No firearms-license or duty check is used.

## Persistent fleet

Fleet configuration stores a catalog ID from `rn-vehicleshop`, a fixed parking
location and one persistent `vehicle_id`. `cm-vehicles` remains the entity,
condition and persistence owner. Calls and returns revalidate current gang,
`gang.vehicle`, minimum tier, facility distance and routing bucket, serialize
per fleet row, and reuse or recall the same vehicle instead of minting a
duplicate. Gang vehicle keys are revocable session access and never personal
ownership.

Permanent placement is available only through `cm-admin`. The server tracks the
temporary placement vehicle and reads its entity coordinates and heading on
confirmation; browser coordinates are not accepted.

## Administration and recovery

The F11 Gangs page displays exactly the five canonical gangs and has no create,
delete or recruitment operation. Reads require `gang.admin.view`; mutations
require `gang.admin.manage` in `cm-admin` and are independently rechecked by
`cm-gang` using the invoking resource. Administrators can configure identity,
leader, facilities, ranks, permissions, armory and fleet, inspect activity, and
run bounded stale-invite/cache recovery actions.

Local logo/art keys, NPC models, weapon/ammunition IDs and vehicle catalog IDs
are code-owned allowlists. Facility and fleet locations come from the current
authorized admin entity. Leader assignment is transactional and preserves the
one-gang-per-character rule without changing family or legal/job memberships.

## v0.2.0 hardening

This package includes a focused static hardening pass over the original
implementation. Important changes include:

- gang and admin rank/leader mutations share one per-gang lock;
- leader-rank/member mismatches fail closed and schema validation detects them;
- invitation acceptance is transaction-safe and stale expired invite slots are
  released immediately before a new invite is created;
- robbery operations revalidate the same loaded actor/target characters while
  holding the target lock, and inventory calls fail closed;
- weapon armory issues are one weapon per unique server-created serial, with
  issue journaling and failure cleanup;
- fleet calls, returns, placement and admin configuration re-read authoritative
  state while serialized, and a newly created persistent vehicle ID is stored
  before later placement steps can fail;
- dashboard ranks can be created/edited/deleted safely, `gang.manage_permissions`
  can manage permissions independently, and `gang.manage_members` implies roster
  visibility for management;
- enabled headquarters require an allowlisted NPC model and online gang members
  are refreshed when the headquarters location changes; and
- the runtime schema audit validates critical uniqueness and leader invariants
  before the domain becomes ready.

The external owner contracts (`cm-playerdata`, `cm-inventory`, `cm-vehicles`,
`cm-vehiclekeys`, `rn-vehicleshop`, `cm-chat` and `cm-admin`) cannot be proven
from this resource alone. They still require integration/runtime testing on the
actual server.

## Graffiti turf income

Administrators place the fixed graffiti locations from the F11 Gangs page.
Only enabled locations count. A member with `gang.graffiti` can repaint a wall
for one of the five fixed gangs after a ten-second, server-authorized action.
There is no wall cooldown; only one active repaint session may hold a wall at a
time. Ownership and the selected gang design persist in
`cm_gang_graffiti` and are streamed by routing bucket.

Creation and edits use an admin-only gameplay-camera wall editor. The client
raycast supplies a candidate center, surface normal, wall-up vector, size and
rotation to a short-lived server placement session. The server validates the
admin permission, character, routing bucket, distance, normalized orthogonal
vectors, wall angle and size bounds before persisting anything. Persistent and
preview artwork share the same world-space quad renderer and use a 1 cm normal
offset to avoid z-fighting. Rows from the old location-only format remain in
the database but have `placement_ready = 0`; they must be repositioned through
Edit Placement rather than receiving a guessed wall orientation.

At each exact UTC hour boundary the server stores one idempotent snapshot per
gang in `cm_gang_turf_snapshots`. The default `full` payout gives every eligible
member the complete snapshot value (`owned tags × moneyPerTag`); it is not
divided among members. Each character can claim that gang/hour only once at the
Profit NPC, enforced by the unique key in `cm_gang_turf_claims`. Changing
`payoutMode` to `equal_split` divides the stored value by the member count
captured at snapshot time. Claims use authoritative character IDs and cash is
issued through `cm-playerdata`.

## Runtime verification

Static syntax, validator and contract-map checks do not prove FiveM, OneSync,
NUI or database behavior. Run the gang suite in
`agent-docs/autopilot/RUNTIME_TESTS.md` on a disposable non-production server
before deployment.


## Dashboard v4 / graffiti renderer update

- F8 management dashboard uses local per-gang hero artwork under `html/assets/gangs/`.
- Dashboard hero art is presentation-only; canonical gang identity remains server-derived.
- Graffiti wall rendering uses the DUI-backed runtime texture directly on saved world-space triangles instead of depending on scaleform texture binding.
- Placement raycast normals are oriented toward the placement camera before saving so the wall offset stays on the visible side.
- SQL `010_cm_gang_graffiti_placement.sql` remains required for 3D placement transforms.


### Dashboard v5 / graffiti renderer
- F8 dashboard uses the supplied private-network visual direction and local per-gang hero artwork.
- Graffiti uses a local transparent PNG runtime texture as the primary renderer, with DUI fallback, and DrawSpritePoly for the saved/placement wall quad.
