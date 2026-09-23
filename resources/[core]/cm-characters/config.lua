Config = Config or {}

-- Change this later for VIP/admin slots without editing UI/server loops.
Config.MaxCharacters = Config.MaxCharacters or 2
Config.MinCharacterAge = Config.MinCharacterAge or 16
Config.MaxCharacterAge = Config.MaxCharacterAge or 100

-- Selector polish/loading timings. Increase if slow PCs still see a blink.
Config.SelectorInitialLoadingMs = Config.SelectorInitialLoadingMs or 1800
Config.SpawnTransitionLoadingMs = Config.SpawnTransitionLoadingMs or 2500

-- Admin/production safety. Commands below still require ACE/cm-auth permissions.
Config.EnableDevCommands = Config.EnableDevCommands or false
-- Production logging: keep false on live server. Set true only when debugging character selector issues.
Config.Debug = Config.Debug == true
Config.VerboseLogs = Config.VerboseLogs == true
Config.AdminPermission = Config.AdminPermission or 'characters.admin'
Config.EditorPermission = Config.EditorPermission or 'characters.selector.edit'

-- Production routing rules.
-- cm-characters owns only selector, creator, appearance save, and safe character exports.
-- Full staff/admin menus belong in cm-admin. Keep legacy character admin UI disabled unless you are migrating.
Config.ProductionMode = Config.ProductionMode ~= false
Config.EnableLegacyCharacterAdmin = Config.EnableLegacyCharacterAdmin or false
Config.EnableManualSelectorCommand = Config.EnableManualSelectorCommand or false
Config.EnableSelectorSceneEditor = Config.EnableSelectorSceneEditor ~= false

-- New character starter money. cm-playerdata is the runtime money owner after load.
Config.StartingCash = Config.StartingCash or 500
Config.StartingBank = Config.StartingBank or 2000

-- Server-side event rate limits. These are intentionally gentle and only stop spam/abuse.
Config.RateLimits = Config.RateLimits or {
    getSlots = { limit = 8, seconds = 10 },
    selectCharacter = { limit = 4, seconds = 10 },
    createCharacter = { limit = 3, seconds = 30 },
    saveAppearance = { limit = 3, seconds = 30 },
    saveCurrentAppearance = { limit = 6, seconds = 60 }
}


-- While player is in character selection / creation, cm-characters owns the local
-- world state. This prevents cm-climatime or other weather resources from changing
-- the preview scene and keeps the screen in a clean fixed night setup.
Config.CharacterScreenWorld = Config.CharacterScreenWorld or {
    enabled = true,
    weather = 'CLEAR',
    hour = 23,
    minute = 0,
    second = 0,
    hideHud = true,
    hideNativeHud = false,
    -- Do not hide GTA radar/minimap from character flow. Only hide cm-hud NUI.
    hideRadar = false,
    suppressClimatime = true,
    hudPulseMs = 650,

    -- Do not constantly force weather. Constant forcing fights cm-climatime and
    -- causes sky/weather blinking. Weather is applied once when selector opens.
    reapplyWeatherWhileLocked = false,
    weatherSoftPulseMs = 8000,

    -- Clock can stay locked every frame without weather flicker.
    clockPulseMs = 0,

    -- Preferred v1.5.6 flow: prepare live cm-climatime BEFORE the real spawn is revealed.
    -- This means the player spawns into the correct weather/time already, instead
    -- of seeing the sky change after spawn.
    preSpawnClimatePrepare = true,
    preSpawnFadeOutMs = 350,
    preSpawnClimatePrepareMs = 2600,
    preSpawnWeatherTransitionSeconds = 1.2,
    preSpawnRainRampSeconds = 1.2,
    preSpawnValidMs = 25000,

    -- Old post-spawn smooth handoff. Keep as fallback only when pre-spawn prepare
    -- is disabled or cm-climatime is missing.
    smoothClimatimeHandoff = false,
    handoffHoldMs = 1200,
    handoffWeatherTransitionSeconds = 32,
    handoffTimeBlendSeconds = 9,
    handoffRainRampSeconds = 10,

    -- After character spawn, resume cm-climatime more than once in case spawn,
    -- hud, or playerdata resources finish a moment later.
    resumeRetries = 4,
    resumeRetryDelayMs = 900
}

-- Barber Shop grooming service configuration
Config.BarberCost = 100
Config.BarberShops = {
    { id = "davis", name = "Davis Barber", coords = vector3(136.83, -1708.38, 29.29), blip = 71 },
    { id = "hawick", name = "Hawick Barber", coords = vector3(-32.88, -152.31, 57.08), blip = 71 },
    { id = "rockford", name = "Rockford Hills Barber", coords = vector3(-814.31, -183.82, 37.57), blip = 71 },
    { id = "vespucci", name = "Vespucci Beach Barber", coords = vector3(-1282.6, -1116.76, 6.99), blip = 71 },
    { id = "sandy", name = "Sandy Shores Barber", coords = vector3(1931.54, 3729.67, 32.84), blip = 71 },
    { id = "paleto", name = "Paleto Bay Barber", coords = vector3(-278.06, 6228.46, 31.69), blip = 71 },
    { id = "mirror_park", name = "Mirror Park Barber", coords = vector3(1212.84, -472.92, 66.21), blip = 71 },
}

-- Barber Shop / Hair Salon Commercial Ownership & Management
Config.BarberOwnership = {
    enabled = true,
    purchasePrice = 200000,     -- $200,000 to acquire a hair salon commercial property (bank payment)
    taxAmount = 12000,         -- $12,000 property tax due every 7 days
    taxPeriodDays = 7,         -- 7-day tax cycle
    ownerRevenuePercent = 80,  -- 80% of customer styling fees go to salon business account
    defaultStock = 1000,       -- Initial grooming supplies units upon salon creation/forfeiture
    maxStock = 5000,           -- Maximum grooming supplies capacity
    restockUnitPrice = 8,      -- $8 per grooming supply unit
    restockBatch = 250,        -- Batch order of 250 units ($2,000 bank payment)
    baseCost = 100,            -- Base service cost ($100)
    priceTiers = {             -- Dynamic pricing tiers for salon customers
        low = 0.80,            -- $80 (-20% discount to attract customers)
        normal = 1.00,         -- $100 (standard salon fee)
        high = 1.50,           -- $150 (+50% luxury salon fee)
    },
}
