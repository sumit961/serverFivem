fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework'
description 'Shared commercial-property ownership engine (buy/manage/pay-tax/withdraw) used by barber shops, clothing stores, and similar businesses.'
version '1.0.0'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}
