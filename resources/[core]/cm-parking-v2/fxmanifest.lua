fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'cm-parking-v2'
description 'CM parking spaces adapted from 3core-parking'
shared_scripts { 'config.lua', 'adapter.lua' }
client_script 'client/main.lua'
server_scripts {'@oxmysql/lib/MySQL.lua','server/db.lua','server/main.lua'}
ui_page 'public/index.html'
files {'public/index.html','public/build/bundle.js','public/build/bundle.css'}
dependencies {'cm-playerdata','cm-vehicles','cm-ui','oxmysql'}
