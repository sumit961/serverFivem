local Config = CMInventory.Config
local isOpen = false
local Drops = {}

local function nui(action, payload)
    payload = payload or {}
    payload.action = action
    SendNUIMessage(payload)
end

local function openInventory(payload)
    isOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    DisplayRadar(false)
    nui('open', payload or {})
    TriggerServerEvent('cm-inventory:server:requestDrops')
end

local function closeInventory()
    isOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    DisplayRadar(true)
    nui('close', {})
end

local function drawText3D(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(235, 245, 245, 230)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(sx, sy)
end

local function getClosestDrop()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDist = nil, 9999.0
    for _, drop in ipairs(Drops) do
        local c = drop.coords or {}
        local dist = #(coords - vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0))
        if dist < closestDist then
            closest = drop
            closestDist = dist
        end
    end
    return closest, closestDist
end

RegisterNetEvent('cm-inventory:client:open', function(payload)
    openInventory(payload)
end)


RegisterNetEvent('cm-inventory:client:update', function(payload)
    if isOpen then
        nui('update', payload or {})
    end
end)

RegisterNetEvent('cm-inventory:client:updateDrops', function(drops)
    Drops = type(drops) == 'table' and drops or {}
end)

RegisterNetEvent('cm-inventory:client:notify', function(message, typeName)
    nui('notify', { message = message or '', type = typeName or 'info' })
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message or '')
    EndTextCommandThefeedPostTicker(false, false)
end)

RegisterNetEvent('cm-inventory:client:useProgress', function(label, ms)
    nui('progress', { label = label or 'Using item...', ms = tonumber(ms) or 1000 })
end)

RegisterNetEvent('cm-inventory:client:applyHealth', function(amount)
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    local maxHealth = GetEntityMaxHealth(ped)
    SetEntityHealth(ped, math.min(maxHealth, health + (tonumber(amount) or 25)))
end)

RegisterNetEvent('cm-inventory:client:applyArmor', function(amount)
    local ped = PlayerPedId()
    local armor = GetPedArmour(ped)
    SetPedArmour(ped, math.min(100, armor + (tonumber(amount) or 75)))
end)


local equippedWeaponHash = nil
local equipmentState = {}

local WeaponMap = {
    weapon_pistol = `WEAPON_PISTOL`,
    weapon_combatpistol = `WEAPON_COMBATPISTOL`,
    weapon_appistol = `WEAPON_APPISTOL`,
    weapon_pumpshotgun = `WEAPON_PUMPSHOTGUN`,
    weapon_smg = `WEAPON_SMG`,
    weapon_carbinerifle = `WEAPON_CARBINERIFLE`
}

local function notifyLocal(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message or '')
    EndTextCommandThefeedPostTicker(false, false)
end

local function applyEquipmentSlot(slot, item)
    equipmentState[slot] = item
    local ped = PlayerPedId()

    if slot == 'weapon' then
        if equippedWeaponHash then
            RemoveWeaponFromPed(ped, equippedWeaponHash)
            equippedWeaponHash = nil
        end
        if item and item.item_name and WeaponMap[item.item_name] then
            equippedWeaponHash = WeaponMap[item.item_name]
            GiveWeaponToPed(ped, equippedWeaponHash, 250, false, true)
            SetPedAmmo(ped, equippedWeaponHash, 250)
            SetCurrentPedWeapon(ped, equippedWeaponHash, true)
            notifyLocal(('Equipped %s'):format(item.label or item.item_name))
        end
    elseif slot == 'bodyarmor' then
        if item then
            local durability = tonumber(item.durability or (item.metadata and item.metadata.durability) or 100) or 100
            SetPedArmour(ped, math.max(0, math.min(100, math.floor(durability))))
            notifyLocal(('Equipped %s'):format(item.label or item.item_name))
        else
            SetPedArmour(ped, 0)
        end
    elseif slot == 'bag' then
        if item then
            notifyLocal(('Equipped %s'):format(item.label or item.item_name))
        end
    end
end


RegisterNetEvent('cm-inventory:client:addWeaponAmmo', function(weaponName, amount)
    local ped = PlayerPedId()
    weaponName = tostring(weaponName or ''):lower()
    amount = tonumber(amount) or 0
    local hash = WeaponMap[weaponName]
    if not hash or amount <= 0 then return end
    if not HasPedGotWeapon(ped, hash, false) then
        GiveWeaponToPed(ped, hash, 0, false, true)
    end
    AddAmmoToPed(ped, hash, amount)
    SetCurrentPedWeapon(ped, hash, true)
    notifyLocal(('Reloaded %sx ammo'):format(amount))
end)


RegisterNetEvent('cm-inventory:client:noInventoryAmmo', function(message)
    local ped = PlayerPedId()
    if equippedWeaponHash then
        SetPedAmmo(ped, equippedWeaponHash, 0)
    end
    notifyLocal(message or 'No inventory ammo available.')
end)

CreateThread(function()
    while true do
        if equippedWeaponHash then
            Wait(0)
            DisableControlAction(0, 45, true) -- disable GTA reload; inventory controls ammo.
            local ped = PlayerPedId()
            if IsPedShooting(ped) then
                TriggerServerEvent('cm-inventory:server:weaponShot')
                Wait(120)
            end
        else
            Wait(400)
        end
    end
end)

RegisterNetEvent('cm-inventory:client:equipmentSlot', function(slot, item)
    applyEquipmentSlot(slot, item)
end)

RegisterNetEvent('cm-inventory:client:setEquipment', function(payload)
    equipmentState = type(payload) == 'table' and payload or {}
    for slot, item in pairs(equipmentState) do
        applyEquipmentSlot(slot, item)
    end
end)

RegisterCommand('inventory', function()
    if isOpen then closeInventory() return end
    TriggerServerEvent('cm-inventory:server:openInventory')
end, false)

RegisterCommand('inv', function()
    if isOpen then closeInventory() return end
    TriggerServerEvent('cm-inventory:server:openInventory')
end, false)

RegisterKeyMapping('inventory', 'Open inventory', 'keyboard', Config.OpenKey or 'I')

RegisterCommand('invping', function()
    print('[CM-INVENTORY-CLIENT] invping works - client/main.lua is loaded')
    TriggerServerEvent('cm-inventory:server:debugPing')
    TriggerServerEvent('cm-inventory:server:requestDrops')
end, false)

RegisterCommand('testgive', function(_, args)
    local itemName = tostring(args[1] or 'water'):lower()
    local amount = tonumber(args[2]) or 1
    print(('[CM-INVENTORY-CLIENT] testgive command called: %sx %s'):format(amount, itemName))
    TriggerServerEvent('cm-inventory:server:debugGiveItem', itemName, amount)
end, false)

RegisterCommand('pickupdrop', function()
    local drop, dist = getClosestDrop()
    if drop and dist <= ((Config.Drops and Config.Drops.pickupDistance) or 2.0) then
        TriggerServerEvent('cm-inventory:server:pickupDrop', drop.id)
    else
        TriggerEvent('cm-inventory:client:notify', 'No item drop nearby.', 'error')
    end
end, false)


RegisterCommand('givetest', function(_, args)
    local itemName = tostring(args[1] or 'water'):lower()
    local amount = tonumber(args[2]) or 1
    print(('[CM-INVENTORY-CLIENT] givetest command called: %sx %s'):format(amount, itemName))
    TriggerServerEvent('cm-inventory:server:devGiveTest', itemName, amount)
end, false)

RegisterCommand('showtestreceiver', function()
    print('[CM-INVENTORY-CLIENT] showtestreceiver command called')
    TriggerServerEvent('cm-inventory:server:showTestReceiver')
end, false)

RegisterCommand('cleartestreceiver', function()
    print('[CM-INVENTORY-CLIENT] cleartestreceiver command called')
    TriggerServerEvent('cm-inventory:server:clearTestReceiver')
end, false)

RegisterNUICallback('close', function(_, cb)
    closeInventory()
    cb({ ok = true })
end)

RegisterNUICallback('moveItem', function(data, cb)
    TriggerServerEvent('cm-inventory:server:moveItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('splitItem', function(data, cb)
    TriggerServerEvent('cm-inventory:server:splitItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('dropItem', function(data, cb)
    TriggerServerEvent('cm-inventory:server:dropItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('useItem', function(data, cb)
    TriggerServerEvent('cm-inventory:server:useItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('giveItem', function(data, cb)
    TriggerServerEvent('cm-inventory:server:giveItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('reloadWeapon', function(_, cb)
    TriggerEvent('cm-inventory:client:notify', 'Manual reload is disabled. Ammo is used from inventory when you shoot.', 'info')
    cb({ ok = true })
end)

CreateThread(function()
    while true do
        if isOpen then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            if IsControlJustPressed(0, 322) then closeInventory() end -- ESC
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- Quick access keys 1-5 while inventory is closed.
CreateThread(function()
    local controls = {157, 158, 160, 164, 165}
    while true do
        if not isOpen then
            for index, control in ipairs(controls) do
                if IsControlJustPressed(0, control) then
                    TriggerServerEvent('cm-inventory:server:useItem', { slot = 'quickaccess-' .. index })
                end
            end
            Wait(0)
        else
            Wait(300)
        end
    end
end)



-- Keep equipped armor durability synced to the bodyarmor item metadata.
CreateThread(function()
    local lastArmor = nil
    while true do
        local item = equipmentState and equipmentState.bodyarmor or nil
        if item then
            local armor = GetPedArmour(PlayerPedId())
            if lastArmor == nil then lastArmor = armor end
            if armor ~= lastArmor then
                lastArmor = armor
                TriggerServerEvent('cm-inventory:server:armorChanged', armor)
                Wait(1200)
            end
            Wait(500)
        else
            lastArmor = nil
            Wait(1200)
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(2500)
    TriggerServerEvent('cm-inventory:server:requestEquipment')
end)

AddEventHandler('playerSpawned', function()
    Wait(2500)
    TriggerServerEvent('cm-inventory:server:requestEquipment')
end)

-- Ground drops: marker + E pickup.
CreateThread(function()
    Wait(1500)
    TriggerServerEvent('cm-inventory:server:requestDrops')

    while true do
        local sleep = 1000
        if not isOpen and Drops and #Drops > 0 then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local markerDistance = (Config.Drops and Config.Drops.markerDistance) or 18.0
            local pickupDistance = (Config.Drops and Config.Drops.pickupDistance) or 2.0

            for _, drop in ipairs(Drops) do
                local c = drop.coords or {}
                local dropCoords = vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0)
                local dist = #(coords - dropCoords)
                if dist <= markerDistance then
                    sleep = 0
                    DrawMarker((Config.Drops and Config.Drops.markerType) or 2, dropCoords.x, dropCoords.y, dropCoords.z + 0.18,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.25, 0.25, 0.25, 39, 231, 255, 170,
                        false, true, 2, false, nil, nil, false)
                    drawText3D(dropCoords.x, dropCoords.y, dropCoords.z + 0.45,
                        ('%sx %s'):format(drop.quantity or 1, drop.label or drop.item_name or 'Item'))
                    if dist <= pickupDistance then
                        drawText3D(dropCoords.x, dropCoords.y, dropCoords.z + 0.65, '[E] Pick up')
                        if IsControlJustPressed(0, 38) then -- E
                            TriggerServerEvent('cm-inventory:server:pickupDrop', drop.id)
                            Wait(500)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
