fx_version 'cerulean'
game 'gta5'

name 'cm-gunstore'
author 'CM / ChatGPT'
description 'Gun/ammo selling store that reads fixed weapon/ammo definitions from cm-weapons.'
version '1.11.2'
lua54 'yes'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/images/*.svg',
    'web/images/custom/*.png',
    'web/images/custom/*.jpg',
    'web/images/custom/*.jpeg',
    'web/images/custom/*.webp'
}

shared_scripts {
    'shared/util.lua',
    'shared/config.lua',
    'shared/weapons.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'cm-core',
    'cm-playerdata',
    'cm-inventory',
    'cm-items',
    'oxmysql',
    'cm-weapons',
    -- Firearms license exports are provided by cm-law's embedded Police
    -- compatibility layer after the cm-police -> cm-law migration.
    'cm-law'
    -- Optional for armor admin photo capture: screenshot-basic
}

-- ox_target is optional at resource-start level. If it is started, cm-gunstore registers NPC target options.
-- Ensure order in server.cfg: ensure ox_lib, ensure ox_target, ensure cm-gunstore.

-- cm-ui is optional at resource-start level too (same convention as
-- cm-electrician/cm-license): the gun store clerk's "Press E" prompt and
-- cinematic conversation are exports['cm-ui']:ShowInteract/OpenNpcDialogue.
-- Without cm-ui running, the prompt/dialogue simply don't show; add it to
-- server.cfg before cm-gunstore to get them: ensure cm-ui, ensure cm-gunstore.

-- Per-item Access control (/gunadmin's Public/Gang Members/Law Org select)
-- optionally calls exports['cm-characters']:GetCharacterId and
-- exports['cm-gang']:GetGangForCharacter for "Gang" items (pcall-guarded --
-- without them, gang-restricted items just deny everyone). "Law Org" items
-- use the already-required cm-law's exports['cm-law']:IsLawMember.

-- The "Banned" weapon toggle exports('IsWeaponBanned', ...) for cm-inventory
-- to call (see cm-inventory/fxmanifest.lua) so a banned weapon can't be
-- equipped/used anywhere on the server, not just hidden from this store.

escrow_ignore {
    'shared/util.lua',
    'shared/config.lua',
    'shared/weapons.lua',
    'client/main.lua',
    'server/main.lua',
    'web/*',
    'install/*',
    'docs/*'
}
