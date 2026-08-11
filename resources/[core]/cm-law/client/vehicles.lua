-- cm-law fleet vehicles (client). Mirrors cm-police/client/vehicles.lua:
--   - NUI relay for the F9 Fleet tab (list, spawn/recall, recall all, set
--     minimum rank, set location).
--   - H keybind: while driving a fleet vehicle, saves/updates its spawn
--     location to wherever it currently is.
--   - Applies a freshly-spawned fleet vehicle's mods (from rn-vehicleshop).
--   - Drive-access enforcement: locks/unlocks nearby fleet vehicles for the
--     LOCAL player based on their own current org membership/duty/rank,
--     using the same SetVehicleDoorsLockedForPlayer pattern cm-police/
--     cm-ems/cm-vehicles already use for owned-vehicle protection.
--
-- Appearance configuration (colors/livery/wheels/photo) happens entirely in
-- rn-vehicleshop's /vehicleadmin -- this file has no configurator of its own.

local function notify(message, kind)
    if lib and lib.notify then lib.notify({ title = 'Fleet', description = message, type = kind or 'inform' }) end
end

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
    local rows = lib.callback.await('cm-law:server:fleetCatalog', false)
    cb({ ok = rows ~= nil, vehicles = rows or {} })
end)

RegisterNUICallback('setFleetVehicleMinTier', function(data, cb)
    data = type(data) == 'table' and data or {}
    local ok, message = lib.callback.await('cm-law:server:setFleetVehicleMinTier', false, data.model, data.minTier)
    if not ok then notify(message or 'Could not update that vehicle.', 'error') end
    cb({ ok = ok == true, error = message })
end)

RegisterNUICallback('setFleetVehicleLocation', function(data, cb)
    data = type(data) == 'table' and data or {}
    local ok, result = lib.callback.await('cm-law:server:beginFleetLocationEdit', false, data.model)
    if not ok or type(result) ~= 'table' then notify(result or 'Could not start location edit.', 'error'); cb({ ok = false, error = result }); return end
    CmLawCloseMenu()
    local vehicle = waitForVehicle(tonumber(result.netId), 10000)
    if not vehicle then notify('The fleet location dummy did not appear.', 'error'); cb({ ok = false }); return end
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    notify(result.message or 'Drive to the location and press H.', 'inform')
    cb({ ok = true })
end)

RegisterNUICallback('recallAllFleetVehicles', function(_, cb)
    local ok, message = lib.callback.await('cm-law:server:recallAllFleetVehicles', false)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, error = message })
end)

RegisterNetEvent('cm-law:client:applyFleetMods', function(netId, mods)
    CreateThread(function()
        local vehicle = waitForVehicle(netId)
        if not vehicle then return end
        pcall(function() exports['cm-vehicles']:ApplyVehicleMods(vehicle, type(mods) == 'table' and mods or {}) end)
    end)
end)

-- ── H: save/update this fleet vehicle's spawn location ───────────────────
RegisterKeyMapping('lawsavevehicle', 'Legal org: Save/update fleet vehicle spawn location here', 'keyboard', 'H')
RegisterCommand('lawsavevehicle', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end -- driver only

    local fleet = Entity(vehicle).state.cmLegalFleet
    if type(fleet) ~= 'table' or not fleet.model or not fleet.placement then return end -- not a location dummy

    local class = GetVehicleClassFromName(GetEntityModel(vehicle))
    local kind = class == 15 and 'helicopter' or 'car' -- 15 = GTA's Helicopters class

    local ok, message = lib.callback.await('cm-law:server:saveFleetVehicleLocation', false, fleet.model, kind)
    notify(message, ok and 'success' or 'error')
end, false)

-- ── Drive-access enforcement ──────────────────────────────────────────────
-- Every client independently locks/unlocks nearby fleet vehicles FOR
-- THEMSELVES based on their own current org/duty/rank -- the same
-- SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), ...) pattern already
-- established in this codebase (cm-vehicles, cm-police, cm-ems), not a new
-- trust model.
CreateThread(function()
    while true do
        Wait(1500)
        local legalState = LocalPlayer.state.cmLegalOrg
        local mine = type(legalState) == 'table' and legalState or nil
        local onDuty = mine and mine.onDuty == true
        local isLeader = mine and mine.isLeader == true
        local tier = (mine and tonumber(mine.tier)) or -1

        local playerCoords = GetEntityCoords(PlayerPedId())
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(vehicle) then
                local vehState = Entity(vehicle).state
                local fleet = vehState.cmLegalFleet
                if type(fleet) == 'table' and not fleet.placement and #(playerCoords - GetEntityCoords(vehicle)) < 40.0 then
                    -- fleet.ready reflects the recalling member's own snapshot at
                    -- the moment of recall; it can stay stuck at false if that
                    -- specific member was never close enough to verify the
                    -- repair. cmConditionReady is the vehicle's live,
                    -- authoritative condition state (cm-vehicles keeps retrying
                    -- it for whoever streams the vehicle in), so honor it
                    -- directly instead of only trusting the one-shot flag.
                    local conditionReady = vehState.cmConditionReady ~= false
                    local minTier = tonumber(fleet.minTier) or 0
                    local sameOrg = mine and fleet.organizationId == mine.id
                    local qualifies = conditionReady and onDuty and sameOrg and (isLeader or tier >= minTier)
                    pcall(SetVehicleDoorsLockedForPlayer, vehicle, PlayerId(), not qualifies)
                end
            end
        end
    end
end)
