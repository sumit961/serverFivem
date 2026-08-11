while not Config do Citizen.Wait(1) end

Config.Trunks = {
    ---@field enabled: boolean [master toggle for putting players in vehicle trunks]
    enabled = true,

    ---@field cameraType: string ['dynamic' (orbit), 'static' (fixed behind) or 'game' (no custom cam)]
    cameraType = 'dynamic',

    ---@field checkVehicleLocks: boolean [if true the vehicle must be unlocked before a player can exit the trunk]
    checkVehicleLocks = true,

    ---@field checkTrunkState: boolean [if true the trunk door must be open before a player can be placed inside]
    checkTrunkState = true,

    ---@field defaultOffset: table [fallback attachment of the player inside the trunk - { coords: vector3, rotation: vector3 }]
    defaultOffset = {
        coords = vector3(0.0, 0.85, -0.87),
        rotation = vector3(0.0, 0.0, 40.0)
    },

    ---@field offsets: table [per-vehicle-model attachment overrides, keyed by model - fill via /trunk_editor or manually]
    offsets = {},

    ---@field allowedGroups: table [groups allowed to use the trunk editor, keyed by group name = boolean]
    allowedGroups = {
        ['owner'] = true,
        ['admin'] = true,
    },

    ---@field onEnter: function [CLIENT - called when a player is placed into a trunk]
    onEnter = function() end,

    ---@field onExit: function [CLIENT - called when a player leaves a trunk]
    onExit = function() end,
}
