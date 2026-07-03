fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Player Data v1.6: vitals, death+kill logging, movement logs, identity hex menu, handshake consent, gameplay rules'
author 'CM Framework'
version '1.8.0'

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
    'ui/main.js',
    'ui/fonts/Nunito.ttf'
}

-- Hard dependency kept only for the @oxmysql file import.
-- cm-core/cm-characters are intentionally NOT hard dependencies anymore:
-- restarting them no longer force-stops this resource. Startup order is
-- guaranteed by the ensure order in server.cfg.
dependencies {
    'oxmysql'
}
