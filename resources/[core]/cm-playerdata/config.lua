CMPlayerData = CMPlayerData or {}

CMPlayerData.Config = {
    Debug = false,

    Save = {
        FullSaveInterval = 3 * 60 * 1000,
        PositionSaveInterval = 15 * 1000,
        MinimumPositionMove = 1.5
    },

    Respawn = {
        Time = 30000, -- legacy, no longer used (bleed-out below drives respawn)
        Cost = 500,
        HospitalSpawn = { x = 341.0, y = -1397.0, z = 33.0, h = 50.0 },
        -- Bleed-out: death screen countdown; auto hospital respawn at zero.
        BleedOutTime = 120000,      -- 2 minutes
        AmbulanceExtraTime = 120000 -- calling an ambulance adds 2 more minutes
    },

    Medical = {
        -- Death presentation
        DeathCam = true,        -- slow orbit camera around the body
        DeathCamRadius = 3.4,
        DeathCamHeight = 1.6,
        DeathCamSpeed = 0.25,
        DeathEffect = true,     -- grayscale screen effect while dead
        DeadPose = 'dead_a',    -- lying pose before calling an ambulance
        AmbulancePose = 'dead_b', -- lying pose after calling an ambulance

        -- Street patch (Patch/Treat on a body via the G menu)
        TreatDuration = 8000,
        RequireBandage = true,
        BandageItem = 'bandage',
        StreetPatchHealthPercent = 30 -- back up weak; full revive stays EMS/admin
    },

    Vitals = {
        HealthSyncInterval = 4000,
        PositionSyncInterval = 6000,
        DamageThreshold = 101,
        MaxHealth = 200,
        MaxArmor = 100,
        InjuredHealth = 140, -- kept for compatibility only; no walkstyle/effect is applied
        MaxPassiveHealDelta = 5
    },

    Defaults = {
        cash = 0,
        bank = 0,
        health = 200,
        armor = 0,
        is_dead = 0,
        death_count = 0
    },

    Gameplay = {
        -- Player never gets tired: stamina is constantly restored.
        InfiniteStamina = true,
        -- Low health never changes movement (no injured limp/hurt walk).
        DisableHurtMovement = true,
        -- Other players sprinting/walking into you can never ragdoll or stumble you.
        BlockShoveRagdoll = true,
        -- Full ped-to-ped collision off between players (walk through, zero push).
        -- Disabled: players stay solid; BlockShoveRagdoll alone stops push/stumble abuse.
        NoPlayerCollision = false,
        NoCollisionDistance = 8.0,
        -- Never let the idle/AFK cinematic camera take over.
        DisableIdleCamera = true
    },

    Logging = {
        -- Rich death records: killer character ID, weapon, distance, coords.
        LogDeaths = true,
        -- Movement sanity logging (log only, never punish automatically).
        LogMovementAnomalies = true,
        MaxOnFootSpeed = 11.0,      -- m/s; normal sprint ~7. Falling is excluded.
        TeleportDistance = 300.0,   -- one position jump larger than this gets logged.
        FallZDelta = -9.0           -- z drop beyond this between samples = falling, skip speed check.
    },

    Interactions = {
        Enabled = true,
        Debug = false,

        -- Blue/cyan interaction theme.
        AccentColour = { r = 0, g = 230, b = 255, a = 255 },
        TextColour = { r = 230, g = 252, b = 255, a = 245 },

        -- Name privacy:
        -- false/unknown player = Stranger.
        -- real name shows only after same organization, same family, shared ID, or handshake.
        PrivacyMode = true,
        ShowRealNameToSelf = true,
        StrangerName = 'Stranger',
        -- Visible IDs are always database character IDs only. Server ID/source stays internal.
        UseServerIdAsIdentityId = false,
        IdentityRefreshInterval = 2000,

        -- Shows above nearby streamed players, like: Stranger / ID: 12 (database character ID).
        OverheadLabels = true,
        OverheadDistance = 18.0,
        OverheadScale = 0.42,
        -- Label anchors to the entity position + this Z offset, so it stays
        -- perfectly still even when the player's head/idle animation moves.
        OverheadZOffset = 1.06,
        -- Label height above a dead body lying on the ground.
        DeadZOffset = 0.45,

        -- G appears only when your camera is aiming at the nearby player body/head.
        Key = 47, -- G
        Distance = 4.5,
        LookDistance = 4.5,
        LookDotThreshold = 0.985, -- strict: crosshair must be on the player
        RequireLineOfSight = false,
        TargetScanInterval = 70,
        PromptScale = 0.58,
        PromptHeight = 0.85,
        PromptZOffset = 0.12,
        DrawTargetArrow = true,

        -- Server-side validation for menu actions.
        ServerMaxDistance = 5.0,
        MaxCashGift = 1000,

        -- Handshake now requires the target's consent (E to accept).
        HandshakeTimeout = 15000,

        -- Hide not-yet-implemented actions (search/escort) until they are wired
        -- to the inventory/carry systems. Buttons that fake success break RP.
        ShowWIPActions = false,

        -- Emotes played automatically on interactions.
        Anims = {
            Enabled = true,
            handshake   = { dict = 'mp_ped_interaction', clip = 'handshake_guy_a', duration = 3500 },
            handshake_b = { dict = 'mp_ped_interaction', clip = 'handshake_guy_b', duration = 3500 },
            greet       = { dict = 'mp_player_int_upperwave', clip = 'mp_player_int_wave_01', duration = 2500, flag = 49 },
            frisk       = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search', duration = 5000 }
        },

        -- Passport-style ID card shown to the other player on Share ID.
        IdCardDuration = 10000
    }
}
