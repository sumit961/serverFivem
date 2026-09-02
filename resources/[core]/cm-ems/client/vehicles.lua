-- cm-ems fleet vehicles (client):
--   - NUI relay for the Fleet tab (list, spawn, set minimum rank).
--   - H keybind: while driving an EMS fleet vehicle, saves/updates its
--     spawn location to wherever it currently is.
--   - Applies a freshly-spawned fleet vehicle's mods (from rn-vehicleshop).
--   - Drive-access enforcement: locks/unlocks nearby EMS fleet vehicles for
--     the LOCAL player based on their own current EMS duty/rank, using the
--     same SetVehicleDoorsLockedForPlayer pattern cm-vehicles already uses
--     for owned-vehicle protection (client/spawn.lua, client/main.lua).
--
-- Appearance configuration (colors/livery/wheels/photo) happens entirely in
-- rn-vehicleshop's /vehicleadmin -- this file has no configurator of its own.

local function notify(message, kind)
    if lib and lib.notify then lib.notify({ title = 'EMS Fleet', description = message, type = kind or 'inform' }) end
end

local fleetPlacementActive = false

local function waitForVehicle(netId, timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 8000)
    while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < deadline do Wait(0) end
    local veh = NetworkGetEntityFromNetworkId(netId)
    while (not veh or veh == 0 or not DoesEntityExist(veh)) and GetGameTimer() < deadline do
        veh = NetworkGetEntityFromNetworkId(netId)
        Wait(0)
    end
    if veh and veh ~= 0 and DoesEntityExist(veh) then return veh end
    return nil
end

RegisterNUICallback('fleetCatalog', function(_, cb)
    local rows = lib.callback.await('cm-ems:server:fleetCatalog', false)
    cb({ ok = rows ~= nil, vehicles = rows or {} })
end)

RegisterNUICallback('setFleetVehicleMinTier', function(data, cb)
    data = type(data) == 'table' and data or {}
    local ok, message = lib.callback.await('cm-ems:server:setFleetVehicleMinTier', false, data.model, data.minTier)
    if not ok then notify(message or 'Could not update that vehicle.', 'error') end
    cb({ ok = ok == true, error = message })
end)

RegisterNUICallback('spawnFleetVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    local ok, message = lib.callback.await('cm-ems:server:spawnFleetVehicle', false, data.model)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, error = message })
end)

RegisterNUICallback('setFleetVehicleLocation', function(data, cb)
    data = type(data) == 'table' and data or {}
    local ok, result = lib.callback.await('cm-ems:server:beginFleetLocationEdit', false, data.model)
    if not ok or type(result) ~= 'table' then notify(result or 'Could not start location edit.', 'error'); cb({ ok = false, error = result }); return end
    TriggerEvent('cm-ems:client:closeMenu')
    local vehicle = waitForVehicle(tonumber(result.netId), 10000)
    if not vehicle then notify('The EMS location dummy did not appear.', 'error'); cb({ ok = false }); return end
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    fleetPlacementActive = true
    notify(result.message or 'Drive to the location. Press H to save or Backspace to cancel.', 'inform')
    cb({ ok = true })
end)

RegisterNetEvent('cm-ems:client:adminFleetPlacement', function(result)
    if type(result) ~= 'table' then return end
    TriggerEvent('cm-admin:client:forceClose')
    local vehicle = waitForVehicle(tonumber(result.netId), 10000)
    if not vehicle then return notify('The EMS placement vehicle did not appear.', 'error') end
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    fleetPlacementActive = true
    notify(result.message or 'Drive to the location. Press H to save or Backspace to cancel.', 'inform')
end)

CreateThread(function()
    while true do
        if not fleetPlacementActive then Wait(500) else
            Wait(0)
            if IsControlJustPressed(0, 177) then
                local ok, message = lib.callback.await('cm-ems:server:cancelFleetLocationEdit', false)
                fleetPlacementActive = false
                notify(message, ok and 'success' or 'error')
            end
        end
    end
end)

RegisterNUICallback('recallAllFleetVehicles', function(_, cb)
    local ok, message = lib.callback.await('cm-ems:server:recallAllFleetVehicles', false)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, error = message })
end)

RegisterNetEvent('cm-ems:client:applyFleetMods', function(netId, mods)
    CreateThread(function()
        local vehicle = waitForVehicle(netId)
        if not vehicle then return end
        pcall(function() exports['cm-vehicles']:ApplyVehicleMods(vehicle, type(mods) == 'table' and mods or {}) end)
    end)
end)

-- ── H: save/update this EMS vehicle's spawn location ────────────────────
RegisterKeyMapping('emssavevehicle', 'Save/update EMS fleet vehicle spawn location here', 'keyboard', 'H')
RegisterCommand('emssavevehicle', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end -- driver only

    local fleet = Entity(vehicle).state.cmEmsFleet
    if type(fleet) ~= 'table' or not fleet.model then return end -- not an EMS fleet vehicle

    local class = GetVehicleClassFromName(GetEntityModel(vehicle))
    local kind = class == 15 and 'helicopter' or 'car' -- 15 = GTA's Helicopters class

    local ok, message = lib.callback.await('cm-ems:server:saveFleetVehicleLocation', false, fleet.model, kind)
    if ok then fleetPlacementActive = false end
    notify(message, ok and 'success' or 'error')
end, false)

-- ── Drive-access enforcement ──────────────────────────────────────────────
-- Every client independently locks/unlocks nearby EMS fleet vehicles FOR
-- THEMSELVES based on their own current duty/rank -- the same
-- SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), ...) pattern
-- cm-vehicles already uses (client/spawn.lua, client/main.lua) to restrict an
-- owned vehicle to its owner. This is a client-side convention already
-- established in this codebase, not a new trust model.
CreateThread(function()
    while true do
        Wait(1500)
        local emsState = LocalPlayer.state.cmEms
        local onDuty = type(emsState) == 'table' and emsState.onDuty == true
        local isLeader = type(emsState) == 'table' and emsState.isLeader == true
        local tier = (type(emsState) == 'table' and tonumber(emsState.tier)) or -1

        local playerCoords = GetEntityCoords(PlayerPedId())
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(vehicle) then
                local vehState = Entity(vehicle).state
                local fleet = vehState.cmEmsFleet
                if type(fleet) == 'table' and #(playerCoords - GetEntityCoords(vehicle)) < 40.0 then
                    -- fleet.ready reflects the recalling admin's own snapshot at
                    -- the moment of recall; it can stay stuck at false if that
                    -- specific admin was never close enough to verify the repair.
                    -- cmConditionReady is the vehicle's live, authoritative
                    -- condition state (cm-vehicles keeps retrying it for whoever
                    -- streams the vehicle in), so honor it directly instead of
                    -- only trusting the one-shot EMS flag.
                    local conditionReady = vehState.cmConditionReady ~= false
                    local minTier = tonumber(fleet.minTier) or 0
                    local qualifies = conditionReady and onDuty and (isLeader or tier >= minTier)
                    pcall(SetVehicleDoorsLockedForPlayer, vehicle, PlayerId(), not qualifies)
                end
            end
        end
    end
end)
