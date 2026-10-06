fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Payday - hourly wage payout, deferred job XP and playtime tracking'
author 'CM Framework'
version '1.0.0'

dependencies {
    'oxmysql',
    'cm-playerdata'
}

shared_script 'shared/config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

-- Recommended order:
-- ensure cm-playerdata
-- ensure cm-hud
-- ensure cm-payday
-- ensure cm-taxi / cm-fishing / cm-electrician (pay into cm-payday when it's running)
