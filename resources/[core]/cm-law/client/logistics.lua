local function logisticsPost(name, data)
    return lib.callback.await(name, false, data)
end

RegisterNUICallback('logistics', function(_, cb)
    cb(logisticsPost('cm-law:server:logistics') or { ok = false })
end)


RegisterNUICallback('logisticsCreate', function(data, cb)
    cb(logisticsPost('cm-law:server:logisticsCreate', type(data) == 'table' and data.lines or {}) or { ok = false })
end)

RegisterNUICallback('logisticsAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    cb(lib.callback.await('cm-law:server:logisticsAction', false, data.action, data.orderId) or { ok = false })
end)

-- Phase 4 is deliberately world-only.  The law dashboard remains the Phase
-- 3 order view; cargo is represented by local visuals whose state is always
-- accepted from the server before an interaction is attempted.
local robbery = (Config.Logistics and Config.Logistics.Robbery) or {}
local cargoVisuals, currentCarry, lastNearbyRequest, nearbyEligible = {}, nil, 0, false
local promptText, promptUntil = nil, 0

local function notify(message, kind)
    TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'info')
end

local function clearCargoVisual(cargoId)
    local visual = cargoVisuals[tonumber(cargoId)]
    if visual and visual.object and DoesEntityExist(visual.object) then DeleteEntity(visual.object) end
    if tonumber(currentCarry) == tonumber(cargoId) then ClearPedSecondaryTask(PlayerPedId()) end
    cargoVisuals[tonumber(cargoId)] = nil
    if tonumber(currentCarry) == tonumber(cargoId) then currentCarry = nil end
end

local function requestModel(model)
    local hash = GetHashKey(model)
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(25) end
    return HasModelLoaded(hash) and hash or nil
end

local function ensureCargoObject(visual)
    if visual.object and DoesEntityExist(visual.object) then return visual.object end
    local model = requestModel(tostring(robbery.CargoModel or 'prop_cs_cardbox_01'))
    if not model then return nil end
    visual.object = CreateObject(model, visual.x or 0.0, visual.y or 0.0, visual.z or 0.0, false, false, false)
    SetEntityAsMissionEntity(visual.object, true, true)
    SetModelAsNoLongerNeeded(model)
    return visual.object
end

local function applyCargoVisual(data)
    if type(data) ~= 'table' or not tonumber(data.id) then return end
    local id = tonumber(data.id)
    if data.state == 'removed' or data.state == 'extracted' or data.state == 'delivered'
        or data.state == 'expired' or data.state == 'recovered' then
        clearCargoVisual(id)
        return
    end
    local visual = cargoVisuals[id] or {}
    for key, value in pairs(data) do visual[key] = value end
    cargoVisuals[id] = visual
    if visual.state == 'carried' then
        currentCarry = tonumber(visual.carrierSource) == GetPlayerServerId(PlayerId()) and id or currentCarry
    end
end

RegisterNetEvent('cm-law:client:logisticsCargoSync', function(data)
    applyCargoVisual(data)
end)

local function cargoObjectUpdate(visual)
    local object = ensureCargoObject(visual)
    if not object then return end
    if visual.state == 'carried' and visual.carrierSource then
        local player = GetPlayerFromServerId(tonumber(visual.carrierSource))
        local ped = player and player ~= -1 and GetPlayerPed(player) or 0
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            if not IsEntityAttachedToEntity(object, ped) then
                AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, 57005),
                    0.22, 0.02, -0.08, 90.0, 0.0, 80.0, true, true, false, true, 1, true)
            end
            if ped == PlayerPedId() then
                local dict = 'anim@heists@box_carry@'
                RequestAnimDict(dict)
                if HasAnimDictLoaded(dict) and not IsEntityPlayingAnim(ped, dict, 'idle', 3) then
                    TaskPlayAnim(ped, dict, 'idle', 2.0, -2.0, -1, 49, 0.0, false, false, false)
                end
            end
            return
        end
    elseif visual.state == 'dropped' or visual.state == 'wrecked' or visual.state == 'available' then
        DetachEntity(object, true, true)
        SetEntityCoordsNoOffset(object, tonumber(visual.x) or 0.0, tonumber(visual.y) or 0.0,
            tonumber(visual.z) or 0.0, false, false, false)
        PlaceObjectOnGroundProperly(object)
        FreezeEntityPosition(object, true)
    end
end

local function rearPosition(vehicle)
    local distance = tonumber(robbery.RearDistance) or 3.5
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -distance, 0.7)
end

local function showPrompt(text)
    promptText, promptUntil = text, GetGameTimer() + 250
end

local function drawPrompt()
    if not promptText or GetGameTimer() > promptUntil then return end
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(promptText)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function callRobbery(action, orderId, vehicleNetId, cargoId)
    local result = lib.callback.await('cm-law:server:logisticsRobbery', false,
        action, orderId, vehicleNetId, cargoId)
    if result and result.ok then
        notify(result.message or 'Cargo operation complete.', 'success')
    elseif result and result.error then
        notify(result.error, 'error')
    end
    return result
end

local function extractionPointNear(coords)
    local points = robbery.ExtractionPoints or {}
    for gangId, configured in pairs(points) do
        if type(gangId) == 'string' and type(configured) == 'table' and configured.x then
            points = configured
            break
        end
    end
    for _, point in ipairs(points) do
        if type(point) == 'table' and tonumber(point.x) and tonumber(point.y) and tonumber(point.z)
            and #(coords - vector3(point.x, point.y, point.z)) <= (tonumber(robbery.ExtractionRadius) or 4.0) then
            return true
        end
    end
    return false
end

CreateThread(function()
    while true do
        Wait(500)
        for _, visual in pairs(cargoVisuals) do cargoObjectUpdate(visual) end
        if currentCarry then
            local visual = cargoVisuals[currentCarry]
            if not visual or visual.state ~= 'carried' then currentCarry = nil end
        end
    end
end)

CreateThread(function()
    while true do
        local wait = 700
        promptText = nil
        nearbyEligible = false
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local nearestVehicle, nearestState, nearestDistance = nil, nil, 99999.0
        if not IsPedInAnyVehicle(ped, false) and not IsPauseMenuActive() then
            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(vehicle) then
                    local state = Entity(vehicle).state.cmLegalLogistics
                    if type(state) == 'table' and state.orderId then
                        local distance = #(coords - GetEntityCoords(vehicle))
                        if distance < nearestDistance then
                            nearestVehicle, nearestState, nearestDistance = vehicle, state, distance
                        end
                    end
                end
            end
        end

        if nearestVehicle and nearestDistance <= (tonumber(robbery.VisualRadius) or 100.0) then
            wait = 0
            local rear = rearPosition(nearestVehicle)
            local rearDistance = #(coords - rear)
            if rearDistance <= (tonumber(robbery.InteractionDistance) or 2.5) then
                if GetGameTimer() - lastNearbyRequest > 1200 then
                    lastNearbyRequest = GetGameTimer()
                    local nearby = lib.callback.await('cm-law:server:logisticsCargoNearby', false,
                        nearestState.orderId, NetworkGetNetworkIdFromEntity(nearestVehicle)) or {}
                    nearbyEligible = nearby.eligible == true
                    local rows = nearby.crates or {}
                    for _, row in ipairs(rows) do
                        row.x, row.y, row.z = rear.x, rear.y, rear.z
                        applyCargoVisual(row)
                    end
                end
                if not currentCarry then
                    local firstAvailable
                    for id, visual in pairs(cargoVisuals) do
                        if tonumber(visual.orderId) == tonumber(nearestState.orderId)
                            and visual.state == 'available' then firstAvailable = id; break end
                    end
                    if firstAvailable then
                        showPrompt('Press ~INPUT_CONTEXT~ to take a convoy crate')
                        if IsControlJustPressed(0, 38) then
                            callRobbery('claim', nearestState.orderId,
                                NetworkGetNetworkIdFromEntity(nearestVehicle), firstAvailable)
                            Wait(500)
                        end
                    elseif nearbyEligible then
                        showPrompt('Press ~INPUT_CONTEXT~ to breach the convoy')
                        if IsControlJustPressed(0, 38) then
                            local vehicleNetId = NetworkGetNetworkIdFromEntity(nearestVehicle)
                            local started = callRobbery('breach_start', nearestState.orderId, vehicleNetId)
                            if started and started.ok then
                                local completed = lib.progressCircle({
                                    duration = (tonumber(robbery.BreachSeconds) or 20) * 1000,
                                    label = 'Breaching military cargo',
                                    position = 'bottom',
                                    useWhileDead = false,
                                    canCancel = true,
                                    disable = { move = false, car = true, combat = true },
                                })
                                callRobbery(completed and 'breach_complete' or 'breach_cancel',
                                    nearestState.orderId, vehicleNetId)
                            end
                            Wait(700)
                        end
                    end
                end
            end
        end

        if currentCarry then
            wait = 0
            local visual = cargoVisuals[currentCarry]
            if visual and visual.state == 'carried' then
                if extractionPointNear(coords) then
                    showPrompt('Press ~INPUT_CONTEXT~ to extract convoy cargo')
                    if IsControlJustPressed(0, 38) then
                        callRobbery('extract', visual.orderId, nil, currentCarry)
                        Wait(700)
                    end
                else
                    showPrompt('Press ~INPUT_CONTEXT~ to drop convoy cargo')
                    if IsControlJustPressed(0, 38) then
                        callRobbery('drop', visual.orderId, nil, currentCarry)
                        Wait(500)
                    end
                end
            end
        else
            for id, visual in pairs(cargoVisuals) do
                if (visual.state == 'dropped' or visual.state == 'wrecked')
                    and visual.x and #(coords - vector3(visual.x, visual.y, visual.z)) <= (tonumber(robbery.InteractionDistance) or 2.5) then
                    wait = 0
                    showPrompt('Press ~INPUT_CONTEXT~ to carry this convoy crate')
                    if IsControlJustPressed(0, 38) then
                        callRobbery('claim', visual.orderId, nil, id)
                        Wait(500)
                    end
                    break
                end
            end
        end
        drawPrompt()
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        if currentCarry then
            local visual = cargoVisuals[currentCarry]
            if visual and visual.state == 'carried' then
                callRobbery('heartbeat', visual.orderId, nil, currentCarry)
                Wait(tonumber(robbery.HeartbeatIntervalMs) or 2500)
            else
                currentCarry = nil
                Wait(500)
            end
        else
            Wait(800)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(cargoVisuals) do clearCargoVisual(id) end
end)
