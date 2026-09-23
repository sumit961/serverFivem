-- cm-law/client/vehicle_scanner.lua
-- Patrol-car plate scanner: while driving, reads plates off nearby vehicles
-- and checks them against the shared BOLO board (server/bolo.lua). Distinct
-- from the embedded legacy Police module's ALPR (fixed camera props an admin
-- places, fully server-side) -- this is an officer-carried scanner usable by
-- any of the four organizations from their own patrol vehicle, matching the
-- reference resource's "patrol-car plate scan" idea, reimplemented cleanly.

local scanning = false
local knownHits = {} -- plate -> GetGameTimer() expiry, so the same hit isn't re-alerted every scan tick

local function notify(message, kind)
    TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'inform')
end

local function legalState()
    local state = LocalPlayer.state.cmLegalOrg
    return type(state) == 'table' and state or nil
end

local function eligible()
    local state = legalState()
    return type(state) == 'table' and state.onDuty == true and state.suspended ~= true
end

local function nearbyPlates(vehicle, radius)
    local origin = GetEntityCoords(vehicle)
    local plates = {}
    for _, candidate in ipairs(GetAllVehicles()) do
        if candidate ~= vehicle and DoesEntityExist(candidate) then
            local distance = #(origin - GetEntityCoords(candidate))
            if distance <= radius then
                local plate = tostring(GetVehicleNumberPlateText(candidate) or ''):gsub('%s+', ''):upper()
                if plate ~= '' then plates[#plates + 1] = plate end
            end
        end
    end
    return plates
end

local function highlightHit(plate)
    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) and tostring(GetVehicleNumberPlateText(vehicle) or ''):gsub('%s+', ''):upper() == plate then
            SetEntityDrawOutline(vehicle, true)
            SetEntityDrawOutlineColor(255, 60, 60, 255)
            SetTimeout(6000, function() if DoesEntityExist(vehicle) then SetEntityDrawOutline(vehicle, false) end end)
        end
    end
end

local function toggleScanning()
    if not eligible() then return notify('You must be on duty to use the plate scanner.', 'error') end
    scanning = not scanning
    notify(scanning and 'Plate scanner active.' or 'Plate scanner stopped.', scanning and 'success' or 'inform')
end

RegisterCommand('lawscan', toggleScanning, false)

CreateThread(function()
    while true do
        local wait = 2000
        if scanning and eligible() then
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                    local plates = nearbyPlates(vehicle, 20.0)
                    if #plates > 0 then
                        local hits = lib.callback.await('cm-law:server:scanVehiclePlates', false, plates) or {}
                        local now = GetGameTimer()
                        for _, bolo in ipairs(hits) do
                            if not knownHits[bolo.plate] or knownHits[bolo.plate] < now then
                                knownHits[bolo.plate] = now + 60000
                                notify(('SCANNER HIT · %s · %s'):format(bolo.plate, bolo.description), 'error')
                                highlightHit(bolo.plate)
                            end
                        end
                    end
                else
                    scanning = false
                end
            else
                scanning = false
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then scanning = false end
end)
