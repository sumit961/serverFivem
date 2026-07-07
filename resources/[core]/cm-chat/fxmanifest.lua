fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Chat - modular cyan RP chat with configurable channel colors'
author 'CM Framework'
version '1.3.0'

shared_script 'config.lua'

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
    'ui/app.js',
    'ui/fonts/PTSansNarrow.ttf',
    'ui/fonts/PTSansNarrow-Bold.ttf'
}

-- Soft integration only: restarting cm-core/cm-playerdata must never stop chat.
-- Startup order is guaranteed by server.cfg ensure order.
