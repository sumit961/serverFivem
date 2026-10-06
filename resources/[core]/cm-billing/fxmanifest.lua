fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Billing - the single authoritative invoice platform (create, pay, void, history)'
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
    'server/invoices.lua',
    'server/payment.lua',
    'server/refund.lua',
    'server/exports.lua',
    'server/main.lua',
    'server/selftest.lua',
    'server/selftest_refund.lua',
    'server/selftest_policy.lua',
    'server/selftest_journal.lua',
    'server/selftest_payment.lua'
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
-- ensure oxmysql / ox_lib / cm-playerdata
-- ensure cm-phone      (optional: invoice notifications)
-- ensure cm-billing
-- Owner resources (cm-law, cm-ems, ...) call cm-billing lazily; start order is not critical.
