# CM PlayerData Stable v1.3-safe

Safe upgrade for `cm-playerdata` using oxmysql, Lua 5.4, state bags, dirty-save pattern, and CM Framework events.

## What this version fixes

- Removes injured/limping walkstyle effects completely.
- Saves dirty player data on `onResourceStop` before restart/stop.
- Cleans `LastEventUse` rate-limit entries on `playerDropped`.
- Adds server sanity checks for `playerDied` so fake death events are rejected when server health is still safe.
- Adds safer vitals sync: client damage is accepted, but large client-side healing jumps are rejected.
- Keeps money changes audited through `playerdata_audit`.
- Adds `GetDeathCount(src)` export.
- Gates `/cash` with ACE permission `cm-playerdata.cash`.
- Audits cash fallback removal during hospital respawn.

## Install

1. Backup your old folder:

```text
resources/[core]/cm-playerdata
```

2. Replace it with this new `cm-playerdata` folder.

3. Keep server.cfg order:

```cfg
ensure oxmysql
ensure ox_lib
ensure cm-core
ensure cm-auth
ensure cm-characters
ensure cm-playerdata
ensure cm-spawn
ensure cm-hud
```

4. Add permission for the dev cash command only for admins:

```cfg
add_ace group.admin cm-playerdata.cash allow
```

5. Restart:

```cfg
restart cm-playerdata
```

## Exports

```lua
exports['cm-playerdata']:GetPlayerData(src)
exports['cm-playerdata']:GetCharId(src)
exports['cm-playerdata']:GetSourceByCharId(characterId)
exports['cm-playerdata']:IsLoaded(src)
exports['cm-playerdata']:GetCash(src)
exports['cm-playerdata']:GetBank(src)
exports['cm-playerdata']:GetMoney(src, 'cash')
exports['cm-playerdata']:SetMoney(src, 'bank', 1000, 'reason')
exports['cm-playerdata']:AddMoney(src, 'cash', 100, 'reason')
exports['cm-playerdata']:RemoveMoney(src, 'bank', 500, 'reason')
exports['cm-playerdata']:SetMetadata(src, key, value)
exports['cm-playerdata']:GetMetadata(src, key)
exports['cm-playerdata']:IsDead(src)
exports['cm-playerdata']:GetDeathCount(src)
exports['cm-playerdata']:SetDead(src, true, 'reason')
exports['cm-playerdata']:Revive(src)
exports['cm-playerdata']:Respawn(src)
exports['cm-playerdata']:Load(src)
exports['cm-playerdata']:Save(src)
```


## Player interaction / identity menu

This version adds the blue/cyan player interaction layer:

- Overhead label shows only database character ID, never FiveM server/source ID.
- Unknown players show as `Stranger`.
- Real character name shows only after same organization, same family, shared ID, or handshake.
- Look at a nearby player and press `G` to open the radial menu.

Visible example:

```text
Stranger
ID: 12
```

`12` is `characters.id` from the database. Server ID/source is still used internally only for online event targeting.

Useful exports:

```lua
exports['cm-playerdata']:GetCharId(src)
exports['cm-playerdata']:GetSourceByCharId(characterId)
exports['cm-playerdata']:KnowPlayerIdentity(viewerSrc, targetSrc, reason)
exports['cm-playerdata']:SetOrganization(src, orgId, orgName)
exports['cm-playerdata']:SetFamily(src, familyId, familyName)
```

## Notes

This package does not include hunger, thirst, stress, or health-based walking effects. Keep those in a separate optional resource if you want them later.
