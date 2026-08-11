while not Config do Citizen.Wait(1) end

Config.Rappel = {
    ---@field enabled: boolean [master toggle for the rappel feature]
    enabled = true,

    ---@field item: string [inventory item required (and consumed) to rappel from a helicopter]
    item = 'rappel_kit',

    ---@field consumeItem: boolean [if true remove one item per rappel; false keeps the kit]
    consumeItem = true,

    ---@field requireJob: boolean [if true restrict rappelling to jobs in Config.Jobs; false allows anyone]
    requireJob = true,

    ---@field keybind: table [key to start a rappel / release an active one - { description: string, key: string }]
    keybind = { description = 'Rappel / release rope', key = 'G' },

    ---@field heli: table [helicopter rappel settings]
    heli = {
        ---@field minHeight: number [minimum height (metres) above ground before a heli rappel is allowed]
        minHeight = 5.0,
        ---@field ropeLength: number [rope length (metres) passed to the rappel task]
        ropeLength = 80.0,
    },
}
