CMTrucking = CMTrucking or {}

CMTrucking.Config = {
    Debug = false,

    JobTitle = 'Commercial Freight Transport Specialist',
    Description = 'Operate heavy-duty commercial freight haulers transporting bulk cargo and industrial supply contracts across San Andreas.',

    InteractKey = 38, -- E (INPUT_CONTEXT)
    InteractKeyLabel = 'E',

    -- Central Logistics Depot (Terminal Island - Port of Los Santos)
    Depot = {
        name = 'Terminal Island Freight Logistics',
        broker = {
            model = 's_m_m_trucker_01',
            coords = vector4(1185.20, -3255.40, 6.00, 90.0),
            name = 'Arthur Briggs',
            role = 'Freight Logistics Dispatcher',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            interactDistance = 3.0,
        },
        truckSpawns = {
            vector4(1198.50, -3245.20, 5.80, 270.0),
            vector4(1198.50, -3235.00, 5.80, 270.0),
        },
        pickupBay = {
            coords = vector3(1210.00, -3225.00, 5.80),
            radius = 10.0,
            label = 'Port Container Cargo Loading Dock',
            loadDurationMs = 8000, -- 8s loading and securing sequence
        },
        returnBay = {
            coords = vector3(1178.00, -3240.00, 5.80),
            radius = 10.0,
            label = 'Depot Truck Return Bay',
        },
    },

    -- Supported Heavy-Duty Freight Vehicle Configuration
    -- Uses 'pounder' (native heavy commercial freight vehicle with roll-up cargo doors).
    -- Single-chassis heavy hauler avoids multi-entity tractor/trailer desync risks.
    Vehicle = {
        model = 'pounder',
        label = 'Heavy Commercial Freight Truck',
        rearDoorOffset = vector3(0.0, -4.5, 0.0), -- Rear cargo bay offset relative to vehicle center
        eligibleModels = {
            ['pounder'] = true,
            ['pounder2'] = true,
            ['mule'] = true,
            ['mule2'] = true,
            ['mule3'] = true,
            ['mule4'] = true,
            ['mule5'] = true,
            ['benson'] = true,
            ['hauler'] = true,
            ['hauler2'] = true,
            ['phantom'] = true,
            ['phantom2'] = true,
            ['phantom3'] = true,
            ['packer'] = true,
        },
    },

    Blip = {
        depot = {
            sprite = 477, -- Semi truck freight icon
            color = 5,    -- Yellow / amber
            scale = 0.85,
            name = 'Terminal Island Freight Depot',
        },
        pickup = {
            sprite = 477,
            color = 25,   -- Green
            scale = 0.80,
            name = 'Cargo Loading Dock',
        },
        destination = {
            sprite = 1,   -- Destination circle
            color = 5,    -- Yellow
            scale = 0.85,
            name = 'Freight Delivery Destination',
        },
        depotReturn = {
            sprite = 477,
            color = 5,
            scale = 0.85,
            name = 'Depot Return Bay',
        },
    },

    Beacon = {
        color = { r = 0, g = 229, b = 255 }, -- CM Cyan (#00e5ff)
        height = 4.0,
        beamWidth = 0.35,
        beamAlpha = 140,
    },

    -- =========================================================================
    -- Economy Calibration (Approved CM Roadmap Economy Standard)
    -- Target Baseline: $37,500 per eligible gameplay hour.
    -- Cycle Time Accounting (includes setup, loading, transit, unloading, return):
    --   - Fixed Cycle Overhead: 95 seconds (1.58 min)
    --     * Order assignment & spawn walk: 25s
    --     * Bay transit & dock alignment: 15s
    --     * Cargo loading & strap animation: 8s
    --     * Cab departure prep: 7s
    --     * Unload bay alignment & manifest inspection: 15s
    --     * Return bay check-in & turnaround: 25s
    --   - Transit Speeds: ~70 km/h heavy freight cruising (~19.4 m/s outbound laden, ~20.8 m/s return unladen).
    --
    -- Route Breakdown & Effective Hourly Rate:
    --   * Cypress Flats (1.8 km x2 = 3.6 km driving):
    --     Drive: 180s + Overhead: 95s = 275s (4.58 min) | 13.09 cycles/hr | Payout: $2,865 -> $37,505/hr
    --   * Davis Maintenance (2.5 km x2 = 5.0 km driving):
    --     Drive: 249s + Overhead: 95s = 344s (5.73 min) | 10.46 cycles/hr | Payout: $3,585 -> $37,514/hr
    --   * Sandy Shores (5.5 km x2 = 11.0 km driving):
    --     Drive: 547s + Overhead: 95s = 642s (10.70 min) | 5.61 cycles/hr | Payout: $6,685 -> $37,485/hr
    --   * Paleto Bay (11.0 km x2 = 22.0 km driving):
    --     Drive: 1095s + Overhead: 95s = 1190s (19.83 min) | 3.03 cycles/hr | Payout: $12,395 -> $37,495/hr
    -- =========================================================================
    Economy = {
        targetHourlyYield = 37500, -- Approved CM Roadmap standard ($37.5k/hr)
        cycleOverheadSec = 95,
        avgTruckSpeedMps = 19.4,
    },

    -- Contract Lifecycle States
    ContractState = {
        Selected = 'selected',       -- Contract chosen, truck spawned/assigned, driving to cargo pickup
        Loading = 'loading',         -- At cargo loading dock, securing freight
        InTransit = 'in_transit',     -- Cargo secured, driving to destination
        Delivered = 'delivered',     -- Cargo unloaded at destination, returning to depot
        Completed = 'completed',     -- Manifest checked in and payout finalized
    },

    -- Broker integration settings
    Broker = {
        providerType = 'trucking',
        supportedTypes = {
            'business_supply', -- Published by cm-commercial-ownership
            -- 'bulk_material_transport' is deferred (no active publisher in repo)
        },
        resource = 'cm-contracts',
    },

    -- Security, Distance Gates & Timings
    Security = {
        brokerDistance = 3.2,
        pickupBayDistance = 14.0,      -- Truck proximity to loading dock
        destinationBayDistance = 14.0, -- Truck proximity to destination unloading bay
        depotReturnDistance = 14.0,    -- Truck proximity to return bay
        truckRearDistance = 6.0,       -- Player distance to truck rear cargo doors
        actionCooldownMs = 1500,       -- Interaction debounce rate limit
        minimumTransitTimeMs = 25000,  -- Minimum route driving time to prevent teleport exploits
    },

    -- Always-Available Repeatable Municipal Freight Routes (City/NPC Work)
    -- Standalone municipal logistical routes ensuring drivers always have work
    -- available even when no player or business restock orders exist on the broker.
    CityRoutes = {
        {
            id = 'CITY-ROUTE-SANDY',
            title = '[CITY FREIGHT] Terminal Island to Sandy Shores Distribution',
            description = 'Standard Municipal Freight Haul - Regular municipal hardware and utility supply run',
            destinationLabel = 'Sandy Shores Regional Distribution Depot',
            destinationCoords = vector3(1700.50, 3788.20, 34.70),
            distanceKm = 5.5,
            cycleDurationSec = 642,
            cargo = 'Municipal Hardware & Utility Crates',
            cargoClass = 'Municipal Supply',
            basePayout = 6685, -- Full cycle: 642s (10.70 min) -> 5.61 cycles/hr @ $6,685 = $37,485/hr
        },
        {
            id = 'CITY-ROUTE-PALETO',
            title = '[CITY FREIGHT] Terminal Island to Paleto Bay Supply Depot',
            description = 'Standard Municipal Freight Haul - Long-distance provincial consumer and dry goods supply',
            destinationLabel = 'Paleto Bay Municipal Supply Yard',
            destinationCoords = vector3(-144.20, 6344.80, 31.50),
            distanceKm = 11.0,
            cycleDurationSec = 1190,
            cargo = 'Civilian Municipal Groceries & Dry Goods',
            cargoClass = 'Municipal Supply',
            basePayout = 12395, -- Full cycle: 1190s (19.83 min) -> 3.03 cycles/hr @ $12,395 = $37,495/hr
        },
        {
            id = 'CITY-ROUTE-DAVIS',
            title = '[CITY FREIGHT] Terminal Island to Davis Industrial Maintenance',
            description = 'Standard Municipal Freight Haul - Short-range city infrastructure maintenance delivery',
            destinationLabel = 'Davis Municipal Maintenance Yard',
            destinationCoords = vector3(151.20, -1632.40, 29.30),
            distanceKm = 2.5,
            cycleDurationSec = 344,
            cargo = 'City Infrastructure Maintenance Materials',
            cargoClass = 'Municipal Supply',
            basePayout = 3585, -- Full cycle: 344s (5.73 min) -> 10.46 cycles/hr @ $3,585 = $37,514/hr
        },
        {
            id = 'CITY-ROUTE-CYPRESS',
            title = '[CITY FREIGHT] Terminal Island to Cypress Flats Hub',
            description = 'Standard Municipal Freight Haul - Local commercial district paper and packaging transport',
            destinationLabel = 'Cypress Flats Logistics Hub',
            destinationCoords = vector3(817.50, -2155.00, 29.60),
            distanceKm = 1.8,
            cycleDurationSec = 275,
            cargo = 'Bulk Commercial Paper & Packaging Cargo',
            cargoClass = 'Municipal Supply',
            basePayout = 2865, -- Full cycle: 275s (4.58 min) -> 13.09 cycles/hr @ $2,865 = $37,505/hr
        },
    },
}

