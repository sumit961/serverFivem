fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'cm-dev'
description 'CM Spawn - production-ready spawn selector, tutorial, and organization-ready spawn flow'
version '1.2.0-cm-ui-performance-climate'

shared_scripts {
    '@cm-core/shared/config.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/tutorial.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/spawnpoints.lua',
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/assets/*.svg',
}

dependencies {
    'cm-ui',
    'cm-core',
    'cm-characters',
    'cm-playerdata',
}
