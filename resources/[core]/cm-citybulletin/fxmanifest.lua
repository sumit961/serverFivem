fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-citybulletin'
author 'CM Development'
description 'CM Framework | Persistent administrator-created public city notices'
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
    'sql/001_cm_citybulletin.sql',
    'README.md',
}

dependencies {
    'oxmysql',
    'ox_lib',
    'cm-playerdata',
    'cm-admin',
    'cm-ui',
}
