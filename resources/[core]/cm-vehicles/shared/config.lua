CMVehicles = CMVehicles or {}

CMVehicles.Config = {
    Debug = true,

    Controls = {
        menuKey = 'G',
        lockKey = 'L',
        engineKey = 'LCONTROL', -- Left Ctrl starts/stops engine
        seatbeltKey = 'B',
        cruiseKey = 'CAPITAL'
    },

    Interaction = {
        -- G menu targeting: strict look-at behavior with a forgiving ray for big/custom vehicles.
        distance = 5.8,
        lookDistance = 7.5,
        capsuleRadius = 0.55,
        lookRadius = 0.85,
        lookDot = 0.82,
        screenMargin = 0.22,
        trunkDistance = 4.5,
        keyGiveDistance = 6.0
    },

    TrunkSlotsByLevel = { [0] = 0, [1] = 6, [2] = 12, [3] = 18, [4] = 24, [5] = 30, [6] = 30 },
    DefaultTrunkLevel = 1,

    Commands = { adminSpawnOwned = true },

    Plate = {
        prefix = 'CM',
        length = 6,
        visualBlank = true
    },

    Rules = {
        DefaultSpawnEngineOn = false,
        DeletePlayerVehiclesOnLogout = true,
        DeleteSpawnedVehiclesOnRestart = true,
        ParkingInsuranceFee = 500,
        ParkingRepairOnRetrieve = true
    },

    Persistence = {
        saveIntervalMs = 30000
    },

    Seatbelt = {
        ejectSpeedKmh = 85.0,
        crashDeltaKmh = 45.0,
        warningIntervalMs = 5000
    },

    Damage = {
        -- GTA engines can look/feel dead before 0.0. Below this value the car cannot be started.
        destroyedEngineHealth = 150.0,
        -- Below this value the engine can randomly stall while driving.
        stallEngineHealth = 400.0,
        stallCheckMs = 4500,
        stallChancePercent = 16,
        stallMinSpeedKmh = 12.0,
        -- Hard impact uses the same severity as seatbelt ejection by default.
        -- Small bumps will not kill the engine; only a crash strong enough to eject an unbelted player will.
        hardImpactUseSeatbeltCrashThreshold = true,
        hardImpactMinSpeedKmh = 85.0,
        hardImpactDeltaKmh = 45.0,
        hardImpactCooldownMs = 3000,
        impactEngineDamage = 120.0,
        restartDelayAfterImpactMs = 5000
    },

    Engine = {
        -- Manual engine stop is blocked above this speed. Hard impact can still shut the engine off.
        manualStopMaxSpeedKmh = 20.0
    },

    Fuel = {
        -- Standalone native fuel support. This keeps fuel controlled by cm-vehicles instead of random GTA defaults.
        defaultFuel = 100.0,
        consumeEnabled = true,
        consumeIntervalMs = 3000,
        -- Values are percent per real minute. These are visible in testing but not too fast for RP.
        idleDrainPerMinute = 0.08,
        speedDrainPerMinute = 0.45,
        rpmDrainPerMinute = 0.35
    },

    Performance = {
        -- Cache nearby vehicle pool for look-at prompts/actions instead of calling GetGamePool every frame.
        vehiclePoolCacheMs = 1200
    }
}
