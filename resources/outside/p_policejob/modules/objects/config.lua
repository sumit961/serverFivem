while not Config do Citizen.Wait(1) end

Config.Objects = {
    ---@field enabled: boolean [master toggle for the placeable objects feature]
    enabled = true,

    ---@field maxObjectsPerPlayer: number [max objects a player can place per session (0 = unlimited)]
    maxObjectsPerPlayer = 50,

    ---@field allowSteal: boolean [if true anyone can pick up police objects, not just cops]
    allowSteal = false,

    ---@field interactDistance: number [max distance (metres) to interact with a placed object]
    interactDistance = 3.0,

    ---@field useGizmo: boolean [use object_gizmo for precise placement (requires the object_gizmo resource)]
    useGizmo = true,

    ---@field snapToGround: boolean [snap objects to the ground after gizmo placement]
    snapToGround = true,

    ---@field Categories: table [object groups shown in the NUI - list of { name: string, label: string, icon: string, objects: { model, label, icon }[] }]
    Categories = {
        {
            name = 'traffic',
            label = locale('obj_cat_traffic'),
            icon = 'fa-solid fa-road',
            objects = {
                { model = 'prop_roadcone02a', label = locale('roadcone'),icon = 'fa-solid fa-cone-striped' },
                { model = 'prop_air_conelight', label = locale('roadcone_light'), icon = 'fa-solid fa-lightbulb' },
                { model = 'prop_consign_01a', label = locale('consign'), icon = 'fa-solid fa-signs-post' },
                { model = 'prop_barrier_work05', label = locale('barrier'), icon = 'fa-solid fa-road-barrier' },
                { model = 'prop_mp_barrier_02', label = locale('barricade'), icon = 'fa-solid fa-road-barrier' },
            },
        },
        {
            name = 'tactical',
            label = locale('obj_cat_tactical'),
            icon = 'fa-solid fa-shield-halved',
            objects = {
                { model = 'p_ld_stinger_s', label = locale('stinger'), icon = 'fa-solid fa-road-spikes' },
            },
        },
    },

    ---@field Items: table [inventory item -> spawned object model, keyed by item name = { model: string }]
    Items = {
        ['roadcone'] = { model = 'prop_roadcone02a' },
        ['barrier'] = { model = 'prop_barrier_work05' },
        ['consign'] = { model = 'prop_consign_01a' },
    },

    ---@field SpikeStrip: table [spike strip settings - { enabled: boolean, model: string, deployAnim: { dict, anim, duration } }]
    SpikeStrip = {
        enabled = true,
        model = 'p_ld_stinger_s',
        deployAnim = { dict = 'weapons@projectile@', anim = 'throw_l_fb_stand', duration = 500 },
    },

    ---@field Trunk: table [vehicle trunk gear storage settings]
    Trunk = {
        ---@field enabled: boolean [enable taking/storing gear from emergency vehicle trunks]
        enabled = true,
        ---@field requireOpenTrunk: boolean [require the boot (door index 5) to be open before interacting]
        requireOpenTrunk = true,
        ---@field interactDistance: number [max distance (metres) to interact with a trunk]
        interactDistance = 2.5,
        ---@field maxHold: number [max amount of each item an officer may carry from a trunk]
        maxHold = 1,
        ---@field anim: table [take/store animation - { dict: string, anim: string, duration: number }]
        anim = { dict = 'random@domestic', anim = 'pickup_low', duration = 1000 },
        ---@field vehicles: table [items per vehicle model, keyed by model = { item, label, icon }[]]
        vehicles = {
            ['police'] = {
                { item = 'spikestrip',  label = locale('trunk_spikestrip'), icon = 'fa-solid fa-road-spikes' },
                { item = 'wheel_clamp', label = locale('trunk_wheel_clamp'), icon = 'fa-solid fa-lock' },
                { item = 'roadcone', label = locale('roadcone'), icon = 'fa-solid fa-cone-striped' },
                { item = 'barrier', label = locale('barrier'), icon = 'fa-solid fa-road-barrier' },
                { item = 'consign', label = locale('consign'), icon = 'fa-solid fa-signs-post' },
            },
            ['police2'] = {
                { item = 'spikestrip', label = locale('trunk_spikestrip'), icon = 'fa-solid fa-road-spikes' },
            },
            ['police3'] = {
                { item = 'spikestrip', label = locale('trunk_spikestrip'), icon = 'fa-solid fa-road-spikes' },
            },
        },
    },

    ---@field Shield: table [ballistic shield settings - { enabled: boolean, defaultModel: string, boneIndex: number, offset: {x,y,z}, rotation: {x,y,z} }]
    Shield = {
        enabled = true,
        defaultModel = 'prop_ballistic_shield',
        boneIndex = 45509,
        offset = { x = 0.35, y = 0.05, z = -0.1 },
        rotation = { x = 300.0, y = 180.0, z = 60.0 },
    },

    ---@field onPlace: function [CLIENT - called when a player places an object - (model: string, coords: vector3)]
    onPlace = function(model, coords) end,

    ---@field onRemove: function [CLIENT - called when a player removes an object - (model: string)]
    onRemove = function(model) end,
}
