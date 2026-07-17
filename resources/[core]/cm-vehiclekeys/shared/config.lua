Config = Config or {}

Config.VehicleKeys = {
    -- Temporary keys are removed when the receiving character unloads,
    -- switches character, disconnects, or the resource restarts.
    defaultDurationSeconds = 0,
    maxDurationSeconds = 86400,

    -- Server-side protection for owner-to-player key sharing.
    requireSameRoutingBucket = true,
    maxGrantDistance = 6.0,

    -- Active character state keys checked in order.
    characterStateKeys = {
        'charId',
        'characterId',
        'character_id',
        'citizenid'
    },

    -- Detect character changes even if another resource does not explicitly
    -- call the lifecycle exports below.
    characterPollIntervalMs = 2500,

    maxPlateLength = 16,

    -- Only these server resources may create/revoke family session keys.
    -- Client events cannot call these exports.
    trustedFamilyResources = {
        'cm-vehicles',
        'cm-family',
        'cm-house',
        'cm-admin',
    },

    debug = false
}
