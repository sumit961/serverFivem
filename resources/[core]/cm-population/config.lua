CMPopulationConfig = {
    -- These multipliers are applied every frame. Set any value back to 1.0
    -- if that population type should use GTA's normal density.
    pedestrianDensity = 0.0,
    scenarioPedDensity = 0.0,
    vehicleDensity = 0.0,
    randomVehicleDensity = 0.0,
    parkedVehicleDensity = 0.0,

    -- This only cancels peds made by GTA's population system. Peds created by
    -- CM resources (shops, parking, vehicle dealers, and previews) still work.
    blockPopulationPedCreation = true,

    disableRandomCops = true,
    disableDispatch = true,
    disableGarbageTrucks = true,
    disableRandomBoats = true,
    disableRandomTrains = true,
    disableLowPriorityVehicleGenerators = true,

    -- Reapply persistent native settings in case another resource changes them.
    reapplyIntervalMs = 5000,
}
