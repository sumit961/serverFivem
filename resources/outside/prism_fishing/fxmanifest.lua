fx_version 'cerulean'
game 'gta5'
lua54 'yes'
description 'Fishing System'
version '1.1.4'
author 'Prism Scripts'

ui_page 'ui/build/index.html'

files {
    'shared/*.lua',
    'ui/build/index.html',
    'ui/build/**/*',

}

shared_scripts {
    '@ox_lib/init.lua',

    'shared/config.lua',
    'shared/utils.lua',
    'shared/framework.lua',
    'locales/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',

}


client_scripts {
    'client/*.lua'
}

dependency {
    'oxmysql',
    'ox_lib',
}
escrow_ignore {
    'locales/*.lua',
    'shared/*.lua',
    'server/core.lua',
    'client/function.lua',
}

dependency '/assetpacks'

--DECRYPTED & 3D FIXED BY BYE CFX. discord.gg/byecfx
--DECRYPTED & 3D FIXED BY BYE CFX. discord.gg/byecfx
--DECRYPTED & 3D FIXED BY BYE CFX. discord.gg/byecfx
--DECRYPTED & 3D FIXED BY BYE CFX. discord.gg/byecfx
--DECRYPTED & 3D FIXED BY BYE CFX. discord.gg/byecfx
