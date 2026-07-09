CMUI = CMUI or {}

CMUI.Theme = {
    name = 'CM Blue/Cyan',
    version = '1.0.0',

    colors = {
        bg = '#07111f',
        panel = '#081222',
        panelSoft = '#0c1a2e',
        primary = '#00e5ff',
        primaryDark = '#0891b2',
        blue = '#2563eb',
        success = '#22c55e',
        warning = '#f59e0b',
        danger = '#ef4444',
        text = '#eaf7ff',
        muted = '#8aa4b8'
    },

    nui = {
        useBackdropFilter = false,
        fontFamily = 'Inter, Segoe UI, Roboto, Arial, sans-serif',
        radius = 16
    }
}

exports('GetTheme', function()
    return CMUI.Theme
end)

exports('GetColor', function(key)
    return CMUI.Theme.colors[key]
end)
