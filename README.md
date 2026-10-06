# cm-clubs

`cm-clubs` is a standalone V1 social-club resource for administrator-created
car, music, cultural, hobby, and community groups. It is deliberately separate
from gangs, families, police/legal organizations, businesses, and the F6
Organization Hub.

## Setup

Apply `sql/001_cm_clubs.sql` through the normal database migration process. The
resource does not execute schema changes automatically. There are no seeded
clubs: administrators create them through the restricted server exports in
`server/main.lua`.

## Owner contracts

- `cm-playerdata:RegisterInteractionAction` exposes the nearby `Invite to club`
  action through the existing player interaction menu.
- `cm-chat:SetPlayerChatGroup(source, 'club', clubId, color)` is used when the
  generic chat owner supports the club group.
- `cm-ui:ShowInteract`, `cm-ui:HideInteract`, and `cm-ui:Confirm` are used for
  shared interaction and confirmation presentation. Notifications use the
  existing `ox_lib` notification convention because `cm-ui` has no notification
  export.
- `cm-admin:HasPermission(source, 'orgs.manage')` is checked for every
  administrator export. `cm-clubs` does not expose those exports to clients.

`cm-admin` currently has no generic social-club CRUD callback/UI contract. The
restricted exports are the integration point for a future admin surface:
`AdminCreateClub`, `AdminSetClubEnabled`, `AdminAssignClubLeader`,
`AdminUpsertClubRank`, and `AdminGetClubs`.

## Commands and UI

`/club` opens the member dashboard. Dashboard data is rebuilt on the server for
the current Character ID. Nearby invitations are only exposed through the
shared player interaction menu; there is no dashboard recruitment path.

There are no physical clubhouses, club vehicles, storage, armories, rewards,
money, XP, duty, crime, or player-created club flows in V1.
