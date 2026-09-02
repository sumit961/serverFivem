fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Bank - ATM deposit/withdraw/transfer using the cm-playerdata cash/bank accounts'
author 'CM Framework'
version '1.8.0'

shared_script 'shared/config.lua'
server_script '@oxmysql/lib/MySQL.lua'

client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/img/*.png'
}

dependencies {
    'oxmysql',
    'cm-playerdata',
    'cm-ui'
}

-- Recommended order:
-- ensure cm-ui
-- ensure cm-playerdata
-- ensure cm-bank
