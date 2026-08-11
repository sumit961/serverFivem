CMVehicles = CMVehicles or {}

CMVehicles.Config = {
    Debug = false,

    Controls = {
        menuKey = 'G',
        lockKey = 'L',
        engineKey = 'LCONTROL', -- Left Ctrl starts/stops engine
        seatbeltKey = 'B',
        cruiseKey = 'X' -- cruise control toggle
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
        adminSpawnOwned = false,
        vehGiveAce = 'cmvehicles.vehgive'
    },

    Plate = {
        prefix = 'CM',
        length = 6,
        visualBlank = true
    },

    Rules = {
        DefaultSpawnEngineOn = false,
        DeletePlayerVehiclesOnLogout = false,
        DeleteSpawnedVehiclesOnRestart = true,
        ParkingInsuranceFee = 500,
        ParkingInsuranceAccount = 'cash',
        ParkingRepairOnRetrieve = true
    },

    Persistence = {
        -- Dirty-state client checks are lightweight; SQL writes happen only when
        -- values moved beyond these thresholds or an immediate lifecycle flush occurs.
        saveIntervalMs = 30000,
        legacyPeriodic = false,
        dirtyCheckIntervalMs = 1000,
        dirtyMaximumDelayMs = 15000,
        fuelThreshold = 0.5,
        healthThreshold = 1.0,
        dirtThreshold = 0.1,
        positionThresholdMeters = 1.5,
        headingThresholdDegrees = 4.0,
        abandonedDespawnSeconds = 1800,
    },

    Location = {
        authorizedResources = {
            ['cm-house'] = true,
            ['cm-family'] = true,
            ['cm-admin'] = true,
            ['cm-parking'] = true,
            ['cm-impound'] = true,
            ['cm-police'] = true,
            ['cm-ems'] = true,
        }
    },

    Operations = {
        authorizedResources = {
            ['cm-house'] = true,
            ['cm-admin'] = true,
            ['cm-parking'] = true,
            ['cm-impound'] = true,
            ['cm-police'] = true,
            ['cm-tuning'] = true,
        }
    },

    -- Temporary placement vehicles requested by trusted server resources.
    -- This lets a rank-limited cm-house interior/garage creator use the real
    -- placement car/helicopter without also granting vehicle-admin powers.
    -- cm-ems uses the same path for its fleet vehicle configurator/spawner:
    -- an EMS rank with ems.manage_vehicles/ems.spawn_vehicles does not need
    -- the separate, broader cm-vehicles.admin permission.
    Placement = {
        authorizedResources = {
            ['cm-house'] = true,
            ['cm-ems'] = true,
        }
    },

    Recovery = {
        ace = 'cmvehicles.recovery',
        adminPermission = 'vehicle.recovery',
    },

    Garage = {
        -- Spawn slightly above the saved slot and settle the model onto the floor.
        -- Add-on vehicles use different origins; exact-Z spawning can put their
        -- engine/body collision nodes inside the garage floor.
        spawnZOffset = 0.45,
        settleOnGround = true,
        conditionTolerance = 5.0,
        protectionCheckMs = 500,
        -- Healthy values used ONLY while a new entity builds its damage skeleton.
        bootstrapHealth = 1000.0,
        conditionApplyMs = 4500
    },

    Seatbelt = {
        ejectSpeedKmh = 85.0,
        crashDeltaKmh = 45.0,
        -- Seatbelt warning is now visual only (fed to cm-hud). No sound.
        warningIntervalMs = 5000
    },

    Damage = {
        -- GTA engines can look/feel dead before 0.0. Below this value the car cannot be started.
        destroyedEngineHealth = 150.0,
        -- Below this value the engine can randomly stall while driving.
        stallEngineHealth = 300.0,
        stallCheckMs = 6000,
        stallChancePercent = 10,
        stallMinSpeedKmh = 12.0,

        -- ── ENGINE WEAR IS SLOW ───────────────────────────────────────
        -- GTA natively drains engine health hard on every collision. We damp
        -- that native drain (see the engine-protect loop in interaction.lua)
        -- and apply our own small, controlled amount instead. Result: an engine
        -- takes a long, sustained beating to actually break.
        engineProtect = true,           -- damp GTA's own engine-health drain
        engineProtectKeepPercent = 0.12,-- keep only 12% of the native loss per tick

        hardImpactUseSeatbeltCrashThreshold = true,
        hardImpactMinSpeedKmh = 65.0,   -- must be going fast for a hit to count
        hardImpactDeltaKmh = 45.0,      -- and lose a lot of speed in one tick
        hardImpactCooldownMs = 3000,    -- longer gap between counted impacts
        impactEngineDamagePercent = 0.35,-- % of 1000 per hard impact (=3.5 health)

        -- ── Crash engine STALL (rare) ────────────────────────────────
        stallOnCrashChancePercent = 12, -- % chance a severe hit also kills the engine
        stallOnCrashMinSpeedKmh = 90.0,
        stallOnCrashMinDeltaKmh = 65.0,
        restartDelayAfterImpactMs = 5000
    },

    Engine = {
        -- Short key-turn animation before the approved engine start.
        startAnimation = true,
        startAnimationDict = 'anim@mp_player_intmenu@key_fob@',
        startAnimationClip = 'fob_click',
        startAnimationDurationMs = 1250,

        -- Manual engine stop is blocked above this speed. Hard impact can still shut the engine off.
        manualStopMaxSpeedKmh = 20.0,
        -- Remove the engine start/gear-up beep cue when re-enabling on exit.
        playStartSound = false
    },

    Fuel = {
        -- Standalone native fuel support. This keeps fuel controlled by cm-vehicles instead of random GTA defaults.
        defaultFuel = 100.0,
        consumeEnabled = true,
        consumeIntervalMs = 3000,
        -- Percent per real minute. Retuned faster + more realistic: a full tank
        -- now lasts roughly 20-30 min of normal driving instead of hours.
        idleDrainPerMinute = 0.30,
        speedDrainPerMinute = 2.60,
        rpmDrainPerMinute = 1.40,
        -- Below this %, cm-hud shows a low-fuel warning flag.
        lowFuelWarnPercent = 15.0
    },

    -- ── Refuel / repair / wash tuning (future petrol pump + gas can + mechanic) ──
    -- These are read by the server exports below. Adding the pump prop, the gas
    -- can item, or a mechanic job later needs NO code change here — just call the
    -- exports (see docs/REFUEL_REPAIR_WASH.md).
    Service = {
        -- Refueling
        maxFuel = 100.0,
        gasCanRefillAmount = 25.0,       -- % a single gas-can use adds
        pumpRefillPerSecond = 5.0,       -- % per second while holding at a pump (for future timed fill)
        -- Repair
        repairKitEngineAmount = 350.0,   -- engine health a repair kit restores
        repairKitBodyAmount = 350.0,     -- body health a repair kit restores
        mechanicFullRepair = true,       -- a mechanic repair sets everything to 1000
        -- Wash
        washResetsDirtTo = 0.0,

        -- Inventory items the G-menu Refuel / Repair / Wash options consume.
        -- These MUST match the item names in cm-gasstations (Config.Items).
        fuelCanItem = 'fuel_can',
        repairKitItem = 'repair_kit',
        washKitItem = 'wash_kit',

        -- ── What a REPAIR KIT actually fixes ──
        -- A kit is bodywork only: it panel-beats the dents, pops the doors back,
        -- and replaces the glass and tyres. It does NOT rebuild the engine and
        -- it does NOT clean the car (that's a car wash).
        RepairKit = {
            fixBody = true,          -- body health + deformation (dents)
            fixDeformation = true,   -- pull the dents out
            fixWindows = true,       -- replace broken glass
            fixDoors = true,         -- un-break / re-attach doors
            fixTyres = true,         -- fix burst tyres
            fixLights = true,        -- fix broken head/tail lights
            fixEngine = false,       -- a kit does NOT repair the engine
            fixTank = false,         -- nor the fuel tank
            fixDirt = false,         -- and it does NOT clean the car
            bodyAmount = 1000.0      -- body health restored (full panel repair)
        },

        -- ── Timers (progress bar length, ms) ──
        refuelDurationMs = 8000,     -- jerry can pour
        repairDurationMs = 12000,    -- repair kit bodywork
        washDurationMs = 10000,      -- wash kit scrub

        -- ── Animations ──
        Anim = {
            refuelDict = 'weapon@w_sp_jerrycan',
            refuelClip = 'fire',
            repairDict = 'mini@repair',
            repairClip = 'fixing_a_ped',
            washDict = 'timetable@floyd@clean_kitchen@base',
            washClip = 'base',
            propRepair = 'prop_tool_wrench',   -- held while repairing
            propJerryCan = 'w_am_jerrycan',    -- held while refueling
            propWash = 'prop_sponge_01'        -- held while washing
        }
    },

    -- ══════════════════════════════════════════════════════════════════
    --  PERFORMANCE TUNING (speed formula)
    --  GTA's native engine mod barely moves the needle (~+15% at Level 4), so a
    --  player cannot feel a $48k upgrade. We therefore override top speed and
    --  power directly, scaled by the vehicle's CLASS, so tuning actually means
    --  something. Level 4 = the full gain below; levels 1-3 interpolate.
    --
    --  e.g. a Super at Level 4: 275 km/h stock -> ~440 km/h tuned.
    -- ══════════════════════════════════════════════════════════════════
    Tuning = {
        enabled = true,

        -- Max gain at Level 4, per GTA vehicle class index.
        -- (0 Compact, 1 Sedan, 2 SUV, 3 Coupe, 4 Muscle, 5 SportsClassic,
        --  6 Sports, 7 Super, 8 Motorcycle, 9 OffRoad, 12 Van, ...)
        ClassGain = {
            [7]  = 0.60,   -- Super
            [6]  = 0.45,   -- Sports
            [5]  = 0.45,   -- Sports Classic
            [4]  = 0.35,   -- Muscle
            [3]  = 0.35,   -- Coupe
            [8]  = 0.40,   -- Motorcycle
            [1]  = 0.25,   -- Sedan
            [0]  = 0.25,   -- Compact
            [2]  = 0.20,   -- SUV
            [9]  = 0.20,   -- Off-road
            [12] = 0.20,   -- Van
        },
        defaultGain = 0.25,   -- any class not listed above

        -- How much of the class gain each engine level unlocks.
        -- index 1..4 -> Level 1..4
        LevelFraction = { 0.25, 0.50, 0.75, 1.00 },

        -- Torque scales a bit less aggressively than top speed, so a tuned car
        -- is fast but not instantly at redline.
        torqueFactorOfGain = 0.70,

        -- ── TYRES (synthetic level) ──
        -- GTA has no tyre-level mod slot, so we store the level ourselves in the
        -- vehicle's saved mods (mods.tyreLevel) and apply it as grip.
        Tyres = {
            enabled = true,
            maxLevel = 4,
            -- Grip multiplier added per level (Level 4 = +20% grip).
            gripPerLevel = 0.05,
            -- Bulletproof comes free with Level 3+.
            bulletproofFromLevel = 3,
        },
    },

    -- ── Rain driving ──
    -- GTA's wet-road grip loss is brutal; a supercar can be undriveable in rain.
    Rain = {
        fixGrip = true,
        wetGripFloor = 0.92,   -- keep at least 92% grip in the heaviest rain
    },

    Security = {
        saveStateMinIntervalMs = 2000,
        maxStateDistance = 12.0,
        maxServiceDistance = 8.0,
        maxMileageSpeedKmh = 450.0,
        authorizedHarnessResources = {
            ['cm-tuning'] = true,
            ['cm-itemactions'] = true,
            ['cm-admin'] = true,
        }
    },

    -- ── Radio ──
    Radio = {
        defaultOff = true,     -- muted on entry; the player can still turn it on
    },

    Dirt = {
        enabled = true,
        accumulateIntervalMs = 30000,    -- how often dirt ticks up while driving
        perTickWhileDriving = 0.35,      -- dirt units added per tick when moving
        perTickIdle = 0.05,              -- dirt units added per tick when parked/running
        maxDirt = 15.0                   -- GTA dirt caps at 15
    },

    -- ── cm-hud live feed ──
    -- cm-vehicles publishes a single state bag (LocalPlayer.state.cmVehicleHud)
    -- so cm-hud can render fuel / seatbelt / cruise / engine without a hard dep.
    Hud = {
        enabled = true,
        updateIntervalMs = 250
    },

    -- ── Key lending / revoking ──
    Keys = {
        maxLentKeysPerVehicle = 8
    },

    Performance = {
        -- Cache nearby vehicle pool for look-at prompts/actions instead of calling GetGamePool every frame.
        vehiclePoolCacheMs = 1200
    }
}
