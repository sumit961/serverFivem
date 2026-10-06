CMGarbage = CMGarbage or {}

CMGarbage.Config = {
    Debug = false,

    JobTitle = 'Sanitation Worker',
    Description = 'Collect curbside residential rubbish across South Los Santos and return full loads to the depot tipping pit.',

    -- Controls / Keys
    InteractKey = 38, -- E (INPUT_CONTEXT)
    InteractKeyLabel = 'E',

    -- Central Sanitation Depot (Innocence Blvd / South Los Santos)
    Depot = {
        name = 'South Los Santos Sanitation Depot',
        -- Supervisor Foreman NPC stationed near the office container
        npc = {
            model = 's_m_y_garbage',
            coords = vector4(-321.75, -1545.92, 31.02, 268.5),
            name = 'Sal Moretti',
            role = 'Sanitation Supervisor',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            interactDistance = 2.8,
        },
        -- Truck spawn bays inside the depot yard
        truckSpawns = {
            vector4(-333.50, -1565.80, 30.90, 269.0),
            vector4(-333.50, -1571.20, 30.90, 269.0),
        },
        -- Tipping pit / industrial compactor hopper at the depot
        tippingPit = {
            coords = vector3(-347.12, -1558.34, 27.50),
            radius = 7.0,
            label = 'Depot Tipping Pit',
        },
    },

    -- Assigned vehicle model
    Vehicle = {
        model = 'trash',
        label = 'City Sanitation Truck',
        rearHopperOffset = vector3(0.0, -4.5, 0.0), -- Approximate rear hopper relative to vehicle center
    },

    -- Blip configuration
    Blip = {
        depot = {
            sprite = 318, -- Standard GTA V garbage truck icon
            color = 25,   -- Dark green
            scale = 0.85,
            name = 'Sanitation Depot',
        },
        stop = {
            sprite = 1,   -- Waypoint circle
            color = 5,    -- Yellow / amber
            scale = 0.70,
            name = 'Collection Stop',
        },
        tipping = {
            sprite = 318,
            color = 5,    -- Yellow / amber
            scale = 0.85,
            name = 'Depot Unload Pit',
        },
    },

    -- CM Design marker beacon (cyan)
    Beacon = {
        color = { r = 0, g = 229, b = 255 }, -- CM Cyan
        height = 3.5,
        beamWidth = 0.25,
        beamAlpha = 120,
    },

    -- Capacity & Route Settings
    Capacity = {
        maxBags = 16,     -- Truck capacity: 16 bags total
        bagsPerStop = 2,  -- Each residential stop yields 2 bags
        totalStops = 8,   -- 8 stops * 2 bags = 16 bags (100% full)
    },

    -- Economy: Grounded strictly in CM_ECONOMY_STANDARD.md
    -- Target: Beginner Legal Activity Band ($50,000 - $62,500 / hour)
    -- Route Cycle Time: ~8.33 minutes (~500s) = ~7.2 routes per hour
    -- $350 per bag * 16 bags = $5,600
    -- Depot route completion bonus = $2,200
    -- Total per route = $7,800
    -- 7.2 routes/hr * $7,800 = $56,160 / hr (exact fit in beginner legal band)
    Earnings = {
        perBag = 350,
        depotBonus = 2200,
    },

    -- Concrete Residential Route (South Los Santos: Strawberry / Davis / Rancho / Chamberlain Hills)
    -- Each stop specifies a street curbside stop for the truck and a sidewalk bin coordinate.
    Route = {
        {
            id = 1,
            label = 'Innocence Blvd Residential',
            truckCoords = vector3(-223.45, -1582.12, 31.85),
            binCoords = vector3(-226.50, -1586.20, 31.85),
            bagsRequired = 2,
        },
        {
            id = 2,
            label = 'Forum Drive Curbside',
            truckCoords = vector3(-144.15, -1645.78, 32.55),
            binCoords = vector3(-148.10, -1649.50, 32.55),
            bagsRequired = 2,
        },
        {
            id = 3,
            label = 'Carson Avenue Residences',
            truckCoords = vector3(89.25, -1742.60, 29.30),
            binCoords = vector3(85.80, -1747.20, 29.30),
            bagsRequired = 2,
        },
        {
            id = 4,
            label = 'Roy Lowenstein Blvd Houses',
            truckCoords = vector3(236.85, -1812.40, 26.85),
            binCoords = vector3(241.10, -1816.50, 26.85),
            bagsRequired = 2,
        },
        {
            id = 5,
            label = 'Dutch London Street Houses',
            truckCoords = vector3(355.20, -1965.10, 24.60),
            binCoords = vector3(359.80, -1968.70, 24.60),
            bagsRequired = 2,
        },
        {
            id = 6,
            label = 'Jamestown Street Curbside',
            truckCoords = vector3(448.60, -1865.30, 27.20),
            binCoords = vector3(453.20, -1862.00, 27.20),
            bagsRequired = 2,
        },
        {
            id = 7,
            label = 'Grove Street Residential Loop',
            truckCoords = vector3(112.50, -1960.80, 20.80),
            binCoords = vector3(116.80, -1964.50, 20.80),
            bagsRequired = 2,
        },
        {
            id = 8,
            label = 'Strawberry Avenue Residences',
            truckCoords = vector3(-102.30, -1774.50, 29.50),
            binCoords = vector3(-106.50, -1778.20, 29.50),
            bagsRequired = 2,
        },
    },

    -- Security, Distance Gates & Timings
    Security = {
        binDistance = 3.5,       -- Max distance from player to bin for pickup
        hopperDistance = 4.2,    -- Max distance from player to truck hopper for deposit
        truckMaxDistance = 45.0, -- Max distance from player to assigned truck during collection
        unloadDistance = 8.5,    -- Max distance from truck to depot tipping pit for unload
        foremanDistance = 3.2,   -- Max distance to supervisor NPC
        actionCooldownMs = 1200, -- Rate limit debounce between interactions
        unloadDurationMs = 8000, -- Duration of hydraulic truck tipping sequence
    },

    -- Animations & Props
    Anim = {
        pickup = {
            dict = 'anim@heists@narcotics@trash',
            clip = 'pickup',
            duration = 2400,
        },
        throw = {
            dict = 'anim@heists@narcotics@trash',
            clip = 'throw_rubbish_into_truck',
            duration = 2200,
        },
        prop = 'prop_cs_rub_binbag_01',
        bone = 28422, -- PH_R_Hand
        offset = vector3(0.0, 0.0, -0.05),
        rotation = vector3(0.0, 0.0, 0.0),
    },
}

