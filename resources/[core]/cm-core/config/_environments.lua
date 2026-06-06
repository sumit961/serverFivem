-- cm-core/config/_environments.lua
-- Environment-specific overrides. Loaded AFTER _master.lua.

local env = GetConvar("cm_environment", "production")

local overrides = {
    development = {
        Server = { devMode = true, whitelistEnabled = false, maxPlayers = 10 },
        Database = { host = "127.0.0.1", password = "your_mysql_password" },
        Logging = { level = "debug", discordWebhook = "" },
        Security = { hwidCheck = false },
    },
    staging = {
        Server = { devMode = false, maxPlayers = 32 },
        Logging = { level = "info" },
    },
    production = {},
}

if overrides[env] then
    for section, values in pairs(overrides[env]) do
        for key, value in pairs(values) do
            if CM.Config[section] then
                CM.Config[section][key] = value
            end
        end
    end
end

-- Only set convar on server side
if IsDuplicityVersion() then
    SetConvar("cm_env", env)
end