while not Config do Citizen.Wait(1) end

-- All location data (coords, cells, NPCs, etc.) lives in maps/prisons/<mapName>.lua
-- Set the map name in config/shared.lua → Config.PrisonMap
Config.Prison = {
    ---@field Enabled: boolean [master toggle for the prison feature]
    Enabled = true,

    ---@field Jobs: table [jobs that can manage the prison (send to jail, management) - { jobName = minGrade }]
    Jobs = {
        ['police'] = 0,
        -- ['sheriff'] = 0,
    },

    ---@field Commands: table [admin/staff chat commands. Each entry can be toggled on/off and renamed. `restricted` is the ACE permission needed (set to false to allow everyone, or e.g. 'group.admin').]
    Commands = {
        ---@field enabled: boolean [master switch for every command below]
        enabled = true,

        ---@field restricted: string|boolean [ACE permission required for all commands ('group.admin', 'group.mod', ... or false for no restriction)]
        restricted = 'group.admin',

        ---@field jail: table [/jail [id] [type] [length] [reason] - type is one of 'prison' | 'community' | 'life' (length is in minutes, ignored for 'life')]
        jail = { enabled = true, name = 'jail' },

        ---@field unjail: table [/unjail [id] - release the player with the given server id]
        unjail = { enabled = true, name = 'unjail' },

        ---@field jailtime: table [/jailtime [id] - show the remaining sentence for a player (omit id to check yourself)]
        jailtime = { enabled = true, name = 'jailtime' },

        ---@field prisoners: table [/prisoners - list every currently jailed player]
        prisoners = { enabled = true, name = 'prisoners' },
    },

    ---@field Cells: table [cell assignment - { assignAutomatically: boolean, maxPerCell: number }]
    Cells = {
        assignAutomatically = true,
        maxPerCell = 1,
    },

    ---@field CellStash: table [hidden per-cell stash inmates can use]
    CellStash = {
        ---@field enabled: boolean [enable cell stashes]
        enabled = true,
        ---@field slots: number [item slots in the stash]
        slots = 2,
        ---@field maxWeight: number [max stash weight in grams]
        maxWeight = 8000,
        ---@field label: string [stash display name]
        label = 'Hidden Stash',
        ---@field icon: string [target icon]
        icon = 'fa-solid fa-box-archive',
        ---@field offset: vector3 [interaction point offset from the cell anchor coords]
        offset = vec3(0.25, 1.1, -0.4),
        ---@field radius: number [interaction zone radius in metres]
        radius = 0.5,
    },

    ---@field Solitary: table [solitary confinement - { enabled: boolean, maxTime: number(minutes) }]
    Solitary = {
        enabled = true,
        maxTime = 60,
    },

    ---@field Mugshot: table [intake mugshot scene - { enabled: boolean, outfit: table|nil, duration: number(ms) }]
    Mugshot = {
        enabled = true,
        outfit = nil,
        duration = 5000,
    },

    ---@field Commissary: table [legal prison shop - { enabled: boolean, items: { name, price, description? }[] } - label is fetched from the inventory via p_bridge, description is a fallback if the inventory has none]
    Commissary = {
        enabled = true,
        items = {
            { name = 'burger', price = 5, description = 'Basic food' },
            { name = 'water', price = 3, description = 'Stay hydrated' },
            { name = 'bandage', price = 15, description = 'Basic medical' },
            { name = 'cigarette', price = 25, description = 'Smoke break' },
            { name = 'phone', price = 100, description = 'One-time use phone' },
        },
    },

    ---@field IllegalShop: table [black-market prison shop - { enabled: boolean, items: { name, price, description? }[] } - label is fetched from the inventory via p_bridge, description is a fallback if the inventory has none]
    IllegalShop = {
        enabled = true,
        items = {
            { name = 'lockpick', price = 200, description = 'Might come in handy' },
            { name = 'shiv', price = 150, description = 'Improvised weapon' },
            { name = 'radio', price = 300, description = 'Communication device' },
        },
    },

    ---@field PrisonJobs: table [inmate work jobs (task locations come from the map file)]
    PrisonJobs = {
        ---@field enabled: boolean [enable inmate jobs]
        enabled = true,
        ---@field creatorAccess: table [job names allowed to edit job locations - list of strings]
        creatorAccess = { 'police', 'sheriff' },
        ---@field stopsPerJob: number [number of randomised task stops per shift]
        stopsPerJob = 5,
        ---@field minigame: table [per-job minigame settings]
        minigame = {
            ---@field perJob: table [built-in minigame per job id - 'scrub' | 'wash' | 'rhythm']
            perJob = {
                cleaning = 'scrub',
                laundry  = 'wash',
                kitchen  = 'rhythm',
            },
            ---@field default: string [fallback minigame when a job id is not listed]
            default = 'scrub',
            ---@field useCustom: boolean [if true call customRun instead of the built-in minigames]
            useCustom = false,
            ---@field customRun: function [custom minigame, must return a boolean success - (jobDef: table)]
            customRun = function(jobDef)
                return true
            end,
        },
        ---@field dirtProps: table [decorative dirt props scattered at the active task point]
        dirtProps = {
            ---@field enabled: boolean [enable dirt props]
            enabled = true,
            ---@field jobs: table [job ids that spawn dirt - { jobId = boolean }]
            jobs = { cleaning = true },
            ---@field models: table [prop models scattered at random - list of strings]
            models = {
                'prop_rub_binbag_03',
                'prop_rub_binbag_01',
                'prop_cardbordbox_01',
                'prop_rub_carrier_01',
                'prop_paper_bag_01',
            },
            ---@field count: number [props per task point]
            count = 5,
            ---@field radius: number [scatter radius (metres) around the point]
            radius = 1.6,
        },
        ---@field stopBlip: table [current task blip - { sprite: number, color: number, scale: number, label: string }]
        stopBlip = { sprite = 280, color = 5, scale = 0.9, label = 'Prison Task' },
        ---@field stopMarker: table [marker drawn above the current task - { enabled, type, size, height, color: {r,g,b,a}, drawDistance }]
        stopMarker = {
            enabled = true,
            type = 2,
            size = 0.35,
            height = 1.4,
            color = { r = 255, g = 170, b = 40, a = 200 },
            drawDistance = 60.0,
        },
        ---@field defaultJobs: table [available inmate jobs - { id, label, description, payment, duration, timeReduction, animation: { dict, clip } }[]]
        defaultJobs = {
            {
                id = 'cleaning',
                label = 'Cleaning Duty',
                description = 'Clean the prison facilities',
                payment = 10,
                duration = 30,
                timeReduction = 5,
                animation = { dict = 'anim@amb@drug_field_workers@rake@male_a@base', clip = 'base' },
            },
            {
                id = 'laundry',
                label = 'Laundry Service',
                description = 'Wash and fold prison uniforms',
                payment = 15,
                duration = 45,
                timeReduction = 8,
                animation = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
            },
            {
                id = 'kitchen',
                label = 'Kitchen Duty',
                description = 'Help prepare meals',
                payment = 12,
                duration = 40,
                timeReduction = 6,
                animation = { dict = 'mini@repair', clip = 'fixing_a_player' },
            },
        },
    },

    ---@field PrisonLife: table [NPC prison life - { enabled: boolean, trading: { enabled: boolean, distance: number } }]
    PrisonLife = {
        enabled = true,
        trading = {
            enabled = true,
            distance = 3.0,
        },
    },

    ---@field CommunityService: table [community service flow (locations come from the map file)]
    CommunityService = {
        ---@field enabled: boolean [enable community service]
        enabled = true,
        ---@field isolatePlayer: boolean [put the player in their own routing bucket so they cannot see or interact with other players]
        isolatePlayer = true,
        ---@field bucketBase: number [base value for the per-player routing bucket (bucket = base + server id)]
        bucketBase = 10000,
        ---@field trashProp: string [prop at each task point the player interacts with]
        trashProp = 'prop_rub_binbag_03',
        ---@field bagProp: string [bag prop attached to the player's hand after collecting]
        bagProp = 'prop_cs_rub_binbag_01',
        ---@field dumpsterProp: string [dumpster prop spawned at the throw point]
        dumpsterProp = 'prop_dumpster_01a',
        ---@field activePiles: number [how many trash piles are active at once]
        activePiles = 3,
        ---@field scatter: number [random scatter (metres) applied to each pile]
        scatter = 1.2,
        ---@field requiredPickups: number [trash items to grab in the minigame]
        requiredPickups = 6,
        ---@field minigameTime: number [seconds allowed for the minigame]
        minigameTime = 16,
        ---@field pickupAnim: table [pickup animation - { dict: string, clip: string }]
        pickupAnim = { dict = 'pickup_object', clip = 'pickup_low' },
        ---@field pickupDuration: number [pickup progress bar duration in milliseconds]
        pickupDuration = 4000,
        ---@field carryAnim: table [carry animation - { dict: string, clip: string }]
        carryAnim  = { dict = 'anim@heists@box_carry@', clip = 'idle' },
        ---@field throwAnim: table [throw-away animation - { dict: string, clip: string }]
        throwAnim  = { dict = 'pickup_object', clip = 'putdown_low' },
        ---@field throwDuration: number [throw progress bar duration in milliseconds]
        throwDuration = 2500,
        ---@field respawnDelay: number [how long (ms) before a cleaned pile respawns]
        respawnDelay = 4000,
        ---@field tasks: table [community service task definitions - { id, label, animation: { dict, clip }, duration }[]]
        tasks = {
            {
                id = 'trash_pickup',
                label = 'Trash Pickup',
                animation = { dict = 'anim@amb@drug_field_workers@rake@male_a@base', clip = 'base' },
                duration = 15,
            },
        },
        ---@field tasksPerMinute: number [how many tasks count toward the sentence per minute]
        tasksPerMinute = 2,
    },

    ---@field Minigames: table [global minigame settings - { enabled: boolean, useExternal: boolean, externalExport: function }]
    Minigames = {
        enabled = true,
        useExternal = false,
        externalExport = function()
            return true
        end,
    },

    ---@field OfficerTasks: table [guard duty tasks (patrol waypoints come from the map file)]
    OfficerTasks = {
        ---@field enabled: boolean [enable officer tasks]
        enabled = true,
        ---@field tasks: table [guard task definitions - { id, label, description, icon, duration: number(ms), animation: { dict, clip }|nil }[]]
        tasks = {
            {
                id = 'cell_inspection',
                label = 'Cell Inspection',
                description = 'Inspect cells for contraband',
                icon = 'fa-solid fa-magnifying-glass',
                duration = 15000,
                animation = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search' },
            },
            {
                id = 'patrol_route',
                label = 'Patrol Route',
                description = 'Walk the patrol route through the prison',
                icon = 'fa-solid fa-person-walking',
                duration = 0,
                animation = nil,
            },
        },
    },

    ---@field PrisonOutfit: table [clothing applied on intake (set to nil to skip) - { male: table, female: table } of component = drawable]
    PrisonOutfit = {
        male = {
            ['tshirt_1'] = 15,  ['tshirt_2'] = 0,
            ['torso_1'] = 146,  ['torso_2'] = 0,
            ['decals_1'] = 0,   ['decals_2'] = 0,
            ['arms'] = 1,
            ['pants_1'] = 98,   ['pants_2'] = 0,
            ['shoes_1'] = 35,   ['shoes_2'] = 0,
        },
        female = {
            ['tshirt_1'] = 15,  ['tshirt_2'] = 0,
            ['torso_1'] = 153,  ['torso_2'] = 0,
            ['decals_1'] = 0,   ['decals_2'] = 0,
            ['arms'] = 1,
            ['pants_1'] = 99,   ['pants_2'] = 0,
            ['shoes_1'] = 35,   ['shoes_2'] = 0,
        },
    },

    ---@field Sentence: table [sentence timing - { minTime: number, maxTime: number, timeUnit: string, tickRate: number(seconds per tick) }]
    Sentence = {
        minTime = 1,
        maxTime = 120,
        timeUnit = 'minutes',
        tickRate = 60,
    },

    ---@field onPlayerJailed: function [CLIENT - called when the player is jailed - (playerId: number, sentenceData: table)]
    onPlayerJailed = function(playerId, sentenceData)
    end,

    ---@field onPlayerReleased: function [CLIENT - called when the player is released - (playerId: number)]
    onPlayerReleased = function(playerId)
    end,

    ---@field onPlayerJailed_Server: function [SERVER - called when a player is jailed - (playerId: number, targetId: number, sentenceData: table)]
    onPlayerJailed_Server = function(playerId, targetId, sentenceData)
    end,

    ---@field onPlayerReleased_Server: function [SERVER - called when a player is released - (playerId: number)]
    onPlayerReleased_Server = function(playerId)
    end,

    ---@field onPlayerEscaped_Server: function [SERVER - called when a prisoner escapes (EscapeJail export) - wire your dispatch resource here - (playerId: number|nil, sentenceData: table)]
    onPlayerEscaped_Server = function(playerId, sentenceData)
    end,
}
