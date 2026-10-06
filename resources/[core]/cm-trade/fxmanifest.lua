fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework'
description 'Authoritative nearby player-to-player trading (cash + inventory items) with a journaled settlement saga.'
version '1.0.0'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/schema.lua',
    'server/core.lua',
    'server/events.lua',
    'server/selftest.lua',
}

client_scripts {
    'client/client.lua',
}
