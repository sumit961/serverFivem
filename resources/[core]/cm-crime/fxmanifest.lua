fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework'
description 'CM Crime: shared criminal-session framework (activity registry, sessions, site locks, cooldowns, police requirement, dispatch trigger, one-time reward authorization). Creates no money, items or XP; has no client surface.'
version '1.0.0'

dependencies {
    'oxmysql',
    'cm-playerdata',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/core.lua',
    'server/store.lua',
    'server/main.lua',
}

-- Start order: oxmysql, cm-playerdata, cm-law (optional: police count + dispatch fail closed without it), cm-crime, then crime content resources.
-- Crime content resources register their activity on start and on the local server event 'cm-crime:server:registryReady'.
