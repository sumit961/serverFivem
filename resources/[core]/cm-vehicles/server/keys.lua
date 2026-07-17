local U = CMVehicles.Utils
local Config = CMVehicles.Config
CMVehicles.Keys = CMVehicles.Keys or {}

RegisterNetEvent('cm-vehicles:server:toggleLock', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    if plate == '' then return U.Notify(src, 'Vehicle id not found yet. Try again.', 'error') end
    if not CMVehicles.Server.HasAccess(src, plate, 'vehicle.lock') then return U.Notify(src, 'You do not have keys for this vehicle.', 'error') end
    local near = CMVehicles.Server.ValidateNearVehicle(src, netId, (Config.Interaction.distance or 4.2) + 2.0)
    if not near then return U.Notify(src, 'You are too far from the vehicle.', 'error') end

    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then return end
    local newLocked = row.is_locked ~= true

    -- An admin vehicle has no row to update. Toggle it in the world only.
    if not (CMVehicles.Admin and CMVehicles.Admin.IsAdminVehicle(plate)) then
        MySQL.update.await('UPDATE cm_owned_vehicles SET is_locked = ? WHERE plate = ?', { newLocked and 1 or 0, plate })
    end

    local finalNetId = tonumber(netId) or CMVehicles.Server.GetSpawnedNetId(plate)
    if finalNetId then
        local ent = NetworkGetEntityFromNetworkId(finalNetId)
        if ent and ent ~= 0 then Entity(ent).state:set('cmLocked', newLocked, true) end
    end

    CMVehicles.Server.Audit(CMVehicles.Server.GetCharacterId(src), plate, newLocked and 'lock' or 'unlock', {})
    TriggerClientEvent('cm-vehicles:client:lockVisuals', -1, plate, finalNetId, newLocked)
    U.Notify(src, newLocked and 'Vehicle locked.' or 'Vehicle unlocked.', 'success')
end)

RegisterNetEvent('cm-vehicles:server:giveTempKey', function(plate, targetSrc)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate)
    targetSrc = tonumber(targetSrc)
    if not CMVehicles.Server.IsOwner(src, plate) then return U.Notify(src, 'Only the vehicle owner can give temporary keys.', 'error') end
    if not targetSrc or not GetPlayerName(targetSrc) then return U.Notify(src, 'Target player is not online.', 'error') end

    local ped, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if ped and targetPed and ped ~= 0 and targetPed ~= 0 then
        if #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > (Config.Interaction.keyGiveDistance or 6.0) then
            return U.Notify(src, 'Target player is too far away.', 'error')
        end
    end

    local ok, result = U.CallExport('cm-vehiclekeys', 'GiveTempKey', src, targetSrc, plate)
    if not ok or result ~= true then return U.Notify(src, tostring(result or 'Could not give temporary key.'), 'error') end
    U.Notify(src, 'Temporary key given.', 'success')
end)


RegisterNetEvent('cm-vehicles:server:requestEngineStart', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    netId = tonumber(netId)

    if plate == '' then
        return TriggerClientEvent('cm-vehicles:client:engineStartResult', src, netId or 0, false, 'Vehicle id not found yet. Try again.')
    end

    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then
        return TriggerClientEvent('cm-vehicles:client:engineStartResult', src, netId or 0, false, 'Vehicle not found.')
    end

    if not CMVehicles.Server.HasAccess(src, plate, 'vehicle.engine') then
        return TriggerClientEvent('cm-vehicles:client:engineStartResult', src, netId or 0, false, 'You do not have keys for this vehicle.')
    end

    if (tonumber(row.fuel) or tonumber(Config.Fuel and Config.Fuel.defaultFuel) or 100.0) <= 0.1 then
        return TriggerClientEvent('cm-vehicles:client:engineStartResult', src, netId or 0, false, 'Vehicle has no fuel.')
    end

    local destroyedThreshold = tonumber(Config.Damage and Config.Damage.destroyedEngineHealth) or 150.0
    local effectiveHealth = tonumber(row.engine_health) or 1000.0
    if netId and netId > 0 then
        local entity = NetworkGetEntityFromNetworkId(netId)
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local state = Entity(entity).state
            local stateVehicleId = tonumber(state.cmVehicleId)
            if stateVehicleId and tonumber(row.id) ~= stateVehicleId then
                return TriggerClientEvent('cm-vehicles:client:engineStartResult', src, netId, false, 'Vehicle identity changed. Try again.')
            end
            -- Use the trusted server registry. Do not authorize the bypass
            -- from a client-replicable state flag alone.
            local isAdminVehicle = CMVehicles.Admin and CMVehicles.Admin.IsAdminVehicle
                and CMVehicles.Admin.IsAdminVehicle(plate) == true
            if not isAdminVehicle and state.cmConditionReady ~= true then
                return TriggerClientEvent('cm-vehicles:client:engineStartResult', src, netId, false,
                    'Vehicle condition is still loading. Try again in a moment.')
            end
            if isAdminVehicle then
                -- Temporary admin/placement vehicles are created from a known
                -- healthy baseline and are never persisted. Some server builds
                -- briefly report native health as 0 for a newly streamed
                -- client-owned entity, so do not turn that transient into a
                -- destroyed-engine rejection.
                effectiveHealth = 1000.0
            else
                local stateHealth = tonumber(state.cmEngineHealth)
                local okNative, nativeHealth = pcall(GetVehicleEngineHealth, entity)
                nativeHealth = okNative and tonumber(nativeHealth) or nil
                if state.cmConditionReady == true and nativeHealth ~= nil then
                    effectiveHealth = math.min(effectiveHealth, nativeHealth)
                elseif stateHealth ~= nil then
                    effectiveHealth = math.min(effectiveHealth, stateHealth)
                end
                if state.cmEngineDestroyed == true then effectiveHealth = 0.0 end
            end
        end
    end
    if effectiveHealth <= destroyedThreshold then
        return TriggerClientEvent('cm-vehicles:client:engineStartResult', src, netId or 0, false, 'Engine is too damaged to start. Repair it first.')
    end

    local near = CMVehicles.Server.ValidateNearVehicle(src, netId, 8.0)
    if not near then
        return TriggerClientEvent('cm-vehicles:client:engineStartResult', src, netId or 0, false, 'You are too far from the vehicle.')
    end

    -- Approved start. Replicate the garage-driving handoff before telling the
    -- driver to start the engine, so protection threads on every streaming client
    -- stop freezing the same network vehicle.
    if netId and netId > 0 then
        local entity = NetworkGetEntityFromNetworkId(netId)
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local state = Entity(entity).state
            if state.cmHouseGarageDisplay == true then
                state:set('cmGarageDriving', true, true)
            end
        end
    end

    -- Approved start. There is intentionally no hotwire/lockpick alternative.
    TriggerClientEvent('cm-vehicles:client:engineStartResult', src, netId or 0, true, 'Engine started.')
end)
