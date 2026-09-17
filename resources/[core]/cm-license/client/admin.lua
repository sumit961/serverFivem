-- CM License in-game setup and route builder.

AdminClient = { Mode='none', BuilderVehicle=0, LicenseTypeId=nil }

local function hint(text)
    SendNUIMessage({ type='builderHint', message=text })
end

-- Passing nil only restores NUI focus; the caller then sends its own dialog.
function AdminClient.OpenMenu(tests)
    SetNuiFocus(true, true)
    if tests then
        SendNUIMessage({ type='openAdminMenu', licenses=tests })
    end
end

function AdminClient.StopBuilder(message)
    AdminClient.Mode='none'
    AdminClient.BuilderVehicle=0
    AdminClient.LicenseTypeId=nil
    hint(nil)
    if message then Client.Notify(message, 'inform') end
end

RegisterNetEvent('cm-license:client:adminResult', function(action, ok, payload)
    payload = type(payload)=='table' and payload or {}

    if payload.message then Client.Notify(payload.message, ok and 'success' or 'error') end
    -- Re-open through OpenMenu so NUI focus comes back with the refreshed list.
    if payload.tests and action ~= 'beginBuilder' and action ~= 'deleteRoute' and action ~= 'toggleRoute' then
        AdminClient.OpenMenu(payload.tests)
    end

    if action=='listRoutes' and ok then
        AdminClient.OpenMenu(nil)
        SendNUIMessage({ type='openRouteManager', licenseTypeId=payload.licenseTypeId,
            licenseLabel=payload.licenseLabel, licenseType=payload.licenseType, routes=payload.routes or {} })
    elseif (action=='deleteRoute' or action=='toggleRoute') and ok and payload.licenseTypeId then
        SendNUIMessage({ type='routesUpdated', licenseTypeId=payload.licenseTypeId,
            routes=payload.routes or {}, tests=payload.tests })
    elseif action=='saveType' and ok and payload.id then
        SendNUIMessage({ type='adminSaved', id=payload.id })
    elseif action=='beginBuilder' then
        if not ok then
            AdminClient.StopBuilder(nil)
            return
        end
        AdminClient.Mode='vehicle_spawn'
        AdminClient.LicenseTypeId=payload.licenseTypeId

        local netId = tonumber(payload.netId)
        local untilAt = GetGameTimer() + 10000
        while netId and not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < untilAt do Wait(50) end
        AdminClient.BuilderVehicle = netId and NetToVeh(netId) or 0

        if AdminClient.BuilderVehicle == 0 then
            Client.Notify('The builder vehicle did not arrive. Try again.', 'error')
            TriggerServerEvent('cm-license:server:adminCancelBuilder')
            AdminClient.StopBuilder(nil)
            return
        end

        hint('[E] Save Vehicle Spawn  •  [BACKSPACE] Cancel')
    elseif action=='builderAction' and ok then
        if payload.stage=='route' then
            AdminClient.Mode='route'
            hint(payload.count==0 and '[E] Set Start Point  •  [G] Finish after checkpoints  •  [BACKSPACE] Cancel'
                or ('[E] Add Checkpoint  •  [G] Finish Route  •  [U] Undo  •  Points: %d'):format(payload.count))
        elseif payload.stage=='complete' then
            AdminClient.StopBuilder(nil)
            SendNUIMessage({ type='routeSaved', count=payload.count })
        end
    end
end)

CreateThread(function()
    while true do
        if AdminClient.Mode=='none' then
            Wait(500)
        else
            Wait(0)
            if IsControlJustReleased(0, 38) then          -- E
                TriggerServerEvent('cm-license:server:adminBuilderAction',
                    AdminClient.Mode=='vehicle_spawn' and 'save_spawn' or 'add_point')
            elseif AdminClient.Mode=='route' and IsControlJustReleased(0, 47) then   -- G
                TriggerServerEvent('cm-license:server:adminBuilderAction', 'finish')
            elseif AdminClient.Mode=='route' and IsControlJustReleased(0, 303) then  -- U
                TriggerServerEvent('cm-license:server:adminBuilderAction', 'undo')
            elseif IsControlJustReleased(0, 177) then     -- BACKSPACE
                TriggerServerEvent('cm-license:server:adminCancelBuilder')
                AdminClient.StopBuilder('Route builder cancelled.')
            end
        end
    end
end)

CreateThread(function()
    while true do
        if AdminClient.Mode~='none' and AdminClient.BuilderVehicle~=0 and DoesEntityExist(AdminClient.BuilderVehicle) then
            Wait(0)
            local c = GetEntityCoords(AdminClient.BuilderVehicle)
            DrawMarker(1, c.x, c.y, c.z-1.0, 0,0,0, 0,0,0, 3.0,3.0,1.0, 0,229,255,90, false,false,2,false,nil,nil,false)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource==GetCurrentResourceName() and AdminClient.Mode~='none' then
        TriggerServerEvent('cm-license:server:adminCancelBuilder')
    end
end)
