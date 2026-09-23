CMTaxi = CMTaxi or {}

CMTaxi.Config = {
    Debug = false,

    -- Branding shown in the NUI meter/office panel.
    StationName = 'LS Taxi',

    -- Notifications are routed through cm-hud when present, falling back to a
    -- native GTA ticker otherwise. See client/notify.lua.
    NotifyResource = 'cm-hud',

    -- Focuses/unfocuses the meter tablet so the player can click its buttons
    -- without losing driving controls the rest of the time.
    Keybind = {
        command = 'cmtaxi_menu',
        defaultKey = 'J',
        description = 'CM Taxi: Open meter menu',
    },

    InteractKey = 38, -- INPUT_CONTEXT (E)
    InteractKeyLabel = 'E',
    OfficeInteractDistance = 2.5,
    OfficeDetectDistance = 40.0,

    MeterUpdateMs = 500,
    FirstRideHintMs = 9000,
    TaxiCallCooldownMs = 30000,
    FareExpiryMs = 900000,
    FareRepeatCooldownMs = 7200000,
    FarePickupMaxDistance = 2500.0,
    NearbyFareDistance = 500.0,
    OfficeServerDistance = 8.0,
    RentalSpawnClearRadius = 3.0,
    RentalIdleGraceMs = 120000,

    -- Vehicle models (hashes) that count as a taxi for meter/duty purposes.
    -- Kept in sync with the `vehicle` field on Config.Levels below.
    Vehicles = {
        [`taxi`] = true,
        [`tempesta2`] = true,
    },

    -- Fare economy. fareMin/fareMax are divided by 10 then multiplied by the
    -- route distance (metres) and divided by 10 again -- whole numbers only.
    FareMin = 10,
    FareMax = 15,
    -- Flat per-fare bonus paid out alongside the fare (stands in for metered
    -- fuel consumption -- simpler and server-authoritative).
    FuelBonus = 5,
    MaxFares = 20,
    NewFareIntervalMs = 60000,
    MinRouteDistance = 800.0,

    XpMin = 10,
    XpMax = 15,
    SkillMultiplier = 1.5,
    SkillMaxLevel = 30,

    ChargeForRental = true,
    CleanupOnDisconnect = true,

    -- Customer AI tuning (metres), mirrors classic taxi-job pacing.
    CustomerSpawnRadius = 150.0,
    CustomerNearbyDistance = 40.0,
    CustomerHailDistance = 20.0,
    CustomerDropoffDistance = 10.0,
    CustomerSpawnTimeoutMs = 60000,
    CustomerBoardTimeoutMs = 60000,
    CustomerBoardRetaskDistance = 4.0,
    CustomerExitTimeoutMs = 15000,
    FarePickupAssignmentTimeoutMs = 180000,
    FareTripTimeoutMs = 1800000,
    FareDropoffValidationDistance = 35.0,
    PlayerPickupValidationDistance = 60.0,
    PlayerTaxiBoardDistance = 5.0,
    TaxiEtaSpeedMps = 8.0,

    -- A prompt-pickup, low-damage ride earns a capped service tip.
    ServiceTipPercent = 0.10,
    ServiceTipMax = 25,
    ServiceTipPickupDeadlineMs = 120000,
    ServiceTipMaxBodyDamage = 80.0,

    -- Progression rewards. `vehicle` (if set) unlocks that model in the
    -- rental menu at this level; `reward` is granted once, on level-up.
    Levels = {
        [1] = {
            vehicle = `taxi`,
            spawnModel = 'taxi',
            vehicleLabel = 'Classic Taxi',
            vehicleRentCost = 1000,
            label = 'Taxi License',
        },
        [2] = {
            reward = { type = 'item', name = 'water', amount = 2 },
            label = '2x Bottled Water',
        },
        [3] = {
            reward = { type = 'money', amount = 3000 },
            vehicle = `tempesta2`,
            spawnModel = 'tempesta2',
            vehicleLabel = 'Lamborghini Huracan',
            vehicleRentCost = 5000,
            label = '$3,000 Bonus',
        },
    },

    -- Taxi offices: on/off duty, rentals, and the customer-spawn zone.
    Offices = {
        ['mirrorpark'] = {
            name = 'Mirror Park Taxi Office',
            coords = vector3(904.5, -173.92, 74.08),
            pedData = {
                coords = vector3(894.92, -179.12, 74.70),
                heading = 240.0,
                model = 'g_m_m_chiboss_01',
            },
            blip = { sprite = 198, scale = 0.8, colour = 5 },
            rentalSpawns = {
                vector4(899.08, -180.64, 73.22, 237.635),
                vector4(897.12, -183.51, 73.16, 237.635),
                vector4(908.81, -183.44, 73.56, 58.57),
                vector4(906.95, -186.48, 73.42, 58.57),
                vector4(905.15, -189.09, 73.23, 58.57),
            },
        },
    },
}
