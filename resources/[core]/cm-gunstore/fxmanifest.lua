fx_version 'cerulean'
game 'gta5'

name 'cm-gunstore'
author 'CM / ChatGPT'
description 'Gun/ammo selling store that reads fixed weapon/ammo definitions from cm-weapons.'
version '1.9.0'
lua54 'yes'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/images/*.svg',
    'web/images/custom/*.png',
    'web/images/custom/*.jpg',
    'web/images/custom/*.jpeg',
    'web/images/custom/*.webp'
}

shared_scripts {
    'shared/util.lua',
    'shared/config.lua',
    'shared/weapons.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'cm-core',
    'cm-playerdata',
    'cm-inventory',
    'cm-items',
    'oxmysql',
    'cm-weapons'
    -- Optional for armor admin photo capture: screenshot-basic
}

-- ox_target is optional at resource-start level. If it is started, cm-gunstore registers NPC target options.
-- Ensure order in server.cfg: ensure ox_lib, ensure ox_target, ensure cm-gunstore.

escrow_ignore {
    'shared/util.lua',
    'shared/config.lua',
    'shared/weapons.lua',
    'client/main.lua',
    'server/main.lua',
    'web/*',
    'install/*',
    'docs/*'
}
