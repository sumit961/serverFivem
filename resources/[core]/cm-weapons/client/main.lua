local adminOpen = false
local lastAdminData = nil
local weaponDamageRules = {}

local function nuiFocus(state)
    adminOpen = state == true
    SetNuiFocus(adminOpen, adminOpen)
    SendNUIMessage({ type = adminOpen and 'show' or 'hide' })
end

local function notify(message, typ)
    TriggerEvent('cm-hud:client:notify', tostring(message or ''), typ or 'info')
end

RegisterNetEvent('cm-weapons:client:openAdmin', function()
    nuiFocus(true)
end)

RegisterNetEvent('cm-weapons:client:adminData', function(payload)
    lastAdminData = payload or {}
    SendNUIMessage({ type = 'adminData', payload = lastAdminData })

    weaponDamageRules = {}
    for _, weapon in ipairs((payload and payload.weapons) or {}) do
        if weapon.enabled and weapon.weaponHash and weapon.weaponHash ~= '' and weapon.damage and weapon.damage > 0 then
            weaponDamageRules[joaat(weapon.weaponHash)] = tonumber(weapon.damage) or 0
        end
    end
end)

RegisterCommand(Config.AdminCommand or 'cmweaponadmin', function()
    TriggerServerEvent('cm-weapons:server:requestAdminData')
end, false)

RegisterNUICallback('close', function(_, cb)
    nuiFocus(false)
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    TriggerServerEvent('cm-weapons:server:requestAdminData')
    cb({ ok = true })
end)

RegisterNUICallback('syncItems', function(_, cb)
    TriggerServerEvent('cm-weapons:server:syncAllToCmItems')
    cb({ ok = true })
end)

RegisterNUICallback('saveAmmo', function(data, cb)
    TriggerServerEvent('cm-weapons:server:saveAmmo', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('saveWeapon', function(data, cb)
    TriggerServerEvent('cm-weapons:server:saveWeapon', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('saveImage', function(data, cb)
    TriggerServerEvent('cm-weapons:server:saveImage', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('deleteAmmo', function(data, cb)
    data = data or {}
    TriggerServerEvent('cm-weapons:server:deleteAmmo', data.itemName or data.item_name, data.force == true)
    cb({ ok = true })
end)

RegisterNUICallback('deleteWeapon', function(data, cb)
    data = data or {}
    TriggerServerEvent('cm-weapons:server:deleteWeapon', data.itemName or data.item_name)
    cb({ ok = true })
end)

RegisterNetEvent('cm-weapons:client:spawnAmmoPickup', function(data)
    data = data or {}
    local coords = data.coords or {}
    local x = tonumber(coords.x or coords[1])
    local y = tonumber(coords.y or coords[2])
    local z = tonumber(coords.z or coords[3])
    local pickupHash = tonumber(data.pickupHash)
    if not x or not y or not z or not pickupHash then return end

    -- Best effort GTA pickup. cm-inventory can still handle its normal custom prop/item drop UI.
    -- This just lets ammo drops use the correct PICKUP_AMMO_* hash when desired.
    local amount = math.max(1, math.floor(tonumber(data.amount) or 1))
    pcall(function()
        CreateAmbientPickup(pickupHash, x, y, z + 0.05, 0, amount, 0, false, true)
    end)
end)

-- Optional damage modifier support. OFF by default in Config.UseClientDamageModifier.
-- Damage is stored per gun in cm-weapons; enable this only after testing your server balance.
CreateThread(function()
    while true do
        local sleep = 1000
        if Config.UseClientDamageModifier and next(weaponDamageRules) ~= nil then
            local ped = PlayerPedId()
            -- Only spend a per-frame native when the player is actually armed;
            -- an unarmed player (the common case) keeps the loop asleep at 500ms.
            if IsPedArmed(ped, 7) then
                local selected = GetSelectedPedWeapon(ped)
                local damage = weaponDamageRules[selected]
                if damage and damage > 0 then
                    local mult = damage / (tonumber(Config.DamageModifierBase) or 30.0)
                    if SetWeaponDamageModifierThisFrame then
                        SetWeaponDamageModifierThisFrame(selected, mult)
                    elseif SetWeaponDamageModifier then
                        SetWeaponDamageModifier(selected, mult)
                    end
                    sleep = 0 -- ThisFrame variant must run every frame while armed
                else
                    sleep = 300
                end
            else
                sleep = 500
            end
        end
        Wait(sleep)
    end
end)

exports('GetCachedAdminData', function()
    return lastAdminData
end)
