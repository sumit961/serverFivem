while not Config do Citizen.Wait(1) end

Config.Helicam = {
    ---@field Enabled: boolean [master toggle for the helicopter camera feature]
    Enabled = true,

    ---@field RestrictToHelicopter: boolean [if true the helicam only works in class 15 (helicopter) vehicles]
    RestrictToHelicopter = true,

    ---@field AllowPilot: boolean [allow the driver/pilot seat to operate the helicam]
    AllowPilot = false,

    ---@field SpeedUnit: string ['kmh' or 'mph' - unit shown for the helicam speed readout]
    SpeedUnit = 'kmh',
    ---@field AltitudeUnit: string ['m' or 'ft' - unit shown for the helicam altitude (height above ground) readout]
    AltitudeUnit = 'm',

    ---@field FovMin: number [maximum zoom (smallest FOV)]
    FovMin = 8.0,
    ---@field FovMax: number [minimum zoom (largest FOV)]
    FovMax = 70.0,
    ---@field FovDefault: number [starting FOV]
    FovDefault = 50.0,
    ---@field FovStep: number [FOV change per zoom tick]
    FovStep = 2.0,
    ---@field RotateSpeed: number [pan/tilt speed (mouse sensitivity multiplier)]
    RotateSpeed = 4.0,
    ---@field PitchMin: number [lowest pitch angle (look almost straight down)]
    PitchMin = -89.0,
    ---@field PitchMax: number [highest pitch angle (limit above horizon)]
    PitchMax = 25.0,

    ---@field EnableSpotlight: boolean [draw a synced spotlight that follows the camera]
    EnableSpotlight = true,

    ---@field Spotlight: table [spotlight beam settings]
    Spotlight = {
        ---@field Color: table [RGB beam colour - { r, g, b }]
        Color = { 245, 245, 220 },
        ---@field Distance: number [how far the beam reaches (metres)]
        Distance = 250.0,
        ---@field Brightness: number [beam intensity]
        Brightness = 25.0,
        ---@field Hardness: number [beam edge hardness]
        Hardness = 0.0,
        ---@field Radius: number [cone radius (starting value)]
        Radius = 13.0,
        ---@field Falloff: number [falloff exponent]
        Falloff = 28.0,
        ---@field RadiusMin: number [minimum cone radius when resizing with Ctrl + wheel]
        RadiusMin = 4.0,
        ---@field RadiusMax: number [maximum cone radius when resizing with Ctrl + wheel]
        RadiusMax = 40.0,
        ---@field RadiusStep: number [radius change per resize tick]
        RadiusStep = 1.5,
        ---@field Smoothing: number [how fast remote beams follow synced direction updates (higher = snappier, lower = smoother)]
        Smoothing = 12.0,
    },

    ---@field Keys: table [helicam keybinds (ox_lib key names)]
    Keys = {
        ---@field toggle: string [open/close the helicam]
        toggle = 'F4',
        ---@field cycleVision: string [cycle Normal -> Night Vision -> Thermal]
        cycleVision = 'N',
        ---@field toggleLight: string [toggle the spotlight]
        toggleLight = 'L',
        ---@field lockTarget: string [lock onto the closest ped/vehicle in view]
        lockTarget = 'E',
    },

    ---@field onStart: function [CLIENT - called when the helicam opens]
    onStart = function() end,

    ---@field onStop: function [CLIENT - called when the helicam closes]
    onStop = function() end,
}
