while not Config do Citizen.Wait(1) end

Config.VehicleTracker = {
    ---@field Enabled: boolean [master toggle for the vehicle tracker feature]
    Enabled = true,

    ---@field ItemName: string [inventory item used to install a tracker]
    ItemName = 'tracking_vehicle',

    ---@field Jobs: table [jobs that can install/remove trackers and see tracked blips - { jobName = minGrade }]
    Jobs = {
        ['police'] = 0,
        -- ['sheriff'] = 0,
    },

    ---@field InstallDistance: number [max distance (metres) from the vehicle to install a tracker]
    InstallDistance = 4.0,

    ---@field RemoveDistance: number [max distance (metres) from the vehicle to remove a tracker]
    RemoveDistance = 4.0,

    ---@field LoopRate: number [how often (ms) tracked blips are refreshed]
    LoopRate = 1200,

    ---@field UpdateCoordsRate: number [how often (ms) a tracked vehicle reports its coords]
    UpdateCoordsRate = 1000,

    ---@field ReturnItemOnPoliceRemove: boolean [if true the tracker item is returned when police remove it]
    ReturnItemOnPoliceRemove = true,

    ---@field Blip: table [appearance of the tracker blip on the map]
    Blip = {
        ---@field scale: number [blip size]
        scale = 0.9,
        ---@field sprite: number [blip icon id]
        sprite = 225,
        ---@field category: number [blip category id]
        category = 3,
        ---@field shrink: boolean [shrink the blip at distance]
        shrink = true,
        ---@field priority: number [blip draw priority]
        priority = 5,
        ---@field height: boolean [show height indicator]
        height = false,
        ---@field color: number [blip colour id]
        color = 5,
        ---@field heading: boolean [show heading arrow]
        heading = true,
        ---@field pulse: boolean [pulse the blip]
        pulse = false,
        ---@field namePrefix: string [text prefixed to the blip name]
        namePrefix = 'Tracker | ',
    },

    ---@field Install: table [install action settings - { duration: number(ms), animation: { dict: string, clip: string } }]
    Install = {
        duration = 6000,
        animation = {
            dict = 'mini@repair',
            clip = 'fixing_a_ped',
        },
    },

    ---@field Remove: table [remove action settings - { duration: number(ms), animation: { dict: string, clip: string } }]
    Remove = {
        duration = 5000,
        animation = {
            dict = 'mini@repair',
            clip = 'fixing_a_ped',
        },
    },

    ---@field Hack: table [thief-side tracker hack settings]
    Hack = {
        ---@field enabled: boolean [allow non-police to hack/remove a tracker]
        enabled = true,
        ---@field duration: number [hack progress duration in milliseconds]
        duration = 9000,
        ---@field animation: table [animation played while hacking - { dict: string, clip: string }]
        animation = {
            dict = 'mini@repair',
            clip = 'fixing_a_ped',
        },
        ---@field miniGame: function [skill check run when hacking - return true on success]
        miniGame = function()
            return lib.skillCheck(
                {
                    { areaSize = 35, speedMultiplier = 1.2 },
                    { areaSize = 30, speedMultiplier = 1.4 },
                    { areaSize = 25, speedMultiplier = 1.5 },
                },
                { '1', '2', '3', '4' }
            )
        end,
    },

    ---@field onInstall: function [CLIENT - called after a tracker is installed - (vehicle: number, plate: string)]
    onInstall = function(vehicle, plate)
    end,

    ---@field onRemove: function [CLIENT - called after a tracker is removed - (vehicle: number, plate: string, reason: string)]
    onRemove = function(vehicle, plate, reason)
    end,

    ---@field onInstall_Server: function [SERVER - called after a tracker is installed - (playerId: number, plate: string)]
    onInstall_Server = function(playerId, plate)
    end,

    ---@field onRemove_Server: function [SERVER - called after a tracker is removed - (playerId: number, plate: string, reason: string)]
    onRemove_Server = function(playerId, plate, reason)
    end,
}
