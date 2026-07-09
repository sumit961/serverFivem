fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-admin'
description 'CM Admin v2.6.5: calibrated live GTA map UI, selectable players/vehicles, staff actions, logs, GPS teleport, playerdata-owned admin tags'
author 'CM Framework'
version '2.6.5-playerdata-owned-admin-tags'

shared_script 'config.lua'

dependency 'cm-ui'

client_scripts {
    'client/noclip.lua',
    'client/admin_menu.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/devtools.lua',
    'server/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/main.js',
    'ui/assets/*.png',
    'ui/assets/map_tiles/*.png',
    'data/*.json'
}
