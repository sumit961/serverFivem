local uiOpen = false
local sessionGeneration = nil
local activeEntity, activeNetId, activeMode = nil, nil, nil
local adoptionCenters = {}
local adoptionNpcs = {}
local nearestCenter
local promptVisible = false
local adoptionDialogueCenterId
local adoptionCenterId, adoptionToken

local function notify(message, kind)
    TriggerEvent('cm-hud:client:notify', tostring(message), kind or 'info')
end

local function hidePrompt()
    if not promptVisible then return end
    promptVisible = false
    pcall(function() exports['cm-ui']:HideInteract('cm-pets-adoption') end)
end

local function closeUi()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    hidePrompt()
end

local function clearLocalPet()
    activeEntity, activeNetId, activeMode = nil, nil, nil
end

local function deleteAdoptionNpc(centerId)
    local ped = adoptionNpcs[centerId]
    adoptionNpcs[centerId] = nil
    if ped and DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end
end

local function clearAdoptionCenters()
    hidePrompt()
    nearestCenter = nil
    adoptionDialogueCenterId = nil
    local ok, open = pcall(function() return exports['cm-ui']:IsNpcDialogueOpen() end)
    if ok and open then pcall(function() exports['cm-ui']:CancelNpcDialogue() end) end
    for centerId in pairs(adoptionNpcs) do deleteAdoptionNpc(centerId) end
end

local function refreshAdoptionCenters()
    local ok, result = pcall(lib.callback.await, 'cm-pets:server:listAdoptionCenters', false)
    clearAdoptionCenters()
    if not ok or type(result) ~= 'table' then
        adoptionCenters = {}
        return
    end
    adoptionCenters = {}
    for _, center in ipairs(result) do
        if type(center) == 'table' and type(center.id) == 'string'
            and Config.ApprovedNpcModels[tostring(center.npcModel or ''):lower()] == true
            and center.enabled == true
            and tonumber(center.x) and tonumber(center.y) and tonumber(center.z) then
            adoptionCenters[center.id] = center
        end
    end
end

local function clientRoutingBucket()
    if type(GetPlayerRoutingBucket) ~= 'function' then return nil end
    local ok, bucket = pcall(GetPlayerRoutingBucket, PlayerId())
    return ok and tonumber(bucket) or nil
end

local function centerVisible(center)
    if center.routingBucket == nil then return true end
    local bucket = clientRoutingBucket()
    return bucket ~= nil and bucket == tonumber(center.routingBucket)
end

local function ensureAdoptionNpc(center)
    if not center or not centerVisible(center) then return nil end
    local existing = adoptionNpcs[center.id]
    if existing and DoesEntityExist(existing) then return existing end
    deleteAdoptionNpc(center.id)

    local modelName = tostring(center.npcModel or ''):lower()
    if not Config.ApprovedNpcModels[modelName] then return nil end
    local model = GetHashKey(modelName)
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return nil end

    local ped = CreatePed(4, model, center.x, center.y, center.z, center.heading or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    if ped == 0 or not DoesEntityExist(ped) then return nil end
    SetEntityAsMissionEntity(ped, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedCanSwitchWeapon(ped, false)
    adoptionNpcs[center.id] = ped
    return ped
end

local function controlEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local deadline = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
    return NetworkHasControlOfEntity(entity)
end

local function applyCosmeticFlags(entity)
    if not controlEntity(entity) then return false end
    SetEntityAsMissionEntity(entity, true, true)
    SetEntityInvincible(entity, true)
    SetBlockingOfNonTemporaryEvents(entity, true)
    SetPedCanRagdoll(entity, false)
    SetPedCanSwitchWeapon(entity, false)
    SetPedCombatAbility(entity, 0)
    SetPedCombatAttributes(entity, 5, false)
    SetPedFleeAttributes(entity, 0, false)
    return true
end

local function applyMode(entity, mode)
    if not applyCosmeticFlags(entity) then return false end
    local playerPed = PlayerPedId()
    ClearPedTasks(entity)
    if mode == 'stay' then
        TaskStandStill(entity, -1)
    else
        TaskFollowToOffsetOfEntity(entity, playerPed, 0.8, -1.2, 0.0, 1.35, -1, 1.5, true)
        mode = 'follow'
    end
    activeEntity, activeMode = entity, mode
    return true
end

local function resolveSummonedPet(netId, model)
    local deadline = GetGameTimer() + 5000
    while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < deadline do Wait(0) end
    if not NetworkDoesNetworkIdExist(netId) then return false end
    local entity = NetToPed(netId)
    if entity == 0 or not DoesEntityExist(entity) or not IsEntityAPed(entity) then return false end
    if GetEntityModel(entity) ~= GetHashKey(tostring(model or '')) then return false end
    if not applyMode(entity, 'follow') then return false end
    activeNetId = netId
    return true
end

local function refreshUi(result, message)
    if type(result) ~= 'table' then return end
    sessionGeneration = tonumber(result.generation) or sessionGeneration
    SendNUIMessage({
        action = 'state', pet = result.pet, active = result.active == true,
        mode = result.mode, message = message,
        adopted = result.adopted, idempotent = result.idempotent,
    })
end

local function openPets(centerId)
    local ok, result = pcall(lib.callback.await, 'cm-pets:server:getOwned', false, centerId)
    if not ok or type(result) ~= 'table' or result.ok ~= true then
        notify('Pets are unavailable at this location.', 'error')
        return
    end
    sessionGeneration = tonumber(result.generation)
    adoptionCenterId = result.center and result.center.id or nil
    adoptionToken = result.adoptionToken
    uiOpen = true
    hidePrompt()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open', pet = result.pet, active = result.active == true,
        mode = result.mode, center = result.center, adoptable = result.adoptable,
    })
end

local function serverAction(action, ...)
    if not sessionGeneration then return { ok = false, message = 'stale_session' } end
    local ok, result = pcall(lib.callback.await, 'cm-pets:server:' .. action, false, sessionGeneration, ...)
    if not ok or type(result) ~= 'table' then return { ok = false, message = 'server_unavailable' } end
    return result
end

local function openAdoptionDialogue(center)
    if not center or uiOpen or not adoptionNpcs[center.id] then return end
    local ped = adoptionNpcs[center.id]
    if not DoesEntityExist(ped) then return end
    adoptionDialogueCenterId = center.id
    pcall(function()
        exports['cm-ui']:OpenNpcDialogue(ped, {
            name = center.displayName,
            role = 'CM PETS ADOPTION',
            quote = 'Choose a cosmetic companion to add to your Character ID.',
            serviceLabel = 'Adoption is free of gameplay effects and does not summon the pet automatically.',
            choices = {
                {
                    id = 'view_pets', label = 'View available pets',
                    description = 'Open the cosmetic adoption list.',
                    event = 'cm-pets:client:adoptionChoice',
                    payload = { centerId = center.id },
                },
            },
            closeEvent = 'cm-pets:client:adoptionDismissed',
        })
    end)
end

RegisterCommand('pets', function() openPets(nil) end, false)

RegisterNetEvent('cm-pets:client:adoptionChoice', function(payload)
    local centerId = type(payload) == 'table' and tostring(payload.centerId or '') or ''
    if centerId == '' or centerId ~= adoptionDialogueCenterId then return end
    SetTimeout(60, function()
        local center = adoptionCenters[centerId]
        adoptionDialogueCenterId = nil
        if center then openPets(centerId) end
    end)
end)

RegisterNetEvent('cm-pets:client:adoptionDismissed', function()
    adoptionDialogueCenterId = nil
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    adoptionCenterId, adoptionToken = nil, nil
    cb({ ok = true })
end)

RegisterNUICallback('action', function(data, cb)
    local action = type(data) == 'table' and tostring(data.action or '') or ''
    local result
    if action == 'summon' then
        result = serverAction('summon')
        if result.ok and not resolveSummonedPet(tonumber(result.netId), result.model) then
            clearLocalPet()
            serverAction('hide')
            result = { ok = false, message = 'entity_control_unavailable' }
        end
    elseif action == 'hide' then
        result = serverAction('hide')
        if result.ok then clearLocalPet() end
    elseif action == 'follow' or action == 'stay' then
        result = serverAction('mode', action)
        if result.ok and activeEntity and not applyMode(activeEntity, action) then
            result = { ok = false, message = 'entity_control_unavailable' }
        end
    elseif action == 'adopt' then
        local typeId = type(data) == 'table' and tostring(data.typeId or '') or ''
        if adoptionCenterId and adoptionToken and typeId ~= '' then
            result = serverAction('adopt', adoptionCenterId, typeId, adoptionToken)
        else
            result = { ok = false, message = 'stale_adoption_session' }
        end
    else
        result = { ok = false, message = 'invalid_action' }
    end
    refreshUi(result, result.ok and (result.adopted and 'Pet adopted. It remains hidden until summoned.' or 'Updated.') or 'Action could not be completed.')
    if not result.ok and result.message ~= 'pet_already_owned' then notify('Pet action could not be completed.', 'error') end
    cb({ ok = result.ok == true })
end)

RegisterNUICallback('rename', function(data, cb)
    local result = serverAction('rename', type(data) == 'table' and data.name or nil)
    refreshUi(result, result.ok and 'Name updated.' or 'Name could not be updated.')
    if not result.ok then notify('Pet name could not be updated.', 'error') end
    cb({ ok = result.ok == true })
end)

RegisterNetEvent('cm-pets:client:applyMode', function(netId, mode)
    if tonumber(netId) ~= tonumber(activeNetId) then return end
    if mode ~= 'follow' and mode ~= 'stay' then return end
    if not activeEntity or not applyMode(activeEntity, mode) then clearLocalPet() end
end)

RegisterNetEvent('cm-pets:client:hidden', function(message)
    clearLocalPet()
    if uiOpen then SendNUIMessage({ action = 'state', active = false, message = message }) end
end)

RegisterNetEvent('cm-pets:client:adoptionCentersUpdated', refreshAdoptionCenters)
RegisterNetEvent('cm-pets:client:notify', notify)

RegisterNetEvent('cm-playerdata:client:characterLoaded', function()
    clearLocalPet()
    refreshAdoptionCenters()
end)

RegisterNetEvent('cm-playerdata:client:characterUnloaded', function()
    clearLocalPet()
    clearAdoptionCenters()
    adoptionCenters = {}
    adoptionCenterId, adoptionToken = nil, nil
    sessionGeneration = nil
    closeUi()
end)

RegisterNetEvent('cm-playerdata:client:unloaded', function()
    clearLocalPet()
    clearAdoptionCenters()
    adoptionCenters = {}
    adoptionCenterId, adoptionToken = nil, nil
    sessionGeneration = nil
    closeUi()
end)

RegisterNetEvent('cm-playerdata:client:lifeStateChanged', function(lifeState)
    if tostring(lifeState) ~= 'alive' then
        clearLocalPet()
        clearAdoptionCenters()
        closeUi()
    end
end)

RegisterNetEvent('cm-playerdata:client:playerDowned', function()
    clearLocalPet()
    clearAdoptionCenters()
    closeUi()
end)

CreateThread(function()
    Wait(750)
    refreshAdoptionCenters()
end)

CreateThread(function()
    while true do
        local wait = 1000
        local playerPed = PlayerPedId()
        local canInteract = playerPed and playerPed ~= 0 and DoesEntityExist(playerPed)
            and not IsEntityDead(playerPed) and not uiOpen
        local coords = canInteract and GetEntityCoords(playerPed) or nil
        local closest, closestDistance

        for centerId, center in pairs(adoptionCenters) do
            local visible = coords and centerVisible(center)
            local distance = visible and #(coords - vector3(center.x, center.y, center.z)) or math.huge
            if visible and distance <= (Config.Adoption.NpcStreamDistance or 80.0) then
                wait = 0
                ensureAdoptionNpc(center)
            else
                deleteAdoptionNpc(centerId)
            end
            if visible and distance <= tonumber(center.interactionDistance or 0.0)
                and (not closestDistance or distance < closestDistance) then
                closest, closestDistance = center, distance
            end
        end

        local dialogueOpen = false
        local dialogueOk, dialogueState = pcall(function() return exports['cm-ui']:IsNpcDialogueOpen() end)
        dialogueOpen = dialogueOk and dialogueState == true
        if closest and not dialogueOpen then
            nearestCenter = closest
            if not promptVisible then
                promptVisible = true
                pcall(function()
                    exports['cm-ui']:ShowInteract({
                        owner = 'cm-pets-adoption', key = 'E',
                        label = closest.interactionLabel or 'ADOPT PET',
                        name = closest.displayName, role = 'CM PETS', priority = 16,
                    })
                end)
            end
            if IsControlJustReleased(0, 38) then openAdoptionDialogue(closest) end
        else
            nearestCenter = nil
            hidePrompt()
        end
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        if uiOpen and (IsEntityDead(PlayerPedId()) or IsPauseMenuActive()) then closeUi() end
        Wait(uiOpen and 500 or 1500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearLocalPet()
    clearAdoptionCenters()
    closeUi()
end)
