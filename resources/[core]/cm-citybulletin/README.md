# cm-citybulletin

`cm-citybulletin` is a standalone player-facing registry for persistent,
administrator-created public city notices. It owns notice records and
per-character read state only. It is not chat, phone notifications or
classifieds, dispatch, a calendar, a job system, or a generic broadcast
framework.

## Setup and start order

Apply `sql/001_cm_citybulletin.sql` through the normal migration process. The
resource checks for its two tables and their primary-key shapes at startup but
never applies SQL automatically. Start it after `cm-playerdata` and
`cm-admin`; the repository's explicit start order places it after
`cm-admin`.

## Owner contracts

- `cm-playerdata:IsCharacterLoaded(source)`, `GetCharacterId(source)`, and
  `IsDead(source)` provide the authoritative loaded Character ID and lifecycle
  state. The raw FiveM source is never persisted as player identity.
- `cm-playerdata:server:characterUnloaded`,
  `cm-playerdata:server:deathStateChanged`, and `playerDropped` clear
  server-side request state. Client character unload/life-state events close
  the NUI and release focus.
- `cm-admin:HasPermission(source, 'orgs.manage')` is the existing approved
  administrator contract. Every administrator export also requires the caller
  resource to be `cm-admin`, so clients cannot invoke these exports directly.
- `cm-admin:server:addLog` receives non-secret audit entries for notice
  mutations. `cm-admin` remains the permission and audit owner.
- `oxmysql` is the persistence owner and `ox_lib` supplies server callbacks and
  notifications. `cm-ui` is declared as a required shared CM UI dependency;
  this dashboard has no world prompt to show.

## Administrator exports

These are server exports and must be called by `cm-admin` with an authorized
player source. All return `{ ok = boolean, reason = string?, ... }`.

```lua
exports['cm-citybulletin']:AdminCreateNotice(adminSource, {
    noticeId = 'water-main-repair', -- stable [a-z0-9_-] identifier
    title = 'Water main repair',
    summary = 'Traffic may slow near the civic centre.',
    body = 'Use alternate routes while crews complete the repair.',
    category = 'services', -- general, city, safety, services, community, events
    priority = 'important', -- normal, important, urgent
    enabled = true,
    pinned = true,
    expiresAt = 1800000000, -- optional server-validated Unix timestamp
})
exports['cm-citybulletin']:AdminUpdateNotice(adminSource, 'water-main-repair', data)
exports['cm-citybulletin']:AdminSetNoticeEnabled(adminSource, 'water-main-repair', false)
exports['cm-citybulletin']:AdminSetNoticePinned(adminSource, 'water-main-repair', false)
exports['cm-citybulletin']:AdminArchiveNotice(adminSource, 'water-main-repair')
local response = exports['cm-citybulletin']:AdminListNotices(adminSource)
```

`published_at` is assigned by the server when a notice is created and is not
client-controlled. Expiry input is bounded and compared against server time.
Archived notices cannot be re-enabled, and archive/disable operations preserve
the notice row and all read history. Mutations use per-admin/per-notice locks,
bounded fields, allow-listed categories/priorities, and server-side state
checks.

There is currently no owner-side admin UI integration in `cm-admin`; the
exports are intentionally the narrow integration contract for that future
surface. This resource does not modify `cm-admin` or add an admin permission.

## Player dashboard

Players use `/bulletin` or `/news` after their character loads. The server
returns active, unexpired notices and archived notice history, with category
filters and read/unread state. Dates are server timestamps. `ESC`, close,
character unload, death/downed state, resource stop, and repeated open/close
requests release NUI focus and reset client state. No automatic chat, phone,
dispatch, or notification broadcast is sent.

Read state is stored in `cm_citybulletin_reads` with a composite primary key
`(character_id, notice_id)`. `INSERT IGNORE` makes repeated mark-read requests
idempotent; the server resolves Character ID from `cm-playerdata` and validates
that the notice is currently public or archived before inserting.

## Schema and retention

- `cm_citybulletin_notices` stores the stable ID, bounded text, category,
  priority, server publication/expiry timestamps, enabled/archived/pinned
  flags, and optional administrator Character ID metadata.
- `cm_citybulletin_reads` stores only Character ID, notice ID, and read time.
- No automatic retention or deletion is performed. Notice and read history is
  retained until an explicitly planned migration changes that policy.
- The migration is forward-safe and must be applied separately; the resource
  fails closed for persistence when its tables or required keys are absent.
