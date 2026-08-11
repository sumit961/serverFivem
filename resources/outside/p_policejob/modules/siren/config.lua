while not Config do Citizen.Wait(1) end

Config.Siren = {
    ---@field enabled: boolean [master toggle for the advanced siren control feature]
    enabled = true,

    ---@field allowedClasses: table [vehicle classes that allow siren control, keyed by class id = boolean (18 = Emergency)]
    allowedClasses = { [18] = true },

    ---@field keybinds: table [siren keybinds, each { description: string, key: string } (rebindable in the pause menu)]
    keybinds = {
        toggleMenu   = { description = 'Toggle siren HUD',           key = 'L' },
        toggleLights = { description = 'Toggle emergency lights',    key = 'J' },
        cycleSiren   = { description = 'Cycle siren tone / arm',     key = 'B' },
        muteToggle   = { description = 'Mute / unmute siren',        key = 'OEM_3' },
        manualHorn   = { description = 'Manual horn / hi-low',       key = 'X' },
    },

    ---@field manualHornIndex: number [siren slot used for the manual horn burst (0 = default GTA horn-siren)]
    manualHornIndex = 0,

    ---@field tones: table [selectable siren tones - list of { label: string, localeKey: string, sound: string }]
    -- Order here drives the on-screen tone buttons (WAIL / YELP / HI-LO / AUX).
    tones = {
        { label = 'Wail',  localeKey = 'siren_tone_wail', sound = 'VEHICLES_HORNS_SIREN_1' },
        { label = 'Yelp',  localeKey = 'siren_tone_yelp', sound = 'VEHICLES_HORNS_SIREN_2' },
        { label = 'Hi-Lo', localeKey = 'siren_tone_hilo', sound = 'VEHICLES_HORNS_AMBULANCE_WARNING' },
        { label = 'Aux',   localeKey = 'siren_tone_aux',  sound = 'VEHICLES_HORNS_POLICE_WARNING' },
    },

    ---@field lights: table [emergency light settings]
    lights = {
        ---@field canControlSeparately: boolean [allow lights ON without siren sound (GTA mode 1)]
        canControlSeparately = true,
    },
}
