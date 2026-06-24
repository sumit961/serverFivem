local Stores = {}
local Points = {}
local Peds = {}
local Blips = {}
local CurrentStoreId = nil
local NuiOpen = false

local function debugPrint(...)
    if CMStoreBase.Config.Debug then print('^3[cm-storebase]^7', ...) end
end

local function toVec3(coords)
    if type(coords) == 'vector3' then return coords end
    if type(coords) == 'vector4' then return vec3(coords.x, coords.y, coords.z) end
    return vec3(coords.x or coords[1] or 0.0, coords.y or coords[2] or 0.0, coords.z or coords[3] or 0.0)
end

local function headingFromCoords(coords)
    if type(coords) == 'vector4' then return coords.w or 0.0 end
    return coords.w or coords.h or coords.heading or coords[4] or 0.0
end

local function requestModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        Wait(10)
        if GetGameTimer() > timeout then return nil end
    end
    return hash
end

local function removePed(storeId)
    if Peds[storeId] and DoesEntityExist(Peds[storeId]) then DeleteEntity(Peds[storeId]) end
    Peds[storeId] = nil
end

local function createPed(storeId, store)
    removePed(storeId)
    local pedData = store.ped
    if not pedData or pedData.enabled == false then return end

    local coords = store.coords
    local hash = requestModel(pedData.model or 'mp_m_shopkeep_01')
    if not hash then return end

    local pos = toVec3(coords)
    local heading = pedData.heading or headingFromCoords(coords)
    local ped = CreatePed(0, hash, pos.x, pos.y, pos.z - 1.0, heading, false, true)

    if pedData.freeze ~= false then FreezeEntityPosition(ped, true) end
    if pedData.invincible ~= false then SetEntityInvincible(ped, true) end
    if pedData.blockEvents ~= false then SetBlockingOfNonTemporaryEvents(ped, true) end
    if pedData.scenario then TaskStartScenarioInPlace(ped, pedData.scenario, 0, true) end

    Peds[storeId] = ped
    SetModelAsNoLongerNeeded(hash)
end

local function removeBlip(storeId)
    if Blips[storeId] then RemoveBlip(Blips[storeId]) end
    Blips[storeId] = nil
end

local function createBlip(storeId, store)
    removeBlip(storeId)
    local blipData = store.blip
    if not blipData or blipData.enabled == false then return end

    local coords = toVec3(store.coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, blipData.sprite or 52)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, blipData.scale or 0.75)
    SetBlipColour(blip, blipData.color or 2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipData.label or store.name or 'Store')
    EndTextCommandSetBlipName(blip)
    Blips[storeId] = blip
end

local function closeStore()
    NuiOpen = false
    CurrentStoreId = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openStore(storeId)
    local response = lib.callback.await('cm-storebase:server:getStoreData', false, storeId)
    if not response or not response.success then
        lib.notify({ type = 'error', description = response and response.error or 'Could not open store' })
        return
    end

    CurrentStoreId = storeId
    NuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', store = response.store })
end

local function removePoint(storeId)
    if Points[storeId] then Points[storeId]:remove() end
    Points[storeId] = nil
end

local function createPoint(storeId, store)
    removePoint(storeId)
    local coords = toVec3(store.coords)
    local distance = tonumber(store.drawDistance or CMStoreBase.Config.DefaultDrawDistance) or 12.0

    Points[storeId] = lib.points.new({
        coords = coords,
        distance = distance,
        storeId = storeId,
        nearby = function(point)
            local openDistance = tonumber(store.pointDistance or store.radius or CMStoreBase.Config.DefaultPointDistance) or 2.0
            if point.currentDistance <= openDistance then
                lib.showTextUI(('[E] Open %s'):format(store.name or 'Store'))
                if IsControlJustReleased(0, CMStoreBase.Config.OpenKey) and not NuiOpen then
                    openStore(point.storeId)
                end
            else
                lib.hideTextUI()
            end
        end,
        onExit = function() lib.hideTextUI() end
    })
end

local function removeStoreObjects(storeId)
    removePoint(storeId)
    removePed(storeId)
    removeBlip(storeId)
end

local function createStoreObjects(storeId, store)
    createPoint(storeId, store)
    createPed(storeId, store)
    createBlip(storeId, store)
end

local function upsertStore(storeId, store)
    Stores[storeId] = store
    removeStoreObjects(storeId)
    createStoreObjects(storeId, store)
    debugPrint(('synced %s'):format(storeId))
end

RegisterNetEvent('cm-storebase:client:setStores', function(stores)
    for storeId in pairs(Stores) do removeStoreObjects(storeId) end
    Stores = stores or {}
    for storeId, store in pairs(Stores) do createStoreObjects(storeId, store) end
end)

RegisterNetEvent('cm-storebase:client:updateStore', function(storeId, store)
    upsertStore(storeId, store)
    if NuiOpen and CurrentStoreId == storeId then SendNUIMessage({ action = 'refresh', store = store }) end
end)

RegisterNetEvent('cm-storebase:client:removeStore', function(storeId)
    Stores[storeId] = nil
    removeStoreObjects(storeId)
    if NuiOpen and CurrentStoreId == storeId then closeStore() end
end)

RegisterNetEvent('cm-storebase:client:requestFullSync', function()
    TriggerServerEvent('cm-storebase:server:requestFullSync')
end)

RegisterNUICallback('close', function(_, cb)
    closeStore()
    cb({ success = true })
end)

RegisterNUICallback('buyItem', function(data, cb)
    if not CurrentStoreId then cb({ success = false, error = 'No store open' }) return end

    local itemName = data and data.itemName
    local quantity = tonumber(data and data.quantity or 1) or 1
    local response = lib.callback.await('cm-storebase:server:purchaseItem', false, CurrentStoreId, itemName, quantity)

    if response and response.success then
        lib.notify({ type = 'success', description = response.message or 'Purchase successful' })
        if response.store then
            Stores[CurrentStoreId] = response.store
            SendNUIMessage({ action = 'refresh', store = response.store })
        end
    else
        lib.notify({ type = 'error', description = response and response.error or 'Purchase failed' })
    end

    cb(response or { success = false })
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('cm-storebase:server:requestFullSync')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    lib.hideTextUI()
    SetNuiFocus(false, false)
    for storeId in pairs(Stores) do removeStoreObjects(storeId) end
end)
