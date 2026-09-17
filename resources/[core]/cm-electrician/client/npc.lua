-- CM Electrician -- Switchboard NPC
--
-- Job sign-up/resignation and service-truck rental are handled by talking
-- to this ped, using cm-ui's shared interact prompt + cinematic dialogue
-- (the same components cm-license/cm-police use for their own job NPCs) --
-- see cm-ui/docs/CM_UI_USAGE.md. main.lua exposes the state this file needs
-- through CMElectrician.Client since the two files don't share locals.

local Config = CMElectrician.Config
CMElectrician.Client = CMElectrician.Client or {}

local npcPed = nil
local promptVisible = false

local function loadModel(model)
    local hash = GetHashKey(model)
    if not IsModelValid(hash) then return nil end

    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 200 do
        Wait(10)
        timeout = timeout + 1
    end

    return HasModelLoaded(hash) and hash or nil
end

CreateThread(function()
    local def = Config.NPC
    if not def or not def.coords then return end

    local hash = loadModel(def.model)
    if not hash then
        print('[CM-ELECTRICIAN] failed to load NPC model: ' .. tostring(def.model))
        return
    end

    local coords = def.coords
    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, false)
    if not DoesEntityExist(ped) then return end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanRagdoll(ped, false)
    if def.scenario then TaskStartScenarioInPlace(ped, def.scenario, 0, true) end
    SetModelAsNoLongerNeeded(hash)

    npcPed = ped
end)

local function buildChoices()
    local Client = CMElectrician.Client
    local employed = Client.IsEmployed()
    local choices = {}

    choices[#choices + 1] = {
        id = 'menu',
        label = employed and 'Manage employment' or 'Get employed',
        description = employed and 'View level, progress and pay rates' or 'Join the electrician crew',
        event = 'cm-electrician:client:npcChoice',
        payload = { action = 'menu' },
    }

    if employed then
        local rent = Config.RentVehicle
        if Client.GetLevel() >= (tonumber(rent.unlockLevel) or 2) then
            local active = Client.IsVehicleActive()
            choices[#choices + 1] = {
                id = 'truck',
                label = active and 'Return service truck' or ('Rent service truck ($%d)'):format(tonumber(rent.cost) or 0),
                description = active and 'Hand the truck back in' or 'Needed for deposit-plate runs',
                event = 'cm-electrician:client:npcChoice',
                payload = { action = 'truck', rent = not active },
            }
        end
    end

    return choices
end

local function openDialogue()
    if not npcPed or not DoesEntityExist(npcPed) then return end
    local def = Config.NPC
    local employed = CMElectrician.Client.IsEmployed()

    exports['cm-ui']:HideInteract()
    promptVisible = false

    exports['cm-ui']:OpenNpcDialogue(npcPed, {
        name = def.name or 'Electrician Foreman',
        role = def.role or 'CM ELECTRICIAN',
        quote = employed
            and 'Back on shift? Let me know what you need.'
            or 'Looking for work? I can get you set up on the crew.',
        choices = buildChoices(),
        closeEvent = 'cm-electrician:client:npcDialogueDismissed',
    })
end

AddEventHandler('cm-electrician:client:npcChoice', function(payload)
    payload = type(payload) == 'table' and payload or {}
    local Client = CMElectrician.Client

    if payload.action == 'menu' then
        Client.OpenMenu()
    elseif payload.action == 'truck' then
        Client.RequestTruck(payload.rent == true)
    end
end)

AddEventHandler('cm-electrician:client:npcDialogueDismissed', function() end)

CreateThread(function()
    if GetResourceState('cm-ui') ~= 'started' then
        print('[CM-ELECTRICIAN] cm-ui is not running -- the switchboard NPC needs it for the interact prompt/dialogue.')
        return
    end

    while true do
        local wait = 800
        local def = Config.NPC

        if def and npcPed and DoesEntityExist(npcPed) and not CMElectrician.Client.IsMenuOpen() then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local npcCoords = vector3(def.coords.x, def.coords.y, def.coords.z)
            local distance = #(playerCoords - npcCoords)

            if distance < (def.interactDistance or 3.0) then
                wait = 0
                exports['cm-ui']:ShowInteract({
                    key = Config.interactKeyLabel or 'E',
                    label = 'INTERACTION',
                    name = def.name or 'Electrician Foreman',
                    role = def.role or 'CM ELECTRICIAN',
                })
                promptVisible = true

                if IsControlJustReleased(0, Config.interactKey) then
                    openDialogue()
                end
            elseif promptVisible then
                exports['cm-ui']:HideInteract()
                promptVisible = false
            end
        elseif promptVisible then
            exports['cm-ui']:HideInteract()
            promptVisible = false
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if GetResourceState('cm-ui') == 'started' then
        exports['cm-ui']:HideInteract()
        exports['cm-ui']:CancelNpcDialogue()
    end
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
end)
