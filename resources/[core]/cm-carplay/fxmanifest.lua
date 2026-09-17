fx_version 'cerulean'
game 'gta5'

author 'CM'
description 'CarPlay in-vehicle infotainment system'
version '2.0.0'

lua54 'yes'
-- valid node_version values are only '16' (default) or '22' -- '1' is not a
-- real Node version and silently prevented the Node runtime from ever
-- starting for this resource (no crash, no output, server.js just never ran)
node_version '22' -- server/server.js uses FiveM's modern Node runtime

ui_page 'web/dist/index.html'

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
    'web/dist/index.html',
    'web/dist/**/*'
}

escrow_ignore {
    'config.lua',
    'locales/locales.lua',
    'locales/*.lua'
}

dependencies {
    'rn-vehicleshop',
    'cm-core',
    'cm-vehicles',
}

dependency '/assetpacks'
