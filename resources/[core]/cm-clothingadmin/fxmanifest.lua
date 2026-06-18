fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Development'
description 'CM Clothing Admin v7: NUI catalog manager and DB-backed clothing cache'
version '2.0.0'

dependency 'cm-items'

shared_scripts {
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/app.js',
    'web/style.css'
}
