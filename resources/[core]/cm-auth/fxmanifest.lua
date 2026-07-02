fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM-Auth: GTA IV-style loading screen, styled auth UI, trusted-device login, and 10-tier RBAC admin auth'
version '2.2.3-native-passwordhash-fix'

dependencies {
    'oxmysql',
    'cm-core'
}

loadscreen 'loading/index.html'
loadscreen_cursor 'yes'
loadscreen_manual_shutdown 'yes'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
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
