fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Farming - plant, water, grow, harvest and sell crops with custom CM UI'
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
-- ensure cm-ui              (plot/NPC interact prompts)
-- ensure cm-farming-assets  (streamed crop/seedling props -- start before cm-farming)
-- ensure cm-payday          (optional -- sell pay becomes hourly payday instead of instant when running)
-- ensure cm-farming
