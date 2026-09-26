-- Patrol-car plate scanner. Client candidate discovery is local and bounded;
-- the server revalidates Law duty, permission, fleet access, buckets, range,
-- target entities, rendered plates and active BOLO matches.

local scanning = false
local scannerLoopRunning = false
local inFlight = false
local recentHits = {}
local DUPLICATE_COOLDOWN_MS = 45000
local lastHitPrune = 0

local function notify(message, kind)
    TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'inform')
end

local function hasPermission(state, permission)
    local permissions = type(state) == 'table' and state.permissions or {}
    return type(state) == 'table' and state.onDuty == true and state.suspended ~= true
        and (state.isLeader == true or (type(permissions) == 'table' and permissions[permission] == true))
end

function LawCanUsePlateScanner()
    local state = LocalPlayer.state.cmLegalOrg
    if type(state) == 'table' then
        return hasPermission(state, 'law.alpr') and (not state.capabilities or state.capabilities.alpr ~= false)
    end
    state = LocalPlayer.state.cmPolice
    return (hasPermission(state, 'police.alpr') or hasPermission(state, 'police.receive_dispatch'))
        and (type(PoliceCapabilityClientEnabled) ~= 'function' or PoliceCapabilityClientEnabled('alpr'))
end

local function forwardVector(vehicle)
    local heading = math.rad(GetEntityHeading(vehicle))
    return vector3(-math.sin(heading), math.cos(heading), 0.0)
end

local function candidates(patrol)
    local origin, forward, found = GetEntityCoords(patrol), forwardVector(patrol), {}
    local pool = GetGamePool('CVehicle') or {}
    for _, vehicle in ipairs(pool) do
        if #found >= 8 then break end
        if vehicle ~= patrol and DoesEntityExist(vehicle) then
            local delta = GetEntityCoords(vehicle) - origin
            local distance = #delta
            if distance <= 22.0 and distance > 1.0
                and (delta.x * forward.x + delta.y * forward.y) / distance >= -0.15 then
                local netId = NetworkGetNetworkIdFromEntity(vehicle)
                if netId and netId > 0 then found[#found + 1] = netId end
            end
        end
    end
    return found
end

local function isLocalFleetVehicle(patrol)
    local state = Entity(patrol).state
    local vehicleId = tonumber(state.cmVehicleId)
    if not vehicleId then return false end
    local org = LocalPlayer.state.cmLegalOrg
    if type(org) == 'table' then
        local fleet = state.cmLegalFleet
        return type(fleet) == 'table' and tonumber(fleet.vehicleId) == vehicleId
            and tostring(fleet.organizationId or '') == tostring(org.id or '')
    end
    local police = LocalPlayer.state.cmPolice
    local fleet = state.cmPoliceFleet
    return type(police) == 'table' and type(fleet) == 'table'
        and tonumber(fleet.vehicleId) == vehicleId
end

local function highlightHit(plate)
    for _, vehicle in ipairs(GetGamePool('CVehicle') or {}) do
        if DoesEntityExist(vehicle) and LawNormalizePlate(GetVehicleNumberPlateText(vehicle)) == plate then
            SetEntityDrawOutline(vehicle, true)
            SetEntityDrawOutlineColor(255, 60, 60, 255)
            SetTimeout(6000, function() if DoesEntityExist(vehicle) then SetEntityDrawOutline(vehicle, false) end end)
            return
        end
    end
end

local function toggleScanning()
    if not LawCanUsePlateScanner() then return notify('You are not authorized to use the plate scanner.', 'error') end
    scanning = not scanning
    notify(scanning and 'Plate scanner enabled.' or 'Plate scanner disabled.', scanning and 'success' or 'inform')
    if scanning and not scannerLoopRunning then
        scannerLoopRunning = true
        CreateThread(function()
            while scanning do
                if not LawCanUsePlateScanner() then
                    notify('Plate scanner disabled because your Law access changed.', 'inform')
                    scanning = false
                    break
                end
                local ped = PlayerPedId()
                local patrol = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or 0
                if patrol == 0 then
                    notify('Plate scanner disabled.', 'inform')
                    scanning = false
                    break
                end
                if not isLocalFleetVehicle(patrol) then
                    notify('Plate scanner requires an authorized Law fleet vehicle.', 'error')
                    scanning = false
                    break
                end
                if not inFlight then
                    local candidateIds = candidates(patrol)
                    if #candidateIds > 0 then
                        inFlight = true
                        CreateThread(function()
                            local hits = lib.callback.await('cm-law:server:scanVehiclePlates', false, candidateIds) or {}
                            inFlight = false
                            if not scanning then return end
                            local now = GetGameTimer()
                            if now - lastHitPrune > 300000 then
                                for key, time in pairs(recentHits) do if now - time > DUPLICATE_COOLDOWN_MS * 2 then recentHits[key] = nil end end
                                lastHitPrune = now
                            end
                            for _, bolo in ipairs(hits) do
                                local plate = LawNormalizePlate(tostring(bolo.plate or ''))
                                if plate then
                                    local key = table.concat({ tostring(bolo.organizationId or ''), plate,
                                        tostring(bolo.createdAt or ''), tostring(bolo.description or '') }, '|')
                                    if not recentHits[key] or now - recentHits[key] >= DUPLICATE_COOLDOWN_MS then
                                        recentHits[key] = now
                                        notify(('ALPR HIT: %s — active %s BOLO. Reason: %s'):format(plate,
                                            tostring(bolo.organizationLabel or bolo.organizationId or 'Law'),
                                            tostring(bolo.description or 'Active vehicle BOLO')), 'error')
                                        highlightHit(plate)
                                    end
                                end
                            end
                        end)
                    end
                end
                Wait(2500)
            end
            scannerLoopRunning = false
        end)
    end
end

function LawTogglePlateScanner()
    return toggleScanning()
end

function LawIsPlateScannerActive()
    return scanning
end

RegisterCommand('lawscan', toggleScanning, false)

local function cleanupScanner()
    scanning = false
end
RegisterNetEvent('cm-law:client:forceDutyCleanup', cleanupScanner)
RegisterNetEvent('cm-police:client:forceDutyCleanup', cleanupScanner)
RegisterNetEvent('cm-playerdata:client:characterUnloaded', cleanupScanner)
local localPlayerBag = ('player:%s'):format(GetPlayerServerId(PlayerId()))
AddStateBagChangeHandler('cmLegalOrg', nil, function(bagName, _, value)
    if bagName == localPlayerBag and (type(value) ~= 'table' or value.onDuty ~= true or value.suspended == true) then cleanupScanner() end
end)
AddStateBagChangeHandler('cmPolice', nil, function(bagName, _, value)
    if bagName == localPlayerBag and (type(value) ~= 'table' or value.onDuty ~= true or value.suspended == true) then cleanupScanner() end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then cleanupScanner() end
end)
