CM = CM or {}

CM.Config = {
    Server = {
        name = GetConvar('sv_hostname', 'Grand RP by Sumit_Yadav'),
        maxPlayers = tonumber(GetConvar('sv_maxclients', '128')) or 128,
        whitelistEnabled = GetConvar('cm_whitelist', 'false') == 'true',
        queueEnabled = GetConvar('cm_queue', 'true') == 'true',
        devMode = GetConvar('cm_dev_mode', 'false') == 'true',
    },

    Core = {
        -- Temporary bridge only. Real cash/bank ownership should live in cm-playerdata.
        legacyMoneyBridge = GetConvar('cm_core_legacy_money', 'true') == 'true',
        auditToDatabase = true,
        stateDebug = false,
    },

    Database = {
        slowQueryThreshold = tonumber(GetConvar('cm_slow_query_ms', '150')) or 150,
    },

    Characters = {
        maxPerAccount = 2,
        minNameLength = 2,
        maxNameLength = 20,
        blockedNames = {'admin', 'owner', 'mod', 'staff', 'support', 'hitler'},
        namePattern = '^[A-Za-z%-%s]+$',
    },

    Spawn = {
        defaultPosition = {x = -1037.0, y = -2737.0, z = 13.8, heading = 0.0},
        defaultDimension = 0,
    },

    -- Legacy caps for compatibility wrappers only. Real balance logic should move to cm-playerdata.
    Economy = {
        startingCash = 500,
        startingBank = 2000,
        maxCash = 999999999,
        maxBank = 9999999999,
    },

    Logging = {
        level = GetConvar('cm_log_level', 'info'),
        discordWebhook = GetConvar('cm_discord_webhook', ''),
        logToDatabase = GetConvar('cm_log_database', 'true') == 'true',
        logToFile = GetConvar('cm_log_file', 'false') == 'true',
        logPath = GetConvar('cm_log_path', 'logs/'),
    },

    Security = {
        maxLoginAttempts = 5,
        lockoutMinutes = 30,
        requireEmailVerification = false,
        hwidCheck = false,
    },
}

return CM.Config
