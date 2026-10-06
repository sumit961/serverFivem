fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM-Auth: GTA IV-style loading screen, styled auth UI, trusted-device login, and character selector handoff'
version '2.4.0-modular'

dependencies {
    'cm-ui',
    'oxmysql',
    'cm-core'
}

-- Player-facing branding (window.CMBranding) now lives in cm-ui, which is
-- already a hard dependency here (nui://cm-ui/web/cm-branding.js), so every
-- onboarding/NUI screen in the server shares exactly one canonical source.

loadscreen 'loading/index.html'
loadscreen_cursor 'yes'
loadscreen_manual_shutdown 'yes'

-- Config is shared so client and server read the same tunables.
shared_scripts {
    'shared/config.lua',
}

-- shared/branding.js is NOT a Lua shared_script — it's plain JS served to the
-- NUI pages below (loading/index.html and ui/index.html both load it) so the
-- player-facing server name/tagline lives in exactly one place.

-- Server modules load in dependency order, entry point last.
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/modules/util.lua',
    'server/modules/crypto.lua',
    'server/modules/database.lua',
    'server/modules/identity.lua',
    'server/modules/security.lua',
    'server/server.lua',
}

client_scripts {
    'client/client.lua',
}

ui_page 'ui/index.html'

files {
    'loading/index.html',
    'loading/style.css',
    'loading/script.js',
    'loading/config.js',
    'loading/audio/loading-theme.wav',
    -- Slide artwork placeholders (slide-01..04). Config-driven, PNG/WebP only
    -- — the old SVG illustrations were confirmed unused and removed.
    'loading/assets/*.webp',
    'loading/assets/*.png',

    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    -- Hero artwork placeholder (login-hero). PNG/WebP only — the old SVG
    -- illustrations (auth-bg.svg, hero-female.svg) were confirmed unused and
    -- removed.
    'ui/assets/*.webp',
    'ui/assets/*.png',
}
