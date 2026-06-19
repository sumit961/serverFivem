fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM HUD - Native Minimap, Vehicle Speedometer, Health, Armor, Location, Server Info, Time'
author 'CM Framework'
version '2.1.0'

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}

dependencies {
    'cm-core',
    'cm-playerdata'
}