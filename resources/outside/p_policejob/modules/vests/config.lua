while not Config do Citizen.Wait(1) end

---@field Vests: table [bulletproof vest items - each key is the inventory item name that applies armour when used]
Config.Vests = {
    ['vest_normal'] = {
        ---@field armourAmount: number [how much armour (%) this vest adds when used]
        armourAmount = 10,

        ---@field maxAmount: number [armour is capped at this value (%) when using this vest]
        maxAmount = 50,

        ---@field useable: boolean [if true a progress bar plays while equipping the vest]
        useable = true,

        ---@field usingTime: number [time in milliseconds the equip progress bar takes]
        usingTime = 5000,

        ---@field usingAnim: table [animation played while equipping - { dict: string, clip: string, flag: number }]
        usingAnim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d', flag = 49 },

        ---@field disableControls: table [controls blocked while equipping - { move: boolean, car: boolean, combat: boolean }]
        disableControls = { move = false, car = true, combat = true },
    },
    ['vest_strong'] = {
        ---@field armourAmount: number [how much armour (%) this vest adds when used]
        armourAmount = 25,

        ---@field maxAmount: number [armour is capped at this value (%) when using this vest]
        maxAmount = 100,

        ---@field useable: boolean [if true a progress bar plays while equipping the vest]
        useable = true,

        ---@field usingTime: number [time in milliseconds the equip progress bar takes]
        usingTime = 5000,

        ---@field usingAnim: table [animation played while equipping - { dict: string, clip: string, flag: number }]
        usingAnim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d', flag = 49 },

        ---@field disableControls: table [controls blocked while equipping - { move: boolean, car: boolean, combat: boolean }]
        disableControls = { move = false, car = true, combat = true },
    },
}