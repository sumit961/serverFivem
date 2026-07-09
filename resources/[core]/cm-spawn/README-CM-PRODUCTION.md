# CM Spawn v1.1.0 Production / Organization Ready

## What this resource owns

`cm-spawn` owns only:

- Spawn selector UI
- First-time default spawn
- Returning-player spawn selection
- Last location spawn validation
- Future-ready organization spawn card
- Spawn completion state handoff
- Tutorial UI/camera flow

## What this resource does not own

- Character identity/data/money: `cm-playerdata`
- Login/session: `cm-auth`
- Weather/time ownership: `cm-climatime`
- HUD ownership: `cm-hud`
- Admin tools/permissions/logs: `cm-admin`
- Organization membership/business logic: future `cm-organizations`

## Organization spawn logic

The old fixed `gang` spawn has been replaced with `organization`.

This one spawn type is future-proof and can represent:

- Gang
- Police
- Army
- Government
- Company
- Club
- Any custom organization

The organization spawn stays locked until the player has a valid org spawn from one of these sources:

1. Future `cm-organizations` exports such as:
   - `GetSpawnForCharacter(charId)`
   - `GetCharacterSpawn(charId)`
   - `GetMemberSpawn(source)`
   - `GetMemberOrganization(source)`
   - `GetCharacterOrganization(charId)`
2. `cm-playerdata` character data or metadata:
   - `organization`
   - `org`
   - `organization_spawn`
   - `org_spawn`
3. Player state:
   - `organization`
   - `org`
   - `organizationSpawn`
   - `orgSpawn`

Supported spawn coordinate formats:

```lua
{ x = 1.0, y = 2.0, z = 3.0, h = 90.0 }
{ x = 1.0, y = 2.0, z = 3.0, heading = 90.0 }
'["json object with x/y/z/h"]'
```

## Security

- Browser/NUI never receives final coordinates.
- Server resolves selected spawn again after click.
- Locked spawn selection is blocked server-side.
- Last location is blocked until `has_spawned = 1`.
- Spawn selection is rate-limited.

## Production logging

Production is quiet by default:

```lua
Config.Debug = false
Config.VerboseLogs = false
```

Enable only while debugging.

## Dev commands

Development recovery commands are disabled by default:

```lua
Config.EnableDevCommands = false
Config.EnableClientFixCommand = false
```

If enabled, server commands still require `cm-admin` permission `spawn.debug` when run by a player.
