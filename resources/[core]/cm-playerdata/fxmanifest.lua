fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Player Data - Stable v1.3-safe: vitals, death, position, money bridge'
author 'CM Framework'
version '1.3.0'

shared_scripts {
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

dependencies {
    'cm-core',
    'cm-characters',
    'oxmysql'
}
