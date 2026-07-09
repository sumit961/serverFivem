Config = {}

Config.Debug = false

-- Admin access:
-- Your server.cfg already has: add_ace group.admin command allow
-- This resource also supports a dedicated permission: cmclimatime.admin
Config.Admin = {
    Command = 'climatime',
    CommandAlias = 'weatheradmin',
    AllowEveryone = false, -- set true only while testing alone
    AcePermission = 'cmclimatime.admin',
    ViewAcePermission = 'cmclimatime.view',
    EditAcePermission = 'cmclimatime.edit',
    -- cm-admin rank permission (manage from the admin panel Ranks tab)
    RankPermission = 'dev.climatime',
    ViewRankPermission = 'dev.climatime.view',
    EditRankPermission = 'dev.climatime.edit'
}

Config.UI = {
    Brand = 'Climatime',
    -- cyan keeps your CM blue/cyan theme. Change here or in cm-ui to update the whole visual style.
    Accent = '#00e5ff',
    Size = 'large'
}


Config.Map = {
    -- Calibrated GTA map bounds shared with cm-admin map calibration.
    Bounds = {
        minX = -3900,
        maxX = 4619,
        minY = -4764,
        maxY = 7510
    }
}

-- Notifications are silent in normal gameplay. Weather/time changes should not
-- spam GTA feed notifications for players. Admin feedback is shown inside the
-- Climatime NUI panel when it is open.
Config.Notifications = {
    UseGtaFeed = false,
    UiToasts = true,
    WeatherChangeToasts = false,
    AdminActionToasts = true
}



-- ==========================================================================
-- Startup / spawn integration
-- cm-climatime should not control weather/time during login, character
-- selection, or appearance creation. With this enabled, the client stores
-- synced state but only starts applying it after cm-spawn emits:
--   cm-spawn:client:spawned
-- ==========================================================================
Config.Startup = {
    -- 'cm-spawn' = recommended for CM Framework.
    -- 'immediate' = old behaviour; applies weather/time after resource start.
    -- 'disabled' = never auto-start; another resource/export must start it.
    StartMode = 'cm-spawn',
    RequireCmSpawn = true,
    ActivateIfAlreadySpawned = true,
    StartDelayMs = 900,
    RequestDebounceMs = 1500,
    DebugLifecycle = false
}


-- v1.5.6 preferred flow: cm-characters asks climatime to prepare live
-- weather/time while the screen is still black BEFORE cm-spawn reveals the
-- player. This removes the visible post-spawn sky/time jump.
Config.PreSpawnPrepare = {
    Enabled = true,
    WeatherTransitionSeconds = 1.2,
    RainRampSeconds = 1.2,
    PrepareMs = 2600,
    ValidMs = 25000,
    -- Guards to prevent duplicate spawn preloads from overflowing reliable events.
    ClientThrottleMs = 900,
    ServerRequestThrottleMs = 1500,
    ServerClientPrepareNudge = false,
    Debug = false
}

-- Old post-spawn handoff fallback. Leave disabled when PreSpawnPrepare is used.
Config.SpawnHandoff = {
    Enabled = false,
    FromWeather = 'CLEAR',
    FromHour = 23,
    FromMinute = 0,
    HoldMs = 1200,
    WeatherTransitionSeconds = 32,
    TimeBlendSeconds = 9,
    RainRampSeconds = 10,
    Debug = false
}

Config.Time = {
    -- Default mode. Admin can still manually override/freeze from UI.
    UseRealLifeTime = true,

    -- true = use the machine/server local time.
    -- false = use UTC + TimezoneOffsetMinutes.
    UseServerLocalTime = true,
    TimezoneOffsetMinutes = 0,

    -- Manual "running" time speed multiplier (1 = real minutes, 5 = 5x, etc).
    -- Only used in manual non-frozen mode.
    Speed = 1,

    DefaultHour = 12,
    DefaultMinute = 0,

    -- How often server resends state so everyone stays exactly synced.
    SyncIntervalSeconds = 30
}

-- ===========================================================================
-- High-end dynamic weather: profiles (weighted pools) + realistic transition
-- chains, so weather evolves believably instead of jumping at random.
-- ===========================================================================
Config.DynamicMode = 'forecast' -- 'forecast' (chain-based) or 'random' (legacy pool)

Config.WeatherProfiles = {
    normal = {
        label = 'Normal Los Santos',
        pool = { CLEAR = 32, EXTRASUNNY = 24, CLOUDS = 20, OVERCAST = 12, RAIN = 7, FOGGY = 5 }
    },
    hot_summer = {
        label = 'Hot Summer',
        pool = { EXTRASUNNY = 55, CLEAR = 30, CLOUDS = 12, SMOG = 3 }
    },
    rainy_week = {
        label = 'Rainy Week',
        pool = { OVERCAST = 28, RAIN = 34, CLOUDS = 18, CLEARING = 12, THUNDER = 8 }
    },
    storm = {
        label = 'Storm Event',
        pool = { OVERCAST = 28, RAIN = 34, THUNDER = 26, CLEARING = 12 }
    },
    winter = {
        label = 'Winter Snow',
        pool = { SNOW = 40, SNOWLIGHT = 30, BLIZZARD = 12, CLOUDS = 10, OVERCAST = 8 }
    },
    foggy_morning = {
        label = 'Foggy Morning',
        pool = { FOGGY = 45, CLOUDS = 25, OVERCAST = 18, CLEARING = 12 }
    },
    halloween = {
        label = 'Halloween',
        pool = { HALLOWEEN = 45, FOGGY = 25, OVERCAST = 20, THUNDER = 10 }
    },
    christmas = {
        label = 'Christmas',
        pool = { XMAS = 45, SNOW = 30, SNOWLIGHT = 25 }
    }
}

Config.DefaultProfile = 'normal'

-- Realistic transition chains: from a given weather, only these can come next
-- (filtered by the active profile's pool). Prevents EXTRASUNNY -> THUNDER jumps.
Config.WeatherChains = {
    EXTRASUNNY = { 'EXTRASUNNY', 'CLEAR', 'CLOUDS' },
    CLEAR      = { 'CLEAR', 'EXTRASUNNY', 'CLOUDS', 'FOGGY' },
    CLOUDS     = { 'CLOUDS', 'CLEAR', 'OVERCAST', 'FOGGY' },
    OVERCAST   = { 'OVERCAST', 'CLOUDS', 'RAIN', 'FOGGY', 'SNOW' },
    RAIN       = { 'RAIN', 'THUNDER', 'CLEARING', 'OVERCAST' },
    THUNDER    = { 'THUNDER', 'RAIN', 'CLEARING' },
    CLEARING   = { 'CLEARING', 'CLOUDS', 'CLEAR' },
    FOGGY      = { 'FOGGY', 'CLOUDS', 'CLEAR', 'OVERCAST' },
    SMOG       = { 'SMOG', 'CLOUDS', 'CLEAR' },
    SNOW       = { 'SNOW', 'SNOWLIGHT', 'BLIZZARD', 'OVERCAST' },
    SNOWLIGHT  = { 'SNOWLIGHT', 'SNOW', 'CLOUDS', 'OVERCAST' },
    BLIZZARD   = { 'BLIZZARD', 'SNOW', 'SNOWLIGHT' },
    XMAS       = { 'XMAS', 'SNOW', 'SNOWLIGHT' },
    HALLOWEEN  = { 'HALLOWEEN', 'FOGGY', 'OVERCAST', 'THUNDER' },
    NEUTRAL    = { 'CLEAR', 'CLOUDS' }
}

-- Forecast queue: how many upcoming weather events to precompute/show.
Config.ForecastLength = 4

-- Zone hysteresis: enter at radius, only leave once past radius * this factor.
-- Stops weather flickering at zone edges.
Config.Zones = Config.Zones or {}
Config.ZoneExitMultiplier = 1.15

-- Admin action logging to the database (staff accountability).
Config.LogAdminActions = true


-- ===========================================================================
-- Advanced weather polish
-- ===========================================================================
Config.WeatherEffects = {
    -- Fixes GTA/FiveM issue where RAIN weather can visually change sky but no
    -- rain particles appear. These rain levels are applied after weather change.
    RainLevels = {
        RAIN = 0.65,
        THUNDER = 0.95,
        CLEARING = 0.22,
        HALLOWEEN = 0.20,
        BLIZZARD = 0.10,
        SNOW = 0.05,
        SNOWLIGHT = 0.03
    },
    Wind = {
        RAIN = 4.0,
        THUNDER = 9.0,
        BLIZZARD = 8.0,
        FOGGY = 1.5
    },
    SmoothDefault = true,
    RainRampSeconds = 10
}

Config.ZoneBlending = {
    Enabled = true,
    -- Inner area is fully local zone weather. Between radius and radius *
    -- EdgeMultiplier we keep the previous local zone briefly and use a softer
    -- transition instead of hard snapping back to global weather.
    EdgeMultiplier = 1.22,
    MinBlendAlpha = 0.12,
    SoftTransitionSeconds = 25
}

Config.ZoneDebug = {
    Enabled = true,
    HeartbeatMs = 5000,
    OverlayCommand = 'climazone',
    DrawDistance = 450.0
}

Config.Temperature = {
    Enabled = true,
    BaseC = 24,
    WeatherOffsets = {
        EXTRASUNNY = 8, CLEAR = 4, CLOUDS = 0, OVERCAST = -2, CLEARING = -1,
        RAIN = -4, THUNDER = -6, FOGGY = -5, SMOG = 3,
        SNOW = -14, SNOWLIGHT = -12, BLIZZARD = -18, XMAS = -12, HALLOWEEN = -3
    },
    NightOffsetC = -4,
    MorningOffsetC = -2
}

Config.GameplayEffects = {
    Enabled = true,
    WetRoads = true,
    StormTraction = true,
    FogTimecycle = false,
    Temperature = true,
    SeasonalEvents = true
}

Config.EventPresets = {
    storm_warning = {
        label = 'Storm Warning',
        weather = 'THUNDER',
        durationMinutes = 45,
        transitionSeconds = 35,
        blackout = false,
        message = 'Storm warning active across Los Santos.'
    },
    heatwave = {
        label = 'Heatwave',
        weather = 'EXTRASUNNY',
        profile = 'hot_summer',
        durationMinutes = 90,
        transitionSeconds = 30,
        message = 'Heatwave conditions are active.'
    },
    foggy_morning = {
        label = 'Foggy Morning',
        weather = 'FOGGY',
        profile = 'foggy_morning',
        durationMinutes = 40,
        transitionSeconds = 25,
        message = 'Dense fog is rolling in.'
    },
    halloween = {
        label = 'Halloween Night',
        weather = 'HALLOWEEN',
        profile = 'halloween',
        durationMinutes = 120,
        transitionSeconds = 30,
        message = 'Halloween weather event started.'
    },
    christmas_snow = {
        label = 'Christmas Snow',
        weather = 'XMAS',
        profile = 'christmas',
        durationMinutes = 120,
        transitionSeconds = 30,
        snow = true,
        message = 'Christmas snow event started.'
    }
}

Config.Weather = {
    Start = 'CLEAR',
    Dynamic = true,
    DefaultDurationMinutes = 30,
    TransitionSeconds = 20,
    InstantChange = false,
    SmoothChange = true,
    NotifyPlayers = false,

    -- More common weather will be repeated more often in random rotation.
    DynamicPool = {
        'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'CLEARING',
        'RAIN', 'FOGGY', 'SMOG', 'THUNDER'
    },

    -- All weather options shown in UI.
    AllTypes = {
        { value = 'EXTRASUNNY', label = 'Extra Sunny', icon = '☀' },
        { value = 'CLEAR',      label = 'Clear',       icon = '☀' },
        { value = 'NEUTRAL',    label = 'Neutral',     icon = '◐' },
        { value = 'CLOUDS',     label = 'Clouds',      icon = '☁' },
        { value = 'OVERCAST',   label = 'Overcast',    icon = '☁' },
        { value = 'CLEARING',   label = 'Clearing',    icon = '⛅' },
        { value = 'RAIN',       label = 'Rain',        icon = '🌧' },
        { value = 'THUNDER',    label = 'Thunder',     icon = '⛈' },
        { value = 'FOGGY',      label = 'Foggy',       icon = '🌫' },
        { value = 'SMOG',       label = 'Smog',        icon = '🌫' },
        { value = 'SNOW',       label = 'Snow',        icon = '❄' },
        { value = 'SNOWLIGHT',  label = 'Light Snow',  icon = '❄' },
        { value = 'BLIZZARD',   label = 'Blizzard',    icon = '❄' },
        { value = 'XMAS',       label = 'Christmas',   icon = '🎄' },
        { value = 'HALLOWEEN',  label = 'Halloween',   icon = '☾' }
    }
}

Config.Zones = {
    Enabled = true,
    DefaultRadius = 200.0,
    CheckIntervalMs = 1200,
    TransitionSeconds = 10,
    DynamicDurationMinutes = 20,
    MaxRadius = 5000.0
}


Config.Sync = Config.Sync or {
    LatentThresholdBytes = 65536,
    LatentBps = 25000,
    RequestThrottleMs = 750
}
