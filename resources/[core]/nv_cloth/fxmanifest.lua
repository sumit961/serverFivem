fx_version 'cerulean'
game 'gta5'

author 'Neva / CM update'
version '2.21.0-manager-torso-preview'
lua54 'yes'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'generated_images/README.txt',
    'generated_images/*.png',
    'generated_images/*.webp',

    'stream/prop_ld_greenscreen_01.ydr'
}

client_scripts {
    'client/cl_framework.lua',
    'client/cl_camera.lua',
    'client/cl_admin.lua',
    'client/cl_shop.lua',
    'client/cl_manage.lua',
    'client/cl_capture.lua',
    'client/cl_clothing.lua',
    'client/cl_main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_*.lua',
}

shared_scripts {
    'shared/config.lua',
}

escrow_ignore {
    'README_CAPTURE.md',
    'VALIDATION.md',
    'shared/config.lua',
    'client/*.lua',
    'server/*.lua',
    'web/*',
    'stream/*'
}

dependency 'cm-items'

-- Used locally by /clothingadmin Capture Inventory Icon. No RCore/API dependency.
dependency 'screenshot-basic'
