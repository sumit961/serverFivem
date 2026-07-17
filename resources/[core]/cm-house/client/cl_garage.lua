-- ============================================================
--  cm-house | cl_garage.lua   |  v1.7.0 multi-exit garage
--
--  Every interior parking bay is always visible:
--    cyan MarkerTypeCarSymbol (36) = available
--    red  MarkerTypeCarSymbol (36) = occupied
--
--  Occupied bays contain real networked CM vehicles: fully visible, F-enterable
--  and compatible with the G menu. Start with Left Ctrl, then drive to the
--  interior vehicle-exit marker and press E to leave the garage.
-- ============================================================

local G = nil
local menuOpen = false
local selectedSlot = nil
local garageMenuToken = nil
local garageMenuRendered = false
local garageNuiReady = false
local CAR_SYMBOL_MARKER = 36 -- MarkerTypeCarSymbol
local syncingGarageVehicles = false

local WINDOW_BONES = {
    [0] = { 'window_lf', 'window_lf1', 'window_lf2', 'window_lf3' },
    [1] = { 'window_rf', 'window_rf1', 'window_rf2', 'window_rf3' },
    [2] = { 'window_lr', 'window_lr1', 'window_lr2', 'window_lr3' },
    [3] = { 'window_rr', 'window_rr1', 'window_rr2', 'window_rr3' },
    [4] = { 'window_lm' },
    [5] = { 'window_rm' },
    [6] = { 'windscreen' },
    [7] = { 'windscreen_r' },
}

local function vehicleHasWindowBone(vehicle, windowIndex)
    local names = WINDOW_BONES[windowIndex]
    if not names then return false end
    for _, boneName in ipairs(names) do
        local ok, boneIndex = pcall(GetEntityBoneIndexByName, vehicle, boneName)
        if ok and tonumber(boneIndex) and tonumber(boneIndex) ~= -1 then return true end
    end
    return false
end

-- Occupied bays are real OneSync vehicles created by the server in this
-- garage's routing bucket. This request is idempotent: it reuses existing
-- entities and only creates/deletes vehicles whose slot assignment changed.
local function syncNetworkedVehicles()
    if not G or syncingGarageVehicles then return end
    syncingGarageVehicles = true
    CreateThread(function()
        local ok, why = lib.callback.await('cm-house:server:ensureGarageVehicles', false, G.houseId)
        syncingGarageVehicles = false
        if ok ~= true and G then
            lib.notify({ description = why or 'Garage vehicles could not be loaded.', type = 'error' })
            print(('[cm-house] networked garage vehicles failed: %s'):format(tostring(why)))
        end
    end)
end


local function captureVehicleConditionState(vehicle)
    local snapshot = {
        windowSchema = 2,
        brokenWindows = {},
        doors = {},
        tyres = {},
        engineRunning = false,
        undriveable = false,
    }

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return snapshot end

    -- Only inspect window indexes whose matching model bone exists. Calling
    -- IsVehicleWindowIntact for an unsupported index can return false, which the
    -- old snapshot interpreted as real broken glass on every recall.
    for i = 0, 7 do
        if vehicleHasWindowBone(vehicle, i) then
            local ok, intact = pcall(IsVehicleWindowIntact, vehicle, i)
            if ok and intact == false then snapshot.brokenWindows[tostring(i)] = true end
        end
    end

    for i = 0, 7 do
        local damaged, angle = false, 0.0
        pcall(function() damaged = IsVehicleDoorDamaged(vehicle, i) == true end)
        pcall(function() angle = tonumber(GetVehicleDoorAngleRatio(vehicle, i)) or 0.0 end)
        snapshot.doors[tostring(i)] = { damaged = damaged, broken = damaged, angle = angle }
    end

    for i = 0, 7 do
        local burst, onRim = false, false
        pcall(function() burst = IsVehicleTyreBurst(vehicle, i, false) == true end)
        pcall(function() onRim = IsVehicleTyreBurst(vehicle, i, true) == true end)
        snapshot.tyres[tostring(i)] = { burst = burst or onRim, onRim = onRim }
    end

    pcall(function() snapshot.engineRunning = GetIsVehicleEngineRunning(vehicle) == true end)
    pcall(function() snapshot.undriveable = not IsVehicleDriveable(vehicle, false) end)
    return snapshot
end

local function draw3d(x, y, z, text)
    if CMHouseInteraction and CMHouseInteraction.Request then
        CMHouseInteraction.Request(('garage:%s:%s'):format(tostring(G and G.houseId or 0), text),
            text, nil, 80)
    end
end

local function closeSlotMenu()
    menuOpen = false
    selectedSlot = nil
    garageMenuToken = nil
    garageMenuRendered = false
    SendNUIMessage({ action = 'closeGarageSlot' })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

local function safeVehicle(v)
    return {
        id = tonumber(v.id) or 0,
        plate = tostring(v.plate or ''),
        model = tostring(v.model or ''),
        label = tostring(v.label or v.model or 'Vehicle'),
        shared = v.shared == true,
        ownerCid = tonumber(v.ownerCid),
        isStored = v.isStored == true,
        assigned = v.assigned == true,
        inGarage = v.inGarage == true,
        outside = v.outside == true,
        parked = v.parked == true,
        parkedHouseId = tonumber(v.parkedHouseId),
        parkedSlotIndex = tonumber(v.parkedSlotIndex),
        parkedHouseLabel = tostring(v.parkedHouseLabel or ''),
        canPark = v.canPark == true,
        canCall = v.canCall == true,
        locationState = tostring(v.locationState or ''),
        locationRef = v.locationRef and tostring(v.locationRef) or nil,
        locationSlot = tonumber(v.locationSlot),
        statusCode = tostring(v.statusCode or ''),
        statusLabel = tostring(v.statusLabel or ''),
        recoverable = v.recoverable == true,
        unavailableReason = v.unavailableReason and tostring(v.unavailableReason) or nil,
    }
end

function openSlotMenu(slot)
    if menuOpen or not G then return end
    menuOpen = true
    selectedSlot = slot
    garageMenuRendered = false
    garageMenuToken = ('%s:%s:%s:%s'):format(
        tostring(GetPlayerServerId(PlayerId())), tostring(G.houseId),
        tostring(slot.index), tostring(GetGameTimer()))

    local current = slot.vehicle and safeVehicle(slot.vehicle) or nil
    local list = {}

    -- An occupied space has one clear job: recall the vehicle already assigned
    -- to it. Do not fetch or render the full owned-vehicle list behind that
    -- action. Empty spaces still list every eligible owned vehicle, including a
    -- car assigned to another house slot so it can be moved here atomically.
    if not current then
        local vehicles, why = lib.callback.await('cm-house:server:parkable', false, G.houseId)
        if not vehicles then
            closeSlotMenu()
            lib.notify({ description = why or 'Could not read your vehicles.', type = 'error' })
            return
        end
        for _, vehicle in ipairs(vehicles) do
            list[#list + 1] = safeVehicle(vehicle)
        end
    end
    local payload = {
        requestId = garageMenuToken,
        slotIndex = tonumber(slot.index) or 0,
        occupied = current ~= nil,
        current = current,
        vehicles = list,
        canShare = current ~= nil and tonumber(current.ownerCid) == tonumber(MyCid),
    }

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'openGarageSlot', data = payload })

    CreateThread(function()
        local token = garageMenuToken
        local deadline = GetGameTimer() + 2500
        while menuOpen and garageMenuToken == token and not garageMenuRendered
              and GetGameTimer() < deadline do
            Wait(300)
            if menuOpen and garageMenuToken == token and not garageMenuRendered then
                SendNUIMessage({ action = 'openGarageSlot', data = payload })
            end
        end
        if menuOpen and garageMenuToken == token and not garageMenuRendered then
            closeSlotMenu()
            lib.notify({ description = 'The CM garage menu could not open. Try again.', type = 'error' })
            print(('[cm-house] garage slot NUI did not render. ready=%s house=%s slot=%s')
                :format(tostring(garageNuiReady), tostring(G and G.houseId), tostring(slot.index)))
        end
    end)
end

RegisterNUICallback('garageSlot:ready', function(data, cb)
    garageNuiReady = data and data.rootFound == true
    if Config.Debug then
        print(('[cm-house] Garage slot NUI ready (v%s, root=%s).')
            :format(tostring(data and data.version or 'unknown'), tostring(garageNuiReady)))
    end
    cb({ ok = true })
end)

RegisterNUICallback('garageSlot:rendered', function(data, cb)
    local token = data and tostring(data.requestId or '') or ''
    local matches = menuOpen and garageMenuToken ~= nil and token == garageMenuToken
    if matches and data.visible == true then garageMenuRendered = true end
    cb({ ok = true, accepted = matches and data.visible == true })
end)

RegisterNUICallback('garageSlot:error', function(data, cb)
    print(('[cm-house] Garage slot NUI error: %s'):format(tostring(data and data.message or 'unknown')))
    cb({ ok = true })
end)

RegisterNUICallback('garageSlot:close', function(_, cb)
    closeSlotMenu()
    cb({ ok = true })
end)

RegisterNUICallback('garageSlot:action', function(data, cb)
    if not menuOpen or not G or not selectedSlot then
        closeSlotMenu()
        cb({ ok = false })
        return
    end

    local action = data and tostring(data.action or '') or ''
    local houseId, slotIndex = G.houseId, selectedSlot.index
    local ok, msg

    if action == 'park' then
        if selectedSlot.vehicle then
            ok, msg = false, 'This parking space already has a vehicle.'
        else
            ok, msg = lib.callback.await('cm-house:server:assignVehicleToSlot', false,
                houseId, slotIndex, tonumber(data.vehicleId), false)
        end
    elseif action == 'call' then
        if selectedSlot.vehicle then
            ok, msg = false, 'This parking space already has a vehicle.'
        else
            ok, msg = lib.callback.await('cm-house:server:callVehicleById', false,
                houseId, slotIndex, tonumber(data.vehicleId))
        end
    elseif action == 'recall' then
        local vehicleId = selectedSlot.vehicle and tonumber(selectedSlot.vehicle.id) or nil
        if not vehicleId then
            ok, msg = false, 'This parking space has no assigned vehicle.'
        else
            local label = tostring(selectedSlot.vehicle.label or selectedSlot.vehicle.model or 'This vehicle')
            closeSlotMenu()
            local choice = lib.alertDialog({
                header = 'Recall vehicle',
                content = ('Recall %s into parking space %d? The vehicle system will safely move or recreate one authoritative garage vehicle.'):format(label, tonumber(slotIndex) or 0),
                centered = true,
                cancel = true,
                labels = { confirm = 'Recall car', cancel = 'Cancel' },
            })
            if choice ~= 'confirm' then
                cb({ ok = false, cancelled = true })
                return
            end
            ok, msg = lib.callback.await('cm-house:server:recallAssignedVehicle', false,
                houseId, slotIndex, vehicleId)
        end
    elseif action == 'remove' then
        local label = selectedSlot.vehicle
            and tostring(selectedSlot.vehicle.label or selectedSlot.vehicle.model or 'This vehicle')
            or 'This vehicle'
        closeSlotMenu()
        local choice = lib.alertDialog({
            header = 'Remove vehicle assignment',
            content = ('Cancel %s from parking space %d? The garage vehicle will be removed and the space cleared.'):format(label, tonumber(slotIndex) or 0),
            centered = true,
            cancel = true,
            labels = { confirm = 'Cancel car', cancel = 'Keep car' },
        })
        if choice ~= 'confirm' then
            cb({ ok = false, cancelled = true })
            return
        end
        ok, msg = lib.callback.await('cm-house:server:removeVehicleFromSlot', false, houseId, slotIndex)
    elseif action == 'share' and selectedSlot.vehicle then
        ok, msg = lib.callback.await('cm-house:server:shareVehicle', false,
            houseId, selectedSlot.vehicle.id, data.share == true)
    else
        cb({ ok = false })
        return
    end

    -- Do not rely only on the broadcast racing this NUI callback. Pull the
    -- committed snapshot directly so red/cyan markers change immediately
    -- after remove, recall, call, or park actions.
    if ok and G and tonumber(G.houseId) == tonumber(houseId) then
        local fresh = lib.callback.await('cm-house:server:garageState', false, houseId)
        if fresh then
            G = fresh
            syncNetworkedVehicles()
        end
    end

    lib.notify({ description = msg or (ok and 'Garage updated.' or 'Garage action failed.'), type = ok and 'success' or 'error' })
    if ok then closeSlotMenu() end
    cb({ ok = ok == true, message = msg })
end)



CreateThread(function()
    while true do
        local sleep = 700
        if G and not menuOpen then
            local pc = GetEntityCoords(PlayerPedId())
            local nearest, nearestDist = nil, 999.0
            local seatedVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
            local physicalVehicles = {}
            for _, entity in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(entity) then
                    local vehicleId
                    pcall(function() vehicleId = tonumber(Entity(entity).state.cmVehicleId) end)
                    if vehicleId then physicalVehicles[vehicleId] = GetEntityCoords(entity) end
                end
            end

            for _, slot in pairs(G.slots or {}) do
                local at = slot.icon or slot.coords
                local d = #(pc - vector3(at.x, at.y, at.z))
                if d < 45.0 then
                    sleep = 0
                    local occupied = slot.vehicle ~= nil
                    local physicalCoords = occupied and physicalVehicles[tonumber(slot.vehicle.id)] or nil
                    local carPhysicallyPresent = physicalCoords ~= nil
                        and #(physicalCoords - vector3(slot.coords.x, slot.coords.y, slot.coords.z)) < 3.0
                    if not carPhysicallyPresent then
                        local r, g, b = occupied and 255 or 47, occupied and 74 or 228, occupied and 74 or 255
                        DrawMarker(CAR_SYMBOL_MARKER,
                            at.x, at.y, at.z + 0.30,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, at.h or (slot.coords and slot.coords.h) or 0.0,
                            0.78, 0.78, 0.78,
                            r, g, b, 215,
                            false, false, 2, false, nil, nil, false)
                    end
                end
                if d < nearestDist then nearest, nearestDist = slot, d end
            end

            if nearest and nearestDist <= 2.6 and seatedVehicle == 0 then
                local at = nearest.icon or nearest.coords
                draw3d(at.x, at.y, at.z + 1.05,
                    nearest.vehicle and 'Manage parking space' or 'Select vehicle')
                if IsControlJustReleased(0, Config.Prompt.key) then openSlotMenu(nearest) end
            end
        end
        Wait(sleep)
    end
end)

-- Leave through the garage vehicle-exit point.
--
-- No world marker is drawn. When the player reaches the configured exit they
-- receive the shared transparent cyan E prompt. A driver takes the same
-- network vehicle outside; a player on foot leaves at the property door.
local drivingOut = false
local leavingOnFoot = false
local missingExitWarned = false
CreateThread(function()
    while true do
        local sleep = 650
        if G and not menuOpen then
            local exits = G.vehicleExits or (G.vehicleExit and { G.vehicleExit } or {})
            local exit, exitIndex, nearestDistance
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            local driver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
            local pos = driver and GetEntityCoords(veh) or GetEntityCoords(ped)
            for index, candidate in ipairs(exits) do
                local distance = #(pos - vector3(candidate.x, candidate.y, candidate.z))
                if nearestDistance == nil or distance < nearestDistance then
                    exit, exitIndex, nearestDistance = candidate, index, distance
                end
            end
            local ex = exit and tonumber(exit.x)
            local ey = exit and tonumber(exit.y)
            local ez = exit and tonumber(exit.z)

            if ex and ey and ez then
                missingExitWarned = false
                local dist = nearestDistance or #(pos - vector3(ex, ey, ez))

                if dist <= ((Config.GarageTemplate and Config.GarageTemplate.exitUseDistance) or 1.35) then
                    sleep = 0
                    if CMHouseInteraction and CMHouseInteraction.Request then
                        CMHouseInteraction.Request('garage:outside-exit', 'Go outside', nil, 85)
                    end

                    if IsControlJustReleased(0, Config.Prompt.key) then
                        if driver and not drivingOut then
                            drivingOut = true

                            local slotIndex = 0
                            pcall(function()
                                slotIndex = tonumber(Entity(veh).state.cmHouseSlot) or 0
                            end)

                            local netId = 0
                            if NetworkGetEntityIsNetworked(veh) then
                                pcall(function()
                                    netId = tonumber(NetworkGetNetworkIdFromEntity(veh)) or 0
                                end)
                            end

                            if netId <= 0 then
                                drivingOut = false
                                lib.notify({
                                    description = 'This vehicle is not network-ready yet. Wait a moment and try again.',
                                    type = 'error'
                                })
                            else
                                DoScreenFadeOut(300)
                                local deadline = GetGameTimer() + 1800
                                while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end

                                local driveCondition = {
                                    fuel = exports['cm-vehicles']:GetVehicleFuel(veh),
                                    engine = GetVehicleEngineHealth(veh),
                                    body = GetVehicleBodyHealth(veh),
                                    tank = GetVehiclePetrolTankHealth(veh),
                                    dirt = GetVehicleDirtLevel(veh),
                                    conditionState = captureVehicleConditionState(veh),
                                }
                                local ok, msg = lib.callback.await(
                                    'cm-house:server:driveVehicleOut', false,
                                    G.houseId, slotIndex, netId, exitIndex, driveCondition)

                                if not ok then
                                    DoScreenFadeIn(250)
                                    lib.notify({
                                        description = msg or 'The vehicle could not leave the garage.',
                                        type = 'error'
                                    })
                                    drivingOut = false
                                end
                            end
                        elseif not driver and veh == 0 and not leavingOnFoot then
                            leavingOnFoot = true
                            if CMHouseInteraction and CMHouseInteraction.BlockFor then
                                CMHouseInteraction.BlockFor(1200)
                            end
                            TriggerEvent('cm-house:client:leave', exitIndex)
                            SetTimeout(1200, function() leavingOnFoot = false end)
                        end
                    end
                end
            elseif not missingExitWarned then
                missingExitWarned = true
                print(('[cm-house] garage %s has no valid exit coordinates.')
                    :format(tostring(G and G.houseId or 'unknown')))
            end
        end
        Wait(sleep)
    end
end)

RegisterNetEvent('cm-house:client:garageUpdate', function(state)
    if not G or G.houseId ~= state.houseId then return end
    if menuOpen then closeSlotMenu() end
    G = state
    syncNetworkedVehicles()
end)

RegisterNetEvent('cm-house:client:enterGarageState', function(houseId)
    local state, why = lib.callback.await('cm-house:server:garageState', false, houseId)
    if not state then
        lib.notify({ description = why or 'Could not read the garage.', type = 'error' })
        return
    end
    G = state
    syncNetworkedVehicles()
    lib.notify({
        description = ('%d of %d spaces used. Go to the configured exit and press %s to leave.')
            :format(state.used, state.capacity, Config.Prompt.keyLabel),
        type = 'inform'
    })
end)

RegisterNetEvent('cm-house:client:leaveGarageState', function()
    closeSlotMenu()
    G = nil
    syncingGarageVehicles = false
    drivingOut = false
    leavingOnFoot = false
end)

-- ============================================================
--  RETURN ZONE  --  drive in to park
--  Outside the property, in the normal world. Driving into this zone remains
--  an alternative way to park the current vehicle; interior slot assignment
--  is handled by the cyan/red parking symbols above.
-- ============================================================
local zones = {}    -- [houseId] = door coords for the return zone
local storingFromReturnZone = false

RegisterNetEvent('cm-house:client:syncGarageZone', function(houseId, coords)
    zones[houseId] = coords
end)

CreateThread(function()
    while true do
        local sleep = 900

        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        -- Only matters if you are actually DRIVING something.
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local pc = GetEntityCoords(veh)

            for houseId, z in pairs(zones) do
                local d = #(pc - vector3(z.x, z.y, z.z))

                if d < 30.0 then sleep = 0 end

                if d <= 3.5 then
                    draw3d(z.x, z.y, z.z + 1.0,
                        'Park vehicle')

                    if not storingFromReturnZone and IsControlJustReleased(0, Config.Prompt.key) then
                        storingFromReturnZone = true
                        local plate = nil
                        pcall(function() plate = Entity(veh).state.cmPlate end)
                        plate = tostring(plate or GetVehicleNumberPlateText(veh) or '')

                        local submittedCondition = {
                            netId = NetworkGetEntityIsNetworked(veh) and NetworkGetNetworkIdFromEntity(veh) or 0,
                            fuel = exports['cm-vehicles']:GetVehicleFuel(veh),
                            engine = GetVehicleEngineHealth(veh),
                            body = GetVehicleBodyHealth(veh),
                            tank = GetVehiclePetrolTankHealth(veh),
                            dirt = GetVehicleDirtLevel(veh),
                            conditionState = captureVehicleConditionState(veh),
                        }
                        DoScreenFadeOut(250)
                        local fadeDeadline = GetGameTimer() + 1200
                        while not IsScreenFadedOut() and GetGameTimer() < fadeDeadline do Wait(0) end

                        local callbackOk, ok, msg, transition = pcall(function()
                            return lib.callback.await(
                                'cm-house:server:storeVehicle', false, houseId, plate, submittedCondition)
                        end)
                        if not callbackOk then
                            ok = false
                            msg = 'The garage did not respond. Your vehicle was not parked.'
                            transition = nil
                        end

                        lib.notify({ description = tostring(msg or (ok and 'Vehicle parked.' or 'Parking failed.')), type = ok and 'success' or 'error' })

                        if ok and type(transition) == 'table' and transition.enterGarage == true then
                            -- The server has atomically stored the car, moved the
                            -- player into this property's garage bucket and
                            -- synchronously removed the world entity. Complete
                            -- the transition from the server-supplied template
                            -- snapshot so no second callback can fail after parking.
                            TriggerEvent('cm-house:client:completeGarageStoreTransition', transition)
                        else
                            DoScreenFadeIn(250)
                        end

                        storingFromReturnZone = false
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

MyCid = nil
RegisterNetEvent('cm-house:client:setCid', function(cid) MyCid = tonumber(cid) or cid end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        closeSlotMenu()
                G = nil
        syncingGarageVehicles = false
        drivingOut = false
        storingFromReturnZone = false
    end
end)
