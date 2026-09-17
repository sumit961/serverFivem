-- CM License System — Shared Constants

Constants = {
    -- License types
    LICENSE_TYPES = {
        DRIVER = 'driver',
        BOAT = 'boat',
        AIR = 'air',
    },

    -- License type labels
    LICENSE_LABELS = {
        driver = 'Driver License',
        boat = 'Boat License',
        air = 'Air License',
    },

    -- License status
    LICENSE_STATUS = {
        ACTIVE = 'active',
        EXPIRED = 'expired',
        REVOKED = 'revoked',
    },

    -- Test status
    TEST_STATUS = {
        WAITING_START = 'waiting_start',
        IN_PROGRESS = 'in_progress',
        COMPLETING = 'completing',
        COMPLETED = 'completed',
        FAILED = 'failed',
        CANCELLED = 'cancelled',
    },

    -- Checkpoint types
    CHECKPOINT_TYPE = {
        START = 'start',
        CHECKPOINT = 'checkpoint',
        FINISH = 'finish',
    },

    -- Test failure reasons
    FAIL_REASON = {
        VEHICLE_DESTROYED = 'vehicle_destroyed',
        PLAYER_DIED = 'player_died',
        ABANDONED_VEHICLE = 'abandoned_vehicle',
        ABANDONED_ROUTE = 'abandoned_route',
        TIMEOUT = 'timeout',
        TOO_MANY_MISTAKES = 'too_many_mistakes',
        DISCONNECTED = 'disconnected',
        CANCELLED = 'cancelled',
        VEHICLE_SPAWN_FAILED = 'vehicle_spawn_failed',
        ADMIN_CANCELLED = 'admin_cancelled',
        WRONG_CHECKPOINT_ORDER = 'wrong_checkpoint_order',
        SPEEDING = 'speeding',
        ALTITUDE_VIOLATION = 'altitude_violation',
        SERVER_RESTART = 'server_restart',
        LICENSE_ISSUANCE_FAILED = 'license_issuance_failed',
        INVALID_CLIENT_FAILURE = 'invalid_client_failure',
    },

    -- Test result messages
    RESULT_MESSAGES = {
        vehicle_destroyed = 'Test vehicle was destroyed',
        player_died = 'You died during the test',
        abandoned_vehicle = 'You abandoned the test vehicle',
        abandoned_route = 'You went too far from the route',
        timeout = 'Test time limit exceeded',
        too_many_mistakes = 'Too many mistakes',
        disconnected = 'You were disconnected',
        cancelled = 'Test cancelled',
        vehicle_spawn_failed = 'The test vehicle could not be prepared',
        admin_cancelled = 'Test was cancelled by an administrator',
        wrong_checkpoint_order = 'You entered checkpoints out of order',
        speeding = 'Exceeded the posted speed limit',
        altitude_violation = 'Violated altitude restrictions',
        server_restart = 'The server restarted during your test',
        license_issuance_failed = 'The license could not be issued',
        invalid_client_failure = 'Test failed',
    },

    -- Vehicle categories
    VEHICLE_CATEGORY = {
        GROUND = 'ground',
        BOAT = 'boat',
        AIR = 'air',
    },

    -- Events (namespace: cm-license)
    EVENTS = {
        SERVER = {
            REQUEST_START_TEST = 'cm-license:server:requestStartTest',
            START_TEST = 'cm-license:server:startTest',
            CHECKPOINT_REACHED = 'cm-license:server:checkpointReached',
            FINISH_TEST = 'cm-license:server:finishTest',
            CANCEL_TEST = 'cm-license:server:cancelTest',
            TEST_FAILED = 'cm-license:server:testFailed',
            REPORT_MISTAKE = 'cm-license:server:reportMistake',
        },
        CLIENT = {
            TEST_STARTED = 'cm-license:client:testStarted',
            SET_CHECKPOINT = 'cm-license:client:setCheckpoint',
            TEST_COMPLETED = 'cm-license:client:testCompleted',
            TEST_FAILED = 'cm-license:client:testFailed',
            UPDATE_HUD = 'cm-license:client:updateHUD',
            COMPLETION_REJECTED = 'cm-license:client:completionRejected',
            CHECKPOINT_REJECTED = 'cm-license:client:checkpointRejected',
            TEST_RESULT = 'cm-license:client:testResult',
        },
    },

    -- Marks a revocation caused by the player discarding the physical card.
    -- Only a revocation carrying this reason can be undone by picking the card
    -- back up; an admin revocation is never reversed that way.
    DISCARD_REASON = 'license_item_discarded',

    -- Permission strings
    PERMISSIONS = {
        MANAGE_LICENSES = 'admin.manage_licenses',
        ISSUE_LICENSES = 'admin.issue_licenses',
        REVOKE_LICENSES = 'admin.revoke_licenses',
    },
}

function CMLog(...)
    if CMLicenseConfig and CMLicenseConfig.Debug then
        print('^2[CM-License]^7', ...)
    end
end

return Constants
