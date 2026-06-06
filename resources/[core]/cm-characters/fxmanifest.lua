fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM-Characters: Creation, Selection, Appearance'
version '1.0.0'

dependencies {'cm-core'}

server_scripts {
    'server/main.lua',
    'server/creation.lua',
    'server/slots.lua',
}

client_scripts {
    'client/main.lua',
    'client/selector.lua',
    'client/creator.lua',
}

ui_page 'ui/index.html'
files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
}