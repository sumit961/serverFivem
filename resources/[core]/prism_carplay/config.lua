

Config = {}

Config.Keybind = 'F5' -- Key to open the CarPlay menu (default: F5)

-- Require CarPlay item to be installed in the vehicle before opening
-- If true, only vehicles with a 'carplay' item installed can open the CarPlay UI
-- If false, any player can open CarPlay in any vehicle using the keybind
Config.RequireCarplayItem = false

Config.PrimaryColor = '#00D1FF' -- Primary color for UI (hex color)

-- Notification function (bridge for multiple resources)
-- Modify this function to integrate with your notification system
Config.Notify = function(message, type)
    -- type: 'success', 'error', 'info'
    -- Examples for different notification systems:

    -- Default (chat message)
    local prefix = type == 'success' and '^2' or type == 'error' and '^1' or '^3'
    TriggerEvent('chat:addMessage', { args = { prefix .. 'CarPlay', message } })

    -- ESX:
    -- exports['esx_notify']:Notify(type, 5000, message)

    -- QBCore:
    -- TriggerEvent('QBCore:Notify', message, type, 5000)

    -- ox_lib:
    -- lib.notify({ title = 'CarPlay', description = message, type = type })

    -- mythic_notify:
    -- exports['mythic_notify']:SendAlert(type, message)

    -- okokNotify:
    -- exports['okokNotify']:Alert('CarPlay', message, 5000, type)
end

-- Seatbelt toggle function (bridge for multiple resources)
-- Modify this function to integrate with your seatbelt resource
Config.ToggleSeatbelt = function(state)
    if state then
        -- Code to fasten seatbelt
        -- Example: TriggerEvent('seatbelt:client:ToggleSeatbelt', true)
    else
        -- Code to unfasten seatbelt
        -- Example: TriggerEvent('seatbelt:client:ToggleSeatbelt', false)
    end
end

-- Dashcam Recording Settings
Config.Dashcam = {
    -- Storage type: 'local' or 'fivemanage'
    -- 'local' - saves to server's recordings/dashcam folder
    -- 'fivemanage' - uploads to Fivemanage cloud storage
    storageType = 'fivemanage',

    -- The API key must never be stored in this shared file because shared
    -- scripts are also sent to every client. Configure it server-side in
    -- server.cfg instead:
    -- set prism_carplay_fivemanage_api_key "YOUR_API_KEY"
    fivemanageApiKey = nil,

    -- Maximum recording duration in seconds (default: 5 minutes)
    maxDuration = 30,
}

-- Drive Mode Handling Modifiers
-- Sports/Eco use multipliers, Drift uses additive modifiers for proper drift physics

Config.DriveModes = {
    -- Sports Mode: Extra power and sharper handling (multipliers)
    sports = {
        type = 'multiplier',
        fInitialDriveMaxFlatVel = 1.15,   -- +15% top speed
        fInitialDragCoeff = 1.25,          -- -15% drag (faster acceleration)
        fBrakeForce = 1.10,                -- +10% brake force
        fTractionCurveMax = 1.05,          -- +5% traction
        fTractionCurveMin = 1.05,
        fSuspensionForce = 1.10,           -- Stiffer suspension
    },
    -- Drift Mode: Loose traction for drifting (additive modifiers)
    drift = {
        type = 'additive',
        fInitialDragCoeff = -2.0,          -- Reduce drag (clamped to stay positive at apply time)
        fDriveInertia = -0.31,             -- Less inertia for quicker response
        fSteeringLock = 22.0,              -- More steering angle
        fTractionCurveMax = -1.1,          -- Reduce max traction
        fTractionCurveMin = -0.4,          -- Reduce min traction
        fTractionCurveLateral = -2.5,      -- Reduce lateral grip
        fLowSpeedTractionLossMult = -0.57, -- Less traction loss at low speed
    },
    -- Eco Mode: Better fuel economy, reduced performance (multipliers)
    eco = {
        type = 'multiplier',
        fInitialDriveMaxFlatVel = 0.90,   -- -10% top speed
        fInitialDragCoeff = 0.55,          -- +15% drag (slower acceleration)
        fBrakeForce = 0.95,                -- -5% brake force
        fTractionCurveMax = 1.00,          -- Normal traction
        fTractionCurveMin = 1.00,
        fSuspensionForce = 1.00,           -- Normal suspension
    },
    -- Normal/Off: No modifications
    normal = {
        type = 'reset'
    }
}

-- Neon Light Patterns
Config.NeonPatterns = {
    { id = 1, name = "Solid" },
    { id = 2, name = "Pulse" },
    { id = 3, name = "Flash" },
    { id = 4, name = "Fade" },
}

-- Neon Light Locations
Config.NeonLocations = {
    { id = 1, title = "Front", index = 2 },   -- Front neon
    { id = 2, title = "Rear", index = 3 },    -- Rear neon
    { id = 3, title = "Left", index = 0 },    -- Left neon
    { id = 4, title = "Right", index = 1 },   -- Right neon
}

-- Tuner Chip Handling Limits
-- These define the maximum percentage increase allowed for each handling property
-- Example: maxPercent = 50 means the value can be increased by up to 50% of the base value

Config.TunerChip = {
    -- Boost Power (Top Speed) - fInitialDriveMaxFlatVel
    -- maxPercent = 50 means top speed can be increased by up to 50% of base value
    BoostPower = {
        maxPercent = 50
    },

    -- Gear Change - fClutchChangeRateScaleUpShift
    -- maxPercent = 100 means clutch speed can be doubled
    GearChange = {
        maxPercent = 100
    },

    -- Acceleration - fInitialDragCoeff (lower = faster, so we decrease it)
    -- maxPercent = 50 means drag can be reduced by up to 50%
    Acceleration = {
        maxPercent = 50
    },

    -- Brakes - fBrakeForce
    -- maxPercent = 100 means brake force can be doubled
    Brakes = {
        maxPercent = 100
    }
}

-- Predefined Music Library
-- Songs available in the CarPlay music player
-- filePath is relative to web/public/sounds/
Config.MusicLibrary = {
    {
        id = 'zigzag',
        title = 'Zig Zag',
        artist = 'NCS',
        filePath = 'zigzag.mp3',
    },
    -- Add more songs here:
    -- {
    --     id = 'unique-id',
    --     title = 'Song Title',
    --     artist = 'Artist Name',
    --     filePath = 'filename.mp3',
    -- },
}

