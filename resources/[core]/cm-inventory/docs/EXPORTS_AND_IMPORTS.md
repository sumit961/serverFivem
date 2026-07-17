# CM Inventory Exports and Imports

This is the integration reference for `cm-inventory` version `4.3.2`.
It documents the exports that are registered by the current files in
`server/exports.lua` and `server/tier2.lua`.

## Contents

- [Requirements](#requirements)
- [How to import CM Inventory](#how-to-import-cm-inventory)
- [Important rules](#important-rules)
- [Quick export reference](#quick-export-reference)
- [Exports that do not exist](#exports-that-do-not-exist)
- [Item exports](#item-exports)
- [Usable-item exports](#usable-item-exports)
- [External-inventory exports](#external-inventory-exports)
- [Weapon and death hooks](#weapon-and-death-hooks)
- [Safe client-to-server integration](#safe-client-to-server-integration)
- [Return data](#return-data)
- [Troubleshooting](#troubleshooting)

## Requirements

`cm-inventory` has two hard resource dependencies:

```cfg
ensure oxmysql
ensure cm-items
ensure cm-inventory
```

Any resource that requires these exports should start after `cm-inventory`.
Declare that relationship in the consuming resource's `fxmanifest.lua`:

```lua
dependency 'cm-inventory'
```

The item being added must exist in `cm-items`, a configured inventory fallback,
or one of the configured dynamic item patterns. Registering a usable handler
does not create the item definition.

## How to import CM Inventory

FiveM exports are runtime APIs; there is no Lua file that needs to be imported
with `shared_script '@cm-inventory/...'`.

All current CM Inventory exports are **server exports**. Core exports from
`server/exports.lua` can be called using either style below:

```lua
-- Recommended style
local Inventory = exports['cm-inventory']
local ok, result = Inventory:AddItem(source, 'water', 1)

-- Also supported
local ok, result = exports['cm-inventory'].AddItem(source, 'water', 1)
```

The core implementation normalises both colon and dot calls. This guide uses
the colon style for those exports. The three newer exports in `server/tier2.lua`
do not currently normalise a colon-call `self` argument, so their examples use
dot calls explicitly.

For optional integration, check the resource state instead of declaring a hard
dependency:

```lua
if GetResourceState('cm-inventory') == 'started' then
    exports['cm-inventory']:AddItem(source, 'water', 1, nil, 'optional_reward')
end
```

## Important rules

- Call these exports from server code. There are currently no public client
  exports.
- The first `src` argument is a player's server ID, not a character ID or player
  object.
- Never accept an arbitrary item name, amount, metadata table, or slot directly
  from an untrusted client.
- Export names are case-sensitive. Use `AddItem`, not `addItem`.
- Use dot calls for `FollowAmmoToInventory`, `DropEquippedWeaponsOnDeath`, and
  `ResetDeathDropState`; use either style for the core exports.
- Item names are normalised to lowercase internally.
- Pass a meaningful `reason` to mutations so `inventory_audit` records explain
  why the change happened.
- Treat `AddItem` or `RemoveItem` as the final authority even after a pre-check;
  inventory state may have changed.

## Quick export reference

| Export | Arguments | Returns |
| --- | --- | --- |
| `AddItem` | `src, itemName, amount?, metadata?, reason?, preferredSlot?` | `boolean, slotOrError` |
| `RemoveItem` | `src, itemName, amount?, metadata?, reason?` | `boolean, error?` |
| `MoveItem` | `src, fromSlot, toSlot` | `boolean, error?` |
| `HasItem` | `src, itemName, amount?` | `boolean, totalCount` |
| `CanCarryItem` | `src, itemName, amount?` | `boolean, error?` |
| `GetInventory` | `src` | `payload` or `nil, error` |
| `GiveItemToNearby` | `src, slot, amount?` | `boolean, error?` |
| `RegisterUseableItem` | `itemName, resourceName, exportName` | `boolean` |
| `CreateUseableItem` | `itemName, callback` | `boolean` |
| `OpenExternalInventory` | `src, context` | `boolean, error?` |
| `CloseExternalInventory` | `src` | `true` |
| `GetOpenExternalInventory` | `src` | `context` or `nil` |
| `ReloadWeapon` | `src` | `false, message` in the current ammo system |
| `FollowAmmoToInventory` | `src` | `boolean` |
| `DropEquippedWeaponsOnDeath` | `src` | No useful return value |
| `ResetDeathDropState` | `src` | No useful return value |

Arguments marked with `?` are optional.

## Exports that do not exist

The current resource does not expose these common compatibility names:

- `addItem` or `AddPlayerItem`;
- `RegisterStash`, `OpenStash`, or `ClearStash`;
- any client-side inventory export.

Use the exact `AddItem` name and use `OpenExternalInventory` for stash-style
storage. External storage is created lazily from its owner context and does not
need a separate registration export. There is currently no public export for
deleting every item in an external storage namespace.

## Item exports

### `AddItem`

Adds an item to the player's character inventory.

```lua
local ok, slotOrError = exports['cm-inventory']:AddItem(
    src,
    'water',
    2,
    { quality = 100 },
    'shop_purchase'
)

if not ok then
    print(('Could not add water: %s'):format(slotOrError or 'unknown error'))
    return
end

print(('Water was placed in %s'):format(slotOrError))
```

Signature:

```lua
AddItem(src, itemName, amount, metadata, reason, preferredSlot)
```

- `amount` defaults to `1` and must be a positive integer.
- `metadata` defaults to an empty table.
- `reason` is written to the inventory audit record.
- `reason` is argument 5. Argument 6 is the preferred slot; do not put an audit
  reason in argument 6.
- `preferredSlot` is optional. If it is incompatible with the item, inventory
  falls back to normal slot selection.
- On success the second return value is the slot that received or stacked the
  item.
- On failure the second return value is an error message.
- The export refreshes the player's inventory and immediately applies items
  added directly to an equipment slot.

Example adding starter clothing directly to an equipment slot:

```lua
local ok, slotOrError = exports['cm-inventory']:AddItem(
    src,
    'clothing_torso',
    1,
    torsoMetadata,
    'starter_clothes',
    'outerwear'
)
```

Common slot names are:

- `quickaccess-1` through `quickaccess-5`;
- `pocket-1` through `pocket-6`;
- `backpack-1` through `backpack-30`, subject to bag level;
- equipment slots such as `outerwear`, `shirt`, `bodyarmor`, `bag`, `weapon`,
  `ammo`, `pants`, and `shoes`.

### `RemoveItem`

Removes a quantity by item name across the player's stacks.

```lua
local hasItem, count = exports['cm-inventory']:HasItem(src, 'bandage', 1)
if not hasItem then
    return false, ('Bandage required; player has %s.'):format(count or 0)
end

local removed, removeError = exports['cm-inventory']:RemoveItem(
    src,
    'bandage',
    1,
    nil,
    'medical_treatment'
)

if not removed then
    return false, removeError
end
```

Signature:

```lua
RemoveItem(src, itemName, amount, metadata, reason)
```

Important current behaviour:

- `metadata` is recorded for auditing but is **not** used to choose a matching
  stack. Removal is by item name.
- Every player slot is searched, including equipment slots. The export does not
  synchronise equipment after removing an equipped item.
- Check `HasItem` immediately before removing. The current implementation can
  consume the available stacks before returning `false` when the requested
  total was larger than the amount owned.
- A successful call returns `true`. A failed call normally returns
  `false, errorMessage`.
- The export does not send a full inventory UI refresh after removal.

### `HasItem`

Checks the total quantity across every stack with the given item name.

```lua
local hasFive, total = exports['cm-inventory']:HasItem(src, 'water', 5)

if hasFive then
    print(('Player has %s water.'):format(total))
end
```

Signature:

```lua
HasItem(src, itemName, amount)
```

`amount` defaults to `1`. It returns the threshold result followed by the
player's total count. The count includes normal and equipment slots.

### `CanCarryItem`

Checks whether the added item weight fits the player's current bag capacity.

```lua
local canCarry, carryError = exports['cm-inventory']:CanCarryItem(src, 'water', 5)
if not canCarry then
    return false, carryError
end
```

This is a **weight check only**. It does not guarantee that a compatible empty
slot exists. Always handle the final result from `AddItem`.

### `MoveItem`

Moves, merges, or swaps items between two player inventory slots.

```lua
local moved, moveError = exports['cm-inventory']:MoveItem(
    src,
    'pocket-1',
    'quickaccess-1'
)
```

The inventory enforces slot compatibility, equipment gender, bag capacity,
locked backpack slots, stacking, and equipment updates. A move into an occupied
compatible stack merges it; otherwise a valid swap may occur. The export
synchronises affected equipment slots but does not send a general inventory UI
refresh.

### `GetInventory`

Returns the current authoritative inventory payload.

```lua
local inventory, inventoryError = exports['cm-inventory']:GetInventory(src)
if not inventory then
    return false, inventoryError
end

print(('Owner: %s/%s'):format(inventory.ownerType, inventory.ownerId))
print(('Weight: %s/%s grams'):format(
    inventory.weight.current,
    inventory.weight.max
))

for _, item in ipairs(inventory.items or {}) do
    print(item.slot, item.item_name, item.quantity)
end
```

See [Return data](#return-data) for the payload shape. Treat the returned table
as a snapshot; do not edit it and expect the database to change.

### `GiveItemToNearby`

Gives an item from a slot to the closest player within `Config.Give.distance`.

```lua
local ok, giveError = exports['cm-inventory']:GiveItemToNearby(
    src,
    'pocket-2',
    1
)
```

The export chooses the closest eligible player; it does not accept a target ID.
It validates distance, recipient character ownership, weight, and final item
placement. OneSync/server-side player coordinates are required.

## Usable-item exports

### Recommended cross-resource pattern

Register the item name with CM Inventory and provide a handler export in the
resource that owns the gameplay effect.

```lua
local function registerInventoryItems()
    if GetResourceState('cm-inventory') ~= 'started' then return false end

    return exports['cm-inventory']:RegisterUseableItem(
        'bandage',
        GetCurrentResourceName(),
        'UseItem'
    )
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() or resourceName == 'cm-inventory' then
        SetTimeout(500, registerInventoryItems)
    end
end)

exports('UseItem', function(itemName, src, item)
    if itemName ~= 'bandage' then
        return {
            success = false,
            remove = 0,
            message = 'No handler exists for this item.'
        }
    end

    TriggerClientEvent('my-medical:client:applyBandage', src, 25)

    return {
        success = true,
        remove = 1,
        message = 'You used a bandage.'
    }
end)
```

The handler receives:

```lua
UseItem(itemName, src, item)
```

- `itemName`: lowercase registered item name;
- `src`: player server ID;
- `item`: the inventory item snapshot, including its slot and metadata.

The handler must return a table:

```lua
{
    success = true,
    remove = 1,
    message = 'Used item.'
}
```

- `success = true` tells inventory that the effect completed.
- `remove` or `removeAmount` is the quantity inventory should consume from the
  exact used slot.
- `message` is an optional success notification.

Do not also call `RemoveItem` for the same use when returning `remove > 0`, or
the item may be consumed twice.

Re-register when either the handler resource or `cm-inventory` starts. Usable
registrations are held in memory and are lost when inventory restarts.

### `CreateUseableItem`

Exact export name:

```lua
CreateUseableItem(itemName, callback)
```

This is retained for a same-resource/local Lua callback. Passing Lua function
callbacks across resource exports is unreliable in FiveM, so other resources
should use `RegisterUseableItem(resourceName, exportName)` instead.

For a local callback, the handler can call `done` or return three values:

```lua
local function handler(src, item, done)
    done(true, 1, 'Used item.')
end

-- Equivalent return form:
local function otherHandler(src, item)
    return true, 1, 'Used item.'
end
```

The spelling `Useable` is part of the current public export names.

## External-inventory exports

Use external inventories for vehicle trunks, houses, warehouses, businesses,
motel rooms, evidence lockers, and similar persistent storage.

The caller must validate ownership, permission, proximity, and any job/rank
requirements **before** calling the export. CM Inventory cannot infer access
rules for another resource.

### `OpenExternalInventory`

```lua
local allowed = playerCanOpenWarehouse(src, warehouseId)

local ok, openError = exports['cm-inventory']:OpenExternalInventory(src, {
    allowed = allowed,
    ownerType = 'warehouse',
    ownerId = tostring(warehouseId),
    slotPrefix = 'warehouse-',
    slots = 30,
    displaySlots = 30,
    kind = 'warehouse',
    label = 'Warehouse Storage',
    subtitle = ('Unit %s'):format(warehouseId),
    icon = 'warehouse',
    replace = 'equipment',
    noWeightLimit = true,
    canDeposit = true,
    canWithdraw = true,
    data = { warehouseId = warehouseId }
})

if not ok then
    print(openError)
end
```

Required context fields:

| Field | Purpose |
| --- | --- |
| `ownerType` | Persistent `inventory_items.owner_type` namespace |
| `ownerId` | Persistent storage identifier within that namespace |
| `slots` | Number of usable storage slots |

Optional fields:

| Field | Default | Purpose |
| --- | --- | --- |
| `slotPrefix` | `slot-` | Database slot names, such as `warehouse-1` |
| `displaySlots` | `30` | Number of visual slots in the right panel |
| `kind` | `ownerType` | Integration/storage type label |
| `label` | `Storage` | UI heading |
| `subtitle` | Empty | UI subheading |
| `icon` | Empty | UI icon hint |
| `replace` | `equipment` | Panel replaced by external storage |
| `noWeightLimit` | `true` | External-storage UI weight flag |
| `canDeposit` | `true` | Whether the player can put items in storage |
| `canWithdraw` | `true` | Whether the player can take items out |
| `data` | `{}` | Caller-owned context returned by the query export |
| `allowed` | Not set | Setting this to `false` denies access |

Current limits and behaviour:

- `slots` must be at least `1` and is clamped to `200` internally.
- The current UI renders at most `30` external slots, so use `slots <= 30` for
  storage that must be fully accessible from this UI.
- `noWeightLimit` is currently forwarded to the UI; setting it to `false` does
  not create a server-enforced external-storage weight cap.
- `slotPrefix` must be at most 35 characters and cannot begin with the reserved
  `external-` prefix.
- Items persist in `inventory_items` using the supplied owner and slot namespace.
- There are no category restrictions inside external storage.
- If `allowed`, `canOpen`, `can_open`, or `isAllowed` is explicitly `false`, the
  external context is cleared, normal inventory is opened, and the export
  returns `false, 'External inventory access denied.'`.

### Vehicle trunk example

```lua
local ok, err = exports['cm-inventory']:OpenExternalInventory(src, {
    ownerType = 'vehicle_trunk',
    ownerId = tostring(vehicleId),
    slotPrefix = 'trunk-',
    slots = 6,
    displaySlots = 30,
    kind = 'vehicle_trunk',
    label = 'Vehicle Trunk',
    noWeightLimit = true,
    data = { plate = plate, vehicleId = vehicleId }
})
```

### `GetOpenExternalInventory`

Returns information about the storage currently open for a player:

```lua
local context = exports['cm-inventory']:GetOpenExternalInventory(src)
if context then
    print(context.ownerType, context.ownerId, context.kind)
end
```

Returned fields are:

```lua
{
    ownerType = 'warehouse',
    ownerId = 'warehouse_1',
    kind = 'warehouse',
    label = 'Warehouse Storage',
    slots = 30,
    slotPrefix = 'warehouse-',
    data = { warehouseId = 1 }
}
```

It returns `nil` when no external inventory is active.

### `CloseExternalInventory`

```lua
exports['cm-inventory']:CloseExternalInventory(src)
```

This clears the server-side external storage context and returns `true`.

More focused examples are available in
[EXTERNAL_INVENTORY_API.md](EXTERNAL_INVENTORY_API.md).

## Weapon and death hooks

### `ReloadWeapon`

```lua
local ok, message = exports['cm-inventory']:ReloadWeapon(src)
```

Manual reload is intentionally disabled in the current RP ammo system. This
export currently returns:

```lua
false, 'Manual reload is disabled. Ammo is used from inventory while shooting.'
```

### `FollowAmmoToInventory`

Moves equipped ammo from the ammo equipment slot into a normal unlocked slot,
normally when a weapon is unequipped.

```lua
local moved = exports['cm-inventory'].FollowAmmoToInventory(src)
```

It returns `false` if there is no equipped ammo, no free slot, insufficient
capacity, or the move fails. It currently needs a completely empty normal slot
and does not merge into an existing ammo stack.

### `DropEquippedWeaponsOnDeath`

```lua
-- Set the authoritative death state before calling this hook.
Player(src).state:set('isDead', true, true)
exports['cm-inventory'].DropEquippedWeaponsOnDeath(src)
```

The hook only acts when:

- `Player(src).state.isDead == true`;
- `Config.Death.dropWeapons` is not `false`;
- the player has equipped weapon or ammo items;
- the same death has not already been handled.

The equipped weapon and ammo become normal world drops. This is a fire-and-
forget hook and has no useful return value.

### `ResetDeathDropState`

Call this when the character is revived or a new death cycle begins:

```lua
Player(src).state:set('isDead', false, true)
exports['cm-inventory'].ResetDeathDropState(src)
```

This export clears the per-player duplicate-death guard and has no useful
return value.

## Safe client-to-server integration

Do not try to call CM Inventory exports directly from a client script. Send a
request to a server event owned by your resource, validate it server-side, and
then call the export with server-controlled values.

Client example:

```lua
TriggerServerEvent('my-jobs:server:claimCompletedDelivery')
```

Server example:

```lua
RegisterNetEvent('my-jobs:server:claimCompletedDelivery', function()
    local src = source

    -- This check must be authoritative and server-owned.
    if not DeliverySessions[src] or DeliverySessions[src].completed ~= true then
        return
    end

    DeliverySessions[src].completed = false

    local ok, slotOrError = exports['cm-inventory']:AddItem(
        src,
        'delivery_token',
        1,
        { route = DeliverySessions[src].routeId },
        'completed_delivery'
    )

    if not ok then
        DeliverySessions[src].completed = true
        print(('Reward failed for %s: %s'):format(src, slotOrError))
    end
end)
```

Never use this unsafe pattern:

```lua
-- UNSAFE: a modified client could request any item and amount.
RegisterNetEvent('my-resource:server:giveAnything', function(itemName, amount)
    exports['cm-inventory']:AddItem(source, itemName, amount)
end)
```

## Return data

### Inventory payload

`GetInventory(src)` returns:

```lua
{
    ownerType = 'character',
    ownerId = '42',
    items = { -- item snapshots },
    weight = {
        current = 2500,
        max = 45000
    },
    bag = {
        level = 1,
        label = 'Bag Level 1',
        backpackSlots = 6,
        maxWeight = 45000
    },
    slots = CMInventory.Config.Slots
}
```

Weights are stored and returned in grams.

### Item snapshot

Each entry in `payload.items` and each usable-item handler receives a table with
the following shape:

```lua
{
    id = 123,
    slot = 'pocket-1',
    item_name = 'water',
    name = 'water',
    label = 'Water Bottle',
    category = 'drink',
    type = 'drink',
    itemType = 'normal',
    rarity = 'normal',
    image = 'water.png',
    icon = 'water.png',
    quantity = 2,
    weight = 500,
    stack = true,
    usable = true,
    description = 'Clean drinking water.',
    durability = 100,
    metadata = {},
    equipmentSlot = nil,
    isClothing = false,
    isBag = false,
    bagLevel = 0
}
```

Fields vary by item definition and metadata. Treat the table as read-only.

## Troubleshooting

### `No such export` or `No such export AddItem`

- Confirm the name is exactly `AddItem`.
- Confirm the call is in a server script.
- Confirm `cm-inventory` reached the `started` state.
- Confirm `server/tier2.lua` and `server/exports.lua` exist; the bootloader fails
  when any required split server module is missing.
- Add `dependency 'cm-inventory'` to the consuming resource.

### `Unknown item`

- Add or enable the item in `cm-items`.
- Confirm its name matches after lowercasing.
- Confirm `cm-items` started before `cm-inventory`.
- Registering a usable handler alone does not define an item.

### `No character owner found`

- Call exports with a valid online player server ID.
- Ensure the character state contains `charId`, `characterId`, `citizenid`, or
  `character_id`, or that `cm-core:GetPlayer` returns an active character.

### `CanCarryItem` succeeds but `AddItem` fails

`CanCarryItem` checks weight only. `AddItem` can still fail because no compatible
slot is free, the requested equipment slot is occupied, or a bag slot is locked.

### A usable item says no effect is registered

- Confirm `RegisterUseableItem` returned `true`.
- Confirm the handler resource is started.
- Confirm the handler export name is exact.
- Re-register after `cm-inventory` restarts.
- Return a result table from the handler export.

### External storage opens but access is wrong

CM Inventory enforces the supplied `canDeposit` and `canWithdraw` flags, but the
calling resource owns permission, distance, and ownership validation. Perform
those checks before `OpenExternalInventory` and use a stable, server-derived
`ownerId`.

For narrower guides, also see:

- [EXTERNAL_INVENTORY_API.md](EXTERNAL_INVENTORY_API.md)
- [USABLE_ITEMS.md](USABLE_ITEMS.md)
