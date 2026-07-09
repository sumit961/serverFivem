CM = CM or {}

CM.Shared = {
    Keys = {
        INTERACT = 38,
        CANCEL = 177,
        PHONE = 311,
        INVENTORY = 289,
        VOICE = 137,
        HUD = 212,
    },

    Theme = {
        primary = '#00e5ff',
        secondary = '#2563eb',
        background = '#07111f',
        panel = 'rgba(8, 18, 34, 0.96)',
        border = 'rgba(0, 229, 255, 0.35)',
        text = '#eaf7ff',
        muted = '#8aa4b8',
        success = '#22c55e',
        warning = '#facc15',
        error = '#ef4444',
        info = '#38bdf8',
    },

    Notify = {
        position = 'top-right',
        duration = 5000,
    },

    Time = {
        dateFormat = '%d/%m/%Y',
        timeFormat = '%H:%M',
        timezone = 'Australia/Sydney',
    },

    Distance = {
        interaction = 2.0,
        voice = 15.0,
        whisper = 5.0,
        yell = 30.0,
    },
}

if IsDuplicityVersion() then
    GlobalState.CMShared = CM.Shared
else
    CM.Shared = GlobalState.CMShared or CM.Shared
end
