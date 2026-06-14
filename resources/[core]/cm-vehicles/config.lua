CMVehicles = CMVehicles or {}

CMVehicles.Config = {
    Debug = false,

    Controls = {
        menuKey = 'G',
        lockKey = 'L',
        engineKey = nil -- disabled: this resource never controls driving/engine
    },

    Interaction = {
        distance = 4.2,
        lookDot = 0.24, -- easier G prompt from all angles while looking at vehicle
        trunkDistance = 4.0,
        keyGiveDistance = 6.0
    },

    TrunkSlotsByLevel = {
        [0] = 0,
        [1] = 6,
        [2] = 12,
        [3] = 18,
        [4] = 24,
        [6] = 36
    },

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
    }
}
