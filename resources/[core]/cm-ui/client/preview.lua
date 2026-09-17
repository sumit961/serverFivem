-- In-game live preview of the shared cm-ui components. Spawns a throwaway
-- demo ped in front of the player, shows the interact prompt, then opens the
-- cinematic dialogue with two sample choices wired to a local event so you
-- can see the full open -> choose -> respond -> close flow.
--
-- Run: /cmuipreview
--
-- For a preview with no FiveM at all, open web/preview.html directly in a
-- browser (see docs/CM_UI_USAGE.md).

local previewPed

local function spawnPreviewPed()
    local playerPed = PlayerPedId()
    local forward = GetEntityForwardVector(playerPed)
    local pos = GetEntityCoords(playerPed) + forward * 2.5
    local model = GetHashKey('a_m_m_business_01')

    RequestModel(model)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(model) then return nil end

    local ped = CreatePed(4, model, pos.x, pos.y, pos.z - 1.0, (GetEntityHeading(playerPed) + 180.0) % 360.0, false, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetModelAsNoLongerNeeded(model)
    return ped
end

local function despawnPreviewPed()
    if previewPed and DoesEntityExist(previewPed) then
        DeleteEntity(previewPed)
    end
    previewPed = nil
end

RegisterCommand('cmuipreview', function()
    if exports['cm-ui']:IsNpcDialogueOpen() then return end
    despawnPreviewPed()

    exports['cm-ui']:ShowInteract({ key = 'E', label = 'PREVIEW', name = 'CM UI Preview', role = 'Demo NPC' })
    previewPed = spawnPreviewPed()

    SetTimeout(300, function()
        exports['cm-ui']:HideInteract()
        exports['cm-ui']:OpenNpcDialogue(previewPed or PlayerPedId(), {
            name = 'CM UI Preview',
            role = 'Demo NPC',
            quote = 'This is the shared cm-ui interaction + cinematic dialogue component. Any resource can call it instead of building its own.',
            continueLabel = 'See sample choices',
            deferChoices = true,
            serviceLabel = 'Pick a sample choice to see a response.',
            choices = {
                { id = 'ok', label = 'Looks good', description = 'Fires a success response', event = 'cm-ui:preview:choice', payload = { kind = 'ok' } },
                { id = 'bad', label = 'Something is off', description = 'Fires an error response', event = 'cm-ui:preview:choice', payload = { kind = 'bad' } },
            },
        })
    end)
end, false)

AddEventHandler('cm-ui:preview:choice', function(payload)
    payload = type(payload) == 'table' and payload or {}
    if payload.kind == 'ok' then
        exports['cm-ui']:NpcDialogueRespond('Great — the shared dialogue component is working.', 'success', 2200)
    else
        exports['cm-ui']:NpcDialogueRespond('Noted. Check cm-ui/docs/CM_UI_USAGE.md for the full API.', 'error', 2200)
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if previewPed and not exports['cm-ui']:IsNpcDialogueOpen() then
            despawnPreviewPed()
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then despawnPreviewPed() end
end)
