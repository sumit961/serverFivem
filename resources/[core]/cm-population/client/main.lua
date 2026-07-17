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

-- This event is only raised for peds created by GTA's population system.
-- Canceling it does not affect peds created explicitly by CM resources.
AddEventHandler('populationPedCreating', function()
    if Config.blockPopulationPedCreation then
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
    if Config.disableRandomCops then
        SetCreateRandomCops(false)
        SetCreateRandomCopsNotOnScenarios(false)
        SetCreateRandomCopsOnScenarios(false)
    end

    if Config.disableDispatch then
        SetDispatchCopsForPlayer(PlayerId(), false)

        for service = 1, 15 do
            EnableDispatchService(service, false)
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
