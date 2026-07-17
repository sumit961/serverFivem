# CM Vehicle Keys v1.2.0

Secure, memory-only temporary vehicle keys. Keys belong to the currently loaded
**character ID**, never the FiveM server ID or an account's last-played character.

## Resource order

```cfg
ensure cm-playerdata
ensure cm-vehiclekeys
ensure cm-vehicles
ensure rn-vehicleshop
```

`oxmysql` is no longer required by this resource. It deliberately does not guess
the active character from the database.

## Behaviour

- Duplicate temporary keys are rejected.
- The giver and receiver must be online, nearby, and in the same routing bucket.
- Keys are cleared when the receiving character unloads, changes character,
  disconnects, or the resource restarts.
- A state-polling fallback detects character changes automatically.
- Optional time-limited keys can be configured or supplied per grant.
- Grant metadata is stored in server memory for management/debug integrations.

## Existing cm-vehicles compatibility

The following exports remain compatible:

```lua
exports['cm-vehiclekeys']:HasTempKey(source, plate)
exports['cm-vehiclekeys']:HasTempKeyByCharId(characterId, plate)
exports['cm-vehiclekeys']:GiveTempKey(ownerSource, targetSource, plate)
exports['cm-vehiclekeys']:RevokeTempKeyByChar(plate, characterId)
exports['cm-vehiclekeys']:RevokeTempKey(source, plate)
exports['cm-vehiclekeys']:ClearTempKeys(source)
```

`GiveTempKey` returns `false, reason` when the target already has the key. This
prevents duplicate entries in the vehicle owner's lent-key metadata.

## Recommended character lifecycle integration

State polling works automatically, but explicit calls provide immediate cleanup:

```lua
-- After a character is fully selected/loaded
exports['cm-vehiclekeys']:RegisterCharacter(source, characterId)

-- Before character switch/logout
exports['cm-vehiclekeys']:UnregisterCharacter(source, characterId)
```

## Additional server exports

```lua
exports['cm-vehiclekeys']:GetActiveCharacterId(source)
exports['cm-vehiclekeys']:GetTempKeys(source)
exports['cm-vehiclekeys']:GetTempKeysByCharId(characterId)
exports['cm-vehiclekeys']:ClearTempKeysByCharId(characterId)
exports['cm-vehiclekeys']:RevokeAllForPlate(plate)
```

## Optional timed grant

The default remains "until character change/logout". A trusted server resource can
issue a limited key:

```lua
local ok, reason = exports['cm-vehiclekeys']:GiveTempKey(
    ownerSource,
    targetSource,
    plate,
    { durationSeconds = 3600 }
)
```

Duration is clamped by `maxDurationSeconds` in `shared/config.lua`.
