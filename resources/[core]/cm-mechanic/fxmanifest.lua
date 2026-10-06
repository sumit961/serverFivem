fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework'
description 'CM Mechanic: mechanic service requests and work orders (phone Services source owner + cm-contracts provider). Business/billing/vehicle state stay with cm-commercial-ownership / cm-billing / cm-vehicles.'
version '1.0.0'

dependencies {
    'oxmysql',
    'ox_lib',
    'cm-playerdata',
    'cm-vehicles',
    'cm-commercial-ownership',
    'cm-contracts',
    'cm-billing',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/pricing.lua',
    'server/core.lua',
    'server/store.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/dev-mock.js',
}

-- Start order: oxmysql, ox_lib, cm-playerdata, cm-vehicles, cm-commercial-ownership, cm-contracts, cm-billing, cm-phone, cm-mechanic.
-- cm-phone / cm-contracts are optional at start: the resource registers its phone service and provider when they (re)start.
