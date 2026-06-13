fx_version 'cerulean'
game 'gta5'

author 'CM Framework'
description 'CM owned vehicle system: engine, locks, menu, trunk inventory'
version '1.2.0'

ui_page 'ui/index.html'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

client_exports {
    'TryOpenNearbyTrunkInventory'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}

dependency 'cm-vehiclekeys'
