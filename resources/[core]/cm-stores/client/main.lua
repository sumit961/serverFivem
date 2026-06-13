local Config = CMStores.Config
local spawnedPeds = {}
local currentStore = nil
local nuiOpen = false
local buyRequestId = 0
local pendingBuy = {}

local function dprint(...)
    if not Config.Debug then return end
    print('[CM-STORES-CLIENT]', ...)
end

local function drawText3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    SetTextScale(0.34, 0.34)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 225)
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)

    local factor = string.len(text) / 370
    DrawRect(x, y + 0.0125, 0.02 + factor, 0.03, 0, 0, 0, 120)
end

local function sendNui(action, payload)
    payload = payload or {}
    payload.action = action
    SendNUIMessage(payload)
end

local function closeStore()
    nuiOpen = false
    currentStore = nil
    SetNuiFocus(false, false)
    sendNui('close')
end

local function openStore(store)
    if nuiOpen then return end
    currentStore = store
    nuiOpen = true
    SetNuiFocus(true, true)
    sendNui('loading', { visible = true })
    TriggerServerEvent('cm-stores:server:requestStore', store.id)
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function spawnStorePeds()
    local pedHash = loadModel(Config.Ped.model)
    if not pedHash then
        print('[CM-STORES] Failed to load ped model:', Config.Ped.model)
        return
    end

    for _, store in ipairs(Config.Stores) do
        local c = store.coords
        local ped = CreatePed(0, pedHash, c.x, c.y, c.z - 1.0, c.w, false, false)
        if DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, Config.Ped.blockEvents)
            SetEntityInvincible(ped, Config.Ped.invincible)
            FreezeEntityPosition(ped, Config.Ped.freeze)
            if Config.Ped.scenario and Config.Ped.scenario ~= '' then
                TaskStartScenarioInPlace(ped, Config.Ped.scenario, 0, true)
            end
            spawnedPeds[#spawnedPeds + 1] = ped
        end

        if Config.Blip.enabled then
            local blip = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipColour(blip, Config.Blip.color)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(Config.Blip.name)
            EndTextCommandSetBlipName(blip)
        end
    end

    SetModelAsNoLongerNeeded(pedHash)
end

CreateThread(function()
    Wait(1200)
    spawnStorePeds()
end)

CreateThread(function()
    while true do
        local sleep = 750
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)

        for _, store in ipairs(Config.Stores) do
            local c = vector3(store.coords.x, store.coords.y, store.coords.z)
            local dist = #(playerCoords - c)

            if dist <= Config.DrawTextDistance then
                sleep = 0
                drawText3D(vector3(c.x, c.y, c.z + 1.1), ('~b~%s~s~\n%s'):format(store.npcName or 'Store Clerk', store.name))
            end

            if dist <= Config.InteractionDistance then
                sleep = 0
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(('Press ~INPUT_CONTEXT~ to open %s'):format(store.name))
                EndTextCommandDisplayHelp(0, false, true, -1)

                if IsControlJustReleased(0, Config.InteractionKey) then
                    openStore(store)
                end
            end
        end

        Wait(sleep)
    end
end)

RegisterNetEvent('cm-stores:client:storeData', function(storeData)
    if not nuiOpen then return end
    sendNui('open', {
        store = storeData,
        title = Config.StoreTitle,
        subtitle = Config.StoreSubtitle
    })
end)

RegisterNetEvent('cm-stores:client:buyResult', function(requestId, ok, message, extra)
    if pendingBuy[requestId] then
        pendingBuy[requestId] = nil
    end
    sendNui('buyResult', {
        ok = ok,
        message = message or (ok and 'Purchased.' or 'Purchase failed.'),
        extra = extra or {}
    })
end)

RegisterNUICallback('close', function(_, cb)
    closeStore()
    cb({ ok = true })
end)

RegisterNUICallback('buyItem', function(data, cb)
    if not currentStore then
        cb({ ok = false, message = 'No store open.' })
        return
    end

    buyRequestId = buyRequestId + 1
    pendingBuy[buyRequestId] = true

    local itemName = tostring(data.itemName or '')
    local amount = tonumber(data.amount) or 1

    TriggerServerEvent('cm-stores:server:buyItem', buyRequestId, currentStore.id, itemName, amount)
    cb({ ok = true })
end)

RegisterCommand('closestore', function()
    if nuiOpen then closeStore() end
end, false)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if nuiOpen then closeStore() end
    for _, ped in ipairs(spawnedPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
end)
