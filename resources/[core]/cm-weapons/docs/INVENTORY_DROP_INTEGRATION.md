# cm-inventory ammo drop integration

When a player drops ammo, ask `cm-weapons` for ammo drop data.

Server-side example inside your inventory drop code:

```lua
local dropData = nil
if GetResourceState('cm-weapons') == 'started' then
    dropData = exports['cm-weapons']:GetAmmoDropData(itemName)
end

if dropData and dropData.pickupHash then
    -- Use GTA ammo pickup hash for ammo drops.
    TriggerClientEvent('cm-weapons:client:spawnAmmoPickup', -1, {
        itemName = itemName,
        pickupHash = dropData.pickupHash,
        ammoKey = dropData.ammoKey,
        amount = amount,
        coords = { x = coords.x, y = coords.y, z = coords.z }
    })

    -- You can still create your normal CM dropped item row/UI prompt if you want.
    -- The important part is: ammo uses pickupHash from cm-weapons.
else
    -- normal item drop prop flow
end
```

Direct export:

```lua
local hash = exports['cm-weapons']:GetAmmoPickupHash('ammo_556')
-- returns 3837603782 for rifle ammo
```

Ammo drop data:

```lua
local data = exports['cm-weapons']:GetAmmoDropData('ammo_9mm')
-- data.pickupHash = 544828034
-- data.ammoKey = 'pistol'
-- data.packSize = 30
```
