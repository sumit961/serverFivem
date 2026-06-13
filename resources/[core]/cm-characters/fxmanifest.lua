fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'cm-dev'
description 'CM Characters - Character slot & appearance system'
version '1.0.0'

shared_scripts {
    '@cm-core/shared/config.lua',
}

client_scripts {
    'client/main.lua',
    'client/creator.lua',
    'client/appearance.lua',
    'client/apply.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/id-generator.lua',
    'server/main.lua',
    'server/creation.lua',
    'server/slots.lua',
    'server/appearance.lua',
    'server/bridge.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/appearance/style.css',
    'ui/appearance/app.js',
    'ui/appearance/translation.js',
}

dependencies {
    'cm-core',
    'cm-auth',
}