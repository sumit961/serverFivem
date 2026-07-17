# cm-house v1.6.0 integration API

## Authority

`cm-house` owns property definitions, access, reusable interior/garage templates,
permanent house parking assignments and per-property garage customization.
`cm-vehicles` remains the authority for owned-vehicle records and physical entities.

## Capability discovery

```lua
local contract = exports['cm-house']:GetHouseIntegrationContract()
```

Relevant v1.6.0 capabilities:

```lua
contract.capabilities.multiGarageExits
contract.capabilities.maxGarageExits
contract.capabilities.garagePlacementVehicle
contract.capabilities.garageCustomizationPoint
contract.capabilities.garageFloorStyles
contract.capabilities.garageWallLighting
contract.capabilities.garageLighting
contract.capabilities.garageDecor
contract.capabilities.garageAccentColors
contract.capabilities.garageCustomizationFineTuning
```

## Garage template fields

`GetGarageTemplate(templateId)` now returns:

```lua
{
    player_entry = { x, y, z, h },
    vehicle_exit = { x, y, z, h },       -- first exit, compatibility
    vehicle_exits = { { x, y, z, h }, ... },
    customization_point = { x, y, z, h },
    customization_anchors = {
        walls = { { x, y, z, h }, ... },
        lights = { { x, y, z, h }, ... },
        props = { { x, y, z, h }, ... },
    },
    slots = { ... },
}
```

## Garage customization exports

### Read

```lua
local customization = exports['cm-house']:GetGarageCustomization(houseId)
```

Returns:

```lua
{
    theme = 'ice_clean',
    floor = 'ice_pad',
    wall = 'cyan_wash',
    light = 'bright_white',
    decor = 'clean',
    accent = 'cyan',
    settings = {
        floorOpacity = 100,
        wallIntensity = 100,
        lightIntensity = 100,
        decorDensity = 100,
    },
}
```

### Write from an authorized server resource

```lua
local ok, result = exports['cm-house']:SetGarageCustomization(houseId, {
    theme = 'racing',
    floor = 'racing_pad',
    wall = 'red_wash',
    light = 'race',
    decor = 'racing',
    accent = 'red',
    settings = {
        floorOpacity = 100,
        wallIntensity = 120,
        lightIntensity = 110,
        decorDensity = 100,
    },
}, actorCharacterId)
```

The invoking resource needs the `garage` integration scope in
`Config.Integration.authorizedResources`.

## Family permission

`cm-family` should resolve:

```text
garage.customize
```

through the existing fail-closed import:

```lua
exports['cm-family']:HasHousePermission(
    characterId,
    familyId,
    houseId,
    'garage.customize',
    'garage.customize'
)
```

The legal property owner always has this permission. Family access is denied when
`cm-family` is missing, stopped, errors or returns anything other than `true`.

## Existing contracts

```lua
exports['cm-house']:GetHouseAdminContract()
exports['cm-house']:GetFamilyHouseContract()
exports['cm-house']:GetFamilyImportContract()
exports['cm-house']:GetHouseWeaponStorageContract()
```
