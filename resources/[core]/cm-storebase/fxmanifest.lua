fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework'
description 'Reusable backend/API store manager for CM resources'
version '2.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/cl_main.lua'
}

server_scripts {
    'server/sv_main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/images/*.svg',
    'ui/images/*.png',
    'ui/images/*.jpg',
    'ui/images/*.webp'
}

dependency 'ox_lib'
