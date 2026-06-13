fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM-Auth: Modern email login/register with bcrypt support'
version '2.0.0-modern-bcrypt'

dependencies {
    'oxmysql',
    'cm-core'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'ui/index.html'
files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
}
