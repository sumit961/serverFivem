# cm-family integration for cm-house v1.6.0

The required fail-closed permission import remains:

```lua
exports('HasHousePermission', function(characterId, familyId, houseId, permissionKey, internalAction)
    -- Return true only when the member's current family rank grants the key.
end)
```

## New permission

```text
garage.customize
```

This permits a family member to use the fixed Garage Settings point and save
floor, wall-light, garage-light, decor and accent choices. It does not grant
slot assignment, vehicle withdrawal or house administration by itself.

## Read current customization

```lua
local style = exports['cm-house']:GetGarageCustomization(houseId)
```

## Change customization from cm-family

`cm-family` has the `garage` integration scope by default:

```lua
local ok, result = exports['cm-house']:SetGarageCustomization(houseId, payload, actorCharacterId)
```

The family resource should still enforce its own rank permission before calling
the export. `cm-house` validates the invoking resource and all submitted option
keys/ranges.

## Contract discovery

```lua
local family = exports['cm-house']:GetFamilyHouseContract()
local imports = exports['cm-house']:GetFamilyImportContract()
```
