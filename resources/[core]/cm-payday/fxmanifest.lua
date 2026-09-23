fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Payday - hourly wage payout, deferred job XP and playtime tracking'
author 'CM Framework'
version '1.0.0'

shared_script 'shared/config.lua'

server_script 'server/main.lua'

-- Recommended order:
-- ensure cm-playerdata
-- ensure cm-hud
-- ensure cm-payday
-- ensure cm-taxi / cm-fishing / cm-electrician (pay into cm-payday when it's running)
