fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework'
description 'CM Crafting: shared server-authoritative crafting framework (recipe/station registry, craft sessions, atomic settlement orchestration). Owns no items, inventory or money; has no client surface.'
version '1.0.0'

dependencies {
    'oxmysql',
    'cm-playerdata',
    'cm-items',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/core.lua',
    'server/store.lua',
    'server/main.lua',
}

-- Start order: oxmysql, cm-playerdata, cm-items, cm-inventory, cm-crafting, then crafting content resources.
-- cm-inventory is a SOFT dependency: without its craft-transaction contract live crafting stays disabled (fail closed).
-- Content resources register recipes/stations on start and on the local server event 'cm-crafting:server:registryReady'.
