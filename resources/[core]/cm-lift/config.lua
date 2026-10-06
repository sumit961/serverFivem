Config = Config or {}

-- Local development diagnostics are enabled while the Hotel lift is being
-- validated. Set false before deploying to a production server.
Config.Debug = true

-- Sessions are intentionally short-lived. The owning resource remains
-- responsible for deciding whether the player may use its lift.
Config.SessionLifetimeMs = 30000
Config.OpenRateLimitMs = 1000
Config.SelectionRateLimitMs = 500
Config.TeleportCooldownMs = 1200

Config.FadeOutDurationMs = 450
Config.FadeInDurationMs = 350
Config.FadeTimeoutMs = 2500
Config.CollisionTimeoutMs = 6000

Config.MaxFloors = 32
Config.MaxIdLength = 64
Config.MaxLabelLength = 80
Config.MaxSubtitleLength = 120
Config.MaxIconLength = 40
Config.MaxExitOffset = 10.0
