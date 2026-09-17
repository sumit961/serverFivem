-- CM License System Configuration
--
-- Every value in this file is read by the resource. If you add something here,
-- wire it up — a config field that nothing reads is a lie to whoever edits it.

CMLicenseConfig = {
    -- Test session configuration
    TestSession = {
        -- Hard time limit for a test, measured from the moment the fee is taken.
        TimeoutMinutes = 20,

        -- Mistakes allowed before failure (ground tests only; boat/air are 0).
        MaxMistakes = 3,

        -- How far past the start-of-leg distance a player may stray from the
        -- next checkpoint before the route counts as abandoned (meters).
        AbandonedDistance = 500,

        -- Grace period before straying that far actually fails the test.
        AbandonedGraceSeconds = 30,

        -- Seconds the player may stay outside the exam vehicle before failing.
        ReturnToVehicleSeconds = 60,

        -- Grace after the vehicle spawns before seating is enforced.
        SeatingGraceSeconds = 8,

        -- Cooldown after a failed attempt before the same test can be retaken.
        RetryCooldownMinutes = 0,
    },

    -- Checkpoint detection
    Checkpoint = {
        -- Radius recorded for new checkpoints; the server validates a reported
        -- checkpoint against this (permissive) bound.
        DefaultRadius = 20.0,
        MinRadius = 2.0,
        MaxRadius = 100.0,

        -- Radius at which the client considers a checkpoint touched, by
        -- vehicle category. Tighter than the stored radius on purpose.
        Touch = {
            ground = 4.0,
            boat = 8.0,
            air = 20.0,
        },

        -- Finish conditions for air tests: the helicopter must be within this
        -- vertical distance of the pad and below this speed.
        LandingVerticalTolerance = 3.0,
        LandingMaxSpeed = 2.5,
    },

    -- Test vehicle configuration
    TestVehicle = {
        -- Mark test vehicles with state bags (prevents storage/sale).
        MarkTemporary = true,

        -- Plate applied to the exam vehicle. Set server-side so temporary keys
        -- match the plate the player actually sees.
        Plate = 'LICENSE',

        -- Lifetime of the temporary key granted for the exam vehicle (seconds).
        TempKeySeconds = 7200,
    },

    -- Money account the test fee is charged to
    MoneyAccount = 'cash',

    -- NPC interaction data
    NPC = {
        -- Interaction distance (meters)
        InteractionDistance = 3.0,
        Model = 's_m_m_autoshop_01',
        Name = 'Alex Morgan',
        Role = 'CM License Instructor',
        Scenario = 'WORLD_HUMAN_CLIPBOARD',
        Coords = { x = -700.5005, y = -1401.3684, z = 5.4953, heading = 148.6945 },
    },

    -- Fixed public choices. Administrators only record their routes.
    StandardTypes = {
        driver = { label='Driver License', item='driver_license', price=500, days=30, model='blista', category='ground' },
        boat = { label='Boat License', item='boat_license', price=1000, days=30, model='dinghy', category='boat' },
        air = { label='Air License', item='air_license', price=5000, days=30, model='havok', category='air' },
    },

    Maintenance = {
        -- Expiry sweep / pending-delivery sweep interval (minutes).
        IntervalMinutes = 5,

        -- Also run the expiry check when a character loads.
        CheckOnLoad = true,

        -- Days of finished test rows to keep before pruning.
        KeepFinishedTestDays = 14,
    },

    -- Verbose server/client logging
    Debug = false,
}

return CMLicenseConfig
