local placementActive=false

local function confirmPlacement()
    if not placementActive then return end
    placementActive=false
    ClearAllHelpMessages()
    if lib.notify then lib.notify({description='Saving gang vehicle location...',type='inform',duration=2500}) end
    TriggerServerEvent('cm-gang:server:confirmFleetPlacement')
end

local function cancelPlacement()
    if not placementActive then return end
    placementActive=false
    ClearAllHelpMessages()
    TriggerServerEvent('cm-gang:server:cancelFleetPlacement')
    if lib.notify then lib.notify({description='Fleet placement cancelled.',type='inform'}) end
end

RegisterCommand('+cmgangsaveplacement',confirmPlacement,false)
RegisterCommand('-cmgangsaveplacement',function() end,false)
RegisterKeyMapping('+cmgangsaveplacement','Save gang vehicle spawn location','keyboard','H')

local function showPlacementHelp(model)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(('[H] Save %s spawn location  |  [BACKSPACE] Cancel'):format(tostring(model or 'vehicle')))
    EndTextCommandDisplayHelp(0, false, false, -1)
end

RegisterNetEvent('cm-gang:client:fleetPlacement',function(data)
    placementActive=true
    SetNuiFocus(false,false)
    local model=tostring(data and data.model or 'vehicle')
    TriggerServerEvent('cm-gang:server:fleetPlacementReady',model)
    if lib.notify then lib.notify({description='Drive the spawned vehicle into position, then press H to save.',type='inform',duration=7000}) end
    CreateThread(function()
        while placementActive do
            showPlacementHelp(model)
            local savePressed=(IsRawKeyReleased and IsRawKeyReleased(72))
                or IsControlJustReleased(0,74) or IsDisabledControlJustReleased(0,74)
            local cancelPressed=(IsRawKeyReleased and IsRawKeyReleased(8))
                or IsControlJustReleased(0,177) or IsDisabledControlJustReleased(0,177)
            if savePressed then
                confirmPlacement()
            elseif cancelPressed then
                cancelPlacement()
            end
            Wait(0)
        end
    end)
end)

RegisterNetEvent('cm-gang:client:fleetPlacementResult',function(ok,result)
    placementActive=false; ClearAllHelpMessages()
    if lib.notify then lib.notify({description=ok and 'Gang vehicle spawn location saved.' or tostring(result or 'Placement failed'):gsub('_',' '),type=ok and 'success' or 'error'}) end
end)

AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then placementActive=false; ClearAllHelpMessages() end end)
