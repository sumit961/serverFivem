fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'cm-dev'
description 'CM Characters - secure selector, creator, admin panel, CM cyan theme'
version '1.5.6-pre-spawn-climatime-prepare'

shared_scripts {
    '@cm-core/shared/config.lua',
    'config.lua',
}

client_scripts {
    'client/worldlock.lua',
    'client/main.lua',
    'client/creator.lua',
    'client/appearance.lua',
    'client/apply.lua',
    'client/admin.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/id-generator.lua',
    'server/utils.lua',
    'server/main.lua',
    'server/creation.lua',
    'server/slots.lua',
    'server/appearance.lua',
    'server/bridge.lua',
    'server/admin.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/assets/*.svg',
    'ui/audio/character-theme.wav',
    'data/selector_scene.json',
    'ui/appearance/style.css',
    'ui/appearance/app.js',
    'ui/appearance/translation.js',
}

dependencies {
    'cm-core',
    'cm-auth',
}
