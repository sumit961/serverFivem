CMPlayerData = CMPlayerData or {}

CMPlayerData.Config = {
    Debug = false,

    Save = {
        FullSaveInterval = 3 * 60 * 1000,
        PositionSaveInterval = 15 * 1000,
        MinimumPositionMove = 1.5
    },

    Respawn = {
        Time = 30000,
        Cost = 500,
        HospitalSpawn = { x = 341.0, y = -1397.0, z = 33.0, h = 50.0 }
    },

    Vitals = {
        HealthSyncInterval = 4000,
        PositionSyncInterval = 6000,
        DamageThreshold = 101,
        MaxHealth = 200,
        MaxArmor = 100,
        InjuredHealth = 140
    },
    Defaults = {
        cash = 0,
        bank = 0,
        health = 200,
        armor = 0,
        is_dead = 0,
        death_count = 0
    }
}
