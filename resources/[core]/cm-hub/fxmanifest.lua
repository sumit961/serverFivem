fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Hub: Centralized M-Menu for Family, Organization, Statistics, and Server Services'
author 'CM Framework'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/images/**/*'
}

dependencies {
    'ox_lib',
    'oxmysql'
}
