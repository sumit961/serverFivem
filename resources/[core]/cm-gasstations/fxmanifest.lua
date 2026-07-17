fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Gas Stations - secure server-priced refuelling, custom interaction prompt and vehicle supplies'
author 'CM Framework'
version '2.0.0'

shared_script 'shared/config.lua'

client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}

-- Recommended order:
-- ensure cm-playerdata
-- ensure cm-items (or cm-item)
-- ensure cm-inventory
-- ensure cm-vehicles
-- ensure cm-gasstations
