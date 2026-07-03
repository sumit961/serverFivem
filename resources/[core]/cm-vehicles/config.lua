CMVehicles = CMVehicles or {}

CMVehicles.Config = {
    Debug = true,

    Controls = {
        menuKey = 'G',
        lockKey = 'L',
        engineKey = nil -- disabled: this resource never controls driving/engine
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

    Commands = {
        adminSpawnOwned = true
    },

    Plate = {
        prefix = 'CM',
        length = 6,
        visualBlank = true -- GTA number plate text is blank; internal id is hidden in entity state.
    },

    Rules = {
        -- Pure native driving mode. The script never controls engine/gears/speed/handbrake/undriveable.
        StrictEngineRequired = false,
        DefaultSpawnEngineOn = false
    },

    Damage = {
        destroyedEngineHealth = 150.0,
        stallEngineHealth = 400.0,
        stallCheckMs = 4500,
        stallChancePercent = 16,
        stallMinSpeedKmh = 12.0,
        hardImpactMinSpeedKmh = 35.0,
        hardImpactDeltaKmh = 28.0,
        hardImpactCooldownMs = 3000,
        impactEngineDamage = 60.0,
        restartDelayAfterImpactMs = 5000
    },

    Engine = {
        manualStopMaxSpeedKmh = 20.0
    },

    Fuel = {
        defaultFuel = 100.0,
        consumeEnabled = true,
        consumeIntervalMs = 5000,
        idleDrainPerMinute = 0.04,
        speedDrainPerMinute = 0.16,
        rpmDrainPerMinute = 0.22
    },

    Performance = {
        vehiclePoolCacheMs = 1200
    }
}
