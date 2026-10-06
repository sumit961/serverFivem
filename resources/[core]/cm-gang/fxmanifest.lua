fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-gang'
author 'CM Development'
description 'CM Framework | Authoritative five-gang V1 system'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/schema.lua',
    'server/domain.lua',
    'server/invites.lua',
    'server/headquarters.lua',
    'server/v1_storage.lua',
    'server/progression.lua',
    'server/fleet.lua',
    'server/admin.lua',
    'server/presentation.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/dashboard.lua',
    'client/progression.lua',
    'client/fleet_placement.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.css',
    'html/supply-war-v2.css',
    'html/gang-v300.css',
    'html/gang-armory-v4.css',
    'html/gang-dashboard-v400.css',
    'html/gang-dashboard-v500.css',
    'html/gang-dashboard-v600.css',
    'html/gang-dashboard-v700.css',
    'html/gang-dashboard-v800.css',
    'html/gang-dashboard-v1300.css',
    'html/gang-dashboard-v1400.css',
    'html/app.js',
    'html/supply-war-v2.js',
    'html/graffiti.html',
    'html/assets/gangs/*.png',
    'html/assets/dashboard/*.png',
    'html/assets/events/*',
    'html/assets/graffiti/*.png',
    'sql/*.sql',
    'README.md',
}

dependencies {
    'oxmysql',
    'ox_lib',
    'cm-playerdata',
    'cm-inventory',
    'cm-ui',
}

-- Owner integrations remain soft and guarded to avoid dependency cycles:
-- cm-admin, cm-chat, cm-items, cm-weapons, cm-vehicles,
-- cm-vehiclekeys and rn-vehicleshop. They must not hard-depend on cm-gang.
