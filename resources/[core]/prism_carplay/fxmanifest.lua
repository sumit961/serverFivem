

fx_version 'cerulean'
game 'gta5'

author 'Prism'
description 'Prism CarPlay — vehicle controls, media, navigation and dashcam'
version '1.1.0'

lua54 'yes'

ui_page 'web/index.html'

shared_scripts {
    'config.lua',
    'locales/locales.lua',
    'locales/*.lua'
}

client_scripts {
    'client/sound.lua',
    'client/main.lua'
}

server_scripts {
    'server/sound.lua',
    'server/server.js',
    'server/main.lua',
    'server/items.lua'
}

files {
    'web/index.html',
    'web/styles.css',
    'web/src/**/*',
    'web/dist/**/*',
    'recordings/dashcam/*.webm'
}

escrow_ignore{
    'config.lua',
    'locales/locales.lua',
    'locales/*.lua'
}

dependency '/assetpacks'

