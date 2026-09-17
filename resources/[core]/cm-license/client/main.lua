-- CM License System — Client Main

Client = {
    ActiveTest = nil,
}

function Client.IsInTest()
    return Client.ActiveTest ~= nil
end

-- One notification path: cm-hud when it is running, chat otherwise.
function Client.Notify(message, kind)
    if not message then return end
    if GetResourceState('cm-hud') == 'started' then
        local ok = pcall(function() exports['cm-hud']:Notify(tostring(message), kind or 'inform') end)
        if ok then return end
    end
    TriggerEvent('chat:addMessage', {
        args = { 'License System', tostring(message) },
        color = kind == 'error' and { 255, 80, 80 } or kind == 'success' and { 90, 220, 120 } or { 0, 229, 255 }
    })
end

-- Big centre-screen text for time-critical prompts.
function Client.Alert(text, durationMs)
    if not text then return end
    BeginTextCommandPrint('STRING')
    AddTextComponentSubstringPlayerName(tostring(text))
    EndTextCommandPrint(durationMs or 2500, true)
end

RegisterNetEvent('cm-license:client:notify', function(message, kind)
    Client.Notify(message, kind)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    NPC.Init()
    Test.Init()
    Checkpoints.Init()
    HUD.Init()

    print('^2[CM-License Client]^7 Started')
end)

-- ============================================================================
-- TEST LIFECYCLE EVENTS
-- ============================================================================

RegisterNetEvent(Constants.EVENTS.CLIENT.TEST_STARTED, function(data)
    if not data then return end

    SendNUIMessage({ type = 'hideLoading' })

    Client.ActiveTest = {
        testId = data.testId,
        licenseType = data.licenseType,
        licenseLabel = data.licenseLabel,
        category = data.category or Constants.VEHICLE_CATEGORY.GROUND,
        vehicleModel = data.vehicleModel,
        maxMistakes = tonumber(data.maxMistakes) or 0,
        timeoutSeconds = tonumber(data.timeoutSeconds) or 1200,
        secondsRemaining = tonumber(data.secondsRemaining) or tonumber(data.timeoutSeconds) or 1200,
        currentCheckpoint = 0,
        seatingGraceUntil = GetGameTimer() + ((tonumber(CMLicenseConfig.TestSession.SeatingGraceSeconds) or 8) * 1000),
    }

    Checkpoints.SetCheckpoints(data.checkpoints or {})

    local netId = tonumber(data.vehicleNetId)
    local timeout = GetGameTimer() + 10000
    while netId and not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < timeout do Wait(50) end

    local vehicle = netId and NetToVeh(netId) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        TriggerServerEvent(Constants.EVENTS.SERVER.TEST_FAILED, Constants.FAIL_REASON.VEHICLE_SPAWN_FAILED)
        Test.Cleanup()
        return
    end

    Test.TestVehicle = vehicle
    Client.ActiveTest.vehicleNetId = netId

    SetEntityAsMissionEntity(vehicle, false, false)
    SetVehicleCustomPrimaryColour(vehicle, 0, 229, 255)
    SetVehicleCustomSecondaryColour(vehicle, 5, 28, 36)
    -- Only relabel when the server could not apply the exam plate itself.
    if not data.plateAlreadySet then
        SetVehicleNumberPlateText(vehicle, data.vehiclePlate or CMLicenseConfig.TestVehicle.Plate)
        SetVehicleNumberPlateTextIndex(vehicle, 0)
    end

    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= vehicle then
        TaskWarpPedIntoVehicle(ped, vehicle, -1)
    end

    Client.Notify('Test booked. Drive to the cyan start marker to begin — the clock is already running.', 'success')
end)

RegisterNetEvent('cm-license:client:testBegan', function(data)
    if not Client.ActiveTest then return end
    HUD.SyncDeadline(data and data.secondsRemaining)
    Client.Alert('~g~Examination started. Follow the checkpoints.~s~', 3000)
end)

RegisterNetEvent(Constants.EVENTS.CLIENT.SET_CHECKPOINT, function(data)
    if not Client.ActiveTest then return end

    Client.ActiveTest.currentCheckpoint = data.currentCheckpoint
    Checkpoints.CurrentCheckpoint = data.currentCheckpoint
    Checkpoints.ClearAck()
    Checkpoints.UpdateRouteBlip()

    local completed = data.currentCheckpoint >= data.totalCheckpoints
    PlaySoundFrontend(-1, completed and 'CHECKPOINT_PERFECT' or 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', true)

    Checkpoints.ShowInstruction(data.currentCheckpoint)
    HUD.UpdateCheckpoint(data)
end)

RegisterNetEvent(Constants.EVENTS.CLIENT.CHECKPOINT_REJECTED, function(data)
    if not Client.ActiveTest then return end
    -- Older payloads were a bare string.
    Checkpoints.OnCheckpointRejected(type(data) == 'table' and data or { message = data })
end)

RegisterNetEvent(Constants.EVENTS.CLIENT.COMPLETION_REJECTED, function(data)
    if not Client.ActiveTest then return end
    Test.ResumeAfterRejectedCompletion(data)
end)

RegisterNetEvent('cm-license:client:mistake', function(data)
    if not Client.ActiveTest then return end
    HUD.UpdateMistakes(data or {})
    PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', true)
    Client.Alert(('~r~MISTAKE %d / %d~s~'):format(tonumber(data and data.mistakes) or 0, tonumber(data and data.maxMistakes) or 0), 2000)
end)

RegisterNetEvent(Constants.EVENTS.CLIENT.TEST_COMPLETED, function(data)
    if not Client.ActiveTest then return end

    local returnPosition = data and data.returnPosition
    Test.Cleanup()

    if returnPosition and returnPosition.x and returnPosition.y and returnPosition.z then
        DoScreenFadeOut(350)
        local fadeTimeout = GetGameTimer() + 3000
        while not IsScreenFadedOut() and GetGameTimer() < fadeTimeout do Wait(0) end

        local ped = PlayerPedId()
        RequestCollisionAtCoord(returnPosition.x, returnPosition.y, returnPosition.z)
        SetEntityCoordsNoOffset(ped, returnPosition.x, returnPosition.y, returnPosition.z + 0.5, false, false, false)
        SetEntityHeading(ped, returnPosition.heading or 0.0)
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
        Wait(250)
        DoScreenFadeIn(350)
    end
end)

RegisterNetEvent(Constants.EVENTS.CLIENT.TEST_FAILED, function(data)
    data = type(data) == 'table' and data or {}
    SendNUIMessage({ type = 'hideLoading' })

    if Client.ActiveTest then
        Test.Cleanup()
    end

    -- The result screen carries the message unless the server already sent a
    -- notification for it (a rejected start, for example).
    if data.silent and data.message then
        return
    end

    CMLog('Test failed: ' .. tostring(data.reason))
end)

-- ============================================================================
-- KEYBINDS AND LOOPS
-- ============================================================================

CreateThread(function()
    while true do
        if NPC.NearbyPed or Client.IsInTest() then
            Wait(0)
            if IsControlJustReleased(0, 38) then  -- E
                if NPC.NearbyPed and not Client.IsInTest() then
                    NPC.CheckNPCInteraction()
                elseif Client.IsInTest() then
                    Test.CheckStartPoint()
                end
            end
        else
            Wait(300)
        end
    end
end)

CreateThread(function()
    while true do
        if Client.IsInTest() then
            Wait(0)
            Checkpoints.DrawMarkers()
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(500)
        if Client.IsInTest() then
            Test.UpdateTestState()
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Test.Cleanup()
    if NPC.PromptVisible then pcall(function() exports['cm-ui']:HideInteract() end) end
    NPC.CloseMenu()
    NPC.DespawnAll()
    SetNuiFocus(false, false)
end)

print('^2[CM-License Client]^7 Client loaded')
