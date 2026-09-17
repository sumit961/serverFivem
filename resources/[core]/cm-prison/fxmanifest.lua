fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-prison'
author 'Sumit'
description 'CM-owned persistent prison sentences, cell assignment and release'
version '2.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared_config.lua',
}

server_script '@oxmysql/lib/MySQL.lua'

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/intake.lua',
}

dependencies { 'ox_lib', 'oxmysql', 'cm-playerdata', 'cm-items', 'cm-weapons', 'cm-inventory', 'cm-admin' }
