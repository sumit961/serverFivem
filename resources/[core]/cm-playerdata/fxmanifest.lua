fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Player Data - Stable v1.1: vitals, needs, death, position, money bridge'
author 'CM Framework'
version '1.1.0'

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
