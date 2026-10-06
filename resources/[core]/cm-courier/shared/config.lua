-- cm-courier/shared/config.lua
-- CM Courier: Authoritative Municipal Courier & Parcel Logistics Configuration.

CMCourier = CMCourier or {}

CMCourier.Config = {
    Debug = false,

    -- Approved municipal gameplay target: $37,500 per eligible gameplay hour ($10.416666.../sec)
    Economy = {
        targetHourly = 37500,
        baselinePerSecond = 37500 / 3600.0,
    },

    -- Courier Depot Facility (Post OP Distribution Terminal - Elysian/Port)
    Facility = {
        supervisor = {
            name = 'Sal Moreno',
            role = 'MUNICIPAL COURIER DISPATCHER',
            model = 's_m_m_postal_01',
            coords = vector4(-424.38, -2789.72, 6.00, 320.0),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            interactDistance = 3.0,
        },
        vehicleSpawns = {
            vector4(-416.75, -2795.50, 6.00, 315.0),
            vector4(-410.50, -2801.50, 6.00, 315.0),
            vector4(-404.20, -2807.80, 6.00, 315.0),
        },
        loadingDock = {
            coords = vector3(-430.50, -2798.20, 6.00),
            radius = 5.0,
            loadTimePerParcelMs = 3000,
        },
        returnBay = {
            coords = vector3(-412.50, -2785.00, 6.00),
            radius = 12.0,
        },
    },

    -- Authorized Courier Vehicle Configuration
    Vehicle = {
        model = 'boxville',
        label = 'Municipal Courier Van',
        eligibleModels = {
            joaat('boxville'),
            joaat('boxville2'),
            joaat('boxville3'),
            joaat('boxville4'),
            joaat('rumpo'),
            joaat('rumpo2'),
            joaat('rumpo3'),
            joaat('mule'),
            joaat('mule2'),
            joaat('mule3'),
            joaat('mule4'),
            joaat('bison'),
            joaat('bison2'),
            joaat('bison3'),
            joaat('speedo'),
            joaat('speedo2'),
            joaat('speedo4'),
            joaat('pony'),
            joaat('pony2'),
        },
    },

    -- Map Blip Display Config
    Blip = {
        facility = {
            sprite = 67, -- delivery van / postal sprite
            color = 5,  -- CM cyan
            scale = 0.85,
            name = 'Municipal Courier Depot',
        },
        stop = {
            sprite = 1,
            color = 5,
            scale = 0.80,
            name = 'Courier Delivery Drop',
        },
        returnBay = {
            sprite = 357,
            color = 5,
            scale = 0.85,
            name = 'Courier Depot Return Bay',
        },
    },

    -- Key Controls
    InteractKey = 38,       -- INPUT_PICKUP (E)
    InteractKeyLabel = 'E',

    -- Server Validation & Anti-Exploit Parameters
    Security = {
        actionCooldownMs = 1500,
        supervisorDistance = 3.5,
        loadingDockDistance = 6.0,
        vehicleProximityToLoading = 18.0,
        deliveryDistance = 15.0,
        vehicleProximityToStop = 45.0,
        depotReturnDistance = 15.0,
        minSecondsPerStop = 18,
    },

    -- =========================================================================
    -- Municipal Delivery Routes
    -- =========================================================================
    -- Authoritative City-Authored Routes. Always available on the Route Board.
    -- Calculation Basis: Target Rate $37,500/hr ($10.416666.../sec) applies at the FULL expected
    -- cycle only. The server accepts sign-off at minCompletionSeconds, so the fastest-allowed rate is higher:
    --   Route 1: full ~$37,503/hr | fastest 260s ~$57,694/hr
    --   Route 2: full ~$37,498/hr | fastest 400s ~$58,122/hr
    --   Route 3: full ~$37,502/hr | fastest 530s ~$58,372/hr
    -- All fastest-allowed rates stay within the approved legal activity band ceiling ($62,500/hr,
    -- CM_MATERIAL_ECONOMY.md), so payouts and minimums are unchanged.
    -- Total Cycle Time = Dispatch (20s) + Vehicle Setup (15s) + Depot Loading +
    --                    Transit Drive Time + Stop Hand-off Delays + Return Staging (20s) +
    --                    Sign-off (15s) + Reset Overhead (15s)
    Routes = {
        {
            id = 'downtown_express',
            title = 'Downtown Commercial Express',
            description = 'Fast-turnaround corporate priority delivery serving Pillbox Hill, Legion Square, and Mission Row business suites.',
            cycleSeconds = 400,
            payout = 4167, -- 400s * ($37,500 / 3,600s) = $4,166.67 -> $4,167
            minCompletionSeconds = 260, -- Physical minimum threshold (65% of full cycle)
            stops = {
                {
                    index = 1,
                    coords = vector3(145.80, -745.20, 45.75),
                    label = 'Pillbox Hill Corporate Suites',
                    recipient = 'Vangelico Corporate Services',
                    packageType = 'Confidential Documents & Jewelry Vault Keycards',
                    durationMs = 4000,
                },
                {
                    index = 2,
                    coords = vector3(215.50, -910.80, 30.70),
                    label = 'Legion Square Financial Building',
                    recipient = 'Maze Bank Accounting Department',
                    packageType = 'Encrypted Audit Tapes & Financial Records',
                    durationMs = 4000,
                },
                {
                    index = 3,
                    coords = vector3(380.20, -825.40, 29.30),
                    label = 'Mission Row Municipal Complex',
                    recipient = 'City Planning & Logistics Bureau',
                    packageType = 'Expedited Municipal Permits & Architectural Plans',
                    durationMs = 4000,
                },
            },
        },
        {
            id = 'metro_circuit',
            title = 'Metro Retail & Commercial Circuit',
            description = 'Comprehensive commercial loop delivering to South LS wholesale, Little Seoul, Del Perro, Rockford Hills, and Burton.',
            cycleSeconds = 620,
            payout = 6458, -- 620s * ($37,500 / 3,600s) = $6,458.33 -> $6,458
            minCompletionSeconds = 400, -- Physical minimum threshold (64.5% of full cycle)
            stops = {
                {
                    index = 1,
                    coords = vector3(485.60, -1302.40, 29.25),
                    label = 'South LS Commercial Wholesale Hub',
                    recipient = 'Apex Logistics Supplies',
                    packageType = 'Industrial Parts & Hardware Manifests',
                    durationMs = 4000,
                },
                {
                    index = 2,
                    coords = vector3(-695.30, -700.50, 31.40),
                    label = 'Little Seoul Commerce Tower - Floor 1',
                    recipient = 'Koreatown Business Association',
                    packageType = 'Commercial Office Equipment & Software Modules',
                    durationMs = 4000,
                },
                {
                    index = 3,
                    coords = vector3(-1390.40, -590.20, 30.30),
                    label = 'Del Perro Plaza Promenade Merchants',
                    recipient = 'Coastal Retail Partners',
                    packageType = 'Imported Apparel & Designer Samples',
                    durationMs = 4000,
                },
                {
                    index = 4,
                    coords = vector3(-765.20, -38.50, 37.80),
                    label = 'Portola Drive Commercial Suite',
                    recipient = 'Le Chien Fashion House',
                    packageType = 'Haute Couture Textiles & Fragrance Shipments',
                    durationMs = 4000,
                },
                {
                    index = 5,
                    coords = vector3(-295.80, -135.40, 43.80),
                    label = 'Hawick Avenue Commercial Center',
                    recipient = 'Burton Department Distributors',
                    packageType = 'High-Value Electronics & Consumer Displays',
                    durationMs = 4000,
                },
            },
        },
        {
            id = 'greater_county_industrial',
            title = 'Greater County & Industrial Loop',
            description = 'High-mileage municipal logistics distribution linking East LS, Murrieta, Mirror Park, Vinewood, Strawberry, and Davis Hospital.',
            cycleSeconds = 825,
            payout = 8594, -- 825s * ($37,500 / 3,600s) = $8,593.75 -> $8,594
            minCompletionSeconds = 530, -- Physical minimum threshold (64.2% of full cycle)
            stops = {
                {
                    index = 1,
                    coords = vector3(820.50, -1960.20, 29.30),
                    label = 'El Burro Heights Supply Depot',
                    recipient = 'Alpha Petroleum Operations',
                    packageType = 'Refinery Valve Replacement & Safety Sensors',
                    durationMs = 4000,
                },
                {
                    index = 2,
                    coords = vector3(1215.30, -1400.60, 35.20),
                    label = 'Murrieta Industrial Park Unit 4',
                    recipient = 'Titan Industrial Supplies',
                    packageType = 'Precision Machine Tooling & Calibrated Gauges',
                    durationMs = 4000,
                },
                {
                    index = 3,
                    coords = vector3(1040.80, -760.50, 57.90),
                    label = 'Mirror Park Retail Commons',
                    recipient = 'Parkside Medical Supply',
                    packageType = 'Specialty Pharmaceuticals & Diagnostic Kits',
                    durationMs = 4000,
                },
                {
                    index = 4,
                    coords = vector3(715.40, -145.20, 59.30),
                    label = 'East Vinewood Commercial Depot',
                    recipient = 'Metro Broadcast Distribution',
                    packageType = 'Broadcast Transmission Components & Cabling',
                    durationMs = 4000,
                },
                {
                    index = 5,
                    coords = vector3(260.50, 180.20, 105.10),
                    label = 'Vinewood Boulevard Suites',
                    recipient = 'Pacific Standard Archival',
                    packageType = 'Secured Legal Records & Archival Storage',
                    durationMs = 4000,
                },
                {
                    index = 6,
                    coords = vector3(140.20, -1480.50, 29.15),
                    label = 'Strawberry Wholesale Terminal',
                    recipient = 'Green Thumb Wholesalers',
                    packageType = 'Cold-Chain Perishables & Floral Shipments',
                    durationMs = 4000,
                },
                {
                    index = 7,
                    coords = vector3(355.60, -2040.20, 21.50),
                    label = 'Davis Municipal Hospital Receiving Dock',
                    recipient = 'Central County Health Logistics',
                    packageType = 'Urgent Clinical Supplies & Sterile Surgical Packs',
                    durationMs = 4000,
                },
            },
        },
    },
}

