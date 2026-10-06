fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework'
description 'CM Contracts: generic player-first / auto-fallback work broker (publication, claim, lease, fallback, audit). Creates no money, items, stock or XP.'
version '1.0.0'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/core.lua',
    'server/store.lua',
    'server/main.lua',
    'server/selftest.lua',
}

dependencies { 'oxmysql' }
