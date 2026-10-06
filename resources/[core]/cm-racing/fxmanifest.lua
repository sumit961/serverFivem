fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-racing'
description 'CM Sanctioned Racing & Time Trials - Server-authoritative racing gameplay with progression and anti-exploit'
author 'CM Framework'
version '1.0.0'

shared_scripts {
    'shared/config.lua'
}

server_scripts {
    'server/progression.lua',
    'server/validation.lua',
    'server/main.lua'
}

client_scripts {
    'client/hud.lua',
    'client/checkpoints.lua',
    'client/menu.lua',
    'client/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}

dependencies {
    'cm-ui',
    'cm-playerdata'
}
