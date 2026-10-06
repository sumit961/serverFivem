fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework'
description 'Shared commercial-property ownership engine (buy/manage/pay-tax/withdraw) plus the shared business employment foundation (employees, ranks, permissions, invites, payroll, atomic business balance).'
version '2.3.0'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/schema.lua',
    'server/foundation.lua',
    'server/supply.lua',
    'server/materials.lua',
    'server/staff.lua',
    'server/main.lua',
    'server/selftest_supply.lua',
    'server/selftest.lua',
}

client_scripts {
    'client/client.lua',
}
