# CM Characters v1.5.0 - Security + Admin Update

## Added
- Server-authoritative account checks for slots, creation, character selection, and appearance saving.
- Strong creation validation for slot, first name, last name, gender, and DOB/age.
- Runtime schema helper for `has_spawned`, `playtime_minutes`, `last_seen`, and `character_slot_limits`.
- Optional DB unique key for `(account_id, slot)` to stop duplicate slot creation.
- Character admin panel: `/charadmin`.
- Selector scene editor permission flow: `/charselectedit` now asks the server first.
- Exports for other CM resources:
  - `GetCharacterId(source)`
  - `GetCurrentCharacterId(source)`
  - `GetCharacter(source)`
  - `GetCharacterById(charId)`
  - `GetCharacterName(source)`
  - `GetCharacterDisplayName(source)`
  - `GetCharacterState(source)`
  - `IsCharacterLoaded(source)`
- Statebags for chat/playerdata/G menu:
  - `charId`
  - `characterId`
  - `charFirstName`
  - `charLastName`
  - `charFullName`
  - `characterName`
  - `charGender`
  - `characterLoaded`

## Fixed
- Client-provided account IDs are no longer trusted.
- Appearance save now waits for server acknowledgement before closing creator/spawning.
- Selector saved scene config is now actually used instead of being ignored.
- Debug/development commands are disabled by default or permission gated.
- Removed all CSS `backdrop-filter` and `-webkit-backdrop-filter` usage.
- Converted purple accents to CM cyan/blue.
- Reduced HUD event spam during the post-select spawn wait.
- Safer character card rendering in NUI to avoid injecting raw character names into HTML.

## Admin permissions
Give admins one of these permissions:

```cfg
add_ace group.admin characters.admin allow
add_ace group.admin cm.characters.admin allow
add_ace group.admin command.charadmin allow
```

For selector scene editing:

```cfg
add_ace group.admin characters.selector.edit allow
add_ace group.admin command.charselectedit allow
```

## Optional SQL
If runtime ALTER statements do not work on your server, run:

```sql
sql/upgrade_security_admin_slots.sql
```
