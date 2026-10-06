# cm-gang

## V1 - fixed five-gang player system

The active V1 manifest is limited to exactly five fixed gang slots:
`gang_1` Marabunta (blue), `gang_2` Bloods (red), `gang_3` Ballas (purple),
`gang_4` Families (green), and `gang_5` Vagos (yellow). The IDs are stable
Character-ID domain keys. NPC models and headquarters locations remain
configuration/admin data; no permanent world coordinates are invented here.
There is no player-created gang flow.

The older Supply War/event material below is retained as historical repository
documentation only; those modules are not loaded by the active V1 manifest.

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

The active authoritative gang domain is exactly `gang_1` through `gang_5`.
The deterministic mapping is `gang_1` Marabunta, `gang_2` Bloods, `gang_3`
Ballas, `gang_4` Families, and `gang_5` Vagos. The IDs are immutable and no
create/delete API exists. Older named gang rows, if present, remain outside
the active runtime domain and are not deleted or reassigned automatically.

## Ownership

`cm-gang` owns gang membership, ranks, permissions, invites, activity,
facilities, armory authorization gates and fleet authorization. Character identity,
inventory, items, weapons, persistent vehicles, vehicle catalog, chat and admin
presentation remain with their existing CM owners.

Gang membership is character-based, limited to one gang per character, and is
independent from family and legal/job organization membership. There is no duty
state.

`cm-playerdata` supplies Character ID, loaded-character state, interaction
registration, and player state publication. `cm-chat` owns gang chat
presentation and calls `SendGangChat`. `cm-vehicles` owns persistent vehicle
identity, entities, condition, and organization fleet persistence. `cm-inventory`
owns gang stash storage, while `cm-items` remains the item-definition owner.
`cm-admin` guards privileged leader, rank, facility, and fleet configuration.
`cm-weapons` currently exposes catalog/read APIs only; it has no supported
server-authoritative faction armory path, so V1 armory operations fail closed
with `weapon_owner_faction_api_missing`. No owner boundary is bypassed.

## Owner integration follow-up

The fixed five-gang mapping is complete inside `cm-gang`, but two existing
owners still contain stale four-slot/legacy registries that this resource does
not bypass:

- `cm-chat/server/main.lua` must recognize `gang_5` in its authoritative gang
  state validation, or expose a supported dynamic gang registration API.
- `cm-vehicles/server/api.lua` and `server/main.lua` must recognize `gang_5`
  as a trusted organization ID and resolve its canonical label. Fleet calls
  must continue to use `gang_5`, not the legacy `vagos` row ID.

Until those owner contracts are updated, Vagos fleet and gang-chat integration
remains unavailable even though membership, dashboard data, stash identity,
and invitation persistence use the correct `gang_5` ID.

## Install

Apply the numbered files in `sql/` in order to a disposable/non-production database first, then
start `cm-gang`. The resource validates the schema and fails closed when the
the migration or any of the five fixed rows is missing. It never rewrites customized
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
- `GetVehicleAccessDecision(...)` (server-only gang authorization used by
  `cm-vehicles`)
- `SendGangChat(...)` (server-only gang chat authorization used by `cm-chat`)

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

## Deferred crime features

Player robbery, cash or item theft, graffiti/turf income, supply-war/events,
profit systems, wardrobe systems, and any duplicate crime/session framework are
not part of V1. They remain deferred until the shared crime/session framework
and safe authoritative transfer contracts exist.

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
owner facility row, and the player's current routing bucket must match. The
physical HQ currently exposes the dashboard and the `cm-inventory` stash path;
the server revalidates Character ID membership, alive state, bucket, distance,
permission, and interaction rate before those actions. Missing coordinates or
models leave the NPC disabled. The configured facility presentation defaults
contain no permanent coordinates; `cm-admin` must configure each
`cm_gang_facilities` headquarters row before it can spawn.

The physical HQ menu does not add chat or fleet actions. `cm-chat` and
`cm-vehicles` still lack the canonical `gang_5` owner contract, so those
integrations fail closed until their owners accept `gang_5` directly; no legacy
`vagos` alias is used.

## Stash and armory

The stash uses `cm-inventory` external storage with `owner_type=gang_stash`
and the fixed gang ID as `owner_id`. Inventory calls the gang access export on
open and every movement, rechecking membership, `gang.stash`, facility
distance, and routing bucket.

Armory callbacks intentionally fail closed with
`weapon_owner_faction_api_missing`. `cm-gang` does not create weapon stock,
issue items, generate serials, bypass a firearms-license check, or create a
parallel weapon/inventory authority. The integration point is the future
server-authoritative faction armory API from `cm-weapons`.

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

`RollbackGrantedOrganizationVehicle(src, gangId, model, vehicleId)` is a
server export reserved for `rn-vehicleshop`. It compensates a failed admin
grant by removing only the exact matching fleet assignment and organization
vehicle after revalidating the initiating admin, fixed gang, catalog model,
and persistent vehicle ownership.

## Administration and recovery

The F11 Gangs page displays exactly the five fixed gangs and has no create,
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
- legacy robbery and weapon-armory implementation files are retained for
  repository compatibility but are not loaded by the active V1 manifest;
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

No gameplay tests, test suites, or QA were run for this Agent 4 build.

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

## Contribution and reputation ledger

The progression ledger is Character ID based and stores contribution points,
reputation level, total earned contribution, timestamps, bounded audit metadata,
and an append-only contribution history. It does not award money, items, weapons,
wages, crime rewards, or automatic ranks.

Server exports:

- `RecordGangContribution(source, reference, points, metadata)` — available only
  to resources explicitly allowlisted in `Config.Progression.trustedContributionResources`.
- `GetOwnGangProgression(source)` — returns the caller's active gang progression.
- `GetGangMemberProgression(source, characterId, gangId)` — returns progression
  for an authorized gang leader or `cm-admin` administrator.

The contribution export resolves the loaded Character ID and active gang on the
server. Client events cannot award contribution. References are unique and are
claimed transactionally so replayed or concurrent requests cannot double-apply.

The `013_cm_gang_contribution_ledger.sql` migration must be applied before the
resource can validate its progression tables.

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
