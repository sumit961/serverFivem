fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM HUD - Visual HUD only: Native Minimap, Vehicle Speedometer, Money, Location, Notifications'
author 'CM Framework'
version '2.6.1-ui-only-hide-bridge'

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/assets/**/*',
    'ui/fonts/Nunito.ttf',
    'ui/fonts/Nekst-Regular.otf',
    'ui/fonts/Nekst-SemiBold.otf',
    'ui/fonts/Nekst-Bold.otf',
    'ui/fonts/RobotoMono.ttf',
    'ui/fonts/Unbounded.ttf'
}

dependencies {
    'cm-core',
    'cm-playerdata'
}