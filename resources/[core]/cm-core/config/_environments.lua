-- Environment-specific overrides. Loaded after _master.lua.

CM = CM or {}
CM.Config = CM.Config or {}

local env = GetConvar('cm_environment', GetConvar('cm_env', 'production'))

local overrides = {
    development = {
        Server = { devMode = true, whitelistEnabled = false, maxPlayers = 10 },
        Logging = { level = 'debug', logToFile = false },
        Security = { hwidCheck = false },
        Core = { stateDebug = true },
    },
    staging = {
        Server = { devMode = false, maxPlayers = 32 },
        Logging = { level = 'info' },
    },
    production = {
        Server = { devMode = false },
        Logging = { level = GetConvar('cm_log_level', 'info') },
    },
}

if overrides[env] then
    for section, values in pairs(overrides[env]) do
        CM.Config[section] = CM.Config[section] or {}
        for key, value in pairs(values) do
            CM.Config[section][key] = value
        end
    end
end

if IsDuplicityVersion() then
    SetConvar('cm_env', env)
end
