fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework / refactored for ClockMate'
description 'CM owned vehicle system: keys, locks, menu, trunk access; inventory delegated to cm-inventory'
version '2.3.0-fuel-engine-impact-fix'

ui_page 'ui/index.html'

shared_scripts {
    'shared/config.lua',
    'shared/utils.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/spawn.lua',
    'server/keys.lua',
    'server/trunk.lua'
}

client_scripts {
    'client/main.lua',
    'client/spawn.lua',
    'client/interaction.lua',
    'client/menu.lua'
}

client_exports {
    'TryOpenNearbyTrunkInventory',
    'HasRacingHarness'
}

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}

dependencies {
    'cm-vehiclekeys',
    'cm-inventory'
}
