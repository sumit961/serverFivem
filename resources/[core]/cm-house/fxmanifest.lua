fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'cm-house'
author      'Sumit'
description 'CM Framework | Housing and family system'
version     '1.7.27'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/cl_interaction.lua',
    'client/cl_photo.lua',    -- must precede cl_create: defines StartPhotoCam
    'client/cl_create.lua',
    'client/cl_admin.lua',
    'client/cl_admin_templates.lua',  -- standalone template capture / re-walk
    'client/cl_door.lua',
    'client/cl_interior.lua',
    'client/cl_weapon_storage.lua',
    'client/cl_garage.lua',   -- real networked garage vehicles + slots
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_compat.lua',    -- first: GetCid / TakeMoney / IsHouseAdmin / SqlNull
    'server/sv_core.lua',
    'server/sv_templates.lua', -- reusable interior + garage layouts
    'server/sv_features.lua',  -- features derive garage size, stars and price
    'server/sv_access.lua',    -- the single CanAccessProperty gate
    'server/sv_phase2.lua',    -- persistence/recovery/admin/family API bridge
    'server/sv_family_lifecycle.lua', -- linked house is authoritative; sale/delete disbands family
    'server/sv_buckets.lua',   -- routing-bucket instancing
    'server/sv_photo.lua',     -- screenshot-basic -> local house photo file
    'server/sv_admin.lua',     -- admin panel
    'server/sv_create.lua',
    'server/sv_door.lua',
    'server/sv_interior.lua',
    'server/sv_weapon_storage.lua',
    'server/sv_garage.lua',   -- PHASE 3: the vehicle state machine
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/img/houses/*.jpg',
    'html/img/weapons/*.*',
    'html/img/weapons/**/*.*',
}

dependencies {
    'oxmysql',
    'ox_lib',
    'cm-playerdata',
    'cm-inventory',
    'cm-vehicles',
}

-- Soft: checked at runtime, and the resource degrades rather than erroring.
--   screenshot-basic  -> property photos saved under html/img/houses.
--   cm-core, cm-admin -> the ACL gate. Falls back to native ACE.
--   cm-family         -> explicit rank/permission imports for family access.

-- Admin access is via the native ACE system -- no admin resource needed.
--   add_ace group.admin cm-house.create allow
--
