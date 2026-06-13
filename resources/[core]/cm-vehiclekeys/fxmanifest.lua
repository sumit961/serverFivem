fx_version 'cerulean'
game 'gta5'

author 'CM Framework'
description 'CM Vehicle temporary key system'
version '1.0.0'

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}
