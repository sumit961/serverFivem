-- cm-police vehicle impound & tow (client). Two independent chat commands,
-- neither routed through the G-menu -- impounding targets a VEHICLE (the
-- G-menu only ever targets nearby players), and releasing must be usable by
-- ANY player, not just Police members (this script runs for every
-- connected client regardless of Police membership, same as
-- cuffs.lua/booking.lua's threads already do).

local function notify(message, kind)
    PoliceNotify(message, kind)
end

local TowTruck, TowTarget
local KioskLocations = {}
local OperatorPeds, OperatorBlips = {}, {}
local impoundReleaseOpen = false

function PoliceGetNearestImpoundOperator()
    local coords, best, bestDistance = GetEntityCoords(PlayerPedId()), 0, 25.0
    for _, ped in pairs(OperatorPeds) do
        if DoesEntityExist(ped) then
            local distance = #(coords - GetEntityCoords(ped))
            if distance < bestDistance then best, bestDistance = ped, distance end
        end
    end
    return best
end

local function nearOperator(entity, radius)
    local coords = GetEntityCoords(entity)
    for index, location in ipairs(KioskLocations) do
        if #(coords - vector3(location.x, location.y, location.z)) <= radius then return location, index end
    end
end

local function configuredTowTruck(vehicle)
    local model = GetEntityModel(vehicle)
    for _, name in ipairs(Config.Impound.TowModels or {}) do
        if model == GetHashKey(name) then return true end
    end
    local fleet = Entity(vehicle).state.cmPoliceFleet or Entity(vehicle).state.cmLegalFleet
    local fleetModel = type(fleet) == 'table' and tostring(fleet.model or ''):lower() or ''
    if fleetModel:find('tow', 1, true) and model == GetHashKey(fleetModel) then return true end
    return false
end

local function closestTowTarget(towTruck)
    local origin, best, bestDistance = GetEntityCoords(towTruck), nil, Config.Impound.TowAttachDistance or 10.0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if vehicle ~= towTruck and DoesEntityExist(vehicle) then
            local distance = #(origin - GetEntityCoords(vehicle))
            if distance < bestDistance then best, bestDistance = vehicle, distance end
        end
    end
    return best
end

local function hookedTowTarget(towTruck)
    local attached = 0
    pcall(function() attached = GetEntityAttachedToTowTruck(towTruck) end)
    if attached and attached ~= 0 and attached ~= towTruck and DoesEntityExist(attached) then return attached end
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if vehicle ~= towTruck and DoesEntityExist(vehicle) and IsEntityAttachedToEntity(vehicle, towTruck) then return vehicle end
    end
end

RegisterCommand('policetow', function()
    if TowTarget and DoesEntityExist(TowTarget) then
        DetachVehicleFromTowTruck(TowTruck, TowTarget)
        return notify('Vehicle detached. Take it to the impound drop-off and press E.', 'inform')
    end
    local ped = PlayerPedId()
    local towTruck = GetVehiclePedIsIn(ped, false)
    if towTruck == 0 then return notify('Enter an authorized organization tow truck first.', 'error') end
    if GetPedInVehicleSeat(towTruck, -1) ~= ped then return notify('You must be in the tow truck driver seat.', 'error') end
    if not configuredTowTruck(towTruck) then return notify('This fleet vehicle is not recognized as a tow truck. Its model name must contain "tow" or be in TowModels.', 'error') end
    local target = closestTowTarget(towTruck)
    if not target then return notify('No vehicle is close enough to attach.', 'error') end
    local ok, message = lib.callback.await('cm-police:server:beginTow', false,
        NetworkGetNetworkIdFromEntity(towTruck), NetworkGetNetworkIdFromEntity(target))
    if not ok then return notify(message or 'Tow could not begin.', 'error') end
    NetworkRequestControlOfEntity(target)
    local deadline = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(target) and GetGameTimer() < deadline do Wait(0); NetworkRequestControlOfEntity(target) end
    AttachVehicleToTowTruck(towTruck, target, false, 0.0, 0.0, 0.0)
    TowTruck, TowTarget = towTruck, target
    if KioskLocations[1] then SetNewWaypoint(KioskLocations[1].x + 0.0, KioskLocations[1].y + 0.0) end
    notify('Vehicle attached. Drive it to the impound drop-off.', 'success')
end, false)

RegisterCommand('policeimpound', function()
    if not TowTarget or not DoesEntityExist(TowTarget) then return notify('Bring a hooked vehicle into an authorized impound drop-off first.', 'error') end
    local target, truck = TowTarget, TowTruck
    local netId = NetworkGetNetworkIdFromEntity(target)
    PolicePlayImpoundArrival(truck, target)
    local ok, message, summary = lib.callback.await('cm-police:server:impoundVehicle', false, netId)
    if ok then
        TowTarget, TowTruck = nil, nil
        PolicePlayImpoundCompletion(truck, summary)
    else PoliceCancelCinematic() end
    notify(message or (ok and 'Done.' or 'Impound failed.'), ok and 'success' or 'error')
end, false)

-- Shared between /impoundlot and every Impound Operator NPC. The server
-- rejects release unless the owner is physically near any configured operator.
local function openImpoundMenu()
    local vehicles = lib.callback.await('cm-police:server:listImpoundedVehicles', false)
    if not vehicles or #vehicles == 0 then return notify('You have no impounded vehicles.', 'inform') end
    impoundReleaseOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'impoundRelease:open', vehicles = vehicles })
end

RegisterNetEvent('cm-law:client:openImpoundRelease', openImpoundMenu)
RegisterNetEvent('cm-police:client:openImpoundRelease', openImpoundMenu)

local function closeImpoundRelease()
    if not impoundReleaseOpen then return end
    impoundReleaseOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'impoundRelease:close' })
end

RegisterNUICallback('closeImpoundRelease', function(_, cb)
    closeImpoundRelease()
    cb({ ok = true })
end)

RegisterNUICallback('payImpoundRelease', function(data, cb)
    local vehicleId = tonumber(data.vehicleId)
    local vehicles = lib.callback.await('cm-police:server:listImpoundedVehicles', false) or {}
    local selected
    for _, vehicle in ipairs(vehicles) do
        if tonumber(vehicle.vehicleId) == vehicleId then selected = vehicle break end
    end
    if not selected then
        notify('That impound record is no longer available.', 'error')
        return cb({ ok = false })
    end
    local confirmed = PoliceConfirm('Release Impounded Vehicle', ('Pay $%d from your bank to release %s?'):format(selected.fee, selected.plate), 'Pay & Release', 'Cancel')
    if impoundReleaseOpen then SetNuiFocus(true, true) end
    if not confirmed then
        return cb({ ok = false })
    end
    local ok, message = lib.callback.await('cm-police:server:payImpound', false, vehicleId)
    notify(message or (ok and 'Vehicle released.' or 'Payment failed.'), ok and 'success' or 'error')
    if ok then
        vehicles = lib.callback.await('cm-police:server:listImpoundedVehicles', false) or {}
        if #vehicles == 0 then closeImpoundRelease()
        else SendNUIMessage({ action = 'impoundRelease:open', vehicles = vehicles }) end
    end
    cb({ ok = ok == true })
end)

RegisterCommand('impoundlot', function() openImpoundMenu() end, false)

-- Public Impound Operators: empty until an admin adds one, fetched once at
-- resource start and pushed live
-- on change -- every player needs this, not just Police, so it can't ride
-- inside the F7 dashboard payload the way the holding cell does.
local function refreshOperators()
    for _, ped in pairs(OperatorPeds) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    for _, blip in pairs(OperatorBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    OperatorPeds, OperatorBlips = {}, {}
    local model = GetHashKey(Config.Impound.OperatorModel or 's_m_y_cop_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(50) end
    for index, location in ipairs(KioskLocations) do
        if HasModelLoaded(model) and not location.organizationId then
            local ped = CreatePed(4, model, location.x, location.y, location.z - 1.0, location.heading or 0.0, false, true)
            if ped ~= 0 then
                FreezeEntityPosition(ped, true); SetEntityInvincible(ped, true); SetBlockingOfNonTemporaryEvents(ped, true)
                OperatorPeds[index] = ped
            end
        end
        local blip = AddBlipForCoord(location.x, location.y, location.z)
        SetBlipSprite(blip, Config.Impound.KioskBlipSprite or 68); SetBlipColour(blip, Config.Impound.KioskBlipColour or 5); SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName('Impound Operator'); EndTextCommandSetBlipName(blip)
        OperatorBlips[index] = blip
    end
    SetModelAsNoLongerNeeded(model)
end

RegisterNetEvent('cm-police:client:impoundKioskUpdated', function(locations)
    KioskLocations = type(locations) == 'table' and locations or {}
    refreshOperators()
end)

CreateThread(function()
    KioskLocations = lib.callback.await('cm-police:server:impoundKioskLocation', false) or {}
    refreshOperators()
end)

CreateThread(function()
    while true do
        Wait(30000)
        local nextLocations = lib.callback.await('cm-police:server:impoundKioskLocation', false) or {}
        if json.encode(nextLocations) ~= json.encode(KioskLocations) then
            KioskLocations = nextLocations
            refreshOperators()
        end
    end
end)

CreateThread(function()
    while true do
        local wait = 1000
        if not TowTarget and #KioskLocations > 0 then
            local ped = PlayerPedId()
            local towTruck = GetVehiclePedIsIn(ped, false)
            if towTruck ~= 0 and GetPedInVehicleSeat(towTruck, -1) == ped and configuredTowTruck(towTruck)
                and nearOperator(towTruck, Config.Impound.DropoffRadius or 18.0) then
                local target = hookedTowTarget(towTruck)
                if target then
                    local ok, message = lib.callback.await('cm-police:server:beginTow', false,
                        NetworkGetNetworkIdFromEntity(towTruck), NetworkGetNetworkIdFromEntity(target))
                    if ok then
                        TowTruck, TowTarget = towTruck, target
                        notify('Hooked vehicle verified. Press E to impound it.', 'success')
                    elseif message then notify(message, 'error') end
                end
            end
        end
        if TowTarget and DoesEntityExist(TowTarget) and #KioskLocations > 0 then
            if nearOperator(TowTarget, Config.Impound.DropoffRadius or 18.0) then
                wait = 0
                PoliceShowHint('[E] Deliver to Police Impound')
                if IsControlJustPressed(0, Config.Impound.KioskInteractKey or 38) then
                    ExecuteCommand('policeimpound')
                end
            else PoliceHideHint() end
        elseif TowTarget then
            TowTarget, TowTruck = nil, nil
            PoliceHideHint()
        end
        Wait(wait)
    end
end)

CreateThread(function()
    local promptIndex
    while true do
        local wait = 1000
        if #KioskLocations > 0 and not IsPedInAnyVehicle(PlayerPedId(), false) then
            local coords = GetEntityCoords(PlayerPedId())
            local nearest, nearestDistance
            for index, location in ipairs(KioskLocations) do
                local distance = #(coords - vector3(location.x, location.y, location.z))
                if not nearestDistance or distance < nearestDistance then nearest, nearestDistance = index, distance end
            end
            if nearest and nearestDistance <= (Config.Impound.OperatorDrawDistance or 7.0) then
                wait = 0; local location, ped = KioskLocations[nearest], OperatorPeds[nearest]
                PoliceDrawNpcName(location, Config.Impound.OperatorName or 'Officer Martinez')
                if nearestDistance <= (Config.Impound.KioskRadius or 2.5) then
                    if promptIndex ~= nearest then
                        if promptIndex then PoliceHideNpcInteraction('impound_operator') end
                        PoliceShowNpcInteraction('impound_operator', Config.Impound.OperatorName or 'Officer Martinez', Config.Impound.OperatorRole or 'Impound Operator', 'car')
                        promptIndex = nearest
                    end
                    if IsControlJustPressed(0, Config.Impound.KioskInteractKey or 38) and ped and DoesEntityExist(ped) then
                        PoliceHideNpcInteraction('impound_operator'); promptIndex = nil
                        PoliceOpenNpcDialogue(ped, { owner = 'impound_operator', name = Config.Impound.OperatorName,
                            role = Config.Impound.OperatorRole, quote = 'I can help you review and release vehicles currently held in Police impound.',
                            continueLabel = 'Show my impounded vehicles' }, openImpoundMenu)
                    end
                elseif promptIndex then PoliceHideNpcInteraction('impound_operator'); promptIndex = nil end
            elseif promptIndex then PoliceHideNpcInteraction('impound_operator'); promptIndex = nil
            end
        elseif promptIndex then PoliceHideNpcInteraction('impound_operator'); promptIndex = nil
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, ped in pairs(OperatorPeds) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    for _, blip in pairs(OperatorBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    if impoundReleaseOpen then SetNuiFocus(false, false) end
end)
