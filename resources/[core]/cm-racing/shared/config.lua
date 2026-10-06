CMRacing = CMRacing or {}

CMRacing.Config = {
    Debug = false,

    -- Paddock / Central Sanctioned Racing Organizer
    Paddock = {
        name = 'Vinewood Sanctioned Racing Paddock',
        npc = {
            model = 's_m_m_autoshop_01',
            coords = vector4(1106.25, 96.50, 80.89, 310.0),
            name = 'Marcus Vance',
            role = 'Sanctioned Racing Marshal',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            interactDistance = 3.0,
        },
        blip = {
            enabled = true,
            sprite = 315,       -- Checkered racing flag
            color = 3,          -- Cyan
            scale = 0.85,
            shortRange = true,
            label = 'Sanctioned Racing Paddock',
        },
    },

    -- Interaction settings
    InteractKey = 38, -- INPUT_CONTEXT (E)
    InteractKeyLabel = 'E',

    -- Anti-Exploit and Server Validation
    Validation = {
        -- Maximum plausible speed in m/s (90 m/s ≈ 324 km/h)
        MaxPlausibleSpeedMps = 90.0,
        -- Permitted checkpoint touch radius (meters)
        DefaultCheckpointRadius = 12.0,
        CheckpointTolerance = 25.0,
        -- Seconds driver is allowed outside the race vehicle before auto-failure
        VehicleExitGraceSeconds = 15,
        -- Maximum race total duration before auto-cancel (seconds)
        RaceTimeoutSeconds = 600,
        -- Staging countdown seconds before race start
        CountdownSeconds = 3,
        -- Maximum distance from staging grid to initiate start
        MaxStagingDistance = 35.0,
    },

    -- Checkpoint visual rendering (Client)
    CheckpointVisual = {
        normalType = 45,        -- Cylinder with directional chevron
        finishType = 9,         -- Checkered cylinder
        diameter = 10.0,
        cylinderHeight = 4.0,
        zOffset = 0.20,
        color = { r = 0, g = 229, b = 255, a = 180 },       -- CM Cyan
        finishColor = { r = 255, g = 215, b = 0, a = 200 }, -- Gold finish
    },

    -- Progression ladder
    Progression = {
        [1] = {
            level = 1,
            label = 'Amateur Street License',
            requiredXp = 0,
            unlockedRoutes = { 'vinewood_sprint' },
        },
        [2] = {
            level = 2,
            label = 'Club Sport License',
            requiredXp = 500,
            unlockedRoutes = { 'vinewood_sprint', 'redwood_rally' },
        },
        [3] = {
            level = 3,
            label = 'Grand Prix Pro License',
            requiredXp = 1500,
            unlockedRoutes = { 'vinewood_sprint', 'redwood_rally', 'lsia_grand_prix' },
        },
    },

    -- Distinct Sanctioned Routes
    -- Grounded in CM_ECONOMY_STANDARD.md:
    -- Class C / Beginner Legal: ~50k - 62.5k / hour
    -- Class B / Established: ~62.5k - 87.5k / hour
    -- Class A / Skilled: ~87.5k - 112.5k / hour
    Routes = {
        ['vinewood_sprint'] = {
            id = 'vinewood_sprint',
            name = 'Vinewood Racetrack Sprint',
            category = 'Class C - Street',
            requiredLevel = 1,
            description = 'A technical circuit circling the Vinewood Park horse track perimeter and grandstand straight.',
            estDurationSeconds = 80,
            cooldownSeconds = 180, -- 3 minutes cooldown
            reward = 4500,         -- ~$54,000/hr @ 12 runs/hr
            xp = 50,
            allowedClasses = {
                [0] = 'Compacts',
                [1] = 'Sedans',
                [2] = 'SUVs',
                [3] = 'Coupes',
                [4] = 'Muscle',
                [8] = 'Motorcycles',
            },
            staging = vector4(1106.2, 90.5, 80.88, 320.0),
            checkpoints = {
                { x = 1128.5, y = 115.4, z = 80.88 },
                { x = 1160.0, y = 145.0, z = 80.88 },
                { x = 1188.0, y = 185.0, z = 80.88 },
                { x = 1198.0, y = 240.0, z = 80.88 },
                { x = 1195.0, y = 310.0, z = 80.88 },
                { x = 1170.0, y = 360.0, z = 80.88 },
                { x = 1120.0, y = 380.0, z = 80.88 },
                { x = 1065.0, y = 350.0, z = 80.88 },
                { x = 1040.0, y = 275.0, z = 80.88 },
                { x = 1045.0, y = 195.0, z = 80.88 },
                { x = 1065.0, y = 130.0, z = 80.88 },
                { x = 1106.2, y = 90.5, z = 80.88, isFinish = true },
            },
        },

        ['redwood_rally'] = {
            id = 'redwood_rally',
            name = 'Redwood Lights Motocross & Rally',
            category = 'Class B - Sport',
            requiredLevel = 2,
            description = 'A demanding mixed-surface track with elevation changes, chicanes, and tight hairpins.',
            estDurationSeconds = 110,
            cooldownSeconds = 210, -- 3.5 minutes cooldown
            reward = 6500,         -- ~$71,500/hr @ 11 runs/hr
            xp = 80,
            allowedClasses = {
                [3] = 'Coupes',
                [4] = 'Muscle',
                [5] = 'Sports Classics',
                [6] = 'Sports',
                [8] = 'Motorcycles',
                [9] = 'Off-road',
            },
            staging = vector4(1025.0, 2360.0, 50.5, 18.0),
            checkpoints = {
                { x = 1055.0, y = 2370.0, z = 49.5 },
                { x = 1090.0, y = 2380.0, z = 48.0 },
                { x = 1125.0, y = 2405.0, z = 47.0 },
                { x = 1150.0, y = 2435.0, z = 46.5 },
                { x = 1120.0, y = 2455.0, z = 46.8 },
                { x = 1070.0, y = 2470.0, z = 47.2 },
                { x = 1020.0, y = 2478.0, z = 48.0 },
                { x = 980.0, y = 2480.0, z = 49.0 },
                { x = 950.0, y = 2455.0, z = 50.0 },
                { x = 920.0, y = 2400.0, z = 51.0 },
                { x = 930.0, y = 2360.0, z = 51.5 },
                { x = 970.0, y = 2340.0, z = 51.5 },
                { x = 1005.0, y = 2345.0, z = 51.0 },
                { x = 1025.0, y = 2360.0, z = 50.5, isFinish = true },
            },
        },

        ['lsia_grand_prix'] = {
            id = 'lsia_grand_prix',
            name = 'LSIA Runway Grand Prix',
            category = 'Class A - Super',
            requiredLevel = 3,
            description = 'High-velocity tarmac grand prix incorporating airport main runways, high-speed sweepers, and perimeter taxiways.',
            estDurationSeconds = 150,
            cooldownSeconds = 240, -- 4 minutes cooldown
            reward = 8500,         -- ~$85,000/hr @ 10 runs/hr
            xp = 120,
            allowedClasses = {
                [6] = 'Sports',
                [7] = 'Super',
                [8] = 'Motorcycles',
            },
            staging = vector4(-1037.0, -2737.0, 13.8, 330.0),
            checkpoints = {
                { x = -1075.0, y = -2670.0, z = 13.8 },
                { x = -1130.0, y = -2580.0, z = 13.8 },
                { x = -1200.0, y = -2470.0, z = 13.8 },
                { x = -1260.0, y = -2400.0, z = 13.8 },
                { x = -1320.0, y = -2450.0, z = 13.8 },
                { x = -1380.0, y = -2530.0, z = 13.8 },
                { x = -1440.0, y = -2630.0, z = 13.8 },
                { x = -1500.0, y = -2730.0, z = 13.8 },
                { x = -1560.0, y = -2830.0, z = 13.8 },
                { x = -1620.0, y = -2950.0, z = 13.8 },
                { x = -1550.0, y = -3050.0, z = 13.8 },
                { x = -1450.0, y = -3100.0, z = 13.8 },
                { x = -1320.0, y = -3080.0, z = 13.8 },
                { x = -1200.0, y = -3020.0, z = 13.8 },
                { x = -1100.0, y = -2950.0, z = 13.8 },
                { x = -1040.0, y = -2860.0, z = 13.8 },
                { x = -1037.0, y = -2737.0, z = 13.8, isFinish = true },
            },
        },
    },
}
