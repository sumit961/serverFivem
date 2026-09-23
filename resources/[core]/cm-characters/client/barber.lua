-- cm-characters/client/barber.lua
-- Barber Shop world interaction, clerk/stylist NPC, map blips, cm-ui dialogue, grooming bridge, and salon commercial ownership

local barberBlips = {}
local barberPeds = {} -- [shopIndex] = ped
local isInteractShowing = false
local isBarberDialogueOpen = false
local isBarberOwnerPanelOpen = false
local isBarberBuyInfoOpen = false
local cachedBarberDetails = {}
local lastRequestTime = {}

local function findBarberShopConfig(shopId)
    for _, shop in ipairs(Config.BarberShops or {}) do
        if tostring(shop.id) == tostring(shopId) then return shop end
    end
    return nil
end

local function createBarberBlips()
    for _, b in ipairs(barberBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    barberBlips = {}

    for _, shop in ipairs(Config.BarberShops or {}) do
        if shop.coords then
            local blip = AddBlipForCoord(shop.coords.x, shop.coords.y, shop.coords.z)
            SetBlipSprite(blip, shop.blip or 71)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, 0.7)
            -- 18 is light ice-blue/cyan in GTA V blip palette, aligning with CM theme
            SetBlipColour(blip, 18)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(shop.name or "Barber Shop")
            EndTextCommandSetBlipName(blip)
            table.insert(barberBlips, blip)
        end
    end
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - t > 4000 then return false end
        Wait(0)
    end
    return true
end

local function spawnBarberNpc(index, shop)
    local modelHash = joaat('s_m_m_hairdress_01')
    if not loadModel(modelHash) then return nil end

    local c = shop.coords
    local npc = CreatePed(4, modelHash, c.x, c.y, c.z - 0.98, shop.heading or 0.0, false, false)
    SetModelAsNoLongerNeeded(modelHash)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetPedCanRagdoll(npc, false)
    SetPedFleeAttributes(npc, 0, false)
    SetPedCanBeTargetted(npc, false)
    FreezeEntityPosition(npc, true)
    TaskStartScenarioInPlace(npc, 'WORLD_HUMAN_STAND_IMPARTIAL', 0, true)
    return npc
end

local function deleteBarberNpc(index)
    local npc = barberPeds[index]
    if npc and DoesEntityExist(npc) then DeleteEntity(npc) end
    barberPeds[index] = nil
end

local function hideBarberInteract()
    if isInteractShowing then
        isInteractShowing = false
        pcall(function() exports['cm-ui']:HideInteract() end)
    end
end

local function formatNumber(n)
    local formatted = tostring(math.floor(tonumber(n) or 0))
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

local function requestBarberShopDetails(shopId)
    if not shopId then return end
    local now = GetGameTimer()
    if lastRequestTime[shopId] and (now - lastRequestTime[shopId] < 4000) then
        return
    end
    lastRequestTime[shopId] = now
    TriggerServerEvent('cm-characters:server:getBarberShopDetails', shopId)
end

RegisterNetEvent('cm-characters:client:barberShopDetailsResult', function(payload)
    if payload and payload.shopId then
        cachedBarberDetails[payload.shopId] = payload
        if isBarberOwnerPanelOpen then
            SendNUIMessage({
                type = 'updateBarberOwner',
                data = payload
            })
        end
    end
end)

local function getBarberShopDetails(shopId)
    if not shopId then return nil end
    requestBarberShopDetails(shopId)
    return cachedBarberDetails[shopId]
end

exports('GetBarberShopDetails', getBarberShopDetails)

RegisterNetEvent('cm-characters:client:barberDialogueClosed', function()
    isBarberDialogueOpen = false
end)

-- Client event triggered by cm-ui dialogue selection
RegisterNetEvent('cm-characters:client:barberStartStyling', function(payload)
    isBarberDialogueOpen = false
    CreateThread(function()
        -- Wait for cm-ui dialogue camera and NUI focus teardown (350ms) to complete
        Wait(380)

        local ped = PlayerPedId()
        local state = LocalPlayer and LocalPlayer.state
        local cuffed = state and (state.isDead or state.cmCuffed or state.cuffed or state.isCuffed or state.handcuffed)

        if cuffed or GetEntityHealth(ped) <= 100 then
            TriggerEvent('cm-hud:client:notify', 'You cannot use the barber right now.', 'error')
            return
        end

        local cost = 100
        local shop = payload and payload.shop
        local shopId = shop and shop.id
        if shop and shop.id then
            local details = cachedBarberDetails[shop.id]
            if details and details.serviceCost then
                cost = tonumber(details.serviceCost) or 100
            end
        else
            local pCoords = GetEntityCoords(ped)
            for _, s in ipairs(Config.BarberShops or {}) do
                if s.coords and #(pCoords - s.coords) < 10.0 then
                    shopId = s.id
                    local details = cachedBarberDetails[s.id]
                    if details and details.serviceCost then
                        cost = tonumber(details.serviceCost) or 100
                    end
                    break
                end
            end
        end

        if shopId then
            TriggerServerEvent('cm-characters:server:barberSessionStart', shopId)
        end

        TriggerEvent('cm-characters:client:openAppearanceService', { service = 'barber', cost = cost })
    end)
end)

RegisterNetEvent('cm-characters:client:barberDialogueBuy', function(payload)
    isBarberDialogueOpen = false
    local shopId = payload and payload.shopId
    if not shopId then return end

    requestBarberShopDetails(shopId)
    local shopCfg = findBarberShopConfig(shopId)
    local details = cachedBarberDetails[shopId] or {}

    isBarberBuyInfoOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = 'openBarberBuyInfo',
        data = {
            shopId = shopId,
            shopName = (shopCfg and shopCfg.name) or 'Hair Salon',
            ownerName = details.ownerName or 'City Commercial Property',
            priceTier = details.priceTier or 'normal',
            priceMultiplier = details.priceMultiplier or 1.0,
            stock = details.stock or (Config.BarberOwnership and Config.BarberOwnership.defaultStock) or 1000,
            isOwned = details.isOwned == true,
            purchasePrice = details.purchasePrice or (Config.BarberOwnership and Config.BarberOwnership.purchasePrice) or 200000,
        }
    })
end)

RegisterNUICallback('closeBarberBuyInfo', function(data, cb)
    isBarberBuyInfoOpen = false
    SetNuiFocus(false, false)
    if cb then cb({ ok = true }) end
end)

RegisterNetEvent('cm-characters:client:barberDialogueManage', function(payload)
    isBarberDialogueOpen = false
    local shopId = payload and payload.shopId
    if not shopId then return end
    requestBarberShopDetails(shopId)
    local details = cachedBarberDetails[shopId] or {
        shopId = shopId,
        isOwner = true,
        isOwned = true,
        serviceCost = 100,
        stock = 1000,
        businessBalance = 0,
        taxDue = 0,
        taxPaidDays = 7,
        ownerName = 'Owner'
    }
    isBarberOwnerPanelOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = 'openBarberOwner',
        data = details
    })
end)

RegisterNetEvent('cm-characters:client:barberShopUpdated', function(shopId)
    requestBarberShopDetails(shopId)
end)

RegisterNetEvent('cm-characters:client:barberShopPurchased', function(shopId)
    requestBarberShopDetails(shopId)
end)

-- NUI Callbacks for Barber Owner Console
RegisterNUICallback('closeBarberOwner', function(data, cb)
    isBarberOwnerPanelOpen = false
    SetNuiFocus(false, false)
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('manageBarberShop', function(data, cb)
    TriggerServerEvent('cm-characters:server:manageBarberShop', data)
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('payBarberShopTax', function(data, cb)
    TriggerServerEvent('cm-characters:server:payBarberShopTax', data and data.shopId)
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('withdrawBarberBalance', function(data, cb)
    TriggerServerEvent('cm-characters:server:withdrawBarberBalance', data and data.shopId)
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('buyBarberShop', function(data, cb)
    TriggerServerEvent('cm-characters:server:buyBarberShop', data and data.shopId)
    if cb then cb({ ok = true }) end
end)

-- Main loop: blips, streaming barber peds, cm-ui [E] interaction, and dialogue
CreateThread(function()
    createBarberBlips()

    while true do
        local sleep = 1000
        local ped = PlayerPedId()

        if isBarberOwnerPanelOpen or isBarberBuyInfoOpen then
            hideBarberInteract()
            sleep = 250
            if IsEntityDead(ped) then
                if isBarberOwnerPanelOpen then
                    isBarberOwnerPanelOpen = false
                    SendNUIMessage({ type = 'closeBarberOwner' })
                end
                if isBarberBuyInfoOpen then
                    isBarberBuyInfoOpen = false
                    SendNUIMessage({ type = 'closeBarberBuyInfo' })
                end
                SetNuiFocus(false, false)
            end
        elseif ped and ped ~= 0 and not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false) then
            local pCoords = GetEntityCoords(ped)
            local closestShop = nil
            local closestIndex = nil
            local closestDist = 999.0

            for i, shop in ipairs(Config.BarberShops or {}) do
                if shop.coords then
                    local dist = #(pCoords - shop.coords)
                    if dist < (Config.BarberNpcDistance or 45.0) then
                        if not barberPeds[i] or not DoesEntityExist(barberPeds[i]) then
                            barberPeds[i] = spawnBarberNpc(i, shop)
                        end
                    elseif barberPeds[i] then
                        deleteBarberNpc(i)
                    end

                    if dist < closestDist then
                        closestDist = dist
                        closestShop = shop
                        closestIndex = i
                    end
                end
            end

            if closestDist < 15.0 and closestShop then
                requestBarberShopDetails(closestShop.id)
            end

            if closestDist < 10.0 and closestShop then
                sleep = 0
                local npc = barberPeds[closestIndex]

                -- Barber turns head to acknowledge customer
                if npc and DoesEntityExist(npc) and closestDist < 3.5 then
                    if not IsPedHeadtrackingPed(npc, ped) then
                        TaskLookAtEntity(npc, ped, 2500, 2048, 3)
                    end
                end

                if not isBarberDialogueOpen and not isBarberOwnerPanelOpen and not isBarberBuyInfoOpen then
                    if closestDist <= 2.6 then
                        if not isInteractShowing then
                            isInteractShowing = true
                            pcall(function()
                                exports['cm-ui']:ShowInteract({
                                    key = 'E',
                                    label = 'TALK TO BARBER',
                                    name = closestShop.name or 'Barber Shop',
                                    role = 'HAIR & GROOMING'
                                })
                            end)
                        end

                        if IsControlJustReleased(0, 38) then -- INPUT_CONTEXT (E)
                            hideBarberInteract()

                            local state = LocalPlayer and LocalPlayer.state
                            local cuffed = state and (state.isDead or state.cmCuffed or state.cuffed or state.isCuffed or state.handcuffed)

                            if cuffed or GetEntityHealth(ped) <= 100 then
                                TriggerEvent('cm-hud:client:notify', 'You cannot use the barber right now.', 'error')
                            else
                                local shopId = closestShop.id or tostring(closestShop.name)
                                local details = cachedBarberDetails[shopId]
                                local isOwner = details and details.isOwner == true
                                local isOwned = details and details.isOwned == true
                                local cost = details and details.serviceCost or tonumber(Config.BarberCost or 100) or 100
                                local stock = details and details.stock or 1000
                                local ownerName = details and details.ownerName or 'City Commercial Property'
                                local balance = details and details.businessBalance or 0

                                local quote = 'Welcome! Looking for a fresh haircut, beard trim, or sharp new style today?'
                                if isOwner then
                                    quote = ('Welcome back, boss! Salon balance: $%s | Grooming supplies: %d units. What are we working on today?'):format(formatNumber(balance), stock)
                                elseif isOwned then
                                    quote = ('Welcome to %s! Operated by %s. Grooming supplies: %d units. Ready for a sharp new style?'):format(closestShop.name or 'our salon', ownerName, stock)
                                else
                                    quote = ('Welcome to %s! This commercial salon is operated by the city and available for purchase ($200,000).'):format(closestShop.name or 'our salon')
                                end

                                local choices = {
                                    {
                                        id = 'styling',
                                        label = 'Haircuts & Grooming',
                                        description = ('Change hair, beard, eyebrows, and styling ($%s). Supplies: %d units.'):format(cost, stock),
                                        event = 'cm-characters:client:barberStartStyling',
                                        payload = { shop = closestShop }
                                    }
                                }

                                if isOwner then
                                    choices[#choices + 1] = {
                                        id = 'manage',
                                        label = 'Manage Salon (Owner Console)',
                                        description = 'Adjust price tiers, order grooming supplies, pay property tax, and withdraw business revenue.',
                                        event = 'cm-characters:client:barberDialogueManage',
                                        payload = { shopId = shopId }
                                    }
                                elseif not isOwned then
                                    choices[#choices + 1] = {
                                        id = 'buy',
                                        label = 'Purchase Hair Salon ($200,000)',
                                        description = 'Acquire this commercial property. Earn 80% revenue from all customer grooming services.',
                                        event = 'cm-characters:client:barberDialogueBuy',
                                        payload = { shopId = shopId }
                                    }
                                end

                                isBarberDialogueOpen = true
                                local opened = false
                                if npc and DoesEntityExist(npc) and GetResourceState('cm-ui') == 'started' then
                                    pcall(function()
                                        opened = exports['cm-ui']:OpenNpcDialogue(npc, {
                                            name = closestShop.name or 'Master Barber',
                                            role = isOwner and 'SALON OWNER SERVICES' or 'BARBER & STYLIST',
                                            quote = quote,
                                            serviceLabel = 'Salon Services',
                                            choices = choices,
                                            closeEvent = 'cm-characters:client:barberDialogueClosed'
                                        })
                                    end)
                                end

                                if not opened then
                                    isBarberDialogueOpen = false
                                    TriggerEvent('cm-characters:client:barberStartStyling', { shop = closestShop })
                                end
                            end
                            Wait(400)
                        end
                    elseif closestDist > 3.2 then
                        hideBarberInteract()
                    end
                else
                    hideBarberInteract()
                end
            else
                hideBarberInteract()
            end
        else
            hideBarberInteract()
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    hideBarberInteract()
    if isBarberOwnerPanelOpen or isBarberBuyInfoOpen then
        SetNuiFocus(false, false)
    end
    for _, b in ipairs(barberBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    barberBlips = {}
    for i in pairs(barberPeds) do
        deleteBarberNpc(i)
    end
end)
