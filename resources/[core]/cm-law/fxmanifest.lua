fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-law'
author 'CM Framework'
description 'CM configurable legal organization foundation'
version '1.5.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
    'client/wardrobe.lua',
    'client/armory.lua',
    'client/logistics.lua',
    'client/arsenal.lua',
    'client/facilities.lua',
    'client/vehicles.lua',
    'client/cuffs.lua',
    'client/escort.lua',
    'client/gmenu.lua',
    'client/dispatch.lua',
    'client/tracking.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',   -- first: defines validOrgId/characterIdFor/memberFor/canManage/nearFacility/logActivity/adminAllowed/rateLimit/LawIsReady, shared with vehicles.lua/cuffs.lua/booking.lua/dispatch.lua
    'server/comms.lua',
    'server/armory.lua',
    'server/logistics.lua',
    'server/arsenal.lua',
    'server/search.lua',
    'server/mdt.lua',
    'server/vehicles.lua',
    'server/cuffs.lua',
    'server/booking.lua', -- cm-prison is an optional soft dependency (exports['cm-prison']:JailSuspect, pcall-guarded) -- booking fails closed with a clear message if it isn't running
    'server/frontdesk.lua',
    'server/dispatch.lua',
    'server/scene_equipment.lua',
    'server/enforcement.lua',
    'server/tracking.lua',  -- org-scoped member map + meeting points
    'server/records.lua',   -- read-only cross-agency record export consumed by cm-police
    'server/retention.lua', -- periodic activity-log pruning
}

dependencies {
    'ox_lib',
    'oxmysql',
    'cm-admin',
    'cm-ui',
    'cm-playerdata',
    'cm-inventory',
    'cm-items',
    'cm-weapons',
    'cm-vehicles',
    'rn-vehicleshop',
}

-- Optional runtime integration: cm-gunstore supplies armor artwork/catalog
-- enrichment when started. Weapon and ammunition definitions remain owned by
-- cm-weapons, and server/armory.lua guards the optional export.

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/dashboard-filters.js',   -- roster + activity log search (standalone, loads after app.js)
    'html/assets/fonts/*.woff2',   -- optional self-hosted Archivo / JetBrains Mono

    'html/style.css',
    'html/law-armory-v4.css',
    'html/command-center.css',
    'html/police-dashboard.css',
    'html/dispatch-board.css',
    'html/app.js',
    'html/assets/org/*.svg',
    'html/assets/org/*.png',
}
