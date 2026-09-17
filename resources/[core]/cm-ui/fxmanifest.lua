fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-ui'
author 'CM Framework / Grand RP'
description 'Central CM Framework UI theme, components, and NUI helper utilities'
version '1.3.0'

shared_script 'shared/theme.lua'

client_scripts {
    'client/interact.lua',
    'client/dialogue.lua',
    'client/preview.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/app.js',
    'web/cm-theme.css',
    'web/cm-dashboard.css',
    'web/cm-components.css',
    'web/cm-armory.css',
    'web/cm-interact.css',
    'web/cm-dialogue.css',
    'web/cm-ui.js',
    'web/cm-icons.css',
    'web/preview.html',
    'web/fonts/*.ttf',
    'docs/CM_UI_USAGE.md'
}
