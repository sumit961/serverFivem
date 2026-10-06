CMRacing = CMRacing or {}
CMRacing.Client = CMRacing.Client or {}

local Config = CMRacing.Config
local HUD = CMRacing.Client.HUD
local Checkpoints = CMRacing.Client.Checkpoints
local Menu = CMRacing.Client.Menu

local paddockPed = nil
local paddockBlip = nil
local activeRaceToken = nil
local currentActiveRoute = nil
local isInteractVisible = false
local currentInteractTarget = nil
local isVehicleFrozen = false

local function showInteract(label, name, role)
    if GetResourceState('cm-ui') == 'started' then
        exports['cm-ui']:ShowInteract({
            key = Config.InteractKeyLabel or 'E',
            label = label or 'INTERACTION',
            name = name or 'Racing Marshal',
            role = role or 'SANCTIONED RACING'
        })
        isInteractVisible = true
    end
end

local function hideInteract()
    if isInteractVisible and GetResourceState('cm-ui') == 'started' then
        exports['cm-ui']:HideInteract()
        isInteractVisible = false
        currentInteractTarget = nil
    end
end

local function setupPaddock()
    local pConfig = Config.Paddock
    if not pConfig then return end

    -- Setup map blip
    if pConfig.blip and pConfig.blip.enabled then
        paddockBlip = AddBlipForCoord(pConfig.npc.coords.x, pConfig.npc.coords.y, pConfig.npc.coords.z)
        SetBlipSprite(paddockBlip, pConfig.blip.sprite or 315)
        SetBlipColour(paddockBlip, pConfig.blip.color or 3)
        SetBlipScale(paddockBlip, pConfig.blip.scale or 0.85)
        SetBlipAsShortRange(paddockBlip, pConfig.blip.shortRange ~= false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(pConfig.blip.label or 'Sanctioned Racing')
        EndTextCommandSetBlipName(paddockBlip)
    end

    -- Setup NPC
    local modelHash = joaat(pConfig.npc.model or 's_m_m_autoshop_01')
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(50)
    end

    local c = pConfig.npc.coords
    paddockPed = CreatePed(4, modelHash, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetEntityHeading(paddockPed, c.w)
    FreezeEntityPosition(paddockPed, true)
    SetEntityInvincible(paddockPed, true)
    SetBlockingOfNonTemporaryEvents(paddockPed, true)
    TaskStartScenarioInPlace(paddockPed, pConfig.npc.scenario or 'WORLD_HUMAN_CLIPBOARD', 0, true)
    SetModelAsNoLongerNeeded(modelHash)
end

-- Interaction & Staging Proximity Loop
CreateThread(function()
    setupPaddock()

    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local inVeh = IsPedInAnyVehicle(ped, false)
        local veh = inVeh and GetVehiclePedIsIn(ped, false) or 0
        local isDriver = inVeh and (GetPedInVehicleSeat(veh, -1) == ped)

        local targetFound = nil

        -- Check Paddock NPC proximity (on foot or in car)
        local pCoords = vector3(Config.Paddock.npc.coords.x, Config.Paddock.npc.coords.y, Config.Paddock.npc.coords.z)
        local pDist = #(playerCoords - pCoords)
        if pDist <= (Config.Paddock.npc.interactDistance or 3.5) then
            targetFound = {
                type = 'paddock',
                label = 'RACE REGISTRATION',
                name = Config.Paddock.npc.name,
                role = Config.Paddock.npc.role
            }
            sleep = 0
        end

        -- Check Route Staging proximity (if sitting in driver seat of a vehicle)
        if not targetFound and isDriver then
            for rId, route in pairs(Config.Routes) do
                local sCoords = vector3(route.staging.x, route.staging.y, route.staging.z)
                local sDist = #(playerCoords - sCoords)
                if sDist <= 20.0 then
                    targetFound = {
                        type = 'route_staging',
                        routeId = rId,
                        label = 'STAGE TIME TRIAL',
                        name = route.name,
                        role = 'SANCTIONED RACING'
                    }
                    sleep = 0
                    break
                end
            end
        end

        if targetFound then
            if currentInteractTarget ~= (targetFound.routeId or targetFound.type) then
                showInteract(targetFound.label, targetFound.name, targetFound.role)
                currentInteractTarget = targetFound.routeId or targetFound.type
            end

            if IsControlJustPressed(0, Config.InteractKey) then
                Menu.Open()
            end
        else
            if isInteractVisible then
                hideInteract()
            end
        end

        Wait(sleep)
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Race Lifecycle Handlers
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('cm-racing:client:startCountdown', function(data)
    activeRaceToken = data.token
    currentActiveRoute = data.route

    hideInteract()

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        FreezeEntityPosition(veh, true)
        isVehicleFrozen = true
    end

    HUD.Show(data.route.name, #data.route.checkpoints)
    HUD.ShowCountdown(data.countdownSeconds or 3, function()
        if veh ~= 0 and isVehicleFrozen then
            FreezeEntityPosition(veh, false)
            isVehicleFrozen = false
        end
        TriggerServerEvent('cm-racing:server:countdownFinished', activeRaceToken)
    end)
end)

RegisterNetEvent('cm-racing:client:raceStarted', function(data)
    if activeRaceToken ~= data.token or not currentActiveRoute then return end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and isVehicleFrozen then
        FreezeEntityPosition(veh, false)
        isVehicleFrozen = false
    end

    Checkpoints.Start(activeRaceToken, currentActiveRoute.checkpoints)
end)

RegisterNetEvent('cm-racing:client:checkpointAck', function(data)
    if activeRaceToken ~= data.token then return end
    Checkpoints.OnAck(data.checkpointIndex, data.totalCheckpoints)
    HUD.UpdateCheckpoint(data.checkpointIndex, data.totalCheckpoints)
end)

RegisterNetEvent('cm-racing:client:checkpointRejected', function(data)
    if activeRaceToken ~= data.token then return end
    Checkpoints.OnRejected(data.expected)
end)

RegisterNetEvent('cm-racing:client:raceFinished', function(results)
    Checkpoints.Clear()
    HUD.ShowResults(results)

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and isVehicleFrozen then
        FreezeEntityPosition(veh, false)
        isVehicleFrozen = false
    end

    activeRaceToken = nil
    currentActiveRoute = nil
end)

RegisterNetEvent('cm-racing:client:raceFailed', function(reason)
    Checkpoints.Clear()
    HUD.Hide()

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and isVehicleFrozen then
        FreezeEntityPosition(veh, false)
        isVehicleFrozen = false
    end

    activeRaceToken = nil
    currentActiveRoute = nil
end)

RegisterNetEvent('cm-racing:client:notify', function(message, kind)
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'info')
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(tostring(message or ''))
        EndTextCommandThefeedPostTicker(false, false)
    end
end)

-- Resource cleanup
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    hideInteract()
    Checkpoints.Clear()
    HUD.Hide()

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and isVehicleFrozen then
        FreezeEntityPosition(veh, false)
    end

    if paddockPed and DoesEntityExist(paddockPed) then
        DeleteEntity(paddockPed)
    end
    if paddockBlip and DoesBlipExist(paddockBlip) then
        RemoveBlip(paddockBlip)
    end
end)
