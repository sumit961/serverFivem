# cm-house API v1.7.0

## Authority

- `cm-house` owns properties, access, reusable templates and permanent house garage slots.
- `cm-vehicles` owns physical vehicles, condition and stored/outside location.
- Interior and garage templates are created and edited only through the protected house module opened from `cm-admin`.
- The house creation wizard only selects existing templates.

## Template exports

```lua
local interior = exports['cm-house']:GetInteriorTemplate(templateId)
local garage = exports['cm-house']:GetGarageTemplate(templateId)
local capacity = exports['cm-house']:GetGarageCapacity(houseId)
```

Garage capacity is exactly the number of physical placement-car slots saved in the garage template. It is not typed by the administrator and is not inferred by the house wizard.

## Admin panel exports

```lua
exports['cm-house']:OpenAdminPanel(source, 'interiors')
exports['cm-house']:OpenAdminPanel(source, 'garages')
exports['cm-house']:OpenHouseCreator(source)
```

These exports open the relevant UI only. Server permission checks still decide whether each action is allowed.

## Family integration

```lua
local allowed, reason = exports['cm-house']:CanAccessProperty(characterId, houseId, action)
local contract = exports['cm-house']:GetFamilyHouseContract()
```

Weapon locker permission keys:

- `weapon_storage.access`
- `weapon_storage.deposit`
- `weapon_storage.withdraw`

Garage customization/settings permissions and exports were removed in v1.7.0.

## Weapon storage contract

```lua
local contract = exports['cm-house']:GetHouseWeaponStorageContract()
```

Rules:

- Weapons must have confirmed durability of 100% before deposit.
- Ammunition remains stackable.
- Weapon serial metadata is recursively removed before the locker row is written.
- The removed serial is not restored when the weapon is withdrawn.
- Existing stored weapon rows are sanitized once at resource startup.
