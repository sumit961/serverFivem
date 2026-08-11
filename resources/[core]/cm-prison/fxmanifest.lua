fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-prison'
author 'Sumit'
description 'CM-owned persistent prison sentences, cell assignment and release'
version '2.0.0'

server_script '@oxmysql/lib/MySQL.lua'

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies { 'oxmysql', 'cm-playerdata', 'cm-items', 'cm-weapons', 'cm-inventory' }
