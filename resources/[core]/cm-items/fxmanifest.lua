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
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/items_catalog.lua',
    'server/item_props.lua',
    'server/image_upload.lua'
}

dependency 'oxmysql'

ui_page 'ui/preview.html'

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
    'ui/images/clothing/custom/*.png',
    'ui/images/clothing/custom/*.webp',
    'ui/images/clothing/custom/*.jpg',
    'ui/images/clothing/custom/*.jpeg',
    'ui/images/catalog/*.png',
    'ui/images/catalog/*.webp',
    'ui/images/catalog/*.jpg',
    'ui/images/catalog/*.jpeg',
    'ui/preview.html',
    'ui/preview.css',
    'ui/preview.js',
    'shared/besttorso_male.json',
    'shared/besttorso_female.json'
}
