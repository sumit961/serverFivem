fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Player Data - Cash, Bank, Position, Character Cache'
author 'CM Framework'
version '1.0.0'

server_scripts {
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

dependencies {
    'cm-core',
    'cm-characters'
}