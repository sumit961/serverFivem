fx_version 'cerulean'
game 'gta5'

author 'Neva / CM update'
version '2.2.0-ui-v2'
lua54 'yes'

-- REQUIRED for the invisible-head capture trick.
-- The stream/ folder ships mp_m_freemode_01^head_000_r.ydd and
-- mp_f_freemode_01^head_000_r.ydd (empty meshes). Those files only OVERRIDE the
-- base game head when the resource is registered as a map. Without this line the
-- streamed head is ignored and the ped's head keeps showing in the screenshot.
-- (This mirrors Bentix's fivem-greenscreener, which uses the exact same files.)
this_is_a_map 'yes'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

client_scripts {
    'client/cl_framework.lua',
    'client/cl_camera.lua',
    'client/cl_admin.lua',
    'client/cl_shop.lua',
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
    'shared/config.lua',
    'client/*.lua',
    'server/*.lua',
    'web/*'
}

dependency 'cm-items'

-- Used by /clothingadmin Capture Inventory Icon
dependency 'screenshot-basic'
