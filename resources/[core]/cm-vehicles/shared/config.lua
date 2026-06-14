CMVehicles = CMVehicles or {}

CMVehicles.Config = {
    Debug = false,

    Controls = {
        menuKey = 'G',
        lockKey = 'L',
        engineKey = 'LCONTROL', -- Left Ctrl starts/stops engine
        seatbeltKey = 'B',
        cruiseKey = 'CAPITAL'
    },

    Interaction = {
        distance = 4.2,
        lookDot = 0.24,
        trunkDistance = 4.0,
        keyGiveDistance = 6.0
    },

    TrunkSlotsByLevel = { [0] = 0, [1] = 6, [2] = 12, [3] = 18, [4] = 24, [6] = 36 },
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
    }
}
