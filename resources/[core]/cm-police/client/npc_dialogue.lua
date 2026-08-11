local dialoguePed
local dialogueCamera
local dialogueContinue
local dialogueChoices = {}
local dialogueOpen = false
local HUD_HIDE_REASON = 'cm-police:npc-dialogue'

local function dialogueShot(kind)
    if not dialogueOpen or not dialoguePed or not DoesEntityExist(dialoguePed) then return end
    local ped, player = dialoguePed, PlayerPedId()
    local position, target
    if kind == 'wide' then
        position = GetOffsetFromEntityInWorldCoords(ped, 2.4, 3.5, 1.45); target = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.65)
    elseif kind == 'shoulder' then
        position = GetOffsetFromEntityInWorldCoords(player, 0.65, -0.7, 0.72); target = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.02)
    else
        local head, forward = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.08), GetEntityForwardVector(ped)
        position = vector3(head.x + forward.x * 1.05, head.y + forward.y * 1.05, head.z + 0.08); target = head
    end
    if type(PoliceResolveCinematicCameraPosition) == 'function' then position = PoliceResolveCinematicCameraPosition(ped, target, position) end
    local nextCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(nextCamera, position.x, position.y, position.z); PointCamAtCoord(nextCamera, target.x, target.y, target.z)
    local desiredFov = kind == 'wide' and 52.0 or kind == 'shoulder' and 42.0 or 38.0
    SetCamFov(nextCamera, type(PoliceCinematicCameraFov) == 'function' and PoliceCinematicCameraFov(desiredFov) or desiredFov)
    if dialogueCamera and DoesCamExist(dialogueCamera) then
        SetCamActiveWithInterp(nextCamera, dialogueCamera, 600, true, true)
        local old = dialogueCamera; SetTimeout(700, function() if DoesCamExist(old) then DestroyCam(old, false) end end)
    else SetCamActive(nextCamera, true); RenderScriptCams(true, true, 450, true, true) end
    dialogueCamera = nextCamera
end

local function setDialogueHudHidden(hidden)
    if GetResourceState('cm-hud') ~= 'started' then return end
    if hidden then
        TriggerEvent('cm-hud:client:hideForUi', HUD_HIDE_REASON)
    else
        TriggerEvent('cm-hud:client:showAfterUi', HUD_HIDE_REASON)
    end
end

local function closeDialogue(runContinue)
    if not dialogueOpen then return end
    dialogueOpen = false
    if dialogueCamera and DoesCamExist(dialogueCamera) then
        RenderScriptCams(false, true, 350, true, true)
        DestroyCam(dialogueCamera, false)
    end
    dialogueCamera, dialoguePed = nil, nil
    FreezeEntityPosition(PlayerPedId(), false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'npcDialogue:close' })
    PoliceSuppressNpcInteraction(false)
    setDialogueHudHidden(false)
    local continuation = dialogueContinue
    dialogueContinue = nil
    dialogueChoices = {}
    if runContinue and continuation then SetTimeout(100, continuation) end
end

function PoliceOpenNpcDialogue(ped, options, continuation)
    if dialogueOpen or not ped or not DoesEntityExist(ped) then return false end
    options = type(options) == 'table' and options or {}
    dialogueOpen, dialoguePed, dialogueContinue = true, ped, type(continuation) == 'function' and continuation or nil
    dialogueChoices = type(continuation) == 'table' and continuation or {}
    local forward = GetEntityForwardVector(ped)
    local player = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local stageX, stageY = pedCoords.x + forward.x * 1.9, pedCoords.y + forward.y * 1.9
    RequestCollisionAtCoord(stageX, stageY, pedCoords.z)
    SetEntityCoordsNoOffset(player, stageX, stageY, pedCoords.z, false, false, false)
    SetEntityHeading(player, (GetEntityHeading(ped) + 180.0) % 360.0)
    FreezeEntityPosition(player, true)
    dialogueShot('wide')
    SetTimeout(950, function() if dialogueOpen then dialogueShot('close') end end)
    PoliceSuppressNpcInteraction(true)
    setDialogueHudHidden(true)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'npcDialogue:open', name = options.name, role = options.role,
        quote = options.quote or 'How can I help you?', continueLabel = options.continueLabel or 'Continue',
        choices = type(options.choices) == 'table' and options.choices or nil,
        deferChoices = options.deferChoices == true })
    return true
end

function PoliceOpenRestrictedNpcDialogue(ped, options, npcType, continuation)
    local allowed, reason = lib.callback.await('cm-police:server:restrictedNpcAccess', false, npcType)
    if allowed == true then return PoliceOpenNpcDialogue(ped, options, continuation) end
    options = type(options) == 'table' and options or {}
    return PoliceOpenNpcDialogue(ped, {
        owner = options.owner or npcType,
        name = options.name,
        role = options.role,
        quote = reason or 'This service is restricted to Police personnel.',
        continueLabel = 'Leave',
    }, nil)
end

function PoliceNpcDialogueRespond(message, tone, closeDelay)
    if not dialogueOpen then return false end
    dialogueShot('close')
    if type(PoliceCinematicSound) == 'function' then PoliceCinematicSound(tone == 'error' and 'door' or 'confirm', dialoguePed) end
    SendNUIMessage({ action = 'npcDialogue:response', message = tostring(message or ''), tone = tostring(tone or 'inform') })
    if tonumber(closeDelay) and tonumber(closeDelay) > 0 then
        Wait(tonumber(closeDelay)); closeDialogue(false)
    end
    return true
end

function PoliceNpcDialogueRestoreChoices()
    if dialogueOpen then dialogueShot('shoulder'); SendNUIMessage({ action = 'npcDialogue:restoreChoices' }) end
end

RegisterNUICallback('npcDialogueClose', function(_, cb) closeDialogue(false); cb({ ok = true }) end)
RegisterNUICallback('npcDialogueContinue', function(_, cb) closeDialogue(true); cb({ ok = true }) end)
RegisterNUICallback('npcDialogueStage', function(data, cb) if dialogueOpen then dialogueShot(data.stage == 'services' and 'shoulder' or 'close') end; cb({ ok = true }) end)
RegisterNUICallback('npcDialogueChoice', function(data, cb)
    if not dialogueOpen then return cb({ ok = false }) end
    local handler = dialogueChoices[tostring(data.choice or '')]
    if type(handler) ~= 'function' then return cb({ ok = false }) end
    dialogueShot('close')
    local closeAfter = handler() == true
    if closeAfter then closeDialogue(false) end
    if dialogueOpen then SetNuiFocus(true, true) end
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and dialogueOpen then closeDialogue(false) end
end)
