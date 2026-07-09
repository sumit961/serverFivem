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
        -- Player respawns weak. GTA/FiveM health uses ~100 as the alive baseline,
        -- so 20% means about 20% of usable health above the downed threshold.
        HealthPercent = 20,
        -- Bleed-out: death screen countdown; auto hospital respawn at zero.
        BleedOutTime = 120000,      -- 2 minutes
        AmbulanceExtraTime = 120000, -- calling an ambulance adds 2 more minutes
        MinimumRejoinBleedOut = 15000 -- if relogging dead, never show 00:00/stuck; give a small valid timer
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
        -- A successful patch now fully revives the body in place ("back from death"):
        -- full health, same location, no hospital trip. Set false to fall back to the
        -- old weak-revive using StreetPatchHealthPercent below.
        PatchFullHeal = true,
        StreetPatchHealthPercent = 30 -- used only when PatchFullHeal = false
    },

    Vitals = {
        HealthSyncInterval = 4000,
        PositionSyncInterval = 6000,
        DamageThreshold = 101,
        MaxHealth = 200,
        MaxArmor = 100,
        -- While unconscious the body carries this % of max health as a "finishing"
        -- buffer above the downed floor. If someone depletes it (kills again), the
        -- player is finished and goes straight to hospital respawn.
        UnconsciousHealthPercent = 10,
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

    Money = {
        -- cm-playerdata owns balances. cm-economy decides prices/payouts.
        Accounts = { cash = true, bank = true },
        ImmediateSave = true,
        TransactionLog = true,
        MaxSingleChange = 1000000000
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

        -- Shows above nearby streamed players, like: musa bhai / ID: 12.
        -- Native mode is used by default because it anchors to the ped position
        -- every render frame. This removes NUI label lag/wobble when the camera moves.
        OverheadLabels = true,
        UseNativeOverheadLabels = true,
        -- Reduced render range: names/IDs only show on closer players now.
        OverheadDistance = 12.0,
        OverheadScale = 0.32,
        -- Vertical gap between the name and ID lines, as a fraction of the label's
        -- current text scale. Because it scales with the text, the lines stay
        -- tight together at distance instead of drifting apart.
        OverheadLineGap = 0.075,
        OverheadFont = 0, -- GTA default simple font, not bold.
        OverheadTextOutline = true,
        -- Label anchors to entity position + this Z offset, so it follows the player
        -- only when the player moves and does not wobble with idle head bones.
        OverheadZOffset = 1.06,
        -- Label height above a dead body lying on the ground.
        DeadZOffset = 0.45,
        -- Unconscious/downed body wording. Shown as its own red line above the
        -- name (Grand-RP style: Unconscious / Name / ID). Uses the replicated
        -- isDead state bag, so it works even though a downed ped stays "alive"
        -- at Vitals.DamageThreshold and never reports IsEntityDead.
        DownedLabelText = 'Unconscious',
        DownedLabelColour = { r = 235, g = 45, b = 45, a = 250 },
        -- In (or entering / attached to) a vehicle, the label references the head
        -- but is expressed in the vehicle's local frame and rebuilt through the
        -- car's matrix each frame -- so it stays above the head AND is locked to the
        -- car (no lag/sway while driving), and stays smooth through the get-in anim.
        -- VehicleHeadLift: how far above the head to float the label (vehicle space).
        VehicleHeadLift = 0.58,
        -- After a player is seated, the label tracks the head for this many ms so it
        -- settles cleanly, then LOCKS to a fixed point in the car's frame -- from
        -- then on it moves only when the car moves (no jitter/swim while driving).
        VehicleLabelLockDelay = 700,
        AdminLabelText = 'Administrator',

        -- G appears only when your camera is aiming at the nearby player body/head.
        Key = 47, -- G
        Distance = 4.5,
        LookDistance = 4.5,
        LookDotThreshold = 0.985, -- strict: crosshair must be on the player
        RequireLineOfSight = false,
        TargetScanInterval = 70,
        TargetHoldMs = 420, -- keeps G stable for a few frames instead of blinking while looking at a player
        BlockInteractionWhenTargetInVehicle = true, -- player label stays visible in cars; G-menu is disabled
        -- No G prompt / G-menu on players while the VIEWER is inside a vehicle.
        -- Overhead name/ID labels still render; only the interaction is suppressed.
        BlockInteractionWhenViewerInVehicle = true,
        -- Single-prompt arbiter: coordinate with a separate vehicle interaction
        -- menu so only ONE G shows at a time. The vehicle resource must publish
        -- LocalPlayer.state.cmVehicleInteractDist and mirror this check (see
        -- docs/INTERACTION_ARBITER.md).
        InteractionArbiter = true,
        -- Who wins when both a player and a vehicle are targeted:
        --   'closest' = nearer target wins (near-ties go to the player)
        --   'player'  = player always wins when it has a target
        --   'vehicle' = vehicle always wins when it has a target
        InteractionPriority = 'closest',
        InteractionArbiterTie = 0.1, -- metres of dead-zone before 'closest' flips
        PromptScale = 0.58,
        -- Native G glyph size when drawn on the target's body (native mode).
        PromptNativeScale = 0.44,
        PromptHeight = 0.85,
        PromptZOffset = 0.12,
        DrawTargetArrow = true,

        -- Performance: NUI label updates are throttled so nearby labels stay smooth
        -- without sending a browser message every frame. Set lower only if needed.
        LabelUpdateInterval = 50,

        -- Extensible player G-menu. Future resources register their own pages/options
        -- through exports/events instead of editing cm-playerdata again.
        ShowEmptyExtensionPages = false,
        ExtensionPages = {
            family = { label = 'Family Menu', icon = 'family', order = 40, emptyLabel = 'No family actions available' },
            organization = { label = 'Organization', icon = 'organization', order = 50, emptyLabel = 'No organization actions available' },
            admin = { label = 'Admin Tools', icon = 'shield', order = 90, emptyLabel = 'No admin actions available' }
        },

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
