CMUI = CMUI or {}

CMUI.Theme = {
    name = 'CM Cyan/Deep Teal',
    version = '2.0.0',

    colors = {
        bg = '#0B171E',
        bgDeep = '#10222B',
        panel = 'rgba(18, 36, 47, 0.94)',
        panelSolid = '#142733',
        border = '#213B4A',
        cyan = '#00E5FF',
        blue = '#1E88E5',
        yellow = '#FFC700',
        green = '#2ECC71',
        orange = '#FF8C00',
        red = '#E74C3C',
        text = '#FFFFFF',
        textSecondary = '#C2D2DC',
        textMuted = '#829DAE',

        -- Semantic aliases
        primary = '#00E5FF',
        primaryDark = '#1E88E5',
        success = '#2ECC71',
        warning = '#FFC700',
        danger = '#E74C3C',
        info = '#00E5FF',
        muted = '#829DAE'
    },

    nui = {
        useBackdropFilter = false,
        fontFamily = '"DM Sans", "Segoe UI", Arial, sans-serif',
        fontDisplay = '"Poppins", "DM Sans", sans-serif',
        radius = '0.5rem'
    }
}

exports('GetTheme', function()
    return CMUI.Theme
end)

exports('GetColor', function(key)
    return CMUI.Theme.colors[key]
end)
