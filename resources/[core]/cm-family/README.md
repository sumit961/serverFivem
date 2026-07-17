# cm-family v1.5.1

Family system for the CM Framework. Players create a family from a house they
own, invite members, manage up to 15 ranks with granular permissions, share
garage vehicles gated by rank tier, and run a shared family bank — all through a
full-screen `/family` menu.

## What it does

- **Create from an NPC.** Talk to the Family Registrar and press E. Choosing
  "create a family" lists the houses you own that are eligible to become a
  family house. If you own none, it refuses. Pick one and it becomes the family
  house (linked through cm-house).
- **Ranks (up to 15).** Rename, reorder by tier, toggle every permission, set a
  per-rank daily bank withdrawal limit. Two safety rules are enforced
  server-side: you can never edit a rank at or above your own tier, and you can
  never grant a permission you don't hold yourself.
- **Members.** Invite by character id (5-minute expiry, accept/decline),
  promote/demote, kick, leave. Online targets receive a top-screen Y/N prompt; the invitation is shown only after a valid database row is confirmed. Founder succession happens automatically if the founder leaves, or explicitly via "make head".
- **Vehicles.** Every family vehicle has a required minimum tier. A member can
  spawn/use it only when their rank tier ≥ that level.
- **Bank.** Shared balance with atomic deposit/withdraw, per-rank daily limits,
  and a full transaction log.
- **Menu.** `/family` opens the full-screen menu: Overview, Members, Ranks,
  Vehicles, Bank, Logs. The Logs page uses the durable append-only activity audit.
- **Audit.** Member, rank, chat, vehicle, storage, weapon, door, bank, property,
  and ownership actions are recorded with severity and high-risk classification.
  Failed database writes are retried from `audit_pending.json`.

## Install

1. Database setup is automatic by default. At startup, `server/sv_schema.lua`
   creates all eight tables, repairs additive drift such as a missing `tag`
   column, validates required columns/indexes, and only then enables callbacks.
   - Keep `Config.Database.autoInstall = true` for normal use.
   - If your database user has no `CREATE`/`ALTER` permission, install the base
     schema and migrations manually. Migration 010 is a non-destructive diagnostic for the installed invite-table layout and database clock.
   - `sql/000_OPTIONAL_reset.sql` is destructive and should only be used when
     you intentionally want to erase all family data.
2. Ensure `cm-house`, `cm-playerdata`, `oxmysql`, and `ox_lib` are started
   before `cm-family`.
3. Add `ensure cm-family` to your server.cfg after cm-house.
4. cm-house already authorizes cm-family in its
   `Config.Integration.authorizedResources` (scopes: access, family, garage,
   weaponStorage). No cm-house config change is required for the base flow.

## How it integrates with cm-house

cm-house stays the property/vehicle authority. cm-family owns people and ranks.
The seam is one export cm-house calls:

    HasHousePermission(characterId, familyId, houseId, permissionKey, action) -> boolean

cm-family answers true only when the member's rank grants the permission.

Because stock cm-house passes fixed action constants (e.g. `garage.spawn_family`)
that carry no vehicle id, the **per-vehicle level** check is enforced through a
second export:

    CanUseFamilyVehicle(characterId, vehicleId, action) -> boolean

This build of cm-house adds a one-line hook in `checkSeatAccess`
(server/sv_garage.lua) that calls it when spawning a family car. It fails closed
only when cm-family is running and explicitly denies, so servers without
cm-family are unaffected.

## Exports (for other resources)

- `HasHousePermission(cid, familyId, houseId, key, action)` — the cm-house seam.
- `GetFamilyForCharacter(cid)` — `{ id, name, house_id, rank_id }` or nil.
- `GetFamilyMemberCharacterIds(familyId)` — array of cids.
- `GetFamilyById(familyId)` — public family summary.
- `CanUseFamilyVehicle(cid, vehicleId, action)` — per-vehicle level gate.
- `GetFamilyVehicleLevel(familyId, vehicleId)` / `SetFamilyVehicleLevel(...)`.
- `FamilyBankCharge(familyId, amount, reason)` — atomic external spend.
- `WriteFamilyActivity(...)` — allowlisted server-resource audit writer.
- `AdminGetFamilyActivity(...)` / `AdminGetHighRiskFamilyActivity(...)` — permission-gated cm-admin readers.

## Notes

- One family per character (enforced by a unique key on `character_id`).
- Disbanding a family unlinks the house and removes active ranks, members, invites,
  vehicle levels, bank rows, and legacy logs in one database transaction. The
  append-only activity history is intentionally retained for the configured audit period.
- The default ranks (Head / Officer / Member / Recruit) and all permission keys
  live in `shared/config.lua`.

## v1.0.1 fixes

- Auto-installs and validates the family schema before callbacks are enabled.
- Repairs stale `cm_families` tables missing `tag`, `color`, `house_id`, or bank columns.
- Prevents concurrent family creation requests from the same character.
- Confirms every family, rank, and founder-membership insert.
- Rolls back partial family creation and refunds the creation fee on failure.
- Normalizes database numeric IDs before caching them.

## v1.0.2 legacy database compatibility

Older `cm_families` tables can use a different signedness or storage engine for
`id`. MySQL rejects new child-table foreign keys in that situation with errno
150. v1.0.2 creates missing child tables without hard FK constraints and uses an
explicit transaction for family cleanup/disband instead. Existing valid foreign
keys are left in place. The resource auto-repairs this schema; manual fallback is
`sql/004_legacy_fk_compat_v1.0.2.sql`.


## v1.0.3 id-less legacy member table compatibility

Some older `cm_family_members` tables use `character_id` as their primary key
or use a composite key, so they do not contain a numeric `id` column. The
runtime never reads or updates `cm_family_members.id`; v1.0.2 incorrectly
required it during startup validation. v1.0.3 treats that column as optional,
keeps numeric IDs for fresh installations, and removes the `AFTER id` assumption
when repairing a missing `family_id` column. No family data reset is required.


## v1.0.4 legacy rank permission compatibility

Older rank tables may retain a `perms` JSON column and its MariaDB CHECK
constraint. v1.0.4 detects the column and its required JSON shape, reads either
`permissions` or `perms`, and safely writes both columns. Permission payloads
are stored as JSON objects by default. No table reset is required.


## v1.0.6 legacy rank grade compatibility

Older `cm_family_ranks` tables can use `grade` with a unique key such as
`uq_rank_grade (family_id, grade)`. v1.0.6 detects that column and writes the
same authority value to both `tier` and `grade`, preventing every inserted rank
from receiving the legacy default grade `0`. Existing rows are read from
`grade` when present. Member inserts now also support id-less member tables by
checking affected rows instead of requiring an auto-increment insert id.

## Family chat integration

With `cm-chat` v1.4.0 running, members receive a dedicated FAMILY tab using the family colour. Both the tab and `/f` / `/familychat` route through `cm-family`. Every active family member can use family chat regardless of rank, with cooldowns, authoritative online recipients, family tag, rank/custom title, and character ID. The default GTA chat event is used only when `cm-chat` is absent.
