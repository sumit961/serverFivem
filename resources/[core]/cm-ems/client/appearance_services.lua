local servicePeds = {}
local promptService = nil
local editorOpen = false
local dialogueService = nil
local dialogueCamera = nil
local greetingState = {}
local HUD_HIDE_REASON = 'cm-ems:npc-dialogue'

local function setDialogueHudHidden(hidden)
    if GetResourceState('cm-hud') ~= 'started' then return end
    if hidden then
        TriggerEvent('cm-hud:client:hideForUi', HUD_HIDE_REASON)
    else
        TriggerEvent('cm-hud:client:showAfterUi', HUD_HIDE_REASON)
    end
end

local function hidePrompt()
    if not promptService then return end
    promptService = nil
    if lib and lib.hideTextUI then lib.hideTextUI() end
end

local function loadModel(modelName)
    local model = joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelValid(model) then return nil end
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(50) end
    return HasModelLoaded(model) and model or nil
end

local function spawnServicePed(service)
    local model = loadModel(service.model)
    if not model then
        print(('[cm-ems] Invalid appearance service NPC model for %s'):format(tostring(service.id)))
        return
    end

    local c = service.coords
    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, false)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    servicePeds[service.id] = ped
    SetModelAsNoLongerNeeded(model)
end

local function drawDoctorName(service, ped)
    if not DoesEntityExist(ped) then return end
    -- Use the configured world position instead of an animated head bone so
    -- the label stays fixed while the doctor waves or changes scenarios.
    SetDrawOrigin(service.coords.x, service.coords.y, service.coords.z + 1.15, 0)
    SetTextFont(4)
    SetTextScale(0.0, 0.31)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 245)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(service.name)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function greetPlayer(service, ped)
    local state = greetingState[service.id] or {}
    local now = GetGameTimer()
    if state.playing or (state.lastAt and now - state.lastAt < 30000) then return end
    state.playing = true
    state.lastAt = now
    greetingState[service.id] = state

    CreateThread(function()
        local dict = 'anim@mp_player_intcelebrationmale@wave'
        RequestAnimDict(dict)
        local deadline = GetGameTimer() + 3000
        while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(20) end
        if DoesEntityExist(ped) then
            ClearPedTasks(ped)
            PlayAmbientSpeech1(ped, 'GENERIC_HI', 'SPEECH_PARAMS_FORCE')
            if HasAnimDictLoaded(dict) then
                TaskPlayAnim(ped, dict, 'wave', 8.0, -4.0, 2200, 49, 0.0, false, false, false)
            end
        end
        Wait(2400)
        if DoesEntityExist(ped) and not editorOpen then
            ClearPedTasks(ped)
            TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
        end
        state.playing = false
    end)
end

local function closeDialogue()
    dialogueService = nil
    editorOpen = false
    if dialogueCamera and DoesCamExist(dialogueCamera) then
        RenderScriptCams(false, true, 350, true, true)
        DestroyCam(dialogueCamera, false)
    end
    dialogueCamera = nil
    FreezeEntityPosition(PlayerPedId(), false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'npcDialogue:close' })
    setDialogueHudHidden(false)
end

local function openDialogue(service, ped)
    if not DoesEntityExist(ped) then return end
    editorOpen = true
    dialogueService = service
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.08)
    local forward = GetEntityForwardVector(ped)
    local player = PlayerPedId()
    local stageX = service.coords.x + forward.x * 1.9
    local stageY = service.coords.y + forward.y * 1.9
    RequestCollisionAtCoord(stageX, stageY, service.coords.z)
    SetEntityCoordsNoOffset(player, stageX, stageY, service.coords.z, false, false, false)
    SetEntityHeading(player, (GetEntityHeading(ped) + 180.0) % 360.0)
    FreezeEntityPosition(player, true)
    local cameraX = head.x + forward.x * 1.05
    local cameraY = head.y + forward.y * 1.05
    local cameraZ = head.z + 0.08
    local probe = StartExpensiveSynchronousShapeTestLosProbe(
        head.x, head.y, head.z, cameraX, cameraY, cameraZ, 1, ped, 7)
    local _, hit, hitCoords = GetShapeTestResult(probe)
    if hit == 1 and hitCoords then
        cameraX = hitCoords.x + (head.x - hitCoords.x) * 0.15
        cameraY = hitCoords.y + (head.y - hitCoords.y) * 0.15
        cameraZ = hitCoords.z + (head.z - hitCoords.z) * 0.15
    end
    dialogueCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(dialogueCamera, cameraX, cameraY, cameraZ)
    PointCamAtCoord(dialogueCamera, head.x, head.y, head.z)
    SetCamFov(dialogueCamera, 38.0)
    SetCamActive(dialogueCamera, true)
    RenderScriptCams(true, true, 450, true, true)
    setDialogueHudHidden(true)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'npcDialogue:open',
        name = service.name,
        role = service.label,
        quote = 'Welcome. I can help update your professional appearance and make sure you are ready for duty.',
        continueLabel = 'I would like to update my appearance',
    })
end

RegisterNUICallback('npcDialogueClose', function(_, cb)
    closeDialogue()
    cb({ ok = true })
end)

RegisterNUICallback('npcDialogueContinue', function(_, cb)
    local service = dialogueService
    closeDialogue()
    if service then
        editorOpen = true
        TriggerEvent('cm-characters:client:openAppearanceService', {
            service = service.service,
            provider = service.name,
        })
    end
    cb({ ok = service ~= nil })
end)

CreateThread(function()
    for _, service in ipairs(Config.AppearanceServices or {}) do
        spawnServicePed(service)
    end

    while true do
        local wait = 1000
        local nearest, nearestDistance

        if not editorOpen and not IsPauseMenuActive() then
            local playerCoords = GetEntityCoords(PlayerPedId())
            for _, service in ipairs(Config.AppearanceServices or {}) do
                local distance = #(playerCoords - vector3(service.coords.x, service.coords.y, service.coords.z))
                if distance <= 12.0 then
                    wait = 0
                    local servicePed = servicePeds[service.id]
                    drawDoctorName(service, servicePed)
                    local state = greetingState[service.id] or {}
                    if distance <= 5.0 and not state.inside then
                        state.inside = true
                        greetingState[service.id] = state
                        greetPlayer(service, servicePed)
                    elseif distance > 7.0 then
                        state.inside = false
                        greetingState[service.id] = state
                    end
                    if not nearestDistance or distance < nearestDistance then
                        nearest, nearestDistance = service, distance
                    end
                else
                    local state = greetingState[service.id]
                    if state then state.inside = false end
                end
            end
        end

        if nearest and nearestDistance <= 2.0 then
            if promptService ~= nearest.id then
                hidePrompt()
                promptService = nearest.id
                lib.showTextUI(('[E] %s - %s'):format(nearest.name, nearest.label), {
                    position = 'left-center',
                    icon = 'user-doctor',
                })
            end

            if IsControlJustReleased(0, 38) then
                hidePrompt()
                openDialogue(nearest, servicePeds[nearest.id])
            end
        else
            hidePrompt()
        end

        Wait(wait)
    end
end)

RegisterNetEvent('cm-ems:client:appearanceServiceClosed', function()
    editorOpen = false
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    hidePrompt()
    closeDialogue()
    for _, ped in pairs(servicePeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
end)
