fx_version 'cerulean'
game 'gta5'

author 'CM Framework'
description 'CM vehicle dealership/store'
version '1.0.0'

ui_page 'ui/index.html'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
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

dependency 'cm-vehicles'
