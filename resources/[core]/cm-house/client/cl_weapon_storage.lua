-- cm-house | property weapon-storage NUI bridge
local open = false
local current = nil

local function setBusy(value)
    if CMHouseInteraction and CMHouseInteraction.SetBusy then
        CMHouseInteraction.SetBusy('weaponStorage', value == true)
    end
end

local function closeWeaponStorage()
    if not open then return end
    open = false
    current = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'weaponStorage:close' })
    setBusy(false)
end

local function showWeaponStorage(payload)
    if type(payload) ~= 'table' then return false end
    current = payload
    open = true
    setBusy(true)
    if CMHouseInteraction and CMHouseInteraction.BlockFor then CMHouseInteraction.BlockFor(1000) end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'weaponStorage:open', data = payload })
    return true
end

local function requestOpen(houseId, index)
    if open then return false end
    local ok, payload = lib.callback.await('cm-house:server:openWeaponStorage', false,
        tonumber(houseId), tonumber(index))
    if not ok then
        lib.notify({ description = payload or 'Weapon storage would not open.', type = 'error' })
        return false
    end
    return showWeaponStorage(payload)
end

RegisterNetEvent('cm-house:client:openWeaponStorageRequested', function(houseId, index)
    requestOpen(houseId, index)
end)

RegisterNetEvent('cm-house:client:openWeaponStorage', function(payload)
    showWeaponStorage(payload)
end)

RegisterNUICallback('weaponStorage:close', function(_, cb)
    closeWeaponStorage()
    cb({ ok = true })
end)

RegisterNUICallback('weaponStorage:refresh', function(_, cb)
    if not open or not current then cb({ ok = false }); return end
    local ok, payload = lib.callback.await('cm-house:server:openWeaponStorage', false,
        current.houseId, current.storageIndex)
    if ok then
        current = payload
        SendNUIMessage({ action = 'weaponStorage:update', data = payload })
    end
    cb({ ok = ok, data = ok and payload or nil, message = ok and nil or payload })
end)

RegisterNUICallback('weaponStorage:transfer', function(data, cb)
    if not open or not current then cb({ ok = false, message = 'Storage is closed.' }); return end
    local ok, payload = lib.callback.await('cm-house:server:weaponStorageTransfer', false,
        current.houseId, current.storageIndex,
        tostring(data and data.direction or ''),
        tonumber(data and data.rowId),
        tonumber(data and data.amount) or 1)
    if ok then
        current = payload
        SendNUIMessage({ action = 'weaponStorage:update', data = payload })
        cb({ ok = true, data = payload })
        return
    end
    lib.notify({ description = payload or 'The weapon transfer failed.', type = 'error' })
    cb({ ok = false, message = payload })
end)

exports('OpenWeaponStorage', requestOpen)
exports('CloseWeaponStorage', closeWeaponStorage)
exports('IsWeaponStorageOpen', function() return open end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeWeaponStorage() end
end)
