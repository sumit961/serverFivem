fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Taxi - fare dispatch, progression and a custom AAA-styled meter HUD'
author 'CM Framework'
version '1.0.0'

shared_scripts {
    'shared/config.lua',
    'shared/zones.lua',
    'shared/names.lua',
    'shared/peds.lua',
    'shared/locations.lua',
    'shared/locales.lua',
}

client_scripts {
    'client/notify.lua',
    'client/main.lua',
    'client/fare.lua',
    'client/office.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/progression.lua',
    'server/rental.lua',
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
}

dependencies {
    'cm-ui',
    'oxmysql',
    'cm-playerdata',
    'cm-vehiclekeys',
    'cm-vehicles',
    'cm-inventory'
}

-- Recommended order:
-- ensure oxmysql
-- ensure cm-playerdata
-- ensure cm-vehiclekeys
-- ensure cm-inventory
-- ensure cm-ui
-- ensure cm-hud
-- ensure cm-payday   (optional -- fare pay/xp becomes hourly payday instead of instant when this is running)
-- ensure cm-taxi
