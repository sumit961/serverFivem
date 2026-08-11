local open, organizationId = false, nil
local HUD_REASON = 'cm-law:armory'

local function closeArmory()
    if not open then return end
    open, organizationId = false, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'legalArmoryClose' })
    TriggerEvent('cm-hud:client:showAfterUi', HUD_REASON)
end

RegisterNetEvent('cm-law:client:openArmory', function(orgId, label)
    if open or IsPauseMenuActive() or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    local result = lib.callback.await('cm-law:server:armory', false, orgId)
    if not result or result.ok ~= true then
        TriggerEvent('cm-hud:client:notify', result and result.error or 'Armory unavailable.', 'error')
        return
    end
    open, organizationId = true, orgId
    TriggerEvent('cm-hud:client:hideForUi', HUD_REASON)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'legalArmoryOpen', label = label, data = result })
end)

RegisterNUICallback('legalArmoryClose', function(_, cb) closeArmory(); cb({ ok = true }) end)

RegisterNUICallback('legalArmoryRefresh', function(_, cb)
    cb(lib.callback.await('cm-law:server:armory', false, organizationId) or { ok = false })
end)

RegisterNUICallback('legalArmoryManagement', function(_, cb)
    cb(lib.callback.await('cm-law:server:armoryManagement', false, organizationId) or { ok = false })
end)

RegisterNUICallback('legalArmorySave', function(data, cb)
    cb(lib.callback.await('cm-law:server:saveArmoryItem', false, organizationId, data) or { ok = false })
end)

RegisterNUICallback('legalArmoryLoadStock', function(_, cb)
    cb(lib.callback.await('cm-law:server:loadArmoryStock', false, organizationId) or { ok = false })
end)

RegisterNUICallback('legalArmoryCheckout', function(data, cb)
    cb(lib.callback.await('cm-law:server:armoryCheckout', false, organizationId, data and data.itemName) or { ok = false })
end)

RegisterNetEvent('cm-law:client:membershipChanged', function(state)
    if open and (type(state) ~= 'table' or state.onDuty ~= true) then closeArmory() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeArmory() end
end)
