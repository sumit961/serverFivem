fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Electrician - panel repair, deposit-plate runs and city power-outage response with custom CM UI'
author 'CM Framework'
version '1.0.0'

shared_script 'shared/config.lua'

client_scripts {
    'client/main.lua',
    'client/npc.lua',
}
server_script 'server/main.lua'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}

-- Recommended order:
-- ensure cm-playerdata
-- ensure cm-hud
-- ensure cm-ui            (switchboard NPC's interact prompt/cinematic dialogue)
-- ensure cm-vehicles      (service truck rental; job still works without it, minus the truck)
-- ensure cm-electrician
