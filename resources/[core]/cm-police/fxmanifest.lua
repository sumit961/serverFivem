fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-police'
author 'Sumit'
description 'CM Framework | Single Police organization'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/ui.lua', -- shared toast/hint/confirm/quick-menu toolkit, loaded first: every other client file below calls its global functions
    'client/npc_dialogue.lua', -- EMS-style cinematic dialogue shared by every Police service NPC
    'client/cinematics.lua', -- shared booking/impound camera sequences and result presentation
    'client/main.lua',
    'client/gmenu.lua',
    'client/tracking.lua',
    'client/vehicles.lua',
    'client/cuffs.lua',
    'client/escort.lua',
    'client/impound.lua',
    'client/radar.lua',
    'client/placement.lua', -- shared camera-relative placement helper, loaded before spikes.lua/barricades.lua which both call it
    'client/spikes.lua',
    'client/barricades.lua',
    'client/clamp.lua',
    'client/quickmenu.lua',
    'client/org_keys.lua', -- single J/F7/TAB router for every organization
    'client/wardrobe.lua',
    'client/jail_npc.lua',
    'client/mdt_terminal.lua',
    'client/dispatch.lua',
    'client/gunfire.lua',
    'client/licenses.lua',
    'client/bolo.lua',
    'client/k9.lua',
    'client/service_npc.lua',
    'client/facility_npcs.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/schema.lua', -- centralized schema readiness and durable operation journal
    'server/main.lua',   -- first: defines cid/memberFor/has/log/rateLimit/nameFor/sourceFor, shared with vehicles.lua/cuffs.lua/booking.lua/citations.lua/impound.lua/spikes.lua/mdt.lua/dispatch.lua
    'server/facility_npcs.lua', -- defines facility location/proximity contracts before booking.lua and armory.lua consume them
    'server/vehicles.lua',
    'server/cuffs.lua',
    'server/booking.lua',
    'server/citations.lua',
    'server/impound.lua',
    'server/spikes.lua',
    'server/barricades.lua',
    'server/clamp.lua',
    'server/mdt.lua',
    'server/dispatch.lua',
    'server/armory.lua',
    'server/alpr.lua',
    'server/wardrobe.lua',
    'server/service_npc.lua',
    'server/search.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.css',
    'html/ranks.css',
    'html/outfits.css',
    'html/fleet.css',
    'html/mdt.css',
    'html/dispatch.css',
    'html/wardrobe.css',
    'html/ui.css',
    'html/mdt-terminal.css',
    'html/theme.css',
    'html/app.js',
    -- Bodycam captures (server/cuffs.lua's captureBodycamEvidence,
    -- screenshot-basic) saved directly here at runtime, served as plain
    -- relative NUI URLs -- same wildcard-glob approach cm-house already
    -- uses for property photos (html/img/houses/*.jpg).
    'html/img/bodycam/*.jpg',
    'html/img/mugshots/*.jpg',
}

dependencies {
    'oxmysql',
    'ox_lib',
    'cm-law', -- authoritative shared law dispatch and EMS-style dispatch presentation
    'cm-ui',
    'cm-hud',
    'cm-playerdata',
    'cm-admin',
    'cm-vehicles',
    -- Fleet vehicle appearance (model/image/mods) is read live from
    -- rn-vehicleshop's "Police fleet vehicle" catalog status (GetPoliceCatalog
    -- export), the same pattern cm-ems uses for its own fleet.
    'rn-vehicleshop',
    -- Police Wardrobe catalog (Duty Outfits tab) reads clothing items an
    -- admin tagged for the "police" job through nv_cloth's /clothingstore
    -- panel, stored in cm-items' own clothing catalog table.
    'cm-items',
    -- Armory tab reads the full weapon catalog from cm-weapons'
    -- GetAllWeapons export and grants checkouts through cm-inventory's
    -- AddItem, same as cm-gunstore already does for purchases.
    'cm-weapons',
    'cm-inventory',
}

-- Soft: checked at runtime via GetResourceState, not a hard dependency --
-- cm-police still starts fine if it's ever missing/stopped.
--   cm-gunstore -> Armory weapon/vest images and wearable armor catalog.
--   It already depends on cm-police for firearms licensing, so declaring it
--   above would create a circular dependency; server/armory.lua fails closed
--   for vest discovery and falls back to cm-weapons data when unavailable.
--   screenshot-basic -> real bodycam captures (server/cuffs.lua). Falls
--   back to a text-only system note when it's not running.
