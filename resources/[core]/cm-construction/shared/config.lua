CMConstruction = CMConstruction or {}

CMConstruction.Config = {
    Debug = false,

    JobTitle = 'Municipal Infrastructure Specialist',
    Description = 'Inspect, maintain, and construct municipal roadworks, drainage vaults, steel framing, and electrical substations across Los Santos.',

    InteractKey = 38, -- E (INPUT_CONTEXT)
    InteractKeyLabel = 'E',

    -- Central Construction Site & Headquarters (Downtown Los Santos / Alta St)
    Depot = {
        name = 'Downtown Los Santos Construction Headquarters',
        superintendent = {
            model = 's_m_y_construct_01',
            coords = vector4(-156.45, -1004.80, 29.30, 0.0),
            name = 'Earle "Mac" McAllister',
            role = 'Site Superintendent',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            interactDistance = 3.0,
        },
        truckSpawns = {
            vector4(-174.50, -1003.20, 28.90, 250.0),
            vector4(-177.80, -998.50, 28.90, 250.0),
        },
        returnBay = {
            coords = vector3(-168.50, -1002.80, 29.00),
            radius = 12.0,
            label = 'Superintendent Inspection & Vehicle Return Bay',
        },
    },

    Vehicle = {
        model = 'bison',
        label = 'Municipal Construction Utility Truck',
    },

    Blip = {
        depot = {
            sprite = 357, -- Construction / crane icon
            color = 5,    -- Yellow
            scale = 0.85,
            name = 'Downtown Construction HQ',
        },
        stage = {
            sprite = 1,   -- Destination circle
            color = 5,    -- Yellow
            scale = 0.75,
            name = 'Construction Stage Waypoint',
        },
        depotReturn = {
            sprite = 357,
            color = 5,
            scale = 0.85,
            name = 'Site Office Inspection Bay',
        },
    },

    Beacon = {
        color = { r = 0, g = 229, b = 255 }, -- CM Cyan (#00e5ff)
        height = 3.5,
        beamWidth = 0.25,
        beamAlpha = 120,
    },

    Security = {
        stageInteractDistance = 4.5,
        depotReturnDistance = 14.0,
        superintendentDistance = 3.5,
        actionCooldownMs = 1500,
        minimumTransitTimeMs = 10000,
    },

    -- =========================================================================
    -- Economy Calibration (Approved CM Roadmap Economy Standard)
    -- Target Baseline: $37,500 per eligible gameplay hour.
    -- Cycle Time Accounting (includes setup, travel, inter-stage movements, animations, return):
    --   - Fixed Task Overhead: 126 seconds (2.10 min)
    --     * Order assignment & yard staging: 25s
    --     * 4 physical stage interactions & tool prep: 16s (4 x 4s)
    --     * 4 physical work animations (drilling, welding, hammering, survey): 30s
    --     * 3 inter-stage physical transitions: 30s (3 x 10s)
    --     * Return bay check-in & manifest sign-off: 25s
    --   - City Street Driving Speed: ~50 km/h utility truck cruising (~13.9 m/s).
    --
    -- Project Breakdown & Effective Hourly Rate:
    --   * Downtown Tower Scaffolding (100m on-site):
    --     Drive: 30s + Overhead: 126s = 156s (2.60 min) | 23.08 cycles/hr | Payout: $1,625 -> $37,500/hr
    --   * Carson Ave Roadway (950m x2 = 1.9 km):
    --     Drive: 136s + Overhead: 126s = 262s (4.37 min) | 13.74 cycles/hr | Payout: $2,730 -> $37,513/hr
    --   * East LS Substation (1,400m x2 = 2.8 km):
    --     Drive: 202s + Overhead: 126s = 328s (5.47 min) | 10.98 cycles/hr | Payout: $3,415 -> $37,495/hr
    --   * Del Perro Storm Drain (2,200m x2 = 4.4 km):
    --     Drive: 316s + Overhead: 126s = 442s (7.37 min) | 8.14 cycles/hr | Payout: $4,605 -> $37,505/hr
    -- =========================================================================
    Tasks = {
        {
            id = 'MUNI-CONST-STRUCTURAL',
            title = '[MUNICIPAL WORK] Downtown Tower Scaffolding & Steel Reinforcement',
            description = 'Reinforce ground-level support beams, weld tension gussets, and torque load-bearing bolts at the Downtown tower site.',
            destinationLabel = 'Downtown Construction Site Tower',
            cycleDurationSec = 156,
            payout = 1625, -- Full cycle: 156s (2.60 min) -> 23.08 cycles/hr @ $1,625 = $37,500/hr
            stages = {
                {
                    index = 1,
                    label = 'Ultrasonic Beam Stress Inspection',
                    coords = vector3(-123.50, -962.20, 29.35),
                    action = 'INSPECT STRUCTURAL GIRDERS',
                    scenario = 'WORLD_HUMAN_CLIPBOARD',
                    durationMs = 7000,
                    minDurationMs = 6000,
                },
                {
                    index = 2,
                    label = 'Weld Structural Steel Gusset',
                    coords = vector3(-118.80, -970.50, 29.35),
                    action = 'WELD TENSION GUSSET PLATE',
                    scenario = 'WORLD_HUMAN_WELDING',
                    durationMs = 9500,
                    minDurationMs = 8000,
                },
                {
                    index = 3,
                    label = 'Impact Torque High-Strength Bolts',
                    coords = vector3(-110.20, -978.80, 29.35),
                    action = 'TORQUE LOAD-BEARING BOLTS',
                    scenario = 'WORLD_HUMAN_HAMMERING',
                    durationMs = 8000,
                    minDurationMs = 6500,
                },
                {
                    index = 4,
                    label = 'Affix Municipal Inspection Signoff Tag',
                    coords = vector3(-105.40, -985.60, 29.35),
                    action = 'AFFIX SAFETY CERTIFICATION',
                    scenario = 'WORLD_HUMAN_STAND_MOBILE',
                    durationMs = 6000,
                    minDurationMs = 5000,
                },
            },
        },
        {
            id = 'MUNI-CONST-ROAD',
            title = '[MUNICIPAL WORK] South LS Roadway & Trench Resurfacing',
            description = 'Resurface damaged pavement sub-base, dig utility trench, and place traffic safety cones along Carson Ave.',
            destinationLabel = 'Carson Ave Infrastructure Site',
            cycleDurationSec = 262,
            payout = 2730, -- Full cycle: 262s (4.37 min) -> 13.74 cycles/hr @ $2,730 = $37,513/hr
            stages = {
                {
                    index = 1,
                    label = 'Survey & Laser Level Trench',
                    coords = vector3(-144.20, -1690.50, 29.80),
                    action = 'SURVEY ROADWAY DEFECTS',
                    scenario = 'WORLD_HUMAN_CLIPBOARD',
                    durationMs = 7000,
                    minDurationMs = 6000,
                },
                {
                    index = 2,
                    label = 'Pneumatic Concrete Breaker',
                    coords = vector3(-149.80, -1694.20, 29.70),
                    action = 'BREAK UP DAMAGED ASPHALT',
                    scenario = 'WORLD_HUMAN_CONST_DRILL',
                    durationMs = 9000,
                    minDurationMs = 7500,
                },
                {
                    index = 3,
                    label = 'Aggregate Base Pour & Compaction',
                    coords = vector3(-154.50, -1698.00, 29.60),
                    action = 'LEVEL & COMPACT AGGREGATE',
                    scenario = 'WORLD_HUMAN_HAMMERING',
                    durationMs = 8000,
                    minDurationMs = 6500,
                },
                {
                    index = 4,
                    label = 'Deploy Municipal Safety Perimeter',
                    coords = vector3(-158.80, -1701.50, 29.50),
                    action = 'PLACE SAFETY CONES & PERIMETER',
                    scenario = 'PROP_HUMAN_BUM_BIN',
                    durationMs = 6000,
                    minDurationMs = 5000,
                },
            },
        },
        {
            id = 'MUNI-CONST-ELECTRICAL',
            title = '[MUNICIPAL WORK] East LS Substation Conduit Overhaul',
            description = 'Trench underground duct banks, route heavy cable sleeves, bolt industrial junction housings, and certify grounding.',
            destinationLabel = 'Murrieta Oil Fields Substation',
            cycleDurationSec = 328,
            payout = 3415, -- Full cycle: 328s (5.47 min) -> 10.98 cycles/hr @ $3,415 = $37,495/hr
            stages = {
                {
                    index = 1,
                    label = 'Verify Zero-Energy & Lockout-Tagout',
                    coords = vector3(712.50, -2012.20, 29.40),
                    action = 'VERIFY DE-ENERGIZATION',
                    scenario = 'WORLD_HUMAN_CLIPBOARD',
                    durationMs = 7000,
                    minDurationMs = 6000,
                },
                {
                    index = 2,
                    label = 'Pneumatic Trench Breaker',
                    coords = vector3(718.80, -2018.50, 29.35),
                    action = 'BREAK CONDUIT TRENCH BED',
                    scenario = 'WORLD_HUMAN_CONST_DRILL',
                    durationMs = 9000,
                    minDurationMs = 7500,
                },
                {
                    index = 3,
                    label = 'Secure Underground Duct Bank Fittings',
                    coords = vector3(725.20, -2024.80, 29.30),
                    action = 'BOLT DUCT SLEEVE COUPLINGS',
                    scenario = 'WORLD_HUMAN_HAMMERING',
                    durationMs = 8000,
                    minDurationMs = 6500,
                },
                {
                    index = 4,
                    label = 'Seal Enclosure & Grounding Certification',
                    coords = vector3(730.50, -2030.20, 29.30),
                    action = 'WELD GROUNDING STRAP',
                    scenario = 'WORLD_HUMAN_WELDING',
                    durationMs = 7500,
                    minDurationMs = 6000,
                },
            },
        },
        {
            id = 'MUNI-CONST-WATERMAIN',
            title = '[MUNICIPAL WORK] Del Perro Storm Drain & Conduit Replacement',
            description = 'Excavate drainage vault access collar, weld sub-grade pipe flange, assemble main flow valve, and lock vault cover.',
            destinationLabel = 'Del Perro Storm Drain Vault',
            cycleDurationSec = 442,
            payout = 4605, -- Full cycle: 442s (7.37 min) -> 8.14 cycles/hr @ $4,605 = $37,505/hr
            stages = {
                {
                    index = 1,
                    label = 'Excavate Vault Access & Clear Sediment',
                    coords = vector3(-1442.20, -685.50, 26.25),
                    action = 'CHIP SEDIMENT & DEBRIS',
                    scenario = 'WORLD_HUMAN_CONST_DRILL',
                    durationMs = 8500,
                    minDurationMs = 7000,
                },
                {
                    index = 2,
                    label = 'Weld High-Pressure Drainage Flange',
                    coords = vector3(-1446.80, -689.20, 26.25),
                    action = 'WELD SUB-GRADE FLANGE JOINT',
                    scenario = 'WORLD_HUMAN_WELDING',
                    durationMs = 9000,
                    minDurationMs = 7500,
                },
                {
                    index = 3,
                    label = 'Torque Vault Valve Assembly',
                    coords = vector3(-1451.50, -693.80, 26.25),
                    action = 'INSTALL & TORQUE MAIN VALVE',
                    scenario = 'WORLD_HUMAN_HAMMERING',
                    durationMs = 8000,
                    minDurationMs = 6500,
                },
                {
                    index = 4,
                    label = 'Pressure Gauge Calibration & Vault Lock',
                    coords = vector3(-1455.20, -698.50, 26.25),
                    action = 'VERIFY PRESSURE & SEAL COVER',
                    scenario = 'WORLD_HUMAN_CLIPBOARD',
                    durationMs = 6500,
                    minDurationMs = 5000,
                },
            },
        },
    },
}

