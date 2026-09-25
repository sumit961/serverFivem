fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-law'
author 'CM Framework'
description 'CM legal organizations and embedded Los Santos Police operations'
version '3.2.2'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'embedded/police/shared/config.lua',
}

client_scripts {
    'client/main.lua',
    'client/daily_desk.lua',
    'client/wardrobe.lua',
    'client/armory.lua',
    'client/logistics.lua',
    'client/arsenal.lua',
    'client/facilities.lua',
    'client/vehicles.lua',
    'client/cuffs.lua',
    'client/escort.lua',
    'client/gmenu.lua',
    'client/prison_intake.lua',
    'client/laptop_terminal.lua',
    'client/dispatch.lua',
    'client/dispatch_cameras.lua',
    'client/vehicle_scanner.lua',
    'client/photo_capture.lua',
    'client/tracking.lua',
    'client/operational_tablet.lua',
    'embedded/police/client/ui.lua',
    'embedded/police/client/npc_dialogue.lua',
    'embedded/police/client/cinematics.lua',
    'embedded/police/client/main.lua',
    'embedded/police/client/gmenu.lua',
    'embedded/police/client/tracking.lua',
    'embedded/police/client/vehicles.lua',
    'embedded/police/client/cuffs.lua',
    'embedded/police/client/escort.lua',
    'embedded/police/client/impound.lua',
    'embedded/police/client/radar.lua',
    'embedded/police/client/placement.lua',
    'embedded/police/client/spikes.lua',
    'embedded/police/client/barricades.lua',
    'embedded/police/client/clamp.lua',
    'embedded/police/client/quickmenu.lua',
    'embedded/police/client/wardrobe.lua',
    'embedded/police/client/dispatch.lua',
    'embedded/police/client/gunfire.lua',
    'embedded/police/client/licenses.lua',
    'embedded/police/client/bolo.lua',
    'embedded/police/client/k9.lua',
    'embedded/police/client/service_npc.lua',
    'embedded/police/client/facility_npcs.lua',
    'embedded/police/client/admin_config.lua',
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
    'server/bolo.lua',
    'server/vehicles.lua',
    'server/cuffs.lua',
    'server/charges.lua', -- editable Criminal Code catalog, read by booking.lua's LawChargeCatalog()
    'server/booking.lua', -- all departments hand off to the central cm-prison intake and sentence authority
    'server/frontdesk.lua',
    'server/dispatch.lua',
    'server/dispatch_cameras.lua',
    'server/photos.lua',   -- shared local-file capture primitive (citizen/officer/report photos)
    'server/scene_equipment.lua',
    'server/enforcement.lua',
    'server/tracking.lua',  -- org-scoped member map + meeting points
    'server/records.lua',   -- read-only cross-agency record export consumed by cm-police
    'server/retention.lua', -- periodic activity-log pruning
    'embedded/police/server/schema.lua',
    'embedded/police/server/main.lua',
    'embedded/police/server/facility_npcs.lua',
    'embedded/police/server/vehicles.lua',
    'embedded/police/server/cuffs.lua',
    'embedded/police/server/booking.lua',
    'embedded/police/server/citations.lua',
    'embedded/police/server/impound.lua',
    'embedded/police/server/barricade_catalog.lua',
    'embedded/police/server/clamp.lua',
    'embedded/police/server/mdt.lua',
    'embedded/police/server/dispatch.lua',
    'embedded/police/server/armory.lua',
    'embedded/police/server/alpr.lua',
    'embedded/police/server/wardrobe.lua',
    'embedded/police/server/service_npc.lua',
    'embedded/police/server/search.lua',
    'embedded/police/server/admin_config.lua',
    'embedded/police/server/retention.lua',
    'server/daily_desk.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'cm-admin',
    'cm-ui',
    'cm-hud',
    'cm-playerdata',
    'cm-inventory',
    'cm-items',
    'cm-weapons',
    'cm-vehicles',
    'rn-vehicleshop',
    'cm-prison',
}

-- Optional runtime integration: cm-gunstore supplies armor artwork/catalog
-- enrichment when started. Weapon and ammunition definitions remain owned by
-- cm-weapons, and server/armory.lua guards the optional export.

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/law.html',
    'html/operations.html', -- standalone MDT, dispatch and facility tools
    'html/organization.js', -- the four-tab F6 Organization Hub
    'html/organization-preview.js', -- local HTTP preview only; never used for game data
    'html/dashboard-filters.js',   -- roster + activity log search (standalone, loads after app.js)
    'html/assets/fonts/*.woff2',   -- optional self-hosted Archivo / JetBrains Mono
    'html/assets/mdt.png',         -- MDT tab icon (sourced from resources/outside/mdt reference resource's static image asset)

    'html/style.css',
    'html/law-armory-v4.css',
    'html/law-command-rail.css',
    'html/dispatch-board.css',
    'html/live-operations-v2.1.css',
    'html/live-operations-v2.1.js',
    'html/app.js',
    'html/daily-desk.js',
    'html/request-feedback.js',
    'html/operations-v2.5.css',
    'html/components.css',
    'html/dashboard.css',
    'html/command-ui-v2.6.js',
    'html/assets/org/*.svg',
    'html/assets/org/*.png',
    'html/police/*.html',
    'html/police/*.css',
    'html/police/*.js',
    'html/police/assets/fonts/*.woff2',
    'html/police/assets/org/*.svg',
    'html/police/assets/org/*.png',
    'html/police/img/bodycam/*.jpg',
    'html/police/img/mugshots/*.jpg',
    'html/captures/citizens/*.jpg',
    'html/captures/officers/*.jpg',
    'html/captures/reports/*.jpg',
}
