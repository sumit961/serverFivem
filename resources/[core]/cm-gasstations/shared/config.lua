CMGas = CMGas or {}

CMGas.Config = {
    Debug = false,

    stationName = 'Xero Gas',
    interactKey = 38, -- E / INPUT_CONTEXT
    interactKeyLabel = 'E',

    -- The custom interaction prompt is shown anywhere inside the forecourt.
    pumpInteractDistance = 6.0,
    stationDetectDistance = 80.0,

    Interaction = {
        title = 'FUEL STATION',
        vehicleAction = 'Refuel vehicle & open store',
        storeAction = 'Open gas station store',
        hint = 'Vehicle is secured while ordering',
    },

    -- Hold the selected vehicle exactly where it is while the menu is open.
    VehicleHold = {
        enabled = true,
        zeroVelocity = true,
        handbrake = true,
        freezePosition = true,
        engineOff = true,
    },

    Security = {
        sessionSeconds = 45,
        openCooldownMs = 700,
        orderCooldownMs = 1200,
        maxVehicleDistance = 7.5,
        playerPumpTolerance = 9.0,
        vehiclePumpTolerance = 10.0,
        maxItemQuantity = 10,
        requireVehicleAccess = true,
        requireManagedVehicle = true,
    },

    Blip = {
        enabled = true,
        sprite = 361,
        color = 3,
        scale = 0.72,
        shortRange = true,
        name = 'Gas Station',
    },

    Pricing = {
        pricePerFuelPercent = 8,
        fuelCanPrice = 350,
        repairKitPrice = 1200,
        washKitPrice = 250,
    },

    Items = {
        fuelCan = 'fuel_can',
        repairKit = 'repair_kit',
        washKit = 'wash_kit',
    },

    Refuel = {
        maxFuel = 100.0,
        allowFillToFull = true,
        minimumPurchase = 1,
    },

    ItemUse = {
        maxVehicleDistance = 6.0,
        fuelCanAmount = 25.0,
        repairBodyAmount = 650.0,
        washDirtLevel = 0.0,
        durationMs = {
            fuelCan = 8000,
            repairKit = 12000,
            washKit = 7000,
        },
        earlyFinishToleranceMs = 750,
        timeoutMs = 30000,
    },

    Pumps = {
        vector3(49.4187, 2778.793, 58.043),
        vector3(263.894, 2606.463, 44.983),
        vector3(1039.958, 2671.134, 39.550),
        vector3(1207.260, 2660.175, 37.899),
        vector3(2539.685, 2594.192, 37.944),
        vector3(2679.858, 3263.946, 55.240),
        vector3(2005.055, 3773.887, 32.403),
        vector3(1687.156, 4929.392, 42.078),
        vector3(1701.314, 6416.028, 32.763),
        vector3(179.857, 6602.839, 31.868),
        vector3(-94.4619, 6419.594, 31.489),
        vector3(-2554.996, 2334.40, 33.078),
        vector3(-1800.375, 803.661, 138.651),
        vector3(-1437.622, -276.747, 46.207),
        vector3(-2096.243, -320.288, 13.168),
        vector3(-724.619, -935.1631, 19.213),
        vector3(-526.019, -1211.003, 18.184),
        vector3(-70.2148, -1761.792, 29.534),
        vector3(265.648, -1261.309, 29.292),
        vector3(819.653, -1028.846, 26.403),
        vector3(1208.951, -1402.567, 35.224),
        vector3(1181.381, -330.847, 69.316),
        vector3(620.843, 268.100, 103.089),
        vector3(2581.321, 362.039, 108.468),
        vector3(176.631, -1562.025, 29.263),
        vector3(-319.292, -1471.715, 30.549),
    },

    Stations = {
        vector3(49.4187, 2778.793, 58.043),
        vector3(263.894, 2606.463, 44.983),
        vector3(1039.958, 2671.134, 39.550),
        vector3(1207.260, 2660.175, 37.899),
        vector3(2539.685, 2594.192, 37.944),
        vector3(2679.858, 3263.946, 55.240),
        vector3(2005.055, 3773.887, 32.403),
        vector3(1687.156, 4929.392, 42.078),
        vector3(1701.314, 6416.028, 32.763),
        vector3(179.857, 6602.839, 31.868),
        vector3(-94.4619, 6419.594, 31.489),
        vector3(-2554.996, 2334.40, 33.078),
        vector3(-1800.375, 803.661, 138.651),
        vector3(-1437.622, -276.747, 46.207),
        vector3(-2096.243, -320.288, 13.168),
        vector3(-724.619, -935.1631, 19.213),
        vector3(-526.019, -1211.003, 18.184),
        vector3(-70.2148, -1761.792, 29.534),
        vector3(265.648, -1261.309, 29.292),
        vector3(819.653, -1028.846, 26.403),
        vector3(1208.951, -1402.567, 35.224),
        vector3(1181.381, -330.847, 69.316),
        vector3(620.843, 268.100, 103.089),
        vector3(2581.321, 362.039, 108.468),
        vector3(176.631, -1562.025, 29.263),
        vector3(-319.292, -1471.715, 30.549),
    },
}
