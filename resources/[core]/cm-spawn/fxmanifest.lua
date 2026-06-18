fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'cm-dev'
description 'CM Spawn - Spawn selector and tutorial system'
version '1.0.0'

shared_scripts {
    '@cm-core/shared/config.lua',
}

client_scripts {
    'client/main.lua',
    'client/tutorial.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/spawnpoints.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/assets/*.svg',
}

dependencies {
    'cm-core',
    'cm-characters',
    'cm-playerdata', -- ensures cm-playerdata loads first (owns position saving)
}