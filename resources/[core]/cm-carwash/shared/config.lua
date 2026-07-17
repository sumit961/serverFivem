CMWash = CMWash or {}

CMWash.Config = {
    Debug = false,

    stationName = 'CM Auto Spa',
    price = 150,             -- Cash only. The server is always the price authority.
    interactKey = 38,        -- E / INPUT_CONTEXT
    interactKeyLabel = 'E',
    interactDistance = 8.0,
    detectDistance = 65.0,

    -- Drive-through wash settings.
    durationMs = 7000,
    minDirtToOffer = 0.5,    -- GTA dirt range is 0.0 to 15.0.
    cleanDirtLevel = 0.0,
    maxDirtLevel = 15.0,

    Interaction = {
        title = 'CAR WASH',
        action = 'Open automatic car wash',
        noVehicle = 'Drive into the wash bay',
        passenger = 'Only the driver can use the wash',
        hint = 'Cash payment · vehicle secured during service',
        cleanHint = 'This vehicle is already clean',
    },

    -- Stops and holds the selected vehicle in the exact position while the
    -- menu/service is active. The engine remains off after release so the
    -- player starts it normally.
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
        purchaseCooldownMs = 1200,
        locationTolerance = 8.0,
        vehicleDistance = 8.0,
        requireDriver = true,
        requireManagedVehicle = true,
        requireVehicleAccess = true,
        logRejectedAttempts = true,
    },

    Blip = {
        enabled = true,
        sprite = 100,
        color = 3,
        scale = 0.70,
        shortRange = true,
        name = 'Car Wash',
    },

    -- Standard GTA V wash points. Adjust coordinates to the centre of your
    -- custom wash bay/MLO where the vehicle should be held.
    Locations = {
        vector3(26.16, -1391.63, 29.32),
        vector3(167.19, -1735.28, 29.29),
        vector3(-699.19, -932.05, 19.01),
        vector3(-53.99, 6427.98, 31.49),
        vector3(1367.13, 3591.16, 34.89),
        vector3(-1907.32, 2044.87, 140.74),
        vector3(5.93, -1759.72, 29.32),
    },
}
