while not Config do Citizen.Wait(1) end

Config.Grenades = {
    ---@field Enabled: boolean [master toggle for the whole grenade system (all types)]
    Enabled = true,

    ---@field MaxThrowDistance: number [anti-abuse - detonation coords must be within this distance (metres) of the thrower]
    MaxThrowDistance = 60.0,

    ---@field CooldownMs: number [minimum interval (ms) between detonations per player (any grenade)]
    CooldownMs = 1500,

    ---@field Flashbang: table [flashbang grenade settings]
    Flashbang = {
        ---@field Enabled: boolean [enable the flashbang]
        Enabled = true,
        ---@field WeaponName: string [weapon name string]
        WeaponName = 'WEAPON_FLASHBANG',
        ---@field WeaponHash: hash [weapon hash]
        WeaponHash = `WEAPON_FLASHBANG`,
        ---@field ProjectileModel: hash [thrown projectile model hash]
        ProjectileModel = `w_ex_flashbang`,

        ---@field FuseMs: number [fuse time (ms) before detonation]
        FuseMs = 2500,

        ---@field Radius: number [outer effect radius (metres) - flashed only with clear line of sight]
        Radius = 35.0,
        ---@field StunRadius: number [inner radius (metres) where the player is always flashed]
        StunRadius = 8.0,

        ---@field MinDurationMs: number [minimum blind duration (ms) at the edge of the radius]
        MinDurationMs = 800,
        ---@field MaxDurationMs: number [maximum blind duration (ms) at point-blank range]
        MaxDurationMs = 4500,

        ---@field RequireLineOfSight: boolean [if true a wall between bang and player blocks the flash]
        RequireLineOfSight = true,
        ---@field RagdollEnabled: boolean [ragdoll affected players]
        RagdollEnabled = false,
        ---@field RagdollMs: number [ragdoll duration (ms) when enabled]
        RagdollMs = 1500,
        ---@field Disarm: boolean [force affected players to drop/holster their weapon]
        Disarm = true,
        ---@field SlowAim: boolean [slow affected players' aim after the flash]
        SlowAim = true,
        ---@field SlowAimScale: number [aim speed multiplier while slowed (lower = slower)]
        SlowAimScale = 0.15,

        ---@field WhiteFlashMs: number [how long the white screen flash takes to fade (close/facing hits)]
        WhiteFlashMs = 3000,
        ---@field DrunkMs: number [duration (ms) of the drunk/cover-eyes effect at point-blank range]
        DrunkMs = 20000,
        ---@field DrunkShakeAmp: number [peak amplitude of the drunk camera wobble (bigger = stronger sway)]
        DrunkShakeAmp = 2.0,
        ---@field FaceAnimDict: string [animation dict for the cover-eyes clip]
        FaceAnimDict = 'anim@heists@ornate_bank@thermal_charge',
        ---@field FaceAnimName: string [animation clip name for covering the eyes]
        FaceAnimName = 'cover_eyes_loop',
    },

    ---@field SmokeGrenade: table [smoke grenade settings (uses native WEAPON_SMOKEGRENADE)]
    SmokeGrenade = {
        ---@field Enabled: boolean [enable the smoke grenade]
        Enabled = true,
        ---@field WeaponName: string [weapon name string]
        WeaponName = 'WEAPON_SMOKEGRENADE',
        ---@field WeaponHash: hash [weapon hash]
        WeaponHash = `WEAPON_SMOKEGRENADE`,
        ---@field ProjectileModel: hash [thrown projectile model hash]
        ProjectileModel = `w_ex_grenadesmoke`,

        ---@field FuseMs: number [fuse time (ms) before the cloud forms]
        FuseMs = 2200,

        ---@field Radius: number [effect radius (metres) around the detonation point]
        Radius = 7.0,
        ---@field LingerMs: number [how long (ms) the cough/blur zone lingers]
        LingerMs = 18000,
        ---@field TickMs: number [interval (ms) to re-check if a player is inside the cloud]
        TickMs = 500,

        ---@field BlurStrength: number [screen blur strength while inside the cloud (0-1)]
        BlurStrength = 0.6,
        ---@field CoughInterval: number [trigger a cough animation every N ms while inside]
        CoughInterval = 2500,

        ---@field ImmuneAllowedJobs: boolean [if true police/allowed jobs are unaffected (gas-mask assumption)]
        ImmuneAllowedJobs = true,
    },
}
