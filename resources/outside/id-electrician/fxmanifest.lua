--[[FX INFO]]
fx_version 'cerulean'
game 'gta5'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
name 'id-electrician'
author 'grandson'
description 'Electrician Job'
version '1.0.0'
 
--[[FX DEPENDENCIES]]
dependencies {
	'/server:5848',
    '/onesync',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/**/*',
}

shared_script {
    'shared/*.lua',
    'shared/**/*.lua'
}

client_scripts {
    'client/*.lua',
}

server_script {
	'@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}
