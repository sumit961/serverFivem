fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM-Auth: Login & Register with Full Debug'
version '1.1.0'

dependencies {'cm-core'}

server_scripts {
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