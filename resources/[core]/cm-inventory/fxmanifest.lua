fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Development'
description 'CM Inventory v4.3.4 - honors cm-gunstore weapon bans on equip'
version '4.3.4'

dependencies {
    'oxmysql',
    'cm-items'
}

-- cm-gunstore is an OPTIONAL soft dependency (like cm-items above is hard):
-- server/equipment.lua calls exports['cm-gunstore']:IsWeaponBanned(itemName)
-- (pcall-guarded) so a /gunadmin "Banned" weapon can't be equipped, and an
-- already-equipped one stops being applied to the ped on the next resync.
-- Without cm-gunstore running, nothing is ever considered banned.

shared_scripts {
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/images/*.png',
    'ui/images/*.jpg',
    'ui/images/*.webp'
}
