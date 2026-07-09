fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'cm-dev'
description 'CM Characters - production selector, creator, appearance and safe character exports'
version '1.7.0-cm-ui-climate-preload'

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
    'ui/vendor/cm-miniquery.js',
    'ui/assets/*.svg',
    'ui/audio/character-theme.wav',
    'data/selector_scene.json',
    'ui/appearance/index.html',
    'ui/appearance/style.css',
    'ui/appearance/app.js',
    'ui/appearance/translation.js',
}

dependencies {
    'cm-ui',
    'cm-core',
    'cm-auth',
    'cm-playerdata',
}
