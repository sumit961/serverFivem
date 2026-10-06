Config = Config or {}

Config.Security = {
    actionCooldownMs = 1000,
    adminCooldownMs = 500,
    maxEventId = 48,
    maxTitle = 96,
    maxDescription = 255,
    maxCategory = 32,
    maxDisplayLabel = 80,
    maxCancellationReason = 160,
    maxCapacity = 100000,
    maxEventDurationSeconds = 31536000,
    minRadius = 1.0,
    maxRadius = 100.0,
    minCoordinate = -10000.0,
    maxCoordinate = 10000.0,
    minZ = -2000.0,
    maxZ = 3000.0,
    maxHeading = 360.0,
    maxRoutingBucket = 65535,
    maxColourLength = 7,
}

-- Existing cm-admin permission contract. This resource does not add or
-- modify administrator permissions.
Config.Admin = {
    permission = 'orgs.manage',
    invokingResource = 'cm-admin',
}

Config.Calendar = {
    markerDistance = 85.0,
    clientRefreshMs = 15000,
    marker = {
        type = 1,
        scale = { x = 0.72, y = 0.72, z = 0.18 },
        colour = { r = 0, g = 229, b = 255, a = 135 },
        bobUpAndDown = false,
        faceCamera = false,
        rotate = false,
    },
}

-- There are intentionally no seeded events or production coordinates.
Config.DefaultEvents = {}
