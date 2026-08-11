while not Config do Citizen.Wait(1) end

Config.HandRadar = {
    ---@field enabled: boolean [master toggle for the hand radar gun feature]
    enabled = true,

    ---@field Weapon: hash [weapon hash that becomes the radar gun when equipped (backtick = hash)]
    Weapon = `WEAPON_RADAR`,

    ---@field Unit: string [speed unit shown on the screen - 'mph' or 'kmh']
    Unit = 'mph',

    ---@field AimDistance: number [max range (metres) to clock a vehicle you point at]
    AimDistance = 200.0,

    ---@field AimCone: number [aim cone half-angle (degrees) around screen centre - larger = more forgiving, smaller = more precise]
    AimCone = 5.0,

    ---@field Dui: table [the floating 3D speed screen (DUI) rendered above the gun]
    Dui = {
        ---@field offset: table [local offset from the weapon - { forward: number, up: number } (raise `up` to lift the screen)]
        offset = { forward = 0.04, up = 0.20 },

        ---@field scale: table [world scale of the screen - { x: number(width), y: number(height), z: number(depth) }, keep x:y ~2:1]
        scale = { x = 0.020, y = 0.010, z = 1.0 },

        ---@field faceCam: boolean [if true the screen always billboards toward the camera for legibility]
        faceCam = true,

        ---@field maxDistance: number [max distance (metres) the screen stays visible before hiding]
        maxDistance = 12.0,
    },
}
