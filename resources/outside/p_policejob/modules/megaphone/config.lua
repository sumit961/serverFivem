while not Config do Citizen.Wait(1) end

Config.Megaphone = {
    ---@field enabled: boolean [master toggle for the megaphone feature]
    enabled = true,

    ---@field forceRange: number [proximity range (metres) the megaphone voice carries]
    forceRange = 5.0,

    ---@field enableSubmix: boolean [if true applies the audio submix filter for the megaphone effect]
    enableSubmix = true,

    ---@field onStart: function [CLIENT - called when the player starts using the megaphone]
    onStart = function() end,

    ---@field onStop: function [CLIENT - called when the player stops using the megaphone]
    onStop = function() end,
}
