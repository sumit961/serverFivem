CmQaClientRunner = {
    registered = false,
    registeredCharacterId = nil,
    activeRunId = nil,
    activeScenario = nil,
    inputState = nil,
    holdState = nil,
    ownerReady = false,
    generation = 0,
}

local QA_PROMPT_OWNER = 'cm-qa:test'

local function hidePrompt()
    pcall(function() exports['cm-ui']:HideInteract(QA_PROMPT_OWNER) end)
end

local function sendCancellation(runId, scenario, reason)
    if not runId or not scenario then return end
    TriggerServerEvent('cm-qa:server:clientEvent', {
        runId = runId,
        scenario = scenario,
        event = 'cancel',
        reason = tostring(reason or 'client_cleanup'),
    })
end

function ResetCmQaClientState(reason, notifyServer)
    local runId = CmQaClientRunner.activeRunId
    local scenario = CmQaClientRunner.activeScenario
    CmQaClientRunner.generation = CmQaClientRunner.generation + 1
    if notifyServer and CmQaClientRunner.registered then sendCancellation(runId, scenario, reason) end
    CmQaClientRunner.activeRunId = nil
    CmQaClientRunner.activeScenario = nil
    CmQaClientRunner.inputState = nil
    CmQaClientRunner.holdState = nil
    CmQaClientRunner.ownerReady = false
    hidePrompt()
    SetNuiFocus(false, false)
    pcall(function() SetNuiFocusKeepInput(false) end)
    SendNUIMessage({ action = 'qaReset' })
end

local function clientEvent(event, extra)
    if not CmQaClientRunner.registered or not CmQaClientRunner.activeRunId or not CmQaClientRunner.activeScenario then return end
    local payload = {
        runId = CmQaClientRunner.activeRunId,
        scenario = CmQaClientRunner.activeScenario,
        event = event,
    }
    for key, value in pairs(extra or {}) do payload[key] = value end
    TriggerServerEvent('cm-qa:server:clientEvent', payload)
end

local function closeNuiAndCancel(reason)
    ResetCmQaClientState(reason or 'escape', true)
end

RegisterNetEvent('cm-qa:client:registrationState', function(enabled, metadata)
    if enabled ~= true then
        CmQaClientRunner.registered = false
        CmQaClientRunner.registeredCharacterId = nil
        ResetCmQaClientState((metadata and metadata.reason) or 'registration_revoked', false)
        return
    end
    CmQaClientRunner.registered = true
    CmQaClientRunner.registeredCharacterId = tonumber(metadata and metadata.characterId)
end)

RegisterNetEvent('cm-qa:client:register', function()
    if CmQaClientRunner.registered then return end
    TriggerServerEvent('cm-qa:server:ready', CmQaClientActions.snapshot())
end)

RegisterNetEvent('cm-qa:client:snapshot', function()
    if CmQaClientRunner.registered then TriggerServerEvent('cm-qa:server:clientSnapshot', CmQaClientActions.snapshot()) end
end)

RegisterNUICallback('cmQaClose', function(_, cb)
    closeNuiAndCancel('escape')
    if cb then cb({ ok = true }) end
end)

RegisterNetEvent('cm-qa:client:startScenario', function(payload)
    if not CmQaClientRunner.registered or type(payload) ~= 'table' then return end
    local runId = tostring(payload.runId or '')
    local scenario = tostring(payload.scenario or '')
    if runId == '' or scenario == '' then return end
    ResetCmQaClientState('new_run', true)
    CmQaClientRunner.activeRunId = runId
    CmQaClientRunner.activeScenario = scenario
    local generation = CmQaClientRunner.generation
    if IsPauseMenuActive() then
        SetFrontendActive(false)
        Wait(100)
    end
    local ownerPhysical = scenario == 'electrician.panel.physical-repair'
        or scenario == 'electrician.panel.early-release'
        or scenario == 'electrician.panel.shock'
    if ownerPhysical then
        -- Enter the normal electrician shift through its existing public
        -- client event. The server-side owner contract supplies the target
        -- only after that real shift-start path succeeds.
        CreateThread(function()
            Wait(250)
            if CmQaClientRunner.activeRunId == runId and CmQaClientRunner.generation == generation then
                TriggerServerEvent('cm-electrician:server:setEmployed', false)
                SetEntityCoords(PlayerPedId(), 718.720886, 152.386810, 80.739258, false, false, false, false)
                Wait(500)
                TriggerServerEvent('cm-electrician:server:setEmployed', true)
            end
        end)
    else
        local promptOk = pcall(function()
            exports['cm-ui']:ShowInteract({ owner = QA_PROMPT_OWNER, key = 'E', label = 'QA TEST', name = 'CM-QA' })
        end)
        if not promptOk then
            clientEvent('client_blocked', { reason = 'cm-ui_prompt_export_unavailable' })
            ResetCmQaClientState('prompt_unavailable', true)
            return
        end
        clientEvent('scenario_ready', {
            phase = 'ACTIVE',
            expectedInput = scenario == 'qa.client.hold-smoke' and 'E_HOLD' or 'E_PRESS',
        })
    end
    CreateThread(function()
        local pressedAt = nil
        while CmQaClientRunner.registered and CmQaClientRunner.activeRunId == runId and CmQaClientRunner.generation == generation do
            Wait(0)
            if IsControlJustReleased(0, 322) or IsDisabledControlJustReleased(0, 322) or IsPauseMenuActive() then
                closeNuiAndCancel('escape')
                break
            end
            if IsControlJustPressed(0, 38) and (not ownerPhysical or CmQaClientRunner.ownerReady) then
                pressedAt = GetGameTimer()
                CmQaClientRunner.inputState = 'pressed'
                clientEvent((scenario == 'qa.client.hold-smoke' or ownerPhysical) and 'hold_start' or 'input_press', { startedAt = pressedAt })
            end
            if (scenario == 'qa.client.hold-smoke' or ownerPhysical) and pressedAt and IsControlJustReleased(0, 38) then
                local duration = GetGameTimer() - pressedAt
                CmQaClientRunner.holdState = { durationMs = duration }
                clientEvent('hold_release', { startedAt = pressedAt, endedAt = GetGameTimer(), durationMs = duration })
                pressedAt = nil
            end
        end
    end)
end)

RegisterNetEvent('cm-qa:client:electricianSetup', function(payload)
    if type(payload) ~= 'table' or payload.runId ~= CmQaClientRunner.activeRunId then return end
    local target = payload.target
    if type(target) ~= 'table' then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, tonumber(target.x) or 0.0, tonumber(target.y) or 0.0, tonumber(target.z) or 0.0, false, false, false, false)
    CreateThread(function()
        local deadline = GetGameTimer() + 5000
        while CmQaClientRunner.activeRunId == payload.runId and GetGameTimer() <= deadline do
            local callOk, contractOk, snapshot = pcall(function()
                return exports['cm-electrician']:QaInteractionSnapshot()
            end)
            if callOk and contractOk == true and type(snapshot) == 'table'
                and snapshot.visible == true
                and snapshot.owner == 'cm-electrician:panel'
                and snapshot.action == 'HOLD TO REPAIR'
            then
                CmQaClientRunner.ownerReady = true
                clientEvent('scenario_ready', {
                    phase = 'ACTIVE',
                    expectedInput = 'E_HOLD',
                    interactionOwner = snapshot.owner,
                    interactionAction = snapshot.action,
                })
                return
            end
            Wait(100)
        end
        if CmQaClientRunner.activeRunId == payload.runId then
            clientEvent('client_blocked', { reason = 'owner_interaction_not_ready' })
            ResetCmQaClientState('owner_interaction_not_ready', true)
        end
    end)
end)

RegisterNetEvent('cm-qa:client:stopScenario', function(payload)
    if type(payload) ~= 'table' or payload.runId == CmQaClientRunner.activeRunId then
        ResetCmQaClientState((payload and payload.reason) or 'server_cleanup', false)
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        CmQaClientRunner.registered = false
        CmQaClientRunner.registeredCharacterId = nil
        ResetCmQaClientState('resource_start', false)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then ResetCmQaClientState('resource_stop', false) end
end)

CreateThread(function()
    while true do
        Wait(1500)
        if CmQaClientRunner.registered then
            local snapshot = CmQaClientActions.snapshot()
            local currentCharacterId = tonumber(snapshot.characterId)
            if not currentCharacterId or currentCharacterId ~= CmQaClientRunner.registeredCharacterId then
                TriggerServerEvent('cm-qa:server:characterChanged')
                CmQaClientRunner.registered = false
                CmQaClientRunner.registeredCharacterId = nil
                ResetCmQaClientState('character_changed', false)
            elseif not CmQaClientRunner.activeRunId then
                TriggerServerEvent('cm-qa:server:clientSnapshot', snapshot)
            end
        end
    end
end)
