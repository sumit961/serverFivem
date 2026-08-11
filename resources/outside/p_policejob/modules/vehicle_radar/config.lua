while not Config do Citizen.Wait(1) end

Config.VehicleRadar = {
    ---@field enabled: boolean [master toggle for the in-vehicle speed radar feature]
    enabled = true,

    ---@field restrictToAllowedVehicles: boolean [if true the radar only works in vehicles listed in AllowedVehicles]
    restrictToAllowedVehicles = false,

    ---@field AllowedVehicles: table [vehicle model names allowed to use the radar, keyed by model = boolean (empty = any)]
    AllowedVehicles = {
        -- ['police'] = true,
        -- ['police2'] = true,
        -- ['police3'] = true,
        -- ['police4'] = true,
        -- ['sheriff'] = true,
        -- ['sheriff2'] = true,
    },

    ---@field Unit: string [speed unit shown in the UI - 'mph' or 'kmh']
    Unit = 'mph',

    ---@field MaxDistance: number [maximum detection distance (metres) for either antenna]
    MaxDistance = 75.0,

    ---@field ConeDot: number [cone tightness - 1.0 = straight line, 0.0 = full 180° hemisphere (higher keeps cross-traffic out)]
    ConeDot = 0.55,

    ---@field MinTargetSpeed: number [minimum reported target speed; anything lower is treated as no target]
    MinTargetSpeed = 1.0,

    ---@field MinFastSpeed: number [minimum speed (UI units) for a target to register a "FAST" reading]
    MinFastSpeed = 35,

    ---@field DefaultMode: string [default direction filter - 'BOTH', 'SAME' (same as patrol) or 'OPP' (opposing)]
    DefaultMode = 'BOTH',

    ---@field UpdateInterval: number [how often (ms) the radar refreshes the UI]
    UpdateInterval = 150,

    ---@field Keys: table [radar keybinds (FiveM/ox_lib key names)]
    Keys = {
        ---@field toggle: string [toggle radar on/off]
        toggle    = 'F7',
        ---@field lockFront: string [lock/unlock the front antenna]
        lockFront = 'OEM_4',
        ---@field lockRear: string [lock/unlock the rear antenna]
        lockRear  = 'OEM_6',
        ---@field cycleMode: string [cycle direction filter BOTH -> SAME -> OPP]
        cycleMode = 'OEM_5',
    },

    ---@field EditCommand: string [command that opens the UI in edit mode to drag/resize the radar (nil/empty to disable)]
    EditCommand = 'radarconfig',

    ---@field Sounds: table [UI sound file names under web/public/sounds (nil disables that sound)]
    Sounds = {
        lock    = 'radar_lock',
        mode    = 'radar_beep',
        powerOn = 'radar_power',
    },

    ---@field onToggleOn: function [CLIENT - called when the radar is toggled on]
    onToggleOn = function() end,

    ---@field onToggleOff: function [CLIENT - called when the radar is toggled off]
    onToggleOff = function() end,

    ---@field onLock: function [CLIENT - called when an antenna locks - (side: string 'front'|'rear', snapshot: { tgt, fast })]
    onLock = function(side, snapshot) end,

    ---@field onUnlock: function [CLIENT - called when an antenna releases its lock - (side: string 'front'|'rear')]
    onUnlock = function(side) end,
}
