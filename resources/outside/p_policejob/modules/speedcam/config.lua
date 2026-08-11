while not Config do Citizen.Wait(1) end

Config.Speedcam = {
    ---@field enabled: boolean [master toggle for the speed camera feature]
    enabled = true,

    ---@field IgnoredJobs: table [jobs ignored by speedcams, keyed by jobName = boolean (empty to ignore none)]
    IgnoredJobs = {
        ['police'] = true,
        ['sheriff'] = true,
        ['ambulance'] = true,
    },

    ---@field Models: table [prop models treated as speedcams, keyed by model = display name]
    Models = {
        ['prop_cctv_pole_03'] = 'CCTV Pole 1',
        ['prop_cctv_pole_01'] = 'CCTV Pole 2',
        ['prop_cctv_pole_02'] = 'CCTV Pole 3',
    },

    ---@field Unit: string [unit shown on the fine notification - 'KMH' or 'MPH']
    Unit = 'KMH',

    ---@field Blip: table [speedcam blip appearance - { sprite: number, color: number, scale: number, label: string }]
    Blip = {
        sprite = 604,
        color = 0,
        scale = 0.85,
        label = 'Speed Camera'
    },

    ---@field Sound: table [detection sound - { enabled: boolean, volume: number }]
    Sound = {
        enabled = true,
        volume = 0.3,
    },

    ---@field OnSpeedingDetected: function [SERVER - called on a speeding violation, customise the fine here - (playerId: number, totalFine: number, vehicleSpeed: number, speedLimit: number)]
    OnSpeedingDetected = function(playerId, totalFine, vehicleSpeed, speedLimit)
        Bridge.Framework.removeMoney(playerId, 'bank', totalFine)
    end,
}
