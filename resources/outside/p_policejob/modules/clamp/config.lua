while not Config do Citizen.Wait(1) end

Config.Clamp = {
    ---@field enabled: boolean [master toggle for the wheel clamp feature]
    enabled = true,

    ---@field Prop: table [clamp prop attachment - { model: string, boneIndex: string, offset: vector3, rotation: vector3 }]
    Prop = {
        model = 'prop_clamp',
        boneIndex = 'wheel_lf',
        offset = vector3(-0.1, 0.1, -0.2),
        rotation = vector3(180.0, 200.0, 90.0),
    },

    ---@field onWheelClamped: function [called when a wheel is clamped - (entity: number)]
    onWheelClamped = function(entity)
    end,

    ---@field onWheelUnclamped: function [called when a wheel is unclamped - (entity: number)]
    onWheelUnclamped = function(entity)
    end,
}
