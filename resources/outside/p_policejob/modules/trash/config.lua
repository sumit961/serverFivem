while not Config do Citizen.Wait(1) end

Config.Trash = {
    ---@field Enabled: boolean [master toggle for the department trash/disposal stash]
    Enabled = true,

    ---@field Slots: number [number of inventory slots in a trash stash]
    Slots = 50,

    ---@field MaxWeight: number [maximum trash stash weight in grams]
    MaxWeight = 100000,

    ---@field StashPrefix: string [prefix used to build each trash bin's unique stash id]
    StashPrefix = 'p_policejob_trash',
}
