while not Config do Citizen.Wait(1) end

Config.Handsup = {
    ---@field Enabled: boolean [master toggle for the hands-up feature]
    Enabled = true,

    ---@field Command: string [chat command that toggles hands up]
    Command = 'p_handsup',

    ---@field Key: string [keybind name used to toggle hands up]
    Key = 'X',

    ---@field Animation: table [hands-up animation played on the player - { dict: string, clip: string }]
    Animation = {
        dict = 'random@mugging3',
        clip = 'handsup_standing_base',
    },

    ---@field DisableControls: table [list of { controlGroup: number, control: number } pairs disabled while hands are up]
    DisableControls = {
        { 2, 24 },   -- Attack
        { 2, 257 },  -- Attack 2
        { 2, 25 },   -- Aim
        { 2, 263 },  -- Melee Attack 1
        { 2, 45 },   -- Reload
        { 2, 37 },   -- Select Weapon
        { 2, 23 },   -- Also Enter
        { 0, 47 },   -- Detonate
        { 0, 264 },  -- Melee Attack 2
        { 0, 257 },  -- Attack 2
        { 0, 140 },  -- Melee Attack Light
        { 0, 141 },  -- Melee Attack Alt
        { 0, 142 },  -- Melee Attack 2
        { 0, 143 },  -- Melee Block
    },
}
