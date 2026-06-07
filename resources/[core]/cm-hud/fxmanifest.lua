fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM HUD - Minimap, Health, Armor, Location, Server Info, Time'
author 'CM Framework'
version '2.0.0'

client_scripts {
    'client/main.lua'
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