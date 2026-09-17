CMElectrician = CMElectrician or {}

CMElectrician.Config = {
    Debug = false,

    interactKey = 38, -- E / INPUT_CONTEXT
    interactKeyLabel = 'E',

    JobTitle = 'Electrician',

    Description = 'Report to the power plant switchboard to start troubleshooting. '
        .. 'Repairing panels builds your skill -- at level 2 you can rent a service '
        .. 'truck and repair deposit plates around the city, and at level 3 you will '
        .. 'be dispatched to fix city-wide power outages for a large payout.',

    Requirements = {
        'No licence required',
        'Government-inspected job site',
        'Payroll paid directly in cash',
    },

    Employment = {
        coords = vector3(718.720886, 152.386810, 80.739258),
        interactDistance = 1.4,
    },

    -- NPC stationed at the switchboard (same spot as Employment.coords) who
    -- handles job sign-up/resignation and service-truck rental through
    -- cm-ui's shared interact prompt + cinematic dialogue, the same
    -- components cm-license/cm-police use for their own job NPCs.
    NPC = {
        model = 's_m_y_construct_01',
        coords = vector4(718.720886, 152.386810, 80.739258, 250.0),
        name = 'Frank Delgado',
        role = 'Chief Electrician',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        interactDistance = 3.0,
    },

    -- Level-1 electricians only work the switchboard panels around the power
    -- plant, so wandering this far from Employment.coords auto-resigns them.
    -- Level 2+ roam the city on purpose (deposit plates, outages) and are not leashed.
    JobLeashRadius = 130.0,

    Blip = {
        enabled = true,
        sprite = 354,
        color = 26,
        scale = 1.05,
        shortRange = true,
        name = 'Electrician',
    },

    -- Tall "destination beacon" for the active random task, visible from far
    -- away: a thin vertical beam topped with a downward chevron (marker type 2,
    -- "Chevron Up x1", rotated 180 on Y) and a floating DESTINATION/distance
    -- label, similar to a GPS waypoint marker.
    DestinationBeacon = {
        height = 5.0,
        beamWidth = 0.35,
        beamAlpha = 110,
        chevronType = 2,
        chevronScale = 1.05,
        color = { r = 255, g = 201, b = 77 },
        label = 'DESTINATION',
    },

    -- Map blip for the single active random task. Sprite 402 is "radar_repair",
    -- the standard wrench/mechanic icon. Long-range blips automatically get
    -- GTA's native short edge-of-radar arrow pointing toward them when
    -- off-screen -- a small, modern GPS-style indicator, no long route line.
    TaskBlip = {
        panel = { sprite = 402, color = 5, scale = 0.65, label = 'Repair Panel' },
        plate = { sprite = 402, color = 5, scale = 0.65, label = 'Repair Deposit Plate' },
    },

    -- Component overrides applied over the player's current outfit while on
    -- duty, then reverted on resignation. Indices follow SetPedComponentVariation
    -- (8 = undershirt, 11 = torso/jacket, 3 = arms, 4 = pants, 6 = shoes).
    Uniform = {
        male = {
            [8]  = { drawable = 0,   texture = 0 },
            [11] = { drawable = 122, texture = 0 },
            [3]  = { drawable = 1,   texture = 0 },
            [4]  = { drawable = 5,   texture = 0 },
        },
        female = {
            [8]  = { drawable = 15, texture = 0 },
            [11] = { drawable = 4,  texture = 14 },
            [3]  = { drawable = 4,  texture = 0 },
            [4]  = { drawable = 25, texture = 1 },
            [6]  = { drawable = 16, texture = 4 },
        },
    },

    -- Rented from the switchboard NPC's dialogue once unlockLevel is
    -- reached (client/npc.lua) rather than a separate walk-up point.
    RentVehicle = {
        model = 'utillitruck3',
        spawnCoords = vector4(667.872559, 187.832977, 92.719360, 337.322845),
        unlockLevel = 2,
        cost = 500,
    },

    LevelUp = {
        panelsForLevel2 = 50,
        platesForLevel3 = 500,
    },

    Earnings = {
        perPanel = 30,
        perPlate = 300,
        perOutageFix = 1000,
    },

    Hold = {
        panelMs = 3000,
        plateMs = 3000,
        outageMs = 15000,
    },

    -- How many random panel/deposit-plate targets are active at once, so
    -- players have a choice of which to head to instead of one forced route.
    -- Replaced one-for-one as each is repaired.
    TaskCount = {
        panels = 3,
        plates = 2,
    },

    -- Chance (0-1) that a hold gets interrupted by a shock partway through --
    -- the repair fails, the player takes a little damage and staggers, and
    -- they have to start over. Higher-voltage tasks are riskier.
    ShockChance = {
        panel = 0.08,
        plate = 0.10,
        outage = 0.15,
    },

    Security = {
        panelDistance = 2.0,
        plateDistance = 2.0,
        outageDistance = 3.0,
        employmentDistance = 3.0,
        actionCooldownMs = 900,
    },

    PowerOutage = {
        -- One random fault location per outage (never the same one twice in a
        -- row), picked the same way panels/plates pick their random target.
        -- The main relay plus a spread of street ATM power boxes across the map.
        locations = {
            vector3(781.239563, 1274.835205, 361.271729),  -- Power plant relay
            vector3(49.4187, 2778.793, 58.043),             -- Paleto Bay ATM feed
            vector3(1039.958, 2671.134, 39.550),            -- Harmony ATM feed
            vector3(2539.685, 2594.192, 37.944),            -- Grand Senora ATM feed
            vector3(-2554.996, 2334.40, 33.078),            -- Chumash ATM feed
            vector3(-1437.622, -276.747, 46.207),           -- Rockford Hills ATM feed
            vector3(-724.619, -935.1631, 19.213),           -- Pillbox ATM feed
            vector3(265.648, -1261.309, 29.292),            -- Strawberry ATM feed
            vector3(819.653, -1028.846, 26.403),            -- La Mesa ATM feed
            vector3(1181.381, -330.847, 69.316),            -- El Burro Heights ATM feed
            vector3(620.843, 268.100, 103.089),             -- East Vinewood ATM feed
            vector3(176.631, -1562.025, 29.263),            -- Davis ATM feed
        },
        minWaitMs = 120000,   -- 2 minutes
        maxWaitMs = 300000,   -- 5 minutes
        soundEffect = true,
        unlockLevel = 3,
        -- If no electrician fixes it in time, the utility company resolves it
        -- for free (no payout) and the next outage gets scheduled normally,
        -- so a fault never sits unattended forever when nobody is available.
        autoFixMinutes = 10,

        -- Radius (client-side blackout hysteresis + server-side "you're in
        -- the area" notification) around the fault. Kept in sync between the
        -- two so the notification a nearby non-electrician gets lines up
        -- with when they'd actually see the lights go out.
        blackoutEnterRadius = 40.0,
        blackoutExitRadius = 60.0,
    },

    -- Switchboard panels around the power plant. Repairing these is the level-1 task.
    Panels = {
        vector3(696.646179, 149.221985, 80.941406),
        vector3(693.560425, 150.221985, 80.941406),
        vector3(690.672546, 151.221985, 80.941406),
        vector3(695.646179, 146.221985, 80.941406),
        vector3(692.560425, 147.221985, 80.941406),
        vector3(689.672546, 148.221985, 80.941406),
        vector3(711.230774, 128.136261, 80.890869),
        vector3(709.411011, 123.098900, 81.059326),
        vector3(704.452759, 109.568229, 80.924561),
        vector3(701.406616, 110.571426, 80.924561),
        vector3(707.459351, 108.356041, 80.924561),
        vector3(706.654968, 106.008797, 81.059326),
        vector3(703.674744, 107.116486, 81.059326),
        vector3(700.615417, 108.250549, 81.059326),
        vector3(698.281311, 163.846161, 81.109863),
        vector3(700.074707, 168.764832, 80.941406),
        vector3(682.549438, 165.138458, 81.093018),
        vector3(679.503296, 166.140656, 81.093018),
        vector3(676.470337, 167.261536, 81.093018),
        vector3(675.652771, 164.808792, 80.924561),
        vector3(678.725281, 163.753845, 80.924561),
        vector3(681.718689, 162.738464, 80.924561),
        vector3(673.898926, 150.079132, 81.076172),
        vector3(672.052734, 145.200012, 80.924561),
        vector3(684.672546, 127.859344, 80.941406),
        vector3(682.931885, 122.901100, 81.109863),
        vector3(666.342834, 121.753845, 80.907715),
        vector3(663.296692, 122.795609, 80.907715),
        vector3(660.290100, 123.942856, 80.907715),
        vector3(661.081299, 126.316483, 81.042480),
        vector3(664.180237, 125.274727, 80.907715),
        vector3(667.160461, 124.127472, 81.076172),
        vector3(681.204407, 108.145058, 80.907715),
        vector3(678.105469, 109.160439, 80.907715),
        vector3(675.151672, 110.294502, 80.907715),
        vector3(674.373657, 107.802200, 81.042480),
        vector3(677.419800, 106.707695, 80.907715),
        vector3(680.492310, 105.731873, 81.076172),
    },

    -- City deposit plates. Level-2 task, reachable with the rented service truck.
    Plates = {
        vector3(2137.740723, 1949.551636, 93.781006),
        vector3(1861.213135, -1104.764893, 84.260864),
        vector3(1111.358276, -2496.567139, 33.357544),
        vector3(371.525269, -2487.402100, 6.077637),
        vector3(-363.098907, -2161.740723, 10.307007),
    },
}
