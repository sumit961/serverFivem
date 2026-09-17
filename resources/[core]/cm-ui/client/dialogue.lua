-- Shared cinematic NPC dialogue: faces the player toward a ped, racks a
-- scripted camera through it, and drives the cm-dialogue NUI overlay.
-- Ported from cm-police's client/npc_dialogue.lua + client/cinematics.lua
-- (dialogueShot camera logic) and generalized so any resource can open it.
--
-- Choices carry an `event` name instead of a Lua function/closure: exported
-- functions execute in cm-ui's own environment, and Lua closures don't
-- marshal across resources, so the caller's own client listens for the
-- event it named (same convention cm-playerdata uses for its G-menu
-- extension options -- see cm-playerdata/client/interactions.lua).
--
-- exports['cm-ui']:OpenNpcDialogue(ped, {
--     name = 'Officer Reyes', role = 'CM POLICE',
--     quote = 'How can I help you today?',
--     continueLabel = 'See services', deferChoices = true,
--     serviceLabel = 'Please choose the service you need.',
--     choices = {
--         { id = 'report', label = 'File a report', description = '...',
--           event = 'my-resource:client:dialogueChoice', payload = { kind = 'report' } },
--     },
--     -- continueEvent / continuePayload fire instead when there are no
--     -- choices and the player just presses "Continue".
--     continueEvent = 'my-resource:client:dialogueContinue',
--     -- Fired only when the player dismisses via "I'm not interested right
--     -- now" (not on a choice/continue path -- those have their own events).
--     -- Use it to restore whatever state you changed before opening (HUD, etc).
--     closeEvent = 'my-resource:client:dialogueDismissed',
-- })
--
-- exports['cm-ui']:NpcDialogueRespond('Report filed.', 'success', 2200)
-- exports['cm-ui']:NpcDialogueRestoreChoices()
-- exports['cm-ui']:CancelNpcDialogue()
-- exports['cm-ui']:IsNpcDialogueOpen()

local dialoguePed
local dialogueCamera
local dialogueOpen = false
local dialogueOptions = {}
local dialogueWasFrozen = false

local function resolveCameraPosition(ignoreEntity, focus, position)
    local ray = StartShapeTestRay(focus.x, focus.y, focus.z, position.x, position.y, position.z, 17, ignoreEntity or 0, 7)
    local _, hit, hitCoords = GetShapeTestResult(ray)
    if hit ~= 1 then return position end
    local direction, length = focus - hitCoords, #(focus - hitCoords)
    return length > 0.01 and hitCoords + direction / length * 0.28 or position
end

local function dialogueShot(kind)
    if not dialogueOpen or not dialoguePed or not DoesEntityExist(dialoguePed) then return end
    local ped, player = dialoguePed, PlayerPedId()
    local position, target

    if kind == 'wide' then
        position = GetOffsetFromEntityInWorldCoords(ped, 2.4, 3.5, 1.45)
        target = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.65)
    elseif kind == 'shoulder' then
        position = GetOffsetFromEntityInWorldCoords(player, 0.65, -0.7, 0.72)
        target = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.02)
    else
        local head, forward = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.08), GetEntityForwardVector(ped)
        position = vector3(head.x + forward.x * 1.05, head.y + forward.y * 1.05, head.z + 0.08)
        target = head
    end

    position = resolveCameraPosition(ped, target, position)
    local nextCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(nextCamera, position.x, position.y, position.z)
    PointCamAtCoord(nextCamera, target.x, target.y, target.z)
    SetCamFov(nextCamera, kind == 'wide' and 52.0 or kind == 'shoulder' and 42.0 or 38.0)

    if dialogueCamera and DoesCamExist(dialogueCamera) then
        SetCamActiveWithInterp(nextCamera, dialogueCamera, 600, true, true)
        local old = dialogueCamera
        SetTimeout(700, function() if DoesCamExist(old) then DestroyCam(old, false) end end)
    else
        SetCamActive(nextCamera, true)
        RenderScriptCams(true, true, 450, true, true)
    end
    dialogueCamera = nextCamera
end

local function closeDialogue(runContinue)
    if not dialogueOpen then return end
    dialogueOpen = false

    if dialogueCamera and DoesCamExist(dialogueCamera) then
        RenderScriptCams(false, true, 350, true, true)
        DestroyCam(dialogueCamera, false)
    end
    dialogueCamera, dialoguePed = nil, nil
    FreezeEntityPosition(PlayerPedId(), dialogueWasFrozen == true)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'cmDialogue:close' })

    local options = dialogueOptions
    dialogueOptions = {}
    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:SetHudVisible(true) end)
        pcall(function() exports['cm-hud']:SetUiVisible(true, 'cm-dialogue') end)
    end
    DisplayRadar(true)
    if runContinue and options.continueEvent then
        SetTimeout(100, function() TriggerEvent(options.continueEvent, options.continuePayload) end)
    end
end

local function findChoice(choiceId)
    for _, choice in ipairs(dialogueOptions.choices or {}) do
        if tostring(choice.id) == tostring(choiceId) then return choice end
    end
    return nil
end

function OpenNpcDialogue(ped, options)
    if dialogueOpen or not ped or not DoesEntityExist(ped) then return false end
    options = type(options) == 'table' and options or {}
    dialogueOpen, dialoguePed, dialogueOptions = true, ped, options

    -- Never move the player's position (no teleport) -- only turn them to
    -- face the ped, from wherever they were already standing when they
    -- pressed the interact key.
    local player = PlayerPedId()
    if options.faceOff ~= false then
        SetEntityHeading(player, (GetEntityHeading(ped) + 180.0) % 360.0)
    end
    local ok, frozen = pcall(IsEntityPositionFrozen, player)
    dialogueWasFrozen = ok and frozen == true
    FreezeEntityPosition(player, true)

    dialogueShot('wide')
    SetTimeout(950, function() if dialogueOpen then dialogueShot('close') end end)

    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:SetHudVisible(false) end)
        pcall(function() exports['cm-hud']:SetUiVisible(false, 'cm-dialogue') end)
    end
    DisplayRadar(false)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'cmDialogue:open',
        name = options.name,
        role = options.role,
        quote = options.quote or 'How can I help you?',
        continueLabel = options.continueLabel or 'Continue',
        serviceLabel = options.serviceLabel,
        choices = type(options.choices) == 'table' and options.choices or nil,
        deferChoices = options.deferChoices == true,
    })
    return true
end

function NpcDialogueRespond(message, tone, closeDelay)
    if not dialogueOpen then return false end
    dialogueShot('close')
    SendNUIMessage({ action = 'cmDialogue:response', message = tostring(message or ''), tone = tostring(tone or 'inform') })
    if tonumber(closeDelay) and tonumber(closeDelay) > 0 then
        Wait(tonumber(closeDelay))
        closeDialogue(false)
    end
    return true
end

function NpcDialogueRestoreChoices(quote)
    if not dialogueOpen then return false end
    dialogueShot('shoulder')
    SendNUIMessage({ action = 'cmDialogue:restoreChoices', quote = quote })
    return true
end

function CancelNpcDialogue()
    closeDialogue(false)
end

function IsNpcDialogueOpen()
    return dialogueOpen == true
end

exports('OpenNpcDialogue', OpenNpcDialogue)
exports('NpcDialogueRespond', NpcDialogueRespond)
exports('NpcDialogueRestoreChoices', NpcDialogueRestoreChoices)
exports('CancelNpcDialogue', CancelNpcDialogue)
exports('IsNpcDialogueOpen', IsNpcDialogueOpen)

RegisterNUICallback('cmDialogueClose', function(_, cb)
    -- Only the explicit "not interested" dismissal fires closeEvent -- the
    -- continue/choice paths already have their own event hooks (continueEvent
    -- / choice.event) for the caller to run its own follow-up + cleanup.
    local closeEvent, closePayload = dialogueOptions.closeEvent, dialogueOptions.closePayload
    closeDialogue(false)
    if closeEvent then TriggerEvent(closeEvent, closePayload) end
    cb({ ok = true })
end)

RegisterNUICallback('cmDialogueContinue', function(_, cb)
    closeDialogue(true)
    cb({ ok = true })
end)

RegisterNUICallback('cmDialogueStage', function(data, cb)
    if dialogueOpen then dialogueShot(data.stage == 'services' and 'shoulder' or 'close') end
    cb({ ok = true })
end)

RegisterNUICallback('cmDialogueChoice', function(data, cb)
    if not dialogueOpen then return cb({ ok = false }) end
    local choice = findChoice(data.choice)
    if not choice then return cb({ ok = false }) end

    dialogueShot('close')
    if choice.event then TriggerEvent(choice.event, choice.payload) end

    if choice.close ~= false then
        closeDialogue(false)
    else
        SetNuiFocus(true, true)
    end
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and dialogueOpen then closeDialogue(false) end
end)
