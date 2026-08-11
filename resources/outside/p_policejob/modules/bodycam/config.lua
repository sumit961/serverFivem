while not Config do Citizen.Wait(1) end

Config.Bodycam = {
    ---@field Enabled: boolean [master toggle for the bodycam feature]
    Enabled = true,

    ---@field jobRestricted: boolean [if true players can only view bodycams from their own job]
    jobRestricted = true,

    ---@field Recording: table [footage recording settings (requires the `screencapture` resource)]
    Recording = {
        ---@field Enabled: boolean [allow the watcher to record footage]
        Enabled = true,
        ---@field Key: number [control id the watcher presses to start/stop recording (default 47 = G)]
        Key = 47,
        ---@field MaxWidth: number [max recording width in pixels]
        MaxWidth = 1280,
        ---@field MaxHeight: number [max recording height in pixels]
        MaxHeight = 720,
    },

    ---@field onStartWatching: function [CLIENT - called when this player starts watching a bodycam]
    onStartWatching = function()
    end,

    ---@field onStopWatching: function [CLIENT - called when this player stops watching a bodycam]
    onStopWatching = function()
    end,

    ---@field onStartWatching_Server: function [SERVER - called when a player starts watching a bodycam - (playerId: number)]
    onStartWatching_Server = function(playerId)
    end,

    ---@field onStopWatching_Server: function [SERVER - called when a player stops watching a bodycam - (playerId: number)]
    onStopWatching_Server = function(playerId)
    end
}
