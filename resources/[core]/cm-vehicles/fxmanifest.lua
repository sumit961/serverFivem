fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Framework'
description 'CM owned vehicle system: keys, locks, menu, trunk access; inventory delegated to cm-inventory'
version '3.5.3'

ui_page 'ui/index.html'

shared_scripts {
    'shared/config.lua',
    'shared/utils.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/admin.lua',   -- admin/temporary vehicles: must precede main.lua,
                          -- which hooks into CMVehicles.Admin
    'server/main.lua',
    'server/location.lua',
    'server/operations.lua',
    'server/persistence.lua',
    'server/spawn.lua',
    'server/recovery.lua',
    'server/api.lua',
    'server/keys.lua',
    'server/trunk.lua'
}

client_scripts {
    'client/admin.lua',   -- admin/temporary vehicles
    'client/main.lua',
    'client/spawn.lua',
    'client/persistence.lua',
    'client/interaction.lua',
    'client/menu.lua'
}

client_exports {
    'TryOpenNearbyTrunkInventory',
    'HasRacingHarness',
    'GetVehicleFuel',
    'AddFuel',
    'SetFuelExact',
    'RepairVehicle',
    'WashVehicle',
    'SaveVehicleMods',
    'ApplyVehicleMods',
    'ApplyPerformance',
    'GetTuningMultiplier',
    'ApplyTyreLevel',
    'GetTyreLevel',
    'EstimateTopSpeed',
    'RunServiceProgress',
    'ShowServiceProgress',
    'UpdateServiceProgress',
    'HideServiceProgress'
}

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}

dependencies {
    'cm-playerdata',
    'cm-vehiclekeys',
    'cm-inventory'
}

-- Soft integrations: cm-family (family rank access), cm-house (garage assignment), rn-vehicleshop (catalog images).
