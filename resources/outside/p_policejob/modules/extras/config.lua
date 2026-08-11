while not Config do Citizen.Wait(1) end

-- Extras menu access points are defined in maps/departments/*.lua under `extras`.
Config.Extras = {
    ---@field enabled: boolean [master toggle for the vehicle extras/mods menu]
    enabled = true,

    ---@field CameraKeybind: string [key that toggles gameplay camera movement while the menu is open]
    CameraKeybind = 'Z',

    ---@field mods: table [vehicle mod categories shown in the menu - list of { modType: number, label: string }]
    mods = {
        {modType = 11, label = 'Engine'},
        {modType = 12, label = 'Brakes'},
        {modType = 13, label = 'Transmission'},
        {modType = 15, label = 'Suspension'},
        {modType = 14, label = 'Horn'},
        {modType = 0,  label = 'Spoiler'},
        {modType = 1,  label = 'Front Bumper'},
        {modType = 2,  label = 'Rear Bumper'},
        {modType = 3,  label = 'Side Skirt'},
        {modType = 4,  label = 'Exhaust'},
        {modType = 6,  label = 'Grille'},
        {modType = 7,  label = 'Hood'},
        {modType = 10, label = 'Roof'},
        {modType = 22, label = 'Xenon Lights'},
        {modType = 18, label = 'Turbo'},
    },
}
