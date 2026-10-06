fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Chat - modular cyan RP chat with configurable channel colors'
author 'CM Framework'
version '1.4.0'

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

-- PHASE 6: the chat UI now loads cm-ui's shared theme/components (visual
-- consistency with the rest of the server), so cm-ui is now a real
-- dependency. This is still a "soft integration" everywhere else: restarting
-- cm-core/cm-playerdata must never stop chat. Startup order beyond cm-ui is
-- guaranteed by server.cfg ensure order.
dependencies {
    'cm-ui'
}
