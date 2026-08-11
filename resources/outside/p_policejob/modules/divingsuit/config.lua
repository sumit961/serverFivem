while not Config do Citizen.Wait(1) end

Config.DivingSuit = {
    ---@field enabled: boolean [master toggle for the diving suit feature]
    enabled = true,

    ---@field outfit: table [clothing components applied when the suit is worn - list of { component: number, drawable: number, texture: number }]
    outfit = {
        {component = 3, drawable = 1, texture = 0},
        {component = 4, drawable = 1, texture = 0},
        {component = 6, drawable = 1, texture = 0},
    },

    ---@field scubaEnabled: boolean [give the player a scuba/oxygen tank while the suit is on]
    scubaEnabled = true,

    ---@field underwaterTime: number [extra underwater breath time (seconds) granted by the suit]
    underwaterTime = 50.0,

    ---@field progressBarDuration: number [equip/remove progress bar duration in milliseconds]
    progressBarDuration = 5000,

    ---@field allowKeybindRemoval: boolean [if true a keybind can remove the suit; false = only the 'player_clothes' item removes it]
    allowKeybindRemoval = false,

    ---@field deactivateKey: string [keybind to remove the suit when allowKeybindRemoval is true]
    deactivateKey = 'G',

    ---@field hudMoveCommand: string [command to enter "move HUD" mode and drag the oxygen UI (position is remembered)]
    hudMoveCommand = 'divingsuithud',

    ---@field onSuitActivated: function [CLIENT - called when the suit is put on]
    onSuitActivated = function()
    end,

    ---@field onSuitDeactivated: function [CLIENT - called when the suit is taken off]
    onSuitDeactivated = function()
    end,
}
