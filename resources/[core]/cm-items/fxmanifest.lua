fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Development'
description 'CM-Items: item registry for CM Roleplay framework'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/categories.lua',
    'shared/items.lua',
    'shared/clothing.lua',
    'shared/virtual.lua',
    'shared/api.lua'
}

server_scripts {
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

files {
    'ui/images/*.png',
    'ui/images/*.webp',
    'ui/images/*.jpg',
    'ui/images/*.jpeg',
    'ui/images/*.svg',
    'ui/images/clothing/*.png',
    'ui/images/clothing/*.webp',
    'ui/images/clothing/*.jpg',
    'ui/images/clothing/*.jpeg',
    'shared/besttorso_male.json',
    'shared/besttorso_female.json'
}
