while not Config do Citizen.Wait(1) end

Config.CCTV = {
    ---@field enabled: boolean [master toggle for the CCTV feature]
    enabled = true,

    ---@field creatorAccess: table [job names allowed to place/manage cameras - list of strings]
    creatorAccess = {'police', 'sheriff'},

    ---@field defaultJobs: table [job names allowed to view cameras - list of strings]
    defaultJobs = {'police', 'sheriff'},

    ---@field loadDistance: number [distance (metres) at which camera props stream in]
    loadDistance = 150.0,

    ---@field models: table [placeable camera props - list of { label: string, model: string }]
    models = {
        {label = 'Camera 1', model = 'prop_cctv_cam_01a'},
        {label = 'Camera 2', model = 'prop_cctv_cam_01b'},
        {label = 'Camera 3', model = 'prop_cctv_cam_02a'},
        {label = 'Camera 4', model = 'prop_cctv_cam_03a'},
        {label = 'Camera 5', model = 'prop_cctv_cam_04a'},
        {label = 'Camera 6', model = 'prop_cctv_cam_04c'},
        {label = 'Camera 7', model = 'prop_cctv_cam_05a'},
        {label = 'Camera 8', model = 'prop_cctv_cam_06a'},
        {label = 'Camera 9', model = 'prop_cctv_cam_07a'},
    },

    ---@field cameraRotation: table [pan/tilt limits while viewing - { speed: number, minPitch/maxPitch/minHeading/maxHeading: number }]
    cameraRotation = {
        speed = 0.3,
        minPitch = -45.0,
        maxPitch = 45.0,
        minHeading = -180.0,
        maxHeading = 180.0
    },

    ---@field cameraOffset: number [distance (metres) the view camera sits from the prop]
    cameraOffset = 2.0,

    ---@field teleportDistance: number [max distance (metres) a camera can be reached/teleported to]
    teleportDistance = 100.0,

    ---@field screenEffect: table [post-fx applied to the CCTV view - { name: string, looped: boolean }]
    screenEffect = {
        name = 'CamPushInNeutral',
        looped = true
    },

    ---@field damage: table [camera damage settings - { enabled: boolean, healthThreshold: number, autoRepairTime: number, breakDistance: number }]
    damage = {
        enabled = true,
        healthThreshold = 0,

        ---@field autoRepairTime: number [time (ms) after which a broken camera repairs itself; 0 disables auto-repair]
        autoRepairTime = 5 * 60 * 1000,

        ---@field breakDistance: number [max distance (metres) a player may be from a camera to break it server-side]
        breakDistance = 10.0,
    }
}
