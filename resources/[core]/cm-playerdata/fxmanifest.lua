fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Player Data: character ID, cash/bank owner, vitals, death, identity labels and interactions'
author 'CM Framework'
version '1.9.14-interaction-arbiter-export'

shared_scripts {
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua',
    'client/gameplay.lua',
    'client/interactions.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/main.js'
}

-- Hard dependencies kept for the @oxmysql import and shared cm-ui NUI theme.
-- cm-core/cm-characters are intentionally NOT hard dependencies anymore:
-- restarting them no longer force-stops this resource. Startup order is
-- guaranteed by the ensure order in server.cfg.
dependencies {
    'oxmysql',
    'cm-ui'
}
