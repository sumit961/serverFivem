CMWarehouse = CMWarehouse or {}

CMWarehouse.Config = {
    Debug = false,

    JobTitle = 'Port Logistics & Warehouse Specialist',
    Description = 'Physically receive, barcode sort, pallet stage, and dispatch municipal and commercial freight cargo across Port of Los Santos Terminal Warehouse.',

    InteractKey = 38, -- E (INPUT_CONTEXT)
    InteractKeyLabel = 'E',

    -- Central Logistics Facility (Port of Los Santos / Elysian Island Terminal)
    Facility = {
        name = 'Port of Los Santos Terminal Logistics Warehouse',
        supervisor = {
            model = 's_m_m_dockwork_01',
            coords = vector4(152.20, -3105.40, 5.90, 355.0),
            name = 'Vince "Cargo" Calderon',
            role = 'Port Logistics Supervisor',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            interactDistance = 3.0,
        },
        vehicleSpawns = {
            vector4(140.50, -3100.80, 5.90, 90.0),
            vector4(140.50, -3108.20, 5.90, 90.0),
        },
        returnBay = {
            coords = vector3(146.50, -3104.50, 5.90),
            radius = 12.0,
            label = 'Supervisor Manifest Sign-Off & Equipment Return Bay',
        },
    },

    Vehicle = {
        model = 'forklift',
        label = 'Terminal Logistics Forklift',
    },

    Blip = {
        facility = {
            sprite = 473, -- Warehouse / shipping icon
            color = 5,    -- Yellow
            scale = 0.85,
            name = 'Port Logistics Warehouse',
        },
        stage = {
            sprite = 1,   -- Waypoint circle
            color = 5,    -- Yellow
            scale = 0.75,
            name = 'Cargo Work Station',
        },
        depotReturn = {
            sprite = 473,
            color = 5,
            scale = 0.85,
            name = 'Manifest Sign-Off Bay',
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
        supervisorDistance = 3.5,
        actionCooldownMs = 1500,
    },

    Economy = {
        targetHourly = 37500, -- Approved CM Roadmap economy target: $37,500/hr ($625/min, ~$10.42/sec)
        baselineRatePerMin = 625,
        referenceModel = 'Yard setup + 4 physical handling stages + forklift transit + manifest sign-off',
    },

    -- =========================================================================
    -- Always-Available Municipal Logistical Shifts (City / Port Work)
    -- Repeatable public cargo manifests ensuring workers always have physical
    -- freight handling available even when no private player orders are placed.
    -- Grounded in CM Economy Standard ($37,500 / hour baseline target).
    --
    -- Cycle Time Accounting Breakdown:
    --   - Supervisor intake & forklift mounting: ~25 sec
    --   - Transit to Receiving Dock: ~10 sec
    --   - Receiving Inspection: ~7-7.5s animation + 2s prompt = ~9-9.5 sec
    --   - Transit to Sorting Conveyor: ~8 sec
    --   - Barcode Scanning & Sorting: ~8-9s animation + 2s prompt = ~10-11 sec
    --   - Transit to Pallet Staging Skid: ~8 sec
    --   - Pallet Staging / Banding: ~8-8.5s animation + 2s prompt = ~10-10.5 sec
    --   - Outbound Forklift Transport: ~15 sec
    --   - Outbound Bay Staging / Logging: ~6-6.5s animation + 2s prompt = ~8-8.5 sec
    --   - Transit to Return Bay & Supervisor Sign-Off: ~31 sec (16s drive/walk + 15s turn-in)
    --   - Total Cycle Duration: 138 - 151 sec (~2.30 - 2.51 min)
    --   - Effective hourly throughput: ~23.9 - 26.1 cycles/hr @ $1,440 - $1,570 = ~$37,500/hr
    -- =========================================================================
    Shifts = {
        {
            id = 'MUNI-WH-CONSUMER',
            title = '[PORT LOGISTICS] Municipal Consumer & Dry Goods Manifest',
            description = 'Process inbound port container of municipal dry goods and packaged consumer cargo for regional community centers.',
            cargoType = 'Municipal Dry Goods',
            cycleDurationSec = 138,
            -- Cycle calculation: 25s setup + 10s transit + 9s receiving + 8s transit + 10s sorting + 8s transit + 10s staging + 15s forklift + 8s dispatch + 35s return & sign-off = 138s (2.30 min)
            -- 3600 / 138 = 26.09 cycles/hr @ $1,440 = $37,565/hr
            payout = 1440,
            stages = {
                {
                    index = 1,
                    taskType = 'receiving',
                    label = 'Receiving: Inbound Container Inspection & Seal Check',
                    coords = vector3(158.50, -3088.20, 5.90),
                    action = 'INSPECT CONTAINER SEALS & MANIFEST',
                    scenario = 'WORLD_HUMAN_CLIPBOARD',
                    durationMs = 7000,
                    minDurationMs = 6000,
                },
                {
                    index = 2,
                    taskType = 'sorting',
                    label = 'Sorting: Barcode Scan & Product Segregation',
                    coords = vector3(168.20, -3098.50, 5.90),
                    action = 'UNPACK & BARCODE SCAN CARGO',
                    scenario = 'PROP_HUMAN_BUM_BIN',
                    durationMs = 8000,
                    minDurationMs = 6500,
                },
                {
                    index = 3,
                    taskType = 'staging',
                    label = 'Pallet Staging: Stack, Band & Shrink-Wrap Pallet',
                    coords = vector3(175.80, -3110.40, 5.90),
                    action = 'BAND & SHRINK-WRAP FREIGHT PALLET',
                    scenario = 'WORLD_HUMAN_HAMMERING',
                    durationMs = 8000,
                    minDurationMs = 6500,
                },
                {
                    index = 4,
                    taskType = 'dispatch',
                    label = 'Dispatch: Transfer Pallet to Outbound Bay 1',
                    coords = vector3(162.40, -3125.60, 5.90),
                    action = 'STAGE AT OUTBOUND DISTRIBUTION DOCK',
                    scenario = 'WORLD_HUMAN_STAND_MOBILE',
                    durationMs = 6000,
                    minDurationMs = 5000,
                },
            },
        },
        {
            id = 'MUNI-WH-ELECTRICAL',
            title = '[PORT LOGISTICS] Municipal Grid High-Voltage Cable Reels',
            description = 'Intake port cable drums, dielectric testing check, staging on heavy timber skids, and transfer to city grid staging area.',
            cargoType = 'High-Voltage Utility Cable',
            cycleDurationSec = 141,
            -- Cycle calculation: 27s setup + 10s transit + 9s receiving + 8s transit + 10.5s sorting + 8s transit + 10s staging + 15s forklift + 8s dispatch + 35.5s return & sign-off = 141s (2.35 min)
            -- 3600 / 141 = 25.53 cycles/hr @ $1,465 = $37,404/hr
            payout = 1465,
            stages = {
                {
                    index = 1,
                    taskType = 'receiving',
                    label = 'Receiving: Cable Drum Intake & Dielectric Seal Inspection',
                    coords = vector3(158.50, -3088.20, 5.90),
                    action = 'VERIFY DRUM DIELECTRIC INTEGRITY',
                    scenario = 'WORLD_HUMAN_CLIPBOARD',
                    durationMs = 7000,
                    minDurationMs = 6000,
                },
                {
                    index = 2,
                    taskType = 'sorting',
                    label = 'Sorting: Spool Gauge Segregation & Terminal Block Tagging',
                    coords = vector3(168.20, -3098.50, 5.90),
                    action = 'TAG CABLE SPOOLS & TERMINAL ENDS',
                    scenario = 'PROP_HUMAN_BUM_BIN',
                    durationMs = 8500,
                    minDurationMs = 7000,
                },
                {
                    index = 3,
                    taskType = 'staging',
                    label = 'Pallet Staging: Timber Skid Chocking & Turnbuckle Restraints',
                    coords = vector3(175.80, -3110.40, 5.90),
                    action = 'CHOCK SPOOL & SECURE TURNBUCKLES',
                    scenario = 'WORLD_HUMAN_HAMMERING',
                    durationMs = 8000,
                    minDurationMs = 6500,
                },
                {
                    index = 4,
                    taskType = 'dispatch',
                    label = 'Dispatch: Municipal Power Grid Outbound Bay 4 Staging',
                    coords = vector3(162.40, -3125.60, 5.90),
                    action = 'TRANSFER TO GRID OUTBOUND DOCK',
                    scenario = 'WORLD_HUMAN_STAND_MOBILE',
                    durationMs = 6000,
                    minDurationMs = 5000,
                },
            },
        },
        {
            id = 'MUNI-WH-MEDICAL',
            title = '[PORT LOGISTICS] City Emergency & Medical Supplies Manifest',
            description = 'Rapid physical intake, cold-chain temperature verification, segregation, and staging of municipal hospital consumables.',
            cargoType = 'Critical Medical Supplies',
            cycleDurationSec = 144,
            -- Cycle calculation: 30s setup + 10s transit + 9s receiving + 8s transit + 10.5s sorting + 8s transit + 10s staging + 15s forklift + 8s dispatch + 35.5s return & sign-off = 144s (2.40 min)
            -- 3600 / 144 = 25.00 cycles/hr @ $1,495 = $37,375/hr
            payout = 1495,
            stages = {
                {
                    index = 1,
                    taskType = 'receiving',
                    label = 'Receiving: Cold-Chain Reefer Intake & Hazmat Verification',
                    coords = vector3(158.50, -3088.20, 5.90),
                    action = 'INSPECT REEFER LOGS & TEMPERATURE',
                    scenario = 'WORLD_HUMAN_CLIPBOARD',
                    durationMs = 7000,
                    minDurationMs = 6000,
                },
                {
                    index = 2,
                    taskType = 'sorting',
                    label = 'Sorting: Lot Number Verification & Acoustic Sensor Tracking',
                    coords = vector3(168.20, -3098.50, 5.90),
                    action = 'SORT & SCAN CLINICAL CONSUMABLES',
                    scenario = 'PROP_HUMAN_BUM_BIN',
                    durationMs = 8500,
                    minDurationMs = 7000,
                },
                {
                    index = 3,
                    taskType = 'staging',
                    label = 'Pallet Staging: Band Insulated Shippers & Thermal Blankets',
                    coords = vector3(175.80, -3110.40, 5.90),
                    action = 'SECURE THERMAL COLD-BOX PALLET',
                    scenario = 'WORLD_HUMAN_HAMMERING',
                    durationMs = 8000,
                    minDurationMs = 6500,
                },
                {
                    index = 4,
                    taskType = 'dispatch',
                    label = 'Dispatch: Express Priority Staging at Outbound Bay 2',
                    coords = vector3(162.40, -3125.60, 5.90),
                    action = 'LOG EXPRESS DISPATCH MANIFEST',
                    scenario = 'WORLD_HUMAN_STAND_MOBILE',
                    durationMs = 6000,
                    minDurationMs = 5000,
                },
            },
        },
        {
            id = 'MUNI-WH-HARDWARE',
            title = '[PORT LOGISTICS] Public Works Heavy Hardware & Valve Pallets',
            description = 'Offload heavy municipal infrastructure iron, sort pipe couplings, band industrial wooden pallets, and transfer to Public Works bay.',
            cargoType = 'Heavy Municipal Hardware',
            cycleDurationSec = 151,
            -- Cycle calculation: 35s setup + 10s transit + 9.5s receiving + 8s transit + 11s sorting + 8s transit + 10.5s staging + 15s forklift + 8.5s dispatch + 35.5s return & sign-off = 151s (2.51 min)
            -- 3600 / 151 = 23.84 cycles/hr @ $1,570 = $37,430/hr
            payout = 1570,
            stages = {
                {
                    index = 1,
                    taskType = 'receiving',
                    label = 'Receiving: Crane Hoist Offload & Structural Crate Inspection',
                    coords = vector3(158.50, -3088.20, 5.90),
                    action = 'INSPECT HEAVY CRATES & RIGGING',
                    scenario = 'WORLD_HUMAN_CLIPBOARD',
                    durationMs = 7500,
                    minDurationMs = 6500,
                },
                {
                    index = 2,
                    taskType = 'sorting',
                    label = 'Sorting: Segregate High-Tension Flanges & Bolt Sets',
                    coords = vector3(168.20, -3098.50, 5.90),
                    action = 'SORT HEAVY FITTINGS & VALVES',
                    scenario = 'PROP_HUMAN_BUM_BIN',
                    durationMs = 9000,
                    minDurationMs = 7500,
                },
                {
                    index = 3,
                    taskType = 'staging',
                    label = 'Pallet Staging: Tension Steel Strapping & Heavy Dunnage Chocking',
                    coords = vector3(175.80, -3110.40, 5.90),
                    action = 'STRAP HEAVY SKID & CHOCK LOAD',
                    scenario = 'WORLD_HUMAN_HAMMERING',
                    durationMs = 8500,
                    minDurationMs = 7000,
                },
                {
                    index = 4,
                    taskType = 'dispatch',
                    label = 'Dispatch: Low-Boy Dock Staging at Heavy Bay 3',
                    coords = vector3(162.40, -3125.60, 5.90),
                    action = 'STAGE AT HEAVY HAUL DISTRIBUTION DOCK',
                    scenario = 'WORLD_HUMAN_STAND_MOBILE',
                    durationMs = 6500,
                    minDurationMs = 5500,
                },
            },
        },
    },
}

