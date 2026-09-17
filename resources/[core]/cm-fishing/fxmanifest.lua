fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Fishing - fishing zones, rod/bait store, catch minigame and fish exchange with custom CM UI'
author 'CM Framework'
version '1.0.0'

shared_script 'shared/config.lua'

client_script 'client/main.lua'

server_scripts {
    'server/items.lua',
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/images/*.png',
}

-- Recommended order:
-- ensure cm-playerdata
-- ensure cm-items
-- ensure cm-inventory
-- ensure cm-hud
-- ensure cm-vehicles      (boat rental; job still works without it, minus the boats)
-- ensure cm-fishing
