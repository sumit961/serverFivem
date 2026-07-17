fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Car Wash - secure cash-only automatic wash with custom CM UI'
author 'CM Framework'
version '2.0.2'

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
-- ensure cm-vehiclekeys
-- ensure cm-vehicles
-- ensure cm-carwash
