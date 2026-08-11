while not Config do Citizen.Wait(1) end

Config.GPS = {
    ---@field enabled: boolean [master toggle for the GPS system]
    enabled = true,

    ---@field requiredItem: boolean [if true the GPS turns off when the player removes the GPS item]
    requiredItem = true,

    ---@field requiredItemName: string [inventory item name for the GPS]
    requiredItemName = 'gps',

    ---@field showHeading: boolean [show the heading arrow on GPS blips]
    showHeading = true,

    ---@field updateInterval: number [how often (ms) GPS positions are refreshed]
    updateInterval = 3000,

    ---@field panic: table [panic button settings]
    panic = {
        ---@field enabled: boolean [enable the panic button feature]
        enabled = true,
        ---@field duration: number [how long (seconds) the panic blip flashes]
        duration = 60,
        ---@field blip: table [panic blip appearance - { sprite: number, color: number, scale: number, flash: boolean }]
        blip = { sprite = 526, color = 1, scale = 1.5, flash = true },
        ---@field sound: boolean [play a sound on a panic alert]
        sound = true,
    },

    ---@field types: table [blip style per vehicle type, keyed by type - set enabled=false to hide that type]
    types = {
        ['walk']  = { enabled = true, sprite = 1,   color = 38, sirenColor = 49, scale = 1.1 },
        ['car']   = { enabled = true, sprite = 56,  color = 38, sirenColor = 49, scale = 1.1 },
        ['boat']  = { enabled = true, sprite = 427, color = 38, sirenColor = 49, scale = 1.1 },
        ['heli']  = { enabled = true, sprite = 43,  color = 38, sirenColor = 49, scale = 1.1 },
        ['plane'] = { enabled = true, sprite = 423, color = 38, sirenColor = 49, scale = 1.1 },
    },
}
