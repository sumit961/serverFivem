fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'cm-dev'
description 'CM Characters - Character slot & appearance system'
version '1.0.0'

shared_scripts {
    '@cm-core/shared/config.lua', -- If you have shared config
}

client_scripts {
    'client/main.lua',       -- Slot selector (existing)
    'client/creator.lua',    -- Character creation form
    'client/appearance.lua', -- Appearance editor
    'client/apply.lua',      -- Apply saved appearance
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- or your MySQL wrapper
    'server/main.lua',       -- Character getters (existing)
    'server/creation.lua',   -- Character creation (existing)
    'server/slots.lua',      -- Slot management (existing)
    'server/appearance.lua',   -- Save appearance
}

ui_page 'ui/appearance/index.html'

files {
    'ui/appearance/index.html',
    'ui/appearance/style.css',
    'ui/appearance/app.js',
    'ui/appearance/translation.js',
    'ui/slots/**/*',  -- Your existing slot UI files
}

-- Dependencies
dependencies {
    'cm-core',      -- Your core resource
    'cm-auth',      -- Auth system
}
