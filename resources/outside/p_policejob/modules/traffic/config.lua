while not Config do Citizen.Wait(1) end

Config.Traffic = {
    ---@field enabled: boolean [master toggle for the traffic zone feature]
    enabled = true,

    ---@field DefaultRadius: number [default traffic zone radius in metres]
    DefaultRadius = 250.0,

    ---@field MinRadius: number [minimum allowed zone radius in metres]
    MinRadius = 50.0,

    ---@field MaxRadius: number [maximum allowed zone radius in metres]
    MaxRadius = 500.0,

    ---@field RadiusStep: number [radius change per adjustment step in metres]
    RadiusStep = 25.0,

    ---@field Presets: table [quick zone presets - list of { name: string, radius: number, speed: number, label: string }]
    Presets = {
        { name = 'residential_area',  radius = 150.0, speed = 20.0, label = 'Residential Area' },
        { name = 'business_district', radius = 200.0, speed = 40.0, label = 'Business District' },
        { name = 'highway',           radius = 300.0, speed = 80.0, label = 'Highway' },
        { name = 'school_zone',       radius = 100.0, speed = 15.0, label = 'School Zone' },
        { name = 'construction_site', radius = 175.0, speed = 5.0,  label = 'Construction Site' },
    },

    ---@field MarkerSettings: table [zone ground marker - { type: number, scale: number, color: { r,g,b,a }, drawDistance: number }]
    MarkerSettings = {
        type = 42,
        scale = 1.0,
        color = { r = 255, g = 0, b = 0, a = 100 },
        drawDistance = 300.0,
    },

    ---@field BlipSettings: table [zone blip - { sprite: number, color: number, scale: number, showLabel: boolean }]
    BlipSettings = {
        sprite = 227,
        color = 1,
        scale = 0.7,
        showLabel = true,
    },

    ---@field NotifySettings: table [zone notification - { duration: number(ms), position: string }]
    NotifySettings = {
        duration = 5000,
        position = 'top',
    },
}
