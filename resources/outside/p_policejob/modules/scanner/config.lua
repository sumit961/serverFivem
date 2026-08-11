while not Config do Citizen.Wait(1) end

Config.Scanner = {
    ---@field enabled: boolean [master toggle for the biometric fingerprint scanner feature]
    enabled = true,

    ---@field requireItem: boolean [if true the officer must carry the scanner item to scan]
    requireItem = false,

    ---@field item: string [inventory item required when requireItem is true]
    item = 'fingerprint_scanner',

    ---@field scanDuration: number [how long (ms) the scan takes before showing the result]
    scanDuration = 4000,

    ---@field scanAnim: table [animation played on the officer while scanning - { dict: string, clip: string, flag: number }]
    scanAnim = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },

    ---@field showMugshot: boolean [show the target ped's mugshot in the result (uses the MugShotBase64 resource, falls back to mugshot records)]
    showMugshot = true,

    ---@field maxDistance: number [max distance (metres) from the target for a valid scan]
    maxDistance = 5.0,
}
