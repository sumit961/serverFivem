shared_script '@WaveShield/resource/include.lua'

fx_version 'cerulean'
game 'gta5'
author 'pScripts [tebex.pscripts.store]'
description 'Police MDT v2 with Dispatch'
lua54 'yes'
version '2.1.7'

ui_page 'web/build/index.html'

dependencies {
	'p_bridge', -- https://github.com/PiotreeQ/p_bridge
	'ox_lib', -- https://github.com/overextended/ox_lib
}

shared_scripts {
	'config/shared.lua'
}

client_scripts {
	'editable/wait_deps_client.lua',
	'@ox_lib/init.lua',
	'@p_bridge/imports.lua',
	'editable/client.lua',
	'modules/**/client.lua',
	'modules/dispatch/client_alerts.lua',
	'modules/dispatch/menu_client.lua',
	'modules/dispatch/ps-dispatch-alerts.lua'
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'editable/wait_deps_server.lua',
	'@ox_lib/init.lua',
	'@p_bridge/imports.lua',
	'editable/server.lua',
	'modules/**/server.lua',
	'modules/base/version_check.lua',
	'config/server.lua'
}

files {
	'data/*.lua',
	'web/build/index.html',
	'web/build/**/*',
	'web/assets/*.png',
	'web/assets/sounds/*.mp3',
	'web/tiles/**/*',
	'web/tiles/**/**/*',
	'web/tiles/**/*.jpg',
	'web/tiles/**/**/*.jpg',
	'web/tiles/*.jpg',
	'web/tiles/*.png',
	'locales/*.json'
}

escrow_ignore {
	'editable/*.lua',
	'data/*.lua',
	'config/*.lua',
	'modules/dispatch/ps-dispatch-alerts.lua',
	'modules/dispatch/client_alerts.lua',
	'modules/mysql/server.lua'
}

provide 'piotreq_gpt'
-- provide 'cd_dispatch'
-- provide 'lb-tablet'
-- provide 'ps-dispatch'
-- provide 'qs-dispatch'
dependency '/assetpacks'
