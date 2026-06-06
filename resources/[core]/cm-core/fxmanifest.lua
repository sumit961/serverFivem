fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM-Core: Database, Config, State, Economy, Logger'
author 'ClockMate'
version '1.0.0'

shared_scripts {
    'config/_master.lua',
    'config/_environments.lua',
    'config/ranks.lua',
    'config/shared.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/config-loader.lua',
    'server/database.lua',
    'server/state-registry.lua',
    'server/economy.lua',
    'server/logger.lua',
    'server/plugin-api.lua',
    'server/cache.lua',
    'server/validation.lua',
    'server/scheduler.lua',
    'server/acl.lua',
    'server/error-boundary.lua',
    'server/main.lua',
}

client_scripts {
    'client/state-bridge.lua',
    'client/main.lua',
}

ui_page 'ui/index.html'
files {
    'ui/index.html',
}