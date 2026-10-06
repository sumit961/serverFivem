fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-lift'
author 'CM Framework'
description 'Generic server-authoritative lift and elevator engine'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/main.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/app.js',
    'ui/style.css'
}

dependencies {
    'cm-ui',
    'cm-core'
}
