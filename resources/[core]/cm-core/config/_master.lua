CM = CM or {}

CM.Config = {
    Server = {
        name = "Grand RP Style Server",
        maxPlayers = 128,
        whitelistEnabled = false,
        queueEnabled = true,
        devMode = true,
    },

    Database = {
        host = "localhost",
        port = 3306,
        user = "root",
        password = "your_mysql_password",
        database = "grandrp",
        maxConnections = 10,
        slowQueryThreshold = 100,
    },

    Characters = {
        maxPerAccount = 2,
        minNameLength = 2,
        maxNameLength = 20,
        blockedNames = {"admin", "owner", "mod", "staff", "support", "nigger", "faggot", "hitler"},
        namePattern = "^[A-Za-z%-%s]+$",
    },

    Spawn = {
        defaultPosition = {x = -1037.0, y = -2737.0, z = 13.8, heading = 0.0},
        defaultDimension = 0,
        hotelInterior = "v_motel_mp",
        tutorialFreezeTime = 3000,
    },

    Economy = {
        startingCash = 500,
        startingBank = 2000,
        maxCash = 999999,
        maxBank = 99999999,
    },

    Rank = {
        xpPer15Min = 10,
        xpSources = {
            playtime = 10,
            tutorial = {min = 50, max = 500},
            job = {min = 25, max = 100},
            gang = {min = 10, max = 50},
        },
    },

    Logging = {
        level = "debug",
        discordWebhook = "",
        logToDatabase = true,
        logToFile = true,
        logPath = "logs/",
    },

    Security = {
        maxLoginAttempts = 5,
        lockoutMinutes = 30,
        requireEmailVerification = false,
        hwidCheck = false,
    },
}

return CM.Config