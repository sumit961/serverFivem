-- CM License System Configuration

Config = {
    -- Default license validity period (days)
    DefaultValidityDays = 30,

    -- Test session configuration
    TestSession = {
        -- Timeout for a test to complete (minutes)
        TimeoutMinutes = 20,

        -- Maximum mistakes allowed before failure (driver only)
        MaxMistakes = 3,

        -- Distance to consider "abandoned route" (meters)
        AbandonedDistance = 500,
    },

    -- Checkpoint detection
    Checkpoint = {
        -- Default radius for checkpoint entry (meters)
        DefaultRadius = 20.0,

        -- Radius for start point (meters)
        StartRadius = 30.0,

        -- Radius for finish point (meters)
        FinishRadius = 30.0,

        -- Radius for aerial checkpoints (meters)
        AirRadius = 50.0,
    },

    -- Test vehicle configuration
    TestVehicle = {
        -- Mark test vehicles with state (prevents storage/sale)
        MarkTemporary = true,

        -- Default spawn distance from NPC (meters)
        SpawnDistance = 50.0,
    },

    -- Logging and notifications
    Debug = false,

    -- Permission checks
    Permissions = {
        ManageLicenses = 'admin.manage_licenses',
        IssueLicenses = 'admin.issue_licenses',
        RevokeLicenses = 'admin.revoke_licenses',
    },

    -- Item names (should match cm-items definitions)
    Items = {
        Driver = 'driver_license',
        Boat = 'boat_license',
        Air = 'air_license',
    },

    -- Account to charge fees to
    MoneyAccount = 'cash',

    -- NPC interaction data
    NPC = {
        -- Interaction distance (meters)
        InteractionDistance = 3.0,
    },

    -- Expiration check intervals
    ExpirationCheck = {
        -- Check expired licenses every X minutes
        IntervalMinutes = 5,

        -- Check on character load
        CheckOnLoad = true,

        -- Check on inventory open
        CheckOnInventoryOpen = true,
    },

    -- UI/NUI configuration
    UI = {
        -- Show debug info in player HUD
        ShowDebugInfo = false,
    }
}

return Config
