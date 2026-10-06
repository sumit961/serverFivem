fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-citycalendar'
author 'CM Development'
description 'CM Framework | Administrator-created civic and social calendar'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/schema.lua',
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
    'sql/001_cm_citycalendar.sql',
    'README.md',
}

dependencies {
    'oxmysql',
    'ox_lib',
    'cm-playerdata',
    'cm-ui',
    'cm-admin',
}
