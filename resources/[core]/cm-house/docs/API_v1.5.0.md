# cm-house v1.5.0 Integration API

`cm-house` is the authority for properties, access, private buckets, reusable interior/garage templates, permanent house garage assignments, and property weapon storage. `cm-vehicles` remains the physical vehicle authority. `cm-inventory` remains the player inventory authority.

## Capability discovery

```lua
local contract = exports['cm-house']:GetHouseIntegrationContract()
local family = exports['cm-house']:GetFamilyHouseContract()
local familyImports = exports['cm-house']:GetFamilyImportContract()
local admin = exports['cm-house']:GetHouseAdminContract()
local weapons = exports['cm-house']:GetHouseWeaponStorageContract()
```

Call capability contracts instead of assuming an export exists. Writable server exports are limited by `Config.Integration.authorizedResources` and still validate the acting player/character.

## Admin panel/button API

An authorized server resource such as `cm-admin` can open a panel for a player:

```lua
local ok, reason = exports['cm-house']:OpenAdminPanel(source, 'houses')
local ok, reason = exports['cm-house']:OpenHouseCreator(source)
local tabs = exports['cm-house']:GetHouseAdminPanelTabs()
```

A client-side button can use:

```lua
exports['cm-house']:OpenAdminPanel('interiors')
exports['cm-house']:OpenHouseCreator()
local open = exports['cm-house']:IsHouseAdminPanelOpen()
```

Every path revalidates the player's current permission. Client exports never grant authority.

### Rank-ready permission keys

```text
house.admin.open
house.create
house.admin.properties
house.admin.interiors
house.admin.garages
house.admin.pricing
house.admin.photos
house.admin.recovery
```

`Config.AdminUseLegacyFallback = true` lets existing ranks continue using `house.create` during migration. Set it to `false` after the granular keys are assigned in `cm-admin`.

## Weapon storage API

The secure container address is:

```text
owner_type = house_weapon_storage
owner_id   = <houseId>:<storageIndex>
```

Only catalogued weapons and ammunition are accepted. The server checks the exact house bucket, exact storage point distance, property permission, row ownership, quantity, and transfer lock.

```lua
local catalog = exports['cm-house']:GetWeaponStorageCatalog(false)
local allowed, reason = exports['cm-house']:CanUseHouseWeaponStorage(characterId, houseId, 'withdraw')
local items, reason = exports['cm-house']:GetHouseWeaponStorage(houseId, storageIndex)
local count, reason = exports['cm-house']:GetHouseWeaponStorageCount(houseId)
local points = exports['cm-house']:GetHouseWeaponStoragePointCount(houseId)
local transfers, reason = exports['cm-house']:GetHouseWeaponStorageTransfers(houseId, 50)
local ok, reason = exports['cm-house']:OpenHouseWeaponStorageForPlayer(source, houseId, storageIndex)
local ok, reason = exports['cm-house']:RefreshWeaponStorageCatalog()
```

Sensitive reads and panel-opening calls require the invoking resource to have `weaponStorage`, `family`, or `admin` scope. Direct gameplay transfers are performed only by the built-in callbacks and cannot be forced through an export.

Permission actions:

```text
weapon_storage.use
weapon_storage.deposit
weapon_storage.withdraw
```

Family-facing permission keys:

```text
weapon_storage.access
weapon_storage.deposit
weapon_storage.withdraw
```

## Family-facing property API

```lua
exports['cm-house']:GetFamilyHouses(familyId)
exports['cm-house']:SetFamilyHouseLink(houseId, familyId, actorCharacterId)
exports['cm-house']:RefreshFamilyAccess(characterId)
exports['cm-house']:RefreshFamilyMembers(familyId)
exports['cm-house']:GetFamilyVehicles(familyId)
exports['cm-house']:SetVehicleFamilyShared(vehicleId, shared, actorCharacterId)
exports['cm-house']:CanFamilyAccessProperty(characterId, houseId, action)
```

`cm-family` must be allowlisted with `family`, `access`, `garage`, and `weaponStorage` scopes. Family access fails closed whenever the configured family export is missing, stopped, errors, or does not return exactly `true`.

## Core property/read APIs

The existing v1.4 APIs remain available, including:

```text
GetHouse
GetHouses
GetHousesForCharacter
CanAccessProperty
GetPropertyPermissionCatalog
GetInteriorTemplate
GetGarageTemplate
GetGarageState
GetGarageCapacity
GetHouseBucket
GetGarageBucket
WhereIsPlayer
GetPropertyPhoto
GetPropertyPhotoFile
GetPropertyPhotoData
GetHouseIntegrationSnapshot
GetGarageDiagnostics
```

## Template safety

Interior or garage templates referenced by any property cannot be disabled or deleted. The admin UI hides deletion, the server checks usage, the DELETE repeats the usage condition atomically, and database foreign keys remain the final guard.
