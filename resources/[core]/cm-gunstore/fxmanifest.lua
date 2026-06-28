fx_version 'cerulean'
game 'gta5'

name 'cm-gunstore'
author 'CM / ChatGPT'
description 'Inventory-based gun and ammo store with admin catalog, built to match nv_cloth purchase-to-inventory flow.'
version '1.0.0'
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
    'cm-inventory',
    'oxmysql'
    -- Optional for armor admin photo capture: screenshot-basic
}

-- ox_target is optional at resource-start level. If it is started, cm-gunstore registers NPC target options.
-- Ensure order in server.cfg: ensure ox_lib, ensure ox_target, ensure cm-gunstore.

escrow_ignore {
    'shared/config.lua',
    'client/main.lua',
    'server/main.lua',
    'web/*',
    'install/*',
    'docs/*'
}
