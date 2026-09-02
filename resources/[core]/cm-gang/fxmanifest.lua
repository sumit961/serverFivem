fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-gang'
author 'CM Development'
description 'CM Framework | Authoritative fixed-slot gang system'
version '0.5.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/schema.lua',
    'server/domain.lua',
    'server/invites.lua',
    'server/robbery.lua',
    'server/storage.lua',
    'server/wardrobe.lua',
    'server/fleet.lua',
    'server/admin.lua',
    'server/coordination.lua',
    'server/event_manager.lua',
    'server/supply_war.lua',
    'server/events.lua',
    'server/profit.lua',
    'server/graffiti.lua',
    'server/presentation.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/dashboard.lua',
    'client/coordination.lua',
    'client/event_manager.lua',
    'client/fleet_placement.lua',
    'client/graffiti.lua',
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
    'cm-law', -- shared armory backend (server/storage.lua); cm-law never depends on cm-gang, so this is not a cycle
}

-- Optional owners remain guarded soft integrations to avoid dependency cycles:
-- cm-admin, cm-chat, cm-items, cm-weapons, cm-vehicles,
-- cm-vehiclekeys and rn-vehicleshop. They must not hard-depend on cm-gang.
