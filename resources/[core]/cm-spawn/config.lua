-- cm-spawn/config.lua
-- Production-safe spawn selector configuration for CM Framework.

Config = Config or {}

-- Keep production quiet. Turn these on only while debugging spawn issues.
Config.Debug = false
Config.VerboseLogs = false

-- First-time players spawn here automatically.
Config.DefaultFirstSpawn = 'hotel'

-- How long the client waits while hidden for climate/time systems to apply before reveal.
Config.PreSpawnClimateWait = 350

-- Spawn page climate preload. This runs during the black/selector transition so the
-- city weather/time is already synced before the player sees the spawn page/reveal.
Config.SpawnPageClimateWait = 120
Config.SpawnPageClimatePrepareMs = 900
Config.SpawnPageClimateValidMs = 30000


-- Manual recovery commands are useful in development, but should stay disabled in production.
Config.EnableDevCommands = false
Config.EnableClientFixCommand = false

-- Keep true for fresh installs. In production, after running sql/upgrade_has_spawned.sql once,
-- you can set this false to avoid the startup schema check.
Config.AutoEnsureHasSpawnedColumn = true

-- Future-proof organization integration. This lets one generic spawn point support
-- gangs, police, army, companies, government, clubs, or any custom org later.
Config.OrganizationSpawn = {
    enabled = true,
    resource = 'cm-organizations',
    fallbackLockedReason = 'Join an organization with an assigned spawn to unlock this.',
    defaultLabel = 'ORGANIZATION',
    defaultDescription = 'Spawn at your organization base when one is assigned.',
    defaultIcon = 'fa-building-shield',
    defaultColor = 'cyan',
    defaultImage = 'assets/organization.svg'
}
