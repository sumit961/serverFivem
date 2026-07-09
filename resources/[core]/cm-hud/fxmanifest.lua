fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM HUD - responsive CM UI, driver-only speedometer, no default ammo/vehicle-name popup, event-driven money HUD'
author 'CM Framework'
version '2.8.1-driver-speedo-no-vehicle-name'

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
    'cm-ui',
    'cm-core',
    'cm-playerdata'
}