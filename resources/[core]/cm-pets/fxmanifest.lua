fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-pets'
author 'CM Framework'
description 'Cosmetic, admin-granted companion pets owned by Character ID'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/adoption_policy.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.js',
    'html/style.css',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'cm-ui',
    'cm-playerdata',
    'cm-admin',
}
