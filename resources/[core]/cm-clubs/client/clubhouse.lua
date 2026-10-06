local clubhouse
local clubhousePed
local generation = 0
local promptVisible = false
local dialogueOpen = false
local dashboardOpen = false
local reopenAt = 0
local INTERACT_OWNER = 'cm-clubs:clubhouse'

local function hidePrompt()
    if GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract(INTERACT_OWNER) end)
    end
    promptVisible = false
end

local function cancelDialogue()
    if GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:CancelNpcDialogue() end)
    end
    dialogueOpen = false
end

local function deletePed()
    if clubhousePed and DoesEntityExist(clubhousePed) then DeleteEntity(clubhousePed) end
    clubhousePed = nil
end

local function clearWorld(deleteNpc)
    hidePrompt()
    cancelDialogue()
    if deleteNpc then deletePed() end
end

local function notify(message, kind)
    TriggerEvent('cm-clubs:client:notify', message, kind or 'inform')
end

local function validFacility(data)
    if type(data) ~= 'table' or data.ok ~= true or type(data.clubhouse) ~= 'table' then return false end
    local f = data.clubhouse
    if type(f.clubId) ~= 'string' or f.clubId == '' then return false end
    if tonumber(f.x) == nil or tonumber(f.y) == nil or tonumber(f.z) == nil or tonumber(f.heading) == nil then return false end
    if type(f.npcModel) ~= 'string' or Config.Clubhouse.modelNames[f.npcModel] ~= true then return false end
    if type(f.displayName) ~= 'string' or f.displayName == '' or type(f.interactionLabel) ~= 'string' or f.interactionLabel == '' then return false end
    local distance = tonumber(f.interactionDistance)
    return distance and distance >= 1.0 and distance <= Config.Clubhouse.maxInteractionDistance
end

local function loadModel(modelName)
    if type(modelName) ~= 'string' or Config.Clubhouse.modelNames[modelName] ~= true then return nil end
    local model = joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelValid(model) then return nil end
    RequestModel(model)
    local deadline = GetGameTimer() + Config.Clubhouse.modelLoadTimeoutMs
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(50) end
    if not HasModelLoaded(model) then return nil end
    return model
end

local function spawnPed()
    if not clubhouse or clubhousePed or GetResourceState('cm-ui') ~= 'started' then return end
    local model = loadModel(clubhouse.npcModel)
    if not model then return end
    RequestCollisionAtCoord(clubhouse.x, clubhouse.y, clubhouse.z)
    local spawnZ = clubhouse.z + 0.0
    local foundGround, groundZ = GetGroundZFor_3dCoord(clubhouse.x + 0.0, clubhouse.y + 0.0, clubhouse.z + 2.0, false)
    if foundGround and math.abs(groundZ - clubhouse.z) <= 4.0 then spawnZ = groundZ end
    local ped = CreatePed(4, model, clubhouse.x + 0.0, clubhouse.y + 0.0, spawnZ, clubhouse.heading + 0.0, false, true)
    SetModelAsNoLongerNeeded(model)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    clubhousePed = ped
end

local function drawMarker()
    if not clubhouse then return end
    local marker = Config.Clubhouse.marker or {}
    local scale = marker.scale or {}
    local colour = marker.colour or {}
    DrawMarker(
        tonumber(marker.type) or 1,
        clubhouse.x + 0.0, clubhouse.y + 0.0, clubhouse.z - 0.92,
        0.0, 0.0, 0.0, 0.0, 0.0, clubhouse.heading + 0.0,
        tonumber(scale.x) or 0.72, tonumber(scale.y) or 0.72, tonumber(scale.z) or 0.22,
        tonumber(colour.r) or 0, tonumber(colour.g) or 229, tonumber(colour.b) or 255, tonumber(colour.a) or 125,
        marker.bobUpAndDown == true, marker.faceCamera == true, 2, marker.rotate == true,
        nil, nil, false
    )
end

local function showPrompt()
    if promptVisible or dashboardOpen or dialogueOpen or GetResourceState('cm-ui') ~= 'started' then return end
    pcall(function()
        exports['cm-ui']:ShowInteract({
            owner = INTERACT_OWNER,
            priority = 20,
            key = 'E',
            label = clubhouse.interactionLabel,
            name = clubhouse.displayName,
            role = 'Social Club',
        })
    end)
    promptVisible = true
end

local function openDialogue()
    if dialogueOpen or dashboardOpen or not clubhousePed or not DoesEntityExist(clubhousePed) or GetGameTimer() < reopenAt then return end
    hidePrompt()
    dialogueOpen = true
    local ok, opened = pcall(function()
        return exports['cm-ui']:OpenNpcDialogue(clubhousePed, {
            name = clubhouse.displayName,
            role = 'Social Club',
            quote = ('Welcome to %s.'):format(clubhouse.clubName or 'the club'),
            serviceLabel = 'Choose a club service.',
            choices = {
                {
                    id = 'dashboard',
                    label = 'Open club dashboard',
                    description = 'View your roster, rank, permissions, and club activity.',
                    event = 'cm-clubs:client:clubhouseChoice',
                    payload = { clubId = clubhouse.clubId },
                    close = false,
                },
            },
            closeEvent = 'cm-clubs:client:clubhouseDismissed',
        })
    end)
    if not ok or opened ~= true then
        dialogueOpen = false
        reopenAt = GetGameTimer() + 750
        notify('Clubhouse dialogue is unavailable.', 'error')
    end
end

RegisterNetEvent('cm-clubs:client:clubhouseChoice', function(payload)
    local clubId = type(payload) == 'table' and payload.clubId or nil
    if not dialogueOpen or not clubhouse or clubId ~= clubhouse.clubId then
        cancelDialogue()
        return
    end
    local authorization = lib.callback.await('cm-clubs:server:authorizeClubhouse', false, {
        clubId = clubId,
        action = 'dashboard',
    })
    if not authorization or authorization.ok ~= true then
        cancelDialogue()
        reopenAt = GetGameTimer() + 750
        notify(('Clubhouse unavailable: %s'):format(tostring(authorization and authorization.reason or 'request_failed'):gsub('_', ' ')), 'error')
        return
    end
    cancelDialogue()
    TriggerEvent('cm-clubs:client:openDashboard')
end)

RegisterNetEvent('cm-clubs:client:clubhouseDismissed', function()
    dialogueOpen = false
    reopenAt = GetGameTimer() + 750
end)

local function refreshClubhouse()
    generation = generation + 1
    local currentGeneration = generation
    TriggerEvent('cm-clubs:client:closeDashboard')
    clearWorld(true)
    clubhouse = nil
    if GetResourceState('cm-playerdata') ~= 'started' or GetResourceState('cm-ui') ~= 'started' then return end
    CreateThread(function()
        local response = lib.callback.await('cm-clubs:server:getClubhouse', false)
        if currentGeneration ~= generation then return end
        if validFacility(response) then clubhouse = response.clubhouse end
    end)
end

RegisterNetEvent('cm-clubs:client:refreshClubhouse', refreshClubhouse)
RegisterNetEvent('cm-clubs:client:dashboardState', function(open)
    dashboardOpen = open == true
    if dashboardOpen then hidePrompt() end
end)
RegisterNetEvent('cm-playerdata:client:characterLoaded', refreshClubhouse)
RegisterNetEvent('cm-playerdata:client:loaded', refreshClubhouse)
RegisterNetEvent('cm-playerdata:client:characterUnloaded', function()
    generation = generation + 1
    clubhouse = nil
    clearWorld(true)
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'cm-ui' or resource == 'cm-playerdata' then
        SetTimeout(750, refreshClubhouse)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == 'cm-ui' or resource == 'cm-playerdata' then
        generation = generation + 1
        clubhouse = nil
        clearWorld(true)
        return
    end
    if resource ~= GetCurrentResourceName() then return end
    generation = generation + 1
    clubhouse = nil
    clearWorld(true)
end)

CreateThread(function()
    while true do
        local wait = 1000
        local playerPed = PlayerPedId()
        if IsEntityDead(playerPed) then
            TriggerEvent('cm-clubs:client:closeDashboard')
            clearWorld(true)
            Wait(500)
        elseif clubhouse then
            local playerCoords = GetEntityCoords(playerPed)
            local distance = #(playerCoords - vector3(clubhouse.x, clubhouse.y, clubhouse.z))
            if distance <= (Config.Clubhouse.markerDistance or 35.0) then drawMarker(); wait = 0 end
            if clubhousePed and not DoesEntityExist(clubhousePed) then clubhousePed = nil end
            if not clubhousePed and distance <= (Config.Clubhouse.spawnDistance or 125.0) then
                spawnPed()
            elseif clubhousePed and DoesEntityExist(clubhousePed) and distance > (Config.Clubhouse.despawnDistance or 150.0) then
                deletePed()
            end
            if clubhousePed and DoesEntityExist(clubhousePed) and distance <= clubhouse.interactionDistance and not dashboardOpen and not dialogueOpen then
                showPrompt()
                wait = 0
                if IsControlJustReleased(0, 38) then openDialogue() end
            elseif promptVisible then
                hidePrompt()
            end
        else
            hidePrompt()
        end
        Wait(wait)
    end
end)
