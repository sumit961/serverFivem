fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Server'
description 'CM License Test System — Driver, Boat, Air exams'
version '1.0.0'

dependencies {
    'cm-core',
    'cm-playerdata',
    'cm-items',
    'cm-inventory',
    'cm-ui',
    'cm-admin',
    'oxmysql'
}

shared_scripts {
    'config.lua',
    'shared/constants.lua',
    'shared/utils.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/cache.lua',
    'server/licenses.lua',
    'server/tests.lua',
    'server/admin.lua',
    'server/main.lua'
}

client_scripts {
    'client/nui.lua',
    'client/npc.lua',
    'client/test.lua',
    'client/checkpoints.lua',
    'client/hud.lua',
    'client/admin.lua',
    'client/main.lua'
}

ui_page 'nui/index.html'

files {
    'shared/constants.lua',
    'shared/utils.lua',
    'server/database.lua',
    'server/cache.lua',
    'server/licenses.lua',
    'server/tests.lua',
    'server/admin.lua',
    'client/nui.lua',
    'client/npc.lua',
    'client/test.lua',
    'client/checkpoints.lua',
    'client/hud.lua',
    'client/admin.lua',
    'nui/index.html',
    'nui/style.css',
    'nui/script.js',
    'sql/001_cm_license.sql',
    'sql/002_cm_license_constraints.sql',
    'sql/003_cm_license_delivery.sql'
}
