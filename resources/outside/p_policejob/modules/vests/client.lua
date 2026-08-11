local Vests = {}

function Vests:register()
    Citizen.Wait(1000) -- Wait for other modules to load
    if not Config?.Vests then
        if Bridge?.Config?.Debug then
            lib.print.warn('No vests configured, skipping registration.')
        end
        return
    end

    if type(Config?.Vests) ~= 'table' then
        lib.print.error('Config?.Vests is not a table! Please check your configuration.')
        return
    end

    for itemName, itemData in pairs(Config?.Vests) do
        exports(itemName, function(data, slot)
            if not itemData.useable then
                goto skip
            end

            if Bridge.Progress.Start({
                duration = itemData.usingTime,
                label = locale('using_vest'),
                useWhileDead = false,
                canCancel = true,
                disable = itemData.disableControls or nil,
                anim = itemData.usingAnim or nil
            }) then
                goto skip
            else
                goto cancel
            end

            ::skip::
            local playerPed = cache.ped
            local plyArmour = GetPedArmour(playerPed)
            local newArmour = math.min(100, plyArmour + itemData.armourAmount)
            if newArmour > itemData.maxAmount then
                newArmour = itemData.maxAmount
            end
            SetPedArmour(playerPed, newArmour)
            TriggerServerEvent('p_bridge/server/removeItem', itemName, 1)

            if Bridge?.Config?.Debug then
                lib.print.info(('Used vest %s, armour set to %s'):format(itemName, tostring(newArmour)))
            end

            ::cancel::
        end)

        RegisterNetEvent('p_policejob/use_vest/' .. itemName, function(data)
            exports['p_policejob'][itemName](data)
        end)
    end
end

Citizen.CreateThread(function()
    Vests:register()
end)