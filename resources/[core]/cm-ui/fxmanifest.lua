fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-ui'
author 'CM Framework / Grand RP'
description 'Central CM Framework UI theme, components, and NUI helper utilities'
version '2.0.0'

shared_script 'shared/theme.lua'

client_scripts {
    'client/interact.lua',
    'client/dialogue.lua',
    'client/confirm.lua',
    'client/preview.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/app.js',
    'web/cm-theme.css',
    'web/cm-dashboard.css',
    'web/cm-organization.css',
    'web/cm-organization-fonts.css',
    'web/cm-organization-icons.css',
    'web/cm-organization.js',
    'web/cm-components.css',
    'web/cm-layout.css',
    'web/cm-armory.css',
    'web/cm-interact.css',
    'web/cm-dialogue.css',
    'web/cm-style.css',
    'web/cm-ui.js',
    'web/cm-style-preview.js',
    'web/cm-icons.css',
    'web/preview.html',
    'web/fonts/*.ttf',
    'web/fonts/*.woff2',
    'docs/CM_UI_USAGE.md',
    'docs/CM_UI_SYSTEM.md'
}
