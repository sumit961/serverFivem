while not Config do Citizen.Wait(1) end

Config.Tackle = {
    ---@field Enabled: boolean [master toggle for the tackle feature]
    Enabled = true,

    ---@field JobRestricted: boolean [if true, only players in a Config.Jobs job may tackle; if false anyone can]
    JobRestricted = false,

    ---@field Type: string [tackle behaviour - 'ragdoll' or 'animation']
    Type = 'animation',

    ---@field Distance: number [max distance (metres) to the target ped to start a tackle]
    Distance = 3.0,

    ---@field Timeout: number [cooldown (ms) before the same officer can tackle again]
    Timeout = 10000,

    ---@field Keybind: string [default key used to trigger a tackle]
    Keybind = 'E',
}
