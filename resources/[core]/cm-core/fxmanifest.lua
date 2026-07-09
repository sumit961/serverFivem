fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM-Core: shared foundation helpers, callbacks, database wrapper, state, logger, security'
author 'CM Framework'
version '1.1.1-db-wait-fix'

dependency 'oxmysql'

shared_scripts {
    'config/_master.lua',
    'config/_environments.lua',
    'config/shared.lua',
    -- Legacy only. Real level/progression should move to cm-progression.
    'config/ranks.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/config-loader.lua',
    'server/database.lua',
    'server/logger.lua',
    'server/validation.lua',
    'server/security.lua',
    'server/callbacks.lua',
    'server/cache.lua',
    'server/state-registry.lua',
    'server/player.lua',
    'server/acl.lua',
    'server/money-ledger.lua',
    'server/economy.lua',
    'server/plugin-api.lua',
    'server/scheduler.lua',
    'server/error-boundary.lua',
    'server/notify.lua',
    'server/main.lua',
}

client_scripts {
    'client/state-bridge.lua',
    'client/callbacks.lua',
    'client/notify.lua',
    'client/main.lua',
}

ui_page 'ui/index.html'
files {
    'ui/index.html',
}
