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

loadscreen 'loading/index.html'
loadscreen_cursor 'yes'
loadscreen_manual_shutdown 'yes'

-- Config is shared so client and server read the same tunables.
shared_scripts {
    'shared/config.lua',
}

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
    'loading/assets/*.svg',

    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/assets/*.svg',
}
