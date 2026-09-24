fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'cm-family'
author      'Sumit'
description 'CM Framework | Family system (ranks, vehicles, bank, family house)'
version     '1.8.4'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/cl_ui_bridge.lua',
    'client/cl_npc.lua',
    'client/cl_menu.lua',
    'client/cl_invites.lua',
    'client/cl_gmenu.lua',
    'client/cl_chat.lua',
    'client/cl_tracking.lua',
    'client/cl_raid.lua',
    'client/cl_admin.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_bridge.lua',   -- wrappers around cm-house / cm-playerdata / cm-inventory
    'server/sv_schema.lua',   -- auto-install/repair and validate DB before callbacks run
    'server/sv_core.lua',     -- state + HasHousePermission (the seam cm-house calls)
    'server/sv_audit.lua',    -- durable activity audit + cm-admin read contract
    'server/sv_progression.lua', -- authoritative progression, leveling & activity reward engine
    'server/sv_contributions.lua', -- multi-category member contribution score & leaderboards
    'server/sv_objectives.lua',  -- weekly family objectives & anti-abuse tracking
    'server/sv_hq.lua',          -- family headquarters upgrades system
    'server/sv_vehicles.lua', -- per-vehicle access level
    'server/sv_raid.lua',     -- family-vs-family raid event
    'server/sv_ranks.lua',    -- rank create/edit with authority rules
    'server/sv_members.lua',  -- invite/kick/promote/succession
    'server/sv_bank.lua',     -- family bank
    'server/sv_gmenu.lua',    -- cm-playerdata G-menu integration
    'server/sv_chat.lua',     -- private family chat + cm-chat integration event
    'server/sv_menu.lua',     -- NPC create flow + menu callbacks
    'server/sv_admin.lua',    -- cm-admin launcher + guarded recovery panel
    'server/sv_hardening_tests.lua', -- live automated verification suite for transactions/hardening
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/fonts/*.ttf',
    'html/assets/*.png',
    'audit_pending.json',
}

dependencies {
    'oxmysql',
    'ox_lib',
    'cm-house',
    'cm-playerdata',
    'cm-vehiclekeys',
    'cm-ui',
    'cm-hud',
}

-- Soft/optional at runtime:
--   cm-vehicles  -> vehicle metadata for the garage list (via cm-house exports)
--
-- cm-house must authorize cm-family in its Config.Integration.authorizedResources
-- (already present by default) so SetFamilyHouseLink and family exports work.
