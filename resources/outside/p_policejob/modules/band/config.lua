while not Config do Citizen.Wait(1) end

Config.Band = {
    ---@field Enabled: boolean [master toggle for the tracking band feature]
    Enabled = true,

    ---@field Jobs: table [jobs that can apply/remove a band and see its blip - { jobName = minGrade }]
    Jobs = {
        ['police'] = 0,
        -- ['sheriff'] = 0,
    },

    ---@field Blip: table [tracking band blip appearance]
    Blip = {
        ---@field scale: number [blip size]
        scale = 1.2,
        ---@field sprite: number [blip icon id]
        sprite = 1,
        ---@field category: number [blip category id (12 = PLAYER)]
        category = 12,
        ---@field shrink: boolean [shrink the blip at distance]
        shrink = true,
        ---@field priority: number [blip draw priority]
        priority = 5,
        ---@field height: boolean [show height indicator]
        height = false,
        ---@field color: number [blip colour id]
        color = 6,
        ---@field heading: boolean [show heading arrow]
        heading = true,
        ---@field pulse: boolean [pulse the blip]
        pulse = true,
    },

    ---@field LoopRate: number [how often (ms) band blips refresh on the client]
    LoopRate = 1100,

    ---@field UpdateCoordsRate: number [how often (ms) a banded player's coords sync from the server]
    UpdateCoordsRate = 900,

    ---@field Prop: table [band prop attachment - { model: string, coords: vector3, rotation: vector3 }]
    Prop = {
        model = 'prop_trackingband_01',
        coords = vector3(-0.03, 0.11, 0.01),
        rotation = vector3(-87.96, 0.0, 24.44),
    },

    ---@field ApplyAnim: table [animation played on the officer while putting the band on - { dict: string, clip: string, flag: number }]
    ApplyAnim  = { dict = 'random@train_tracks', clip = 'idle_e', flag = 1 },

    ---@field RemoveAnim: table [animation played on the officer while removing the band - { dict: string, clip: string, flag: number }]
    RemoveAnim = { dict = 'random@train_tracks', clip = 'idle_e', flag = 1 },

    ---@field onAttach: function [CLIENT - called when a band is attached]
    onAttach = function()
    end,

    ---@field onRemove: function [CLIENT - called when a band is removed]
    onRemove = function()
    end,

    ---@field onAttach_Server: function [SERVER - called when a band is attached - (playerId: number, targetId: number)]
    onAttach_Server = function(playerId, targetId)
    end,

    ---@field onRemove_Server: function [SERVER - called when a band is removed - (playerId: number, targetId: number)]
    onRemove_Server = function(playerId, targetId)
    end,
}
