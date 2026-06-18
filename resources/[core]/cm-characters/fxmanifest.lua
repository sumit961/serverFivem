fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'cm-dev'
description 'CM Characters - freemode dummy selector preview with creator-style camera and inventory clothing'
version '1.4.3-creation-preload-hud-hide'

shared_scripts {
    '@cm-core/shared/config.lua',
    'config.lua',
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
