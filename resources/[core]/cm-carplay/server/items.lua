-- cm-inventory bridge for CarPlay's usable items ('carplay', 'tunerchip').
-- Replaces the original ESX/QBCore detection: this server only runs cm-core.

local function waitForInventory()
    local attempts = 0
    while GetResourceState('cm-inventory') ~= 'started' and attempts < 40 do
        Wait(500)
        attempts = attempts + 1
    end
    return GetResourceState('cm-inventory') == 'started'
end

local function registerUsableItems()
    local resourceName = GetCurrentResourceName()

    -- cm-itemactions owns the generic usable-item router. Register this
    -- resource as the explicit domain handler there so its catalog scan
    -- cannot later replace CarPlay with the generic "cannot use" handler.
    if GetResourceState('cm-itemactions') == 'started' then
        local ok, carplayRegistered, tunerRegistered = pcall(function()
            return exports['cm-itemactions']:RegisterExternalItem('carplay', resourceName, 'UseItem'),
                exports['cm-itemactions']:RegisterExternalItem('tunerchip', resourceName, 'UseItem')
        end)
        if ok and carplayRegistered == true and tunerRegistered == true then
            print('^2[Prism-CarPlay]^7 Registered carplay/tunerchip with cm-itemactions.')
            return true
        end
    end

    -- Compatibility fallback for a server that intentionally runs without
    -- cm-itemactions. This server normally takes the route above.
    if not waitForInventory() then return false end
    local ok = pcall(function()
        exports['cm-inventory']:RegisterUseableItem('carplay', resourceName, 'UseItem')
        exports['cm-inventory']:RegisterUseableItem('tunerchip', resourceName, 'UseItem')
    end)
    if ok then
        print('^2[Prism-CarPlay]^7 Registered carplay/tunerchip directly with cm-inventory.')
    end
    return ok
end

function UseCarplayItem(src)
    TriggerClientEvent('prism-carplay:client:useCarplayItem', src)
end

function UseTunerChip(src)
    TriggerClientEvent('prism-carplay:client:useTunerChip', src)
end

function RemoveCarplayItem(src, plate)
    exports['cm-inventory']:AddItem(src, 'carplay', 1)
end

function RemoveTunerChip(src, plate)
    exports['cm-inventory']:AddItem(src, 'tunerchip', 1)
end

exports('UseItem', function(itemName, src)
    itemName = tostring(itemName or ''):lower()
    if itemName == 'carplay' then
        UseCarplayItem(src)
        return { success = true, remove = 1, message = 'You install the CarPlay unit.' }
    elseif itemName == 'tunerchip' then
        UseTunerChip(src)
        return { success = true, remove = 1, message = 'You install the tuner chip.' }
    end
    return { success = false, remove = 0, message = 'No action is registered for this item.' }
end)

CreateThread(function()
    if not registerUsableItems() then
        print('^1[Prism-CarPlay]^7 cm-inventory is not running; usable items were not registered.')
    end
end)

-- Reclaim the route automatically if cm-itemactions is restarted on its own.
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= 'cm-itemactions' then return end
    CreateThread(function()
        Wait(250)
        registerUsableItems()
    end)
end)
