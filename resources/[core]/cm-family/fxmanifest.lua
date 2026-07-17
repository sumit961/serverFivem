fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'cm-family'
author      'Sumit'
description 'CM Framework | Family system (ranks, vehicles, bank, family house)'
version     '1.6.10'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/cl_npc.lua',
    'client/cl_menu.lua',
    'client/cl_invites.lua',
    'client/cl_gmenu.lua',
    'client/cl_chat.lua',
    'client/cl_tracking.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_bridge.lua',   -- wrappers around cm-house / cm-playerdata / cm-inventory
    'server/sv_schema.lua',   -- auto-install/repair and validate DB before callbacks run
    'server/sv_core.lua',     -- state + HasHousePermission (the seam cm-house calls)
    'server/sv_audit.lua',    -- durable activity audit + cm-admin read contract
    'server/sv_vehicles.lua', -- per-vehicle access level
    'server/sv_ranks.lua',    -- rank create/edit with authority rules
    'server/sv_members.lua',  -- invite/kick/promote/succession
    'server/sv_bank.lua',     -- family bank
    'server/sv_gmenu.lua',    -- cm-playerdata G-menu integration
    'server/sv_chat.lua',     -- private family chat + cm-chat integration event
    'server/sv_menu.lua',     -- NPC create flow + menu callbacks
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'audit_pending.json',
}

dependencies {
    'oxmysql',
    'ox_lib',
    'cm-house',
    'cm-playerdata',
    'cm-vehiclekeys',
}

-- Soft/optional at runtime:
--   cm-vehicles  -> vehicle metadata for the garage list (via cm-house exports)
--   cm-inventory -> only used indirectly through cm-house weapon/storage gates
--
-- cm-house must authorize cm-family in its Config.Integration.authorizedResources
-- (already present by default) so SetFamilyHouseLink and family exports work.
