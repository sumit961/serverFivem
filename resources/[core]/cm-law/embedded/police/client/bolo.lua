-- cm-police alert relays with no persistent state of their own -- BOLO
-- (Be-On-The-Lookout) issue/clear are pure toast + MDT-refresh (a BOLO
-- isn't tied to one fixed location, so no blip); ALPR hits DO have a
-- location, so that one gets a one-shot self-expiring blip, same shape as
-- client/dispatch.lua's own backupRequested handler. All real logic
-- (issuing/clearing BOLOs, camera placement/detection) lives server-side.

RegisterNetEvent('cm-police:client:boloIssued', function(alertText)
    PoliceNotify(('BOLO: %s'):format(tostring(alertText or '')), 'error', 'Dispatch')
    SendNUIMessage({ cmInterface = "police", action = 'bolosRefresh' })
end)

RegisterNetEvent('cm-police:client:boloCleared', function()
    SendNUIMessage({ cmInterface = "police", action = 'bolosRefresh' })
end)

local alprBlips = {}

RegisterNetEvent('cm-police:client:alprHit', function(plate, cameraLabel, coords, matches)
    local first = type(matches) == 'table' and matches[1] or nil
    local organization = first and tostring(first.organizationLabel or first.organizationId or 'Law') or 'Law'
    local reason = first and tostring(first.reason or first.description or '') or ''
    local count = type(matches) == 'table' and #matches or 0
    local suffix = count > 1 and (' · %d active Law BOLOs'):format(count) or (' · Active %s BOLO'):format(organization)
    if reason ~= '' then suffix = suffix .. (' · %s'):format(reason) end
    PoliceNotify(('ALPR HIT: %s — %s near %s'):format(tostring(plate or ''), suffix, tostring(cameraLabel or 'a camera')), 'error', 'Dispatch')
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.1)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('ALPR: %s'):format(tostring(plate or '')))
    EndTextCommandSetBlipName(blip)
    alprBlips[blip] = true
    CreateThread(function()
        Wait(60000)
        if alprBlips[blip] and DoesBlipExist(blip) then RemoveBlip(blip) end
        alprBlips[blip] = nil
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for blip in pairs(alprBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    alprBlips = {}
end)
