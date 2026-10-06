Config = Config or {}

Config.Security = {
    discoveryCooldownMs = 1000,
    adminCooldownMs = 500,
    maxLandmarkId = 48,
    maxName = 80,
    maxDescription = 255,
    maxCategory = 32,
    maxDisplayLabel = 80,
    minRadius = 1.0,
    maxRadius = 100.0,
    minCoordinate = -10000.0,
    maxCoordinate = 10000.0,
    minZ = -2000.0,
    maxZ = 3000.0,
    maxHeading = 360.0,
    maxRoutingBucket = 65535,
    maxBlipSprite = 1000,
    maxBlipColor = 1000,
    maxBlipScale = 5.0,
}

-- This is an existing cm-admin permission contract. cm-discovery does not
-- create or modify administrator permissions.
Config.Admin = {
    permission = 'orgs.manage',
    invokingResource = 'cm-admin',
}

Config.Discovery = {
    markerDistance = 85.0,
    marker = {
        type = 1,
        scale = { x = 0.65, y = 0.65, z = 0.18 },
        colour = { r = 0, g = 229, b = 255, a = 135 },
        bobUpAndDown = false,
        faceCamera = false,
        rotate = false,
    },
}

-- Landmark definitions are deliberately empty. Administrators must create
-- configured landmarks through the restricted server exports. No permanent
-- production coordinates are invented or seeded here.
Config.DefaultLandmarks = {}
