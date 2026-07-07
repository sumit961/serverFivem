fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-admin'
description 'CM Admin v2.5: character-id admin mode, F11 menu, ranks, permissions, players, inventory, vehicles, cash, logs, noclip'
author 'CM Framework'
version '2.5.0'

shared_script 'config.lua'

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
    'ui/main.js'
}
