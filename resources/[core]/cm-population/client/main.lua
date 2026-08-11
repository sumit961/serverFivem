local Config = CMPopulationConfig

local function clampDensity(value)
    value = tonumber(value) or 0.0
    return math.max(0.0, math.min(1.0, value))
end

local pedestrianDensity = clampDensity(Config.pedestrianDensity)
local scenarioPedDensity = clampDensity(Config.scenarioPedDensity)
local vehicleDensity = clampDensity(Config.vehicleDensity)
local randomVehicleDensity = clampDensity(Config.randomVehicleDensity)
local parkedVehicleDensity = clampDensity(Config.parkedVehicleDensity)
local reapplyIntervalMs = math.max(1000, tonumber(Config.reapplyIntervalMs) or 5000)
local wantedStars = 0

local policeDispatchServices = { 1, 2, 4, 6, 7, 8, 9, 10, 12, 13 }

local function aiPoliceActive()
    return Config.enablePoliceDispatchAtSixStars == true
        and wantedStars >= (tonumber(Config.aiWantedThreshold) or 6)
end

RegisterNetEvent('cm-playerdata:client:update', function(key, value)
    if key == 'wantedStars' then wantedStars = math.max(0, math.floor(tonumber(value) or 0)) end
end)

local function applyLoadedWanted(data)
    wantedStars = math.max(0, math.floor(tonumber(type(data) == 'table' and data.wantedStars or 0) or 0))
end

RegisterNetEvent('cm-playerdata:client:loaded', applyLoadedWanted)
RegisterNetEvent('cm-playerdata:client:characterLoaded', applyLoadedWanted)
RegisterNetEvent('cm-playerdata:client:unloaded', function() wantedStars = 0 end)
RegisterNetEvent('cm-playerdata:client:characterUnloaded', function() wantedStars = 0 end)

-- This event is only raised for peds created by GTA's population system.
-- Canceling it does not affect peds created explicitly by CM resources.
AddEventHandler('populationPedCreating', function()
    if Config.blockPopulationPedCreation and not aiPoliceActive() then
        CancelEvent()
    end
end)

-- Density multipliers are frame-scoped and therefore must run every frame.
CreateThread(function()
    while true do
        SetPedDensityMultiplierThisFrame(pedestrianDensity)
        SetScenarioPedDensityMultiplierThisFrame(scenarioPedDensity, scenarioPedDensity)
        SetVehicleDensityMultiplierThisFrame(vehicleDensity)
        SetRandomVehicleDensityMultiplierThisFrame(randomVehicleDensity)
        SetParkedVehicleDensityMultiplierThisFrame(parkedVehicleDensity)

        Wait(0)
    end
end)

local function applyPersistentSuppression()
    if GetResourceState('cm-playerdata') == 'started' then
        pcall(function() wantedStars = tonumber(exports['cm-playerdata']:GetWantedStars()) or wantedStars end)
    end
    local enableAiPolice = aiPoliceActive()
    if Config.disableRandomCops then
        SetCreateRandomCops(enableAiPolice)
        SetCreateRandomCopsNotOnScenarios(enableAiPolice)
        SetCreateRandomCopsOnScenarios(enableAiPolice)
    end

    if Config.disableDispatch then
        SetDispatchCopsForPlayer(PlayerId(), enableAiPolice)

        for service = 1, 15 do
            EnableDispatchService(service, false)
        end
        if enableAiPolice then
            for _, service in ipairs(policeDispatchServices) do EnableDispatchService(service, true) end
        end
    end

    if Config.disableGarbageTrucks then
        SetGarbageTrucks(false)
    end

    if Config.disableRandomBoats then
        SetRandomBoats(false)
    end

    if Config.disableRandomTrains then
        SetRandomTrains(false)
    end

    if Config.disableLowPriorityVehicleGenerators then
        SetAllLowPriorityVehicleGeneratorsActive(false)
    end
end

CreateThread(function()
    while true do
        applyPersistentSuppression()
        Wait(reapplyIntervalMs)
    end
end)
