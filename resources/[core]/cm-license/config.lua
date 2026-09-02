-- CM License System Configuration

CMLicenseConfig = {
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
        Model = 's_m_m_autoshop_01',
        Name = 'Alex Morgan',
        Role = 'CM License Instructor',
        Scenario = 'WORLD_HUMAN_CLIPBOARD',
        Coords = { x = -700.5005, y = -1401.3684, z = 5.4953, heading = 148.6945 },
    },

    -- Fixed public choices. Administrators only record their routes.
    StandardTypes = {
        driver = { label='Driver License', item='driver_license', price=500, days=30, model='blista', category='ground' },
        boat = { label='Boat License', item='boat_license', price=1000, days=30, model='dinghy', category='boat' },
        air = { label='Air License', item='air_license', price=5000, days=30, model='havok', category='air' },
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

return CMLicenseConfig
