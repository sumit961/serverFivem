fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Tuning - secure performance and visual customisation'
author 'CM Framework'
version '3.0.0-secure-ui'

shared_script 'shared/config.lua'
client_script 'client/main.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'ui/index.html'
files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}

dependencies {
    'oxmysql',
    'cm-playerdata',
    'cm-vehicles'
}
