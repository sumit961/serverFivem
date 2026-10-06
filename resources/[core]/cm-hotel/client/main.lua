CMHotelClient = CMHotelClient or {}

local receptionistPed = nil
local rentalPed = nil
local hotelBlip = nil
local hotelDialogueOpen = false
local editorActive = false
local activeSetup = nil

local function readVector4(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then return nil end
    local ok, x, y, z, heading = pcall(function()
        return value.x or value[1], value.y or value[2], value.z or value[3], value.w or value.heading or value.h or value[4]
    end)
    if not ok or not tonumber(x) or not tonumber(y) or not tonumber(z) then return nil end
    return vector4(tonumber(x), tonumber(y), tonumber(z), tonumber(heading or 0))
end

local function fallbackSetup()
    local hotel = Config.Hotel or {}
    local mainLift = hotel.lifts and hotel.lifts.main or {}
    local floors = {}
    for _, floor in ipairs(mainLift.floors or {}) do
        if type(floor) == 'table' then
            floors[#floors + 1] = { id = floor.id, label = floor.label, interaction = floor.interaction,
                arrival = floor.destination, destination = floor.destination, interactionDistance = floor.interactionDistance }
        end
    end
    return { enabled = hotel.enabled == true, firstSpawn = hotel.firstSpawn, receptionist = hotel.receptionist or {},
        rental = hotel.rental or {}, lifts = { main = { label = mainLift.label or 'Hotel Elevator', floors = floors } },
        help = Config.HelpLocations or {}, blip = Config.Blip or {} }
end

local function setup()
    return activeSetup or fallbackSetup()
end

local function notify(message, notifyType)
    if GetResourceState('cm-core') == 'started' then
        local ok = pcall(function() exports['cm-core']:Notify(message, notifyType or 'info', 4000) end)
        if ok then return end
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message or ''))
    EndTextCommandThefeedPostTicker(false, false)
end

local function loadModel(model)
    if type(model) ~= 'string' or model == '' then return nil end
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function spawnPed(definition)
    local coords = readVector4(definition and definition.coords)
    local hash = loadModel(definition and definition.model)
    if not coords or not hash then return nil end
    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z, coords.w, false, true)
    if not ped or ped == 0 then SetModelAsNoLongerNeeded(hash) return nil end
    SetEntityAsMissionEntity(ped, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetPedCanRagdoll(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCanBeTargetted(ped, false)
    SetPedKeepTask(ped, true)
    SetModelAsNoLongerNeeded(hash)
    return ped
end

local function hidePrompt()
    if GetResourceState('cm-ui') == 'started' then exports['cm-ui']:HideInteract() end
end

local function showPrompt(label)
    if GetResourceState('cm-ui') == 'started' then exports['cm-ui']:ShowInteract({ key = 'E', label = label }) end
end

local function cleanupWorld()
    hidePrompt()
    if receptionistPed and DoesEntityExist(receptionistPed) then DeletePed(receptionistPed) end
    if rentalPed and DoesEntityExist(rentalPed) then DeletePed(rentalPed) end
    receptionistPed, rentalPed = nil, nil
    if hotelBlip and DoesBlipExist(hotelBlip) then RemoveBlip(hotelBlip) end
    hotelBlip = nil
end

local function setWorldVisibility(visible)
    for _, ped in ipairs({ receptionistPed, rentalPed }) do
        if ped and DoesEntityExist(ped) then
            SetEntityVisible(ped, visible == true, false)
            SetEntityCollision(ped, visible == true, visible == true)
        end
    end
end

local function createBlip()
    local blipConfig = setup().blip or {}
    local coords = readVector4(blipConfig.coords)
    if blipConfig.enabled ~= true or not coords or not tonumber(blipConfig.sprite) or not tonumber(blipConfig.colour) then return end
    hotelBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(hotelBlip, tonumber(blipConfig.sprite))
    SetBlipColour(hotelBlip, tonumber(blipConfig.colour))
    SetBlipScale(hotelBlip, tonumber(blipConfig.scale) or 0.8)
    SetBlipAsShortRange(hotelBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Hotel')
    EndTextCommandSetBlipName(hotelBlip)
end

local function rebuildWorld()
    cleanupWorld()
    if setup().enabled ~= true then return end
    receptionistPed = spawnPed(setup().receptionist or {})
    rentalPed = spawnPed(setup().rental or {})
    createBlip()
    if editorActive then setWorldVisibility(false) end
end

function CMHotelClient.GetSetup()
    return setup()
end

function CMHotelClient.SetEditorActive(active)
    editorActive = active == true
    if editorActive then setWorldVisibility(false); hidePrompt() else setWorldVisibility(true) end
end

RegisterNetEvent('cm-hotel:client:setupUpdated', function(payload)
    if type(payload) ~= 'table' or type(payload.setup) ~= 'table' then return end
    activeSetup = payload.setup
    rebuildWorld()
    TriggerEvent('cm-hotel:client:setupDataApplied', payload)
end)

local function openReception()
    if editorActive or hotelDialogueOpen or not receptionistPed or not DoesEntityExist(receptionistPed) then return end
    hotelDialogueOpen = true
    TriggerServerEvent('cm-hotel:server:useReception')
end

local function openRental()
    if editorActive or hotelDialogueOpen or not rentalPed or not DoesEntityExist(rentalPed) then return end
    hotelDialogueOpen = true
    TriggerServerEvent('cm-hotel:server:openRental')
end

local function receptionChoices(sessionToken)
    return {
        { id = 'new', label = "I'M NEW HERE", description = 'A short city starting guide.', event = 'cm-hotel:client:receptionChoice', payload = { token = sessionToken, id = 'new' }, close = false },
        { id = 'rental', label = 'WHERE CAN I RENT A VEHICLE?', description = 'Mark the beginner rental desk.', event = 'cm-hotel:client:receptionChoice', payload = { token = sessionToken, id = 'rental' }, close = false },
        { id = 'license', label = 'WHERE IS THE DRIVING TEST CENTRE?', description = 'Mark the driving test location.', event = 'cm-hotel:client:receptionChoice', payload = { token = sessionToken, id = 'license' }, close = false },
        { id = 'job', label = 'WHERE CAN I FIND WORK?', description = 'Mark the Job Centre.', event = 'cm-hotel:client:receptionChoice', payload = { token = sessionToken, id = 'job' }, close = false },
        { id = 'essentials', label = 'CITY ESSENTIALS', description = 'Mark an essential city service.', event = 'cm-hotel:client:receptionChoice', payload = { token = sessionToken, id = 'essentials' }, close = false }
    }
end

RegisterNetEvent('cm-hotel:client:openReception', function(payload)
    if editorActive or not hotelDialogueOpen or not receptionistPed or not DoesEntityExist(receptionistPed) then return end
    hidePrompt()
    local opened = exports['cm-ui']:OpenNpcDialogue(receptionistPed, { name = 'Hotel Reception', role = 'CM ROLEPLAY',
        quote = 'WELCOME TO CM ROLEPLAY', serviceLabel = 'How can I help you get started?', choices = receptionChoices(payload and payload.token),
        closeEvent = 'cm-hotel:client:dialogueClosed' })
    if not opened then hotelDialogueOpen = false end
end)

RegisterNetEvent('cm-hotel:client:receptionChoice', function(payload)
    if type(payload) == 'table' then TriggerServerEvent('cm-hotel:server:receptionChoice', payload.token, payload.id) end
end)

RegisterNetEvent('cm-hotel:client:receptionResponse', function(payload)
    if type(payload) ~= 'table' then return end
    if payload.unavailable then exports['cm-ui']:NpcDialogueRespond('LOCATION NOT AVAILABLE', 'inform', 2200); hotelDialogueOpen = false; return end
    if payload.waypoint then
        SetNewWaypoint(payload.waypoint.x + 0.0, payload.waypoint.y + 0.0)
        exports['cm-ui']:NpcDialogueRespond(('%s\nWAYPOINT SET'):format(payload.message or 'Location marked.'), 'success', 2600)
    else exports['cm-ui']:NpcDialogueRespond(payload.message or 'Welcome to the city.', 'inform', 4200) end
    hotelDialogueOpen = false
end)

local function rentalChoices(payload)
    local choices = {}
    for _, option in ipairs(payload.options or {}) do
        choices[#choices + 1] = { id = option.id, label = option.label, description = option.description,
            event = 'cm-hotel:client:rentalChoice', payload = { token = payload.token, id = option.id }, close = false }
    end
    return choices
end

RegisterNetEvent('cm-hotel:client:openRental', function(payload)
    if editorActive or not hotelDialogueOpen or not rentalPed or not DoesEntityExist(rentalPed) then return end
    hidePrompt()
    if not payload or payload.configured ~= true then
        local opened = exports['cm-ui']:OpenNpcDialogue(rentalPed, { name = 'Hotel Rental', role = 'BEGINNER TRANSPORT',
            quote = 'RENTAL SERVICE IS NOT CONFIGURED YET.', continueLabel = 'CLOSE', closeEvent = 'cm-hotel:client:dialogueClosed' })
        if not opened then hotelDialogueOpen = false end
        return
    end
    local opened = exports['cm-ui']:OpenNpcDialogue(rentalPed, { name = 'Hotel Rental', role = 'BEGINNER TRANSPORT',
        quote = payload.active and 'YOU ALREADY HAVE A RENTAL VEHICLE.' or 'SELECT A TEMPORARY VEHICLE.',
        serviceLabel = 'Temporary rentals are never added to your garage.', choices = rentalChoices(payload), closeEvent = 'cm-hotel:client:dialogueClosed' })
    if not opened then hotelDialogueOpen = false end
end)

RegisterNetEvent('cm-hotel:client:rentalChoice', function(payload)
    if type(payload) == 'table' then TriggerServerEvent('cm-hotel:server:rentalChoice', payload.token, payload.id) end
end)

RegisterNetEvent('cm-hotel:client:rentalResult', function(payload)
    if type(payload) ~= 'table' then return end
    exports['cm-ui']:NpcDialogueRespond(payload.message or 'RENTAL UNAVAILABLE', payload.type or 'error', 2600)
    hotelDialogueOpen = false
end)

RegisterNetEvent('cm-hotel:client:dialogueClosed', function()
    hotelDialogueOpen = false
end)

CreateThread(function()
    Wait(500)
    TriggerServerEvent('cm-hotel:server:requestSetup')
end)

CreateThread(function()
    while true do
        if setup().enabled ~= true or editorActive then
            hidePrompt()
            Wait(750)
        else
            local waitMs = 750
            local playerCoords = GetEntityCoords(PlayerPedId())
            local action, actionLabel, actionData, actionDistance = nil, nil, nil, math.huge
            local reception = setup().receptionist or {}
            if receptionistPed and DoesEntityExist(receptionistPed) then
                local distance = #(playerCoords - GetEntityCoords(receptionistPed))
                if distance <= (tonumber(reception.interactionDistance) or 2.0) and distance < actionDistance then action, actionLabel, actionDistance = 'reception', 'HOTEL RECEPTION', distance end
            end
            local rental = setup().rental or {}
            if rentalPed and DoesEntityExist(rentalPed) then
                local distance = #(playerCoords - GetEntityCoords(rentalPed))
                if distance <= (tonumber(rental.interactionDistance) or 2.0) and distance < actionDistance then action, actionLabel, actionDistance = 'rental', 'RENT A VEHICLE', distance end
            end
            for liftId, liftDef in pairs(setup().lifts or {}) do
                for _, floor in ipairs(type(liftDef) == 'table' and liftDef.floors or {}) do
                    local coords = readVector4(type(floor) == 'table' and floor.interaction)
                    if coords then
                        local distance = #(playerCoords - vector3(coords.x, coords.y, coords.z))
                        if distance <= (tonumber(floor.interactionDistance or liftDef.interactionDistance) or 2.0) and distance < actionDistance then
                            action, actionLabel, actionData, actionDistance = 'lift', 'USE ELEVATOR', { liftId = liftId, floorId = floor.id }, distance
                        end
                    end
                end
            end
            if action and not hotelDialogueOpen then
                waitMs = 0
                showPrompt(actionLabel)
                if IsControlJustReleased(0, 38) then
                    hidePrompt()
                    if action == 'reception' then openReception()
                    elseif action == 'rental' then openRental()
                    elseif action == 'lift' then TriggerServerEvent('cm-hotel:server:useLift', actionData.liftId, actionData.floorId) end
                    Wait(250)
                end
            else hidePrompt() end
            Wait(waitMs)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    hidePrompt()
    if hotelDialogueOpen and GetResourceState('cm-ui') == 'started' then pcall(function() exports['cm-ui']:CancelNpcDialogue() end) end
    cleanupWorld()
end)
