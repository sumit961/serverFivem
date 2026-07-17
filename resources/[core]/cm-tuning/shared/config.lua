CMTuning = CMTuning or {}

CMTuning.Config = {
    Debug = false,

    interactKey = 38,          -- E
    interactDistance = 6.0,
    detectDistance = 70.0,
    requireDriver = true,
    requireOwnership = true,   -- owner or temporary key holder

    -- Cash and bank are both available by default. Disable either account here.
    defaultAccount = 'cash',
    allowCash = true,
    allowBank = true,

    Security = {
        maxVehicleDistance = 8.0,
        sessionTimeoutMs = 120000,
        requestCooldownMs = 1500,
        purchaseCooldownMs = 2000,
        maxChangesPerPurchase = 32,
        failClosed = true,
    },

    VehicleLock = {
        enabled = true,
        engineOff = true,
        leaveEngineOff = true,
        freezePosition = true,
        disableExit = true,
    },

    Interaction = {
        title = 'CM MOTORWORKS',
        hint = 'Vehicle is secured while customising',
    },

    Camera = {
        enabled = true,
        fov = 45.0,
        distance = 5.2,
        height = 1.15,
        startAngle = 320.0,
        rotateSpeed = 1.6,
        Presets = {
            { label = 'Front', angle = 0.0 },
            { label = '3/4', angle = 320.0 },
            { label = 'Side', angle = 270.0 },
            { label = 'Rear', angle = 180.0 },
            { label = 'Top', angle = 320.0, height = 4.0, distance = 4.0 },
        },
    },

    Shops = {
        chip = {
            label = 'Chip Tuning',
            sub = 'Performance and mechanical upgrades',
            Blip = { enabled = true, sprite = 446, color = 47, scale = 0.75, shortRange = true, name = 'Chip Tuning' },
            Locations = {
                vector3(-337.0, -136.7, 39.0),
                vector3(731.5, -1088.8, 22.2),
                vector3(1174.9, 2640.2, 37.8),
                vector3(110.6, 6626.4, 32.0),
            },
        },
        workshop = {
            label = 'Auto Workshop',
            sub = 'Paint, bodywork and visual upgrades',
            Blip = { enabled = true, sprite = 72, color = 3, scale = 0.75, shortRange = true, name = 'Auto Workshop' },
            Locations = {
                vector3(-1155.5, -2007.1, 13.2),
                vector3(-205.9, -1310.5, 31.3),
                vector3(1182.0, 2648.0, 37.8),
                vector3(-1420.0, -449.0, 35.9),
            },
        },
    },

    -- maxLevel is used by the server. GTA indices are -1 (stock), then 0..maxLevel-1.
    Performance = {
        { key = 'engine',       modType = 11, label = 'Engine',       pricePerLevel = 12000, maxLevel = 4 },
        { key = 'brakes',       modType = 12, label = 'Brakes',       pricePerLevel = 8000,  maxLevel = 4 },
        { key = 'transmission', modType = 13, label = 'Transmission', pricePerLevel = 10000, maxLevel = 4 },
        { key = 'suspension',   modType = 15, label = 'Suspension',   pricePerLevel = 6000,  maxLevel = 4 },
        { key = 'armor',        modType = 16, label = 'Armor',        pricePerLevel = 9000,  maxLevel = 5 },
    },

    Turbo = { modType = 18, label = 'Turbo Tuning', price = 25000 },

    Tyres = {
        enabled = true,
        label = 'Tyres',
        maxLevel = 4,
        pricePerLevel = 7000,
        bulletproofFromLevel = 3,
        Names = { 'Street', 'Sport', 'Semi-Slick', 'Racing' },
    },

    Harness = {
        enabled = true,
        label = 'Racing Harness',
        price = 18000,
    },

    EngineRepair = {
        enabled = true,
        basePrice = 800,
        pricePerHealthPoint = 4,
        maxPrice = 25000,
        durationMs = 15000,
        fullRebuild = true,
    },

    -- maxIndex is a hard server ceiling. The UI still reads the exact options
    -- supported by the current vehicle and never shows unavailable indices.
    Visual = {
        { key = 'spoiler',     modType = 0,  label = 'Spoiler',      pricePerLevel = 3500, maxIndex = 200 },
        { key = 'frontBumper', modType = 1,  label = 'Front Bumper', pricePerLevel = 4000, maxIndex = 200 },
        { key = 'rearBumper',  modType = 2,  label = 'Rear Bumper',  pricePerLevel = 4000, maxIndex = 200 },
        { key = 'skirts',      modType = 3,  label = 'Side Skirts',  pricePerLevel = 3000, maxIndex = 200 },
        { key = 'exhaust',     modType = 4,  label = 'Exhaust',      pricePerLevel = 2500, maxIndex = 200 },
        { key = 'rollcage',    modType = 5,  label = 'Roll Cage',    pricePerLevel = 6000, maxIndex = 200 },
        { key = 'grille',      modType = 6,  label = 'Grille',       pricePerLevel = 2000, maxIndex = 200 },
        { key = 'hood',        modType = 7,  label = 'Hood',         pricePerLevel = 5000, maxIndex = 200 },
        { key = 'fender',      modType = 8,  label = 'Fenders',      pricePerLevel = 3000, maxIndex = 200 },
        { key = 'roof',        modType = 10, label = 'Roof',         pricePerLevel = 3500, maxIndex = 200 },
        { key = 'horn',        modType = 14, label = 'Horn',         pricePerLevel = 1200, maxIndex = 200 },
        { key = 'wheels',      modType = 23, label = 'Wheels',       pricePerLevel = 5500, maxIndex = 200 },
        { key = 'livery',      modType = 48, label = 'Livery',       pricePerLevel = 2500, maxIndex = 200 },
    },

    Xenon = { modType = 22, label = 'Xenon Lights', price = 4000 },

    resprayPrice = 2500,
    windowTintPrice = 1500,
    neonPrice = 6000,
    wheelColorPrice = 1800,
    headlightColorPrice = 2200,
    plateStylePrice = 900,

    HeadlightColors = {
        { -1, 'Stock', '#f0e6c8' }, { 0, 'White', '#ffffff' },
        { 1, 'Blue', '#3aa0ff' }, { 2, 'Electric', '#00e5ff' },
        { 3, 'Mint', '#7ed321' }, { 4, 'Lime', '#c6ff00' },
        { 5, 'Yellow', '#ffd400' }, { 6, 'Gold', '#ffb300' },
        { 7, 'Orange', '#ff8a00' }, { 8, 'Red', '#ff2d2d' },
        { 9, 'Pink', '#ff4fd8' }, { 10, 'Purple', '#a24bff' },
    },

    PlateStyles = {
        { 0, 'Blue / White' }, { 1, 'Yellow / Black' },
        { 2, 'Yellow / Blue' }, { 3, 'Blue / White 2' },
        { 4, 'Blue / White 3' }, { 5, 'North Yankton' },
    },

    WindowTints = {
        { 0, 'None' }, { 1, 'Limo' }, { 2, 'Light Smoke' },
        { 3, 'Dark Smoke' }, { 4, 'Pure Black' },
    },

    Colors = {
        { 0, 'Black', '#0d0d0d' }, { 1, 'Graphite', '#26282a' },
        { 11, 'Anthracite', '#1c1d21' }, { 12, 'Silver', '#9a9a9a' },
        { 4, 'Iron Grey', '#5a5e63' }, { 111, 'White', '#ffffff' },
        { 27, 'Red', '#c00e1a' }, { 28, 'Torino Red', '#da1918' },
        { 43, 'Orange', '#f78616' }, { 88, 'Yellow', '#ffcf20' },
        { 55, 'Lime Green', '#66b81f' }, { 49, 'Dark Green', '#22383e' },
        { 64, 'Blue', '#47578f' }, { 70, 'Ultra Blue', '#22228b' },
        { 71, 'Light Blue', '#3b39e0' }, { 145, 'Purple', '#621276' },
        { 135, 'Hot Pink', '#f21f99' }, { 91, 'Bronze', '#7b6a58' },
        { 38, 'Gold', '#b1923d' }, { 117, 'Brushed Steel', '#5d7581' },
    },

    NeonColors = {
        { 'White', 255, 255, 255 }, { 'Cyan', 0, 255, 255 },
        { 'Blue', 0, 0, 255 }, { 'Green', 0, 255, 0 },
        { 'Red', 255, 0, 0 }, { 'Pink', 255, 0, 255 },
        { 'Yellow', 255, 255, 0 }, { 'Orange', 255, 128, 0 },
    },
}

-- Backward compatibility for older references while correcting the typo.
CMTuning.Config.respayPrice = CMTuning.Config.resprayPrice
