fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-ems'
author 'Sumit'
description 'CM Framework | Single EMS medical organization'
version '5.10.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
    'client/wardrobe.lua',
    'client/gmenu.lua',
    'client/tracking.lua',
    'client/vehicles.lua',
    'client/dispatch.lua',
    'client/government_doctor.lua',
    'client/patch.lua',
    'client/stretcher.lua',
    'client/missions.lua',
    'client/medicine_stock.lua',
    'client/appearance_services.lua',
    'client/admin_config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',   -- first: defines cid/memberFor/has/log/rateLimit/nameFor, shared with vehicles.lua
    'server/tasks.lua',
    'server/missions.lua',
    'server/vehicles.lua',
    'server/dispatch.lua',
    'server/medical.lua',
    'server/patch.lua',
    'server/stretcher.lua',
    'server/medicine.lua',
    'server/stock.lua',
    'server/admin_config.lua',
    'server/retention.lua', -- periodic activity-log pruning
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/dashboard-filters.js',   -- roster + activity log search (standalone, loads after app.js)
    'html/assets/fonts/*.woff2',   -- optional self-hosted Archivo / JetBrains Mono

    'html/app.css',
    'html/command-center.css',
    'html/ranks.css',
    'html/ems-cyan.css',
    'html/theme-v130.css',
    'html/fleet.css',
    'html/outfits.css',
    'html/wardrobe.css',
    'html/dispatch.css',
    'html/app.js',
    'html/assets/org/*.svg',
    'html/assets/org/*.png',
}

dependencies {
    'oxmysql',
    'ox_lib',
    'cm-ui',
    'cm-hud',
    'cm-playerdata',
    'cm-characters',
    'cm-admin',
    'cm-vehicles',
    -- Fleet vehicle appearance (model/image/mods) is read live from
    -- rn-vehicleshop's "EMS fleet vehicle" catalog status (GetEmsCatalog
    -- export) -- cm-ems no longer configures colors/livery/etc itself, so
    -- cm-tuning is no longer a direct dependency here.
    'rn-vehicleshop',
    'nv_cloth',
    'cm-items',
    'cm-inventory',
}
