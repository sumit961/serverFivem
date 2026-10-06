fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Construction - Municipal Infrastructure, Public Works & Heavy Maintenance'
author 'CM Framework'
version '1.0.0'

shared_scripts {
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
    'client/npc.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'shared/config.lua',
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
}

dependencies {
    'oxmysql',
    'cm-ui',
    'cm-playerdata',
}

