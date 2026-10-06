fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Phone - character phone numbers, contacts, SMS, calls, emergency and classifieds'
author 'CM Framework'
version '1.0.0'

dependencies {
    'oxmysql',
    'ox_lib',
    'cm-playerdata'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/core.lua',
    'server/schema.lua',
    'server/numbers.lua',
    'server/contacts.lua',
    'server/messages.lua',
    'server/calls.lua',
    'server/adverts.lua',
    'server/emergency.lua',
    'server/services_core.lua',
    'server/services.lua',
    'server/exports.lua',
    'server/main.lua',
    'server/selftest.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/dev-mock.js'
}

-- Recommended order:
-- ensure oxmysql
-- ensure ox_lib
-- ensure cm-playerdata
-- ensure cm-hud        (notifications, optional)
-- ensure cm-phone
-- cm-ems / cm-law are called lazily for emergency dispatch (optional at start order)
