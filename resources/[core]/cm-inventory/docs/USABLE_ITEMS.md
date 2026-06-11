# Usable Item System v2.5

Cross-resource Lua function callbacks are unreliable in FiveM exports, so this version uses a stable export-handler model.

## Register an item from another resource

```lua
exports['cm-inventory'].RegisterUseableItem('bandage', GetCurrentResourceName(), 'UseItem')
```

## Provide the handler export

```lua
exports('UseItem', function(itemName, src, item)
    if itemName == 'bandage' then
        TriggerClientEvent('my-resource:client:heal', src, 25)
        return { success = true, remove = 1, message = 'You used a bandage.' }
    end

    return { success = false, remove = 0, message = 'No action.' }
end)
```

Return format:

```lua
{ success = true, remove = 1, message = 'Used item.' }
```

- `success`: true/false
- `remove`: amount to consume from inventory
- `message`: notification text
