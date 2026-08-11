while not Config do Citizen.Wait(1) end

Config.SmallItems = {
    ---@field Enabled: boolean [master toggle for the small wearable items (vision goggles)]
    Enabled = true,

    ---@field NightVision: table [night vision goggle settings]
    NightVision = {
        ---@field enabled: boolean [enable the night vision item]
        enabled = true,
        ---@field itemName: string [inventory item used to wear the goggles]
        itemName = 'nightvision',
        ---@field toggleKey: string [keybind to toggle night vision on/off while worn]
        toggleKey = 'N',
        ---@field requireJob: boolean [if true only police job members can equip]
        requireJob = true,
        ---@field putOnTime: number [equip progress bar duration in milliseconds]
        putOnTime = 2000,
        ---@field putOnAnim: table [equip animation - { dict: string, clip: string, flag: number }]
        putOnAnim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d', flag = 49 },
        ---@field disableControls: table [controls blocked while equipping - { move: boolean, car: boolean, combat: boolean }]
        disableControls = { move = false, car = true, combat = true },
        ---@field hat: table [hat prop shown on the ped while the goggles are worn]
        hat = {
            ---@field enabled: boolean [enable the visible hat prop]
            enabled = true,
            ---@field propIndex: number [ped prop slot - 0 = hats/helmets]
            propIndex = 0,
            ---@field male: table [drawable/texture for mp_m_freemode_01]
            male = { drawable = 117, texture = 0 },
            ---@field female: table [drawable/texture for mp_f_freemode_01]
            female = { drawable = 116, texture = 0 },
        },
    },

    ---@field ThermalVision: table [thermal vision goggle settings]
    ThermalVision = {
        ---@field enabled: boolean [enable the thermal vision item]
        enabled = true,
        ---@field itemName: string [inventory item used to wear the goggles]
        itemName = 'thermalvision',
        ---@field toggleKey: string [keybind to toggle thermal vision on/off while worn]
        toggleKey = 'T',
        ---@field requireJob: boolean [if true only police job members can equip]
        requireJob = true,
        ---@field putOnTime: number [equip progress bar duration in milliseconds]
        putOnTime = 2000,
        ---@field putOnAnim: table [equip animation - { dict: string, clip: string, flag: number }]
        putOnAnim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d', flag = 49 },
        ---@field disableControls: table [controls blocked while equipping - { move: boolean, car: boolean, combat: boolean }]
        disableControls = { move = false, car = true, combat = true },
        ---@field hat: table [hat prop shown on the ped while the goggles are worn]
        hat = {
            ---@field enabled: boolean [enable the visible hat prop]
            enabled = true,
            ---@field propIndex: number [ped prop slot - 0 = hats/helmets]
            propIndex = 0,
            ---@field male: table [drawable/texture for mp_m_freemode_01]
            male = { drawable = 117, texture = 0 },
            ---@field female: table [drawable/texture for mp_f_freemode_01]
            female = { drawable = 116, texture = 0 },
        },
    },
}
