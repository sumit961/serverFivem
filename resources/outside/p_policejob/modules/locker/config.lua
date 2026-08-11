while not Config do Citizen.Wait(1) end

Config.Locker = {
    ---@field Enabled: boolean [master toggle for personal/shared lockers]
    Enabled = true,

    ---@field Slots: number [number of inventory slots in a locker stash]
    Slots = 100,

    ---@field MaxWeight: number [maximum locker weight in grams]
    MaxWeight = 250000,

    ---@field StashPrefix: string [prefix used to build each locker's unique stash id]
    StashPrefix = 'p_policejob_locker',
}
