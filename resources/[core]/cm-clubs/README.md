# cm-clubs

`cm-clubs` is a standalone V1 social-club resource for administrator-created
car, music, cultural, hobby, and community groups. It is separate from gangs,
families, police/legal organizations, businesses, and the F6 Organization Hub.

Apply `sql/001_cm_clubs.sql` through the normal database migration process. The
resource does not execute schema changes automatically and does not seed clubs.
Apply `sql/002_cm_clubhouses.sql` as the forward migration before enabling
clubhouse access. Administrators create clubs and configure clubhouses through
the restricted server exports in `server/main.lua`.

Owner contracts used:

- `cm-playerdata:RegisterInteractionAction` and its client interaction registry
  expose the nearby one-use invitation action.
- `cm-chat:SetPlayerChatGroup(source, 'club', clubId, color)` synchronizes the
  generic club chat group when that owner is running.
- `cm-ui:Confirm` is used for invitation acceptance. `cm-ui` has no notification
  export, so normal notifications follow the repository's `ox_lib` convention.
- `cm-admin:HasPermission(source, 'orgs.manage')` protects every administrator
  export. `cm-clubs` does not expose those exports to clients.

The clubhouse administrator contract is:

```lua
exports['cm-clubs']:AdminSetClubhouse(adminSource, clubId, {
    enabled = true,
    x = 0.0, y = 0.0, z = 0.0, heading = 0.0,
    npcModel = 'a_m_m_business_01',
    displayName = 'Clubhouse',
    interactionLabel = 'OPEN CLUBHOUSE',
    interactionDistance = 2.5,
    routingBucket = nil, -- optional; nil permits the current bucket
})
```

Coordinates are never seeded by this resource. The clubhouse remains disabled
until an administrator supplies a complete configuration using an allowlisted
NPC model. `AdminCreateClub` also accepts the same object as `data.clubhouse`.

`cm-admin` currently has no generic social-club CRUD callback or UI contract.
The restricted exports are the integration points for that future admin surface:
`AdminCreateClub`, `AdminSetClubEnabled`, `AdminAssignClubLeader`,
`AdminUpsertClubRank`, `AdminSetClubhouse`, and `AdminGetClubs`.

`/club` opens the member dashboard. Nearby invitations are only exposed through
the shared player interaction menu; there is no dashboard recruitment path.

V1 intentionally has no club vehicles, storage, armories, rewards, money, XP,
duty, crime, or player-created club flow beyond the optional administrator-
configured clubhouse NPC layer described above.
