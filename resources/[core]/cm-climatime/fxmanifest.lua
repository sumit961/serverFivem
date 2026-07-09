fx_version 'cerulean'
game 'gta5'
lua54 'yes'

version '1.7.2-clock-map-zone-ui-fix'
author 'CM Framework / Sumit Yadav'
description 'CM Climatime - production weather/time with cm-ui admin panel, silent pre-spawn climate, overflow guard, and improved GTA zone map'

dependency 'cm-ui'

shared_scripts {
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/leaflet-loader.js',
    'ui/assets/map-vendor-Ig5MRTue.js',
    'ui/assets/ui-vendor-BkK9XKBi.js',
    'ui/assets/react-vendor-BtP0CW_r.js',
    'ui/assets/gta-map.png',
    'ui/assets/gta-map-local.png',
    'ui/assets/*.png',
    'ui/assets/map_tiles/*.png',
    'data/state.json'
}
