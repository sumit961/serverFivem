CMRecycling = CMRecycling or {}

CMRecycling.Config = {
    Debug = false,

    JobTitle = 'Rogers Salvage & Recycling Specialist',
    Description = 'Collect industrial scrap and recyclable materials across the city, then sort and process them at the central facility.',

    InteractKey = 38, -- E (INPUT_CONTEXT)
    InteractKeyLabel = 'E',

    -- Central Processing Facility (Rogers Salvage & Scrap - Dutch London St / La Puerta)
    Facility = {
        name = 'Rogers Salvage & Recycling Center',
        supervisor = {
            model = 's_m_m_dockwork_01',
            coords = vector4(-433.80, -1726.50, 19.78, 120.0),
            name = 'Frank Kovac',
            role = 'Salvage Operations Supervisor',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            interactDistance = 2.8,
        },
        truckSpawns = {
            vector4(-440.50, -1715.20, 19.40, 140.0),
            vector4(-448.20, -1708.50, 19.40, 140.0),
        },
        unloadBay = {
            coords = vector3(-445.00, -1700.00, 19.40),
            radius = 8.0,
            label = 'Bulk Salvage Unloading Bay',
        },
        sortingStation = {
            coords = vector3(-425.20, -1710.80, 19.80),
            radius = 2.5,
            label = 'Material Separator & Sorting Table',
            processDurationMs = 7000, -- 7 second sorting mini-cycle
        },
    },

    Vehicle = {
        model = 'bison',
        label = 'Salvage Utility Truck',
        truckBedOffset = vector3(0.0, -2.4, 0.0), -- Rear truck bed offset relative to vehicle center
    },

    Blip = {
        facility = {
            sprite = 365, -- Recycling / salvage badge
            color = 25,  -- Dark green / teal
            scale = 0.85,
            name = 'Rogers Salvage & Recycling',
        },
        pickup = {
            sprite = 1,   -- Destination circle
            color = 25,  -- Green
            scale = 0.70,
            name = 'Salvage Pickup Point',
        },
        unload = {
            sprite = 365,
            color = 5,    -- Yellow
            scale = 0.85,
            name = 'Salvage Unload Bay',
        },
        sorting = {
            sprite = 402, -- Gear / processing icon
            color = 5,
            scale = 0.80,
            name = 'Material Sorting Station',
        },
    },

    Beacon = {
        color = { r = 0, g = 229, b = 255 }, -- CM Cyan
        height = 3.5,
        beamWidth = 0.25,
        beamAlpha = 120,
    },

    -- Capacity & Cycle Settings
    Capacity = {
        totalStops = 5,
        bundlesPerStop = 2,
        maxBundles = 10,
    },

    -- =========================================================================
    -- Total Economic Value Accounting (CM_ECONOMY_STANDARD.md & CM_ECONOMY_AUDIT.md)
    -- Target Activity Band: Beginner Legal ($50,000 - $62,500 / hour)
    -- Cycle Time: 5 stops * 60s drive + 30s collect = 450s + 60s return + 30s sort = 540s (9.0 min)
    -- Expected Completions per Hour: 3,600s / 540s = 6.67 cycles / hr
    --
    -- Material Economics:
    --   Trace of 'metal_scrap' and 'plastic' across the repository confirms NO vendor
    --   sell paths, shop prices, or pawn values currently exist in the codebase.
    --   Per requirements: if material value cannot be established from current data/APIs,
    --   we must not invent a value. Material yield is therefore made configurable via
    --   'materialsEnabled' and safely disabled by default until an authoritative economy
    --   trade/sale valuation is established.
    --
    -- Calculation:
    --   When materialsEnabled = false (Default):
    --     Cash per stop: $1,200 * 5 = $6,000
    --     Sorting & processing bonus: $2,400
    --     Total Cash per cycle: $8,400
    --     Hourly Economic Value: 6.67 * $8,400 = $56,028 / hr (fits Beginner Legal 50k-62.5k)
    --   When materialsEnabled = true:
    --     Material yield: 2x 'metal_scrap' + 2x 'plastic'
    --     Cash subsidy adjusts via (baseTotal - estimatedMaterialValue) to strictly preserve
    --     total economic value within the $50,000 - $62,500 / hr band.
    -- =========================================================================
    Earnings = {
        perStop = 1200,
        processingBonus = 2400,

        -- Configurable material yield: disabled until official trade/sale values exist
        materialsEnabled = false,
        estimatedMaterialValuePerCycle = 0,

        materials = {
            { item = 'metal_scrap', amount = 2, label = 'Metal Scrap' },
            { item = 'plastic', amount = 2, label = 'Plastic' },
        },
    },

    -- Explicit Batch Lifecycle States for Safe Retries
    BatchState = {
        Ready = 'ready',                         -- Unloaded at facility hopper; awaiting sorting
        MaterialsGranted = 'materials_granted',   -- Inventory materials added (or skipped); pending payroll
        PayrollAccepted = 'payroll_accepted',     -- Payday confirmed pending cash credit
        Completed = 'completed',                 -- Cycle finished; progression awarded; cleared
    },

    -- Concrete Salvage Pickup Route (5 verified industrial & commercial salvage locations)
    Route = {
        {
            id = 1,
            label = 'Port Logistics Scrap Compound',
            material = 'Machinery & Shipping Brackets',
            truckCoords = vector3(155.40, -2200.20, 6.20),
            salvageCoords = vector3(151.20, -2204.50, 6.20),
        },
        {
            id = 2,
            label = 'Banning Metal Works Alley',
            material = 'Heavy Plate & Pipe Scrap',
            truckCoords = vector3(808.20, -2068.50, 29.40),
            salvageCoords = vector3(812.40, -2072.10, 29.40),
        },
        {
            id = 3,
            label = 'Cypress Flats Salvage Yard',
            material = 'Industrial Conduit & Frame Offcuts',
            truckCoords = vector3(936.50, -1528.20, 30.80),
            salvageCoords = vector3(940.80, -1532.50, 30.80),
        },
        {
            id = 4,
            label = 'Murrieta Heights Infrastructure Point',
            material = 'Insulated Wiring & Transformer Parts',
            truckCoords = vector3(1206.20, -1386.40, 35.40),
            salvageCoords = vector3(1210.50, -1390.20, 35.40),
        },
        {
            id = 5,
            label = 'Elysian Island Shipbreaking Dock',
            material = 'Marine Polymers & Hull Scrap',
            truckCoords = vector3(324.50, -2691.20, 6.00),
            salvageCoords = vector3(328.60, -2695.40, 6.00),
        },
    },

    -- Security, Distance Gates & Timings
    Security = {
        salvageDistance = 3.2,     -- Max distance from player to salvage pile
        truckBedDistance = 3.8,    -- Max distance from player to truck bed
        truckMaxDistance = 45.0,   -- Max distance between player and truck during collection
        facilityUnloadDistance = 8.5,
        sortingStationDistance = 3.0,
        supervisorDistance = 3.2,
        actionCooldownMs = 1200,   -- Rate limiting debounce
    },

    -- Animations & Props
    Anim = {
        carry = {
            dict = 'anim@heists@box_carry@',
            clip = 'idle',
        },
        salvage = {
            dict = 'mini@repair',
            clip = 'fixing_a_ped',
            duration = 2000,
        },
        sort = {
            dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
            clip = 'machinic_loop_mechandplayer',
        },
        prop = 'prop_cs_package_01',
        bone = 60309, -- PH_L_Hand
        offset = vector3(0.08, 0.08, 0.0),
        rotation = vector3(0.0, 90.0, 0.0),
    },
}

