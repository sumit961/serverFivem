Config = Config or {}

-- Local development diagnostics are enabled while the Hotel lift is being
-- validated. Set false before deploying to a production server.
Config.Debug = true

Config.Hotel = {
    enabled = true,

    -- Authoritative Hotel first-spawn point captured in-game. Keep the exact
    -- Z value; this is an interior/MLO coordinate and must not be grounded.
    firstSpawn = vector4(-717.6809, -2319.9050, 48.2639, 261.74),

    receptionist = {
        model = 'cs_molly',
        coords = vector4(-719.9081, -2260.5525, 13.4524, 180.63),
        interactionDistance = 2.0
    },

    rental = {
        -- Set this once a valid rental attendant model is selected. Do not
        -- invent a model solely to make the coordinate appear configured.
        model = nil,
        coords = vector4(-747.6341, -2290.1362, 13.0609, 47.59),
        vehicleSpawn = vector4(-793.7281, -2343.8887, 14.5706, 132.18),
        interactionDistance = 2.0,
        returnDistance = 12.0
    },

    -- Authoritative Hotel lift points captured in-game. Interaction points
    -- detect E; destination points are used only for arrival after teleport.
    -- Two valid floors use a direct transfer; three or more use cm-lift's menu.
    lifts = {
        main = {
            label = 'Hotel Elevator',
            floors = {
                {
                    id = 'rooms',
                    label = 'Hotel Rooms',
                    interaction = vector4(-709.7803, -2252.7759, 39.3299, 348.42),
                    destination = vector4(-705.9849, -2251.6576, 39.3455, 177.78)
                },
                {
                    id = 'lobby',
                    label = 'Ground Floor',
                    interaction = vector4(-709.6461, -2258.1189, 13.4629, 356.00),
                    destination = vector4(-705.8812, -2256.6580, 13.4623, 172.43)
                }
            }
        }
    }
}

-- These are intentionally unset until verified city locations are supplied.
Config.HelpLocations = {
    rental = nil,
    license = nil,
    jobCentre = nil,
    hospital = nil
}

Config.Blip = {
    enabled = false,
    coords = nil,
    sprite = nil,
    colour = nil,
    scale = nil
}

-- Model names are intentionally unset. A configured option is only offered
-- when it has a real model and the rental spawn point is configured.
Config.RentalVehicles = {
    { id = 'bike', label = 'Bicycle', model = nil, price = 0, durationMinutes = 30 },
    { id = 'scooter', label = 'Scooter', model = nil, price = 0, durationMinutes = 30 },
    { id = 'starter_car', label = 'Starter Car', model = nil, price = 250, durationMinutes = 30 }
}

-- Reserved for future cm-onboarding integration. Current behaviour is driven
-- only by each rental option's authoritative price field.
Config.FirstRentalFree = false

Config.Rental = {
    account = 'cash',
    platePrefix = 'CMR',
    sessionLifetimeMs = 15000,
    requestCooldownMs = 750,
    spawnClearRadius = 3.5,
    expiryCheckMs = 10000,
    highSpeedCleanupMps = 15.0
}
