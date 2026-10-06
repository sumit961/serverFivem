fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM development-only QA orchestrator and connected-client runner'
author 'CM Framework'
version '0.1.0'

dependency 'cm-ui'
ui_page 'ui/index.html'

files { 'ui/index.html', 'ui/app.js', 'ui/style.css' }

shared_script 'shared/scenarios.lua'
shared_script 'shared/assertions.lua'

server_scripts {
    'server/fixtures.lua',
    'server/runner.lua',
    'server/main.lua',
}

client_scripts {
    'client/actions.lua',
    'client/runner.lua',
    'client/main.lua',
}

-- Intentionally not ensured by server.cfg. Start it only in a local,
-- development-only QA session after the console-only cm_qa_enable command.
