# CM Characters v1.6.0 Production Ready Notes

`cm-characters` owns only the character selector, character creator, appearance save flow, selector preview scene, and safe character database exports.

## Important ownership rules

- `cm-auth` owns login/account session only.
- `cm-playerdata` owns runtime character data, loaded state, cash, bank, and money exports.
- `cm-core` owns database helpers, callbacks, notifications, logs, cache, and validation helpers.
- `cm-admin` owns staff UI, permissions, and admin logs.
- `cm-characters` must not own admin ranks, money rules, economy, jobs, inventory logic, vehicles, houses, or progression.

## Production defaults

- `Config.EnableLegacyCharacterAdmin = false`
- `Config.EnableManualSelectorCommand = false`
- `Config.EnableDevCommands = false`

The old `/charadmin` panel is disabled by default. Use `cm-admin` for staff tools. This resource still exposes safe admin exports that `cm-admin` can call.

## Safe exports for other resources

```lua
exports['cm-characters']:GetCharacterId(source)
exports['cm-characters']:GetCharacter(source)
exports['cm-characters']:GetCharacterName(source)
exports['cm-characters']:GetCharacterDisplayName(source)
exports['cm-characters']:GetCharacterState(source)
exports['cm-characters']:GetCharacterById(charId)
exports['cm-characters']:GetCharactersByAccount(accountId)
exports['cm-characters']:OpenCharacterSelector(source, accountId)
```

For new systems, prefer `cm-playerdata` for runtime player data:

```lua
local charId = exports['cm-playerdata']:GetCharacterId(source)
local loaded = exports['cm-playerdata']:IsCharacterLoaded(source)
```

## Safe exports for cm-admin

```lua
exports['cm-characters']:AdminSearchCharacters(adminSource, query, limit)
exports['cm-characters']:AdminRefreshCharacterState(adminSource, charId)
exports['cm-characters']:AdminSetAccountSlots(adminSource, accountId, maxSlots, reason)
```

These exports check `cm-admin` permissions through `CMCharacters.HasPermission()`.

## Spawn handoff

Existing character:

1. `cm-auth` opens selector.
2. Player selects character.
3. Client fades out and asks `cm-climatime` to prepare live weather before real spawn.
4. Server validates ownership and sets character state.
5. Server asks `cm-playerdata` to load runtime data.
6. Server fires `cm-core:characterLoaded` for `cm-spawn` compatibility.
7. `cm-spawn` finishes spawn and HUD/minimap restore.

New character:

1. Player creates character.
2. Server validates slot/name/date/gender.
3. Server inserts character with `Config.StartingCash` and `Config.StartingBank`.
4. Player saves appearance.
5. Server stores naked/base appearance and starter clothing items.
6. `cm-playerdata` loads runtime data.
7. Client releases creator world lock after live climate is prepared.

## Notes

- Server ID is never used as visible RP identity.
- Visible player ID must be database character ID.
- Client-provided account ID, price, money, or permission values are not trusted.
- Selector scene/admin edit tools require `cm-admin`/ACE permissions.
- No CSS `backdrop-filter` is used in active UI.
