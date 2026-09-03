-- CM License System — Shared Constants

local Constants = {
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
        ADMIN_CANCELLED = 'admin_cancelled',
        WRONG_CHECKPOINT_ORDER = 'wrong_checkpoint_order',
        SPEEDING = 'speeding',
        ALTITUDE_VIOLATION = 'altitude_violation',
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
        admin_cancelled = 'Test was cancelled by an administrator',
        wrong_checkpoint_order = 'You entered checkpoints out of order',
        speeding = 'Exceeded speed limit',
        altitude_violation = 'Violated altitude restrictions',
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
            INTERACT_NPC = 'cm-license:server:interactNPC',
            REQUEST_START_TEST = 'cm-license:server:requestStartTest',
            START_TEST = 'cm-license:server:startTest',
            CHECKPOINT_REACHED = 'cm-license:server:checkpointReached',
            FINISH_TEST = 'cm-license:server:finishTest',
            CANCEL_TEST = 'cm-license:server:cancelTest',
            TEST_FAILED = 'cm-license:server:testFailed',
            LICENSE_ISSUED = 'cm-license:server:licenseIssued',
        },
        CLIENT = {
            TEST_STARTED = 'cm-license:client:testStarted',
            SET_CHECKPOINT = 'cm-license:client:setCheckpoint',
            TEST_COMPLETED = 'cm-license:client:testCompleted',
            TEST_FAILED = 'cm-license:client:testFailed',
            UPDATE_HUD = 'cm-license:client:updateHUD',
        },
    },

    -- Permission strings
    PERMISSIONS = {
        MANAGE_LICENSES = 'admin.manage_licenses',
        ISSUE_LICENSES = 'admin.issue_licenses',
        REVOKE_LICENSES = 'admin.revoke_licenses',
    },
}

if GetResourceState('cm-license') == 'started' then
    _G.CMLog = function(...)
        print('^2[CM-License]^7', ...)
    end
end

return Constants
