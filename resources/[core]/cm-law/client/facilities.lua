local facilities, peds = {}, {}
local refreshing = false
local promptKey, dialogueOpen, dialoguePed, dialogueCam, dialogueAction, dialogueServiceFacility
local HUD_REASON = 'cm-law:facility-dialogue'

local function notify(message, kind)
    TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'info')
end

local function drawNpcName(location, name)
    SetDrawOrigin(tonumber(location.x) or 0.0, tonumber(location.y) or 0.0,
        (tonumber(location.z) or 0.0) + 1.15, 0)
    SetTextFont(4); SetTextScale(0.0, 0.31); SetTextCentre(true); SetTextOutline()
    SetTextColour(255, 255, 255, 245)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(tostring(name or 'Organization Officer'))
    EndTextCommandDisplayText(0.0, 0.0); ClearDrawOrigin()
end

local function hidePrompt()
    if promptKey then SendNUIMessage({ action = 'facilityPrompt', visible = false }); promptKey = nil end
end

local function clearPeds()
    hidePrompt()
    for _, ped in pairs(peds) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    peds = {}
end

local function spawnAll()
    clearPeds()
    for index, facility in ipairs(facilities) do
        local location = facility.location
        local model = GetHashKey(facility.model or 's_m_y_cop_01')
        RequestModel(model)
        local deadline = GetGameTimer() + 4000
        while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(25) end
        if not HasModelLoaded(model) then
            model = GetHashKey('s_m_y_cop_01'); RequestModel(model)
            local fallbackDeadline = GetGameTimer() + 3000
            while not HasModelLoaded(model) and GetGameTimer() < fallbackDeadline do Wait(25) end
        end
        if HasModelLoaded(model) then
            local ped = CreatePed(4, model, location.x, location.y, location.z - 1.0,
                location.heading or 0.0, false, false)
            SetEntityInvincible(ped, true); FreezeEntityPosition(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            peds[index] = ped
            SetModelAsNoLongerNeeded(model)
        end
    end
end

local function refreshFacilities()
    if refreshing then return end
    refreshing = true
    facilities = lib.callback.await('cm-law:server:facilities', false) or {}
    spawnAll()
    refreshing = false
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
    local nextCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(nextCamera, position.x, position.y, position.z)
    PointCamAtCoord(nextCamera, target.x, target.y, target.z)
    SetCamFov(nextCamera, kind == 'wide' and 52.0 or kind == 'shoulder' and 42.0 or 38.0)
    if dialogueCam and DoesCamExist(dialogueCam) then
        SetCamActiveWithInterp(nextCamera, dialogueCam, 600, true, true)
        local old = dialogueCam
        SetTimeout(700, function() if DoesCamExist(old) then DestroyCam(old, false) end end)
    else
        SetCamActive(nextCamera, true); RenderScriptCams(true, true, 450, true, true)
    end
    dialogueCam = nextCamera
end

local function closeDialogue()
    if not dialogueOpen then return end
    dialogueOpen = false
    if dialogueCam and DoesCamExist(dialogueCam) then
        RenderScriptCams(false, true, 350, true, true); DestroyCam(dialogueCam, false)
    end
    dialogueCam, dialoguePed, dialogueAction, dialogueServiceFacility = nil, nil, nil, nil
    FreezeEntityPosition(PlayerPedId(), false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'facilityDialogue', visible = false })
    TriggerEvent('cm-hud:client:showAfterUi', HUD_REASON)
end

local function openDialogue(ped, facility, allowed, refusal)
    if dialogueOpen or not DoesEntityExist(ped) then return end
    hidePrompt(); dialogueOpen, dialoguePed = true, ped
    dialogueAction = allowed and facility or nil
    local forward = GetEntityForwardVector(ped)
    local player, pedCoords = PlayerPedId(), GetEntityCoords(ped)
    RequestCollisionAtCoord(pedCoords.x + forward.x * 1.9, pedCoords.y + forward.y * 1.9, pedCoords.z)
    SetEntityCoordsNoOffset(player, pedCoords.x + forward.x * 1.9, pedCoords.y + forward.y * 1.9,
        pedCoords.z, false, false, false)
    SetEntityHeading(player, (GetEntityHeading(ped) + 180.0) % 360.0)
    FreezeEntityPosition(player, true)
    dialogueShot('wide')
    SetTimeout(950, function() if dialogueOpen then dialogueShot('close') end end)
    TriggerEvent('cm-hud:client:hideForUi', HUD_REASON)
    SetNuiFocus(true, true)
    local quote = refusal
    if allowed then
        quote = facility.facilityType == 'front_desk' and ('Welcome to %s. How can I help you?'):format(facility.organizationLabel)
            or facility.facilityType == 'intake' and 'Bring the cuffed suspect to this desk. I will process the approved charges and transfer them to the shared jail.'
            or ('I can help you access the %s %s.'):format(facility.shortLabel, facility.label:lower())
    end
    SendNUIMessage({ action = 'facilityDialogue', visible = true, name = facility.name,
        role = facility.role, quote = quote, continueLabel = allowed and (facility.facilityType == 'front_desk'
            and 'Show me public services' or ('Open ' .. facility.label)) or 'Leave' })
end

RegisterNUICallback('facilityDialogueClose', function(_, cb)
    dialogueAction = nil; closeDialogue(); cb({ ok = true })
end)

RegisterNUICallback('facilityDialogueContinue', function(_, cb)
    local facility = dialogueAction
    dialogueAction = nil; cb({ ok = true })
    if not facility then closeDialogue(); return end
    CreateThread(function()
        local keepCinematic = facility.facilityType == 'front_desk' or facility.facilityType == 'intake'
        if not keepCinematic then closeDialogue() else dialogueShot('close') end
        local result = lib.callback.await('cm-law:server:useFacility', false,
            facility.organizationId, facility.facilityType)
        if keepCinematic and result and result.ok == true and result.action == 'frontdesk' then
            dialogueServiceFacility = facility
            SendNUIMessage({ action = 'facilityDialogueChoices', message = 'How can I help you today?', choices = {
                { id = 'assistance', label = 'Request assistance', description = 'Notify all on-duty legal units that you need help here.', primary = true },
                { id = 'surrender', label = 'Voluntary surrender', description = 'Turn yourself in for your active wanted level.' },
                { id = 'weapons', label = 'Surrender illegal items', description = 'Hand over unlicensed weapons, ammunition, and illegal items.' },
            } })
            return
        end
        if keepCinematic then
            local ok = result and result.ok == true
            SendNUIMessage({ action = 'facilityDialogueResponse',
                message = ok and (result.message or 'Your request has been accepted.')
                    or (result and result.error or 'Service unavailable.'), tone = ok and 'success' or 'error' })
            Wait(tonumber(Config.CinematicResponseDuration) or 2200)
            closeDialogue()
            return
        end
        if not result or result.ok ~= true then return notify(result and result.error or 'Service unavailable.', 'error') end
        if result.action == 'wardrobe' then
            TriggerEvent('cm-law:client:openWardrobe', result.organizationId, result.label)
        elseif result.action == 'armory' then
            TriggerEvent('cm-law:client:openArmory', result.organizationId, result.label)
        elseif result.action == 'fleet' then
            OpenLawMenu('fleet')
        elseif result.action == 'impound' then
            TriggerEvent('cm-law:client:openImpoundRelease')
        elseif result.message then notify(result.message, 'success') end
    end)
end)

local function showFrontDeskChoices(message)
    SendNUIMessage({ action = 'facilityDialogueChoices', message = message or 'How can I help you today?', choices = {
        { id = 'assistance', label = 'Request assistance', description = 'Notify all on-duty legal units that you need help here.', primary = true },
        { id = 'surrender', label = 'Voluntary surrender', description = 'Turn yourself in for your active wanted level.' },
        { id = 'weapons', label = 'Surrender illegal items', description = 'Hand over unlicensed weapons, ammunition, and illegal items.' },
    } })
end

RegisterNUICallback('facilityPublicService', function(data, cb)
    local facility, supplied = dialogueServiceFacility, tostring(data and data.service or '')
    cb({ ok = true })
    if not dialogueOpen or not facility then return end
    if supplied == 'back' then showFrontDeskChoices(); return end
    local service, token = supplied:match('^([^:]+):(.+)$')
    service = service or supplied
    CreateThread(function()
        local result = lib.callback.await('cm-law:server:frontDeskService', false, facility.organizationId, service, token)
        if result and result.confirmation then
            SendNUIMessage({ action = 'facilityDialogueChoices', message = result.message, choices = {
                { id = result.confirmAction .. ':' .. result.token, label = 'Confirm', primary = true },
                { id = 'back', label = 'Go back' },
            } })
            return
        end
        local ok = result and result.ok == true
        SendNUIMessage({ action = 'facilityDialogueResponse', message = ok and (result.message or 'Your request has been accepted.')
            or (result and result.error or 'Service unavailable.'), tone = ok and 'success' or 'error' })
        Wait(tonumber(Config.CinematicResponseDuration) or 2200)
        closeDialogue()
    end)
end)

RegisterNetEvent('cm-law:client:facilitiesChanged', function()
    CreateThread(function()
        Wait(150)
        refreshFacilities()
    end)
end)

CreateThread(function()
    Wait(1200); refreshFacilities()
    while true do
        local wait, nearest, nearestIndex, nearestDistance = 900, nil, nil, 99999.0
        local playerPed = PlayerPedId()
        if not dialogueOpen and not CmLawMenuOpen() and not IsNuiFocused()
            and not IsPauseMenuActive() and not IsPedInAnyVehicle(playerPed, false) then
            local coords = GetEntityCoords(playerPed)
            for index, facility in ipairs(facilities) do
                local location = facility.location
                local distance = #(coords - vector3(location.x, location.y, location.z))
                if distance < nearestDistance then nearest, nearestIndex, nearestDistance = facility, index, distance end
            end
            if nearest and nearestDistance <= (Config.FacilityDrawDistance or 18.0) then
                wait = 0
                drawNpcName(nearest.location, nearest.name)
                if nearestDistance <= (Config.FacilityInteractDistance or 2.5) then
                    local key = nearest.organizationId .. ':' .. nearest.facilityType
                    if promptKey ~= key then
                        promptKey = key
                        SendNUIMessage({ action = 'facilityPrompt', visible = true,
                            name = nearest.name, role = nearest.organizationLabel .. ' · ' .. nearest.label })
                    end
                    if IsControlJustPressed(0, 38) then
                        local allowed, reason = lib.callback.await('cm-law:server:facilityAccess', false,
                            nearest.organizationId, nearest.facilityType)
                        openDialogue(peds[nearestIndex], nearest, allowed == true, reason)
                        Wait(400)
                    end
                else hidePrompt() end
            else hidePrompt() end
        else hidePrompt() end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closeDialogue(); clearPeds()
end)
