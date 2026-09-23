-- nv_cloth/client/cl_stores.lua
-- Clerk NPC behind each counter, [E] interaction at the counter,
-- and per-store dressing position (no more shared teleport spot).

local clerks = {}        -- [shopId] = ped
local session = nil      -- { shop, returnHeading }
local pending = nil

local function shopReady(shop)
    return shop and shop.id and shop.clerk and shop.clerk.model and shop.clerk.coords
        and shop.interact and shop.dressing
        and (shop.interact.x ~= 0.0 or shop.interact.y ~= 0.0)
end

CreateThread(function()
    if type(Config.Shops) ~= 'table' then return end
    for _, shop in ipairs(Config.Shops) do
        if not shopReady(shop) then
            print(('^3[nv_cloth] shop "%s" is missing id/clerk/interact/dressing - skipped until configured via /clothdev^0')
                :format(shop.id or shop.label or '?'))
        end
    end
end)

---------------------------------------------------------------- clerks
local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - t > 5000 then return false end
        Wait(0)
    end
    return true
end

local function spawnClerk(shop)
    local c = shop.clerk
    local hash = type(c.model) == 'number' and c.model or joaat(c.model)
    if not loadModel(hash) then return nil end
    local p = c.coords
    local npc = CreatePed(4, hash, p.x, p.y, p.z, p.w, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetPedCanRagdoll(npc, false)
    SetPedFleeAttributes(npc, 0, false)
    SetPedCanBeTargetted(npc, false)
    SetEntityHeading(npc, p.w)
    FreezeEntityPosition(npc, true)
    if c.scenario then TaskStartScenarioInPlace(npc, c.scenario, 0, true) end
    return npc
end

local function deleteClerk(id)
    local npc = clerks[id]
    if npc and DoesEntityExist(npc) then DeleteEntity(npc) end
    clerks[id] = nil
end

CreateThread(function()
    while true do
        local me = PlayerPedId()
        local pos = GetEntityCoords(me)
        if type(Config.Shops) == 'table' then
            for _, shop in ipairs(Config.Shops) do
                if shopReady(shop) then
                    local near = #(pos - shop.clerk.coords.xyz) < (Config.ClerkSpawnDistance or 60.0)
                    local npc = clerks[shop.id]
                    if npc and not DoesEntityExist(npc) then clerks[shop.id], npc = nil, nil end

                    if near and not npc then
                        clerks[shop.id] = spawnClerk(shop)
                    elseif not near and npc then
                        deleteClerk(shop.id)
                    elseif npc then
                        -- clerk looks at the customer when they walk up
                        local close = #(pos - shop.interact) < 4.0
                        if close and not IsPedHeadtrackingPed(npc, me) then
                            TaskLookAtEntity(npc, me, 3000, 2048, 3)
                        end
                    end
                end
            end
        end
        Wait(1000)
    end
end)

---------------------------------------------------------------- helpers
local function fadeOut()
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end
end

local function teleport(ent, c, heading)
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetEntityCoordsNoOffset(ent, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(ent, heading)
    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ent) and GetGameTimer() - t < 2000 do Wait(0) end
end

local function nearestShop(pos)
    if type(Config.Shops) ~= 'table' then return nil end
    for _, shop in ipairs(Config.Shops) do
        if shopReady(shop) and #(pos - shop.interact) <= (Config.InteractDistance or 1.6) then
            return shop
        end
    end
    return nil
end

---------------------------------------------------------------- open / close
RegisterNetEvent('nv_cloth:client:enterStoreResult', function(ok, reason)
    if pending and not pending.done then
        pending.done = true
        pending.p:resolve({ ok = ok, reason = reason })
    end
end)

local function requestEnter(shopId)
    local req = { p = promise.new(), done = false }
    pending = req
    TriggerServerEvent('nv_cloth:server:enterStore', shopId)
    SetTimeout(5000, function()
        if not req.done then req.done = true; req.p:resolve({ ok = false, reason = 'timeout' }) end
    end)
    local res = Citizen.Await(req.p)
    pending = nil
    return res
end

function OpenStore(shop)
    if session or pending then return end
    local me = PlayerPedId()
    if IsPedInAnyVehicle(me, false) or IsEntityDead(me) then return end

    local res = requestEnter(shop.id)
    if not res or not res.ok then
        local msg = 'Unable to enter store.'
        if res and res.reason == 'too_far' then msg = 'You are too far from the counter.'
        elseif res and res.reason == 'cuffed' then msg = 'You cannot shop while restrained.'
        elseif res and res.reason == 'escorted' then msg = 'You cannot shop while being escorted.'
        elseif res and res.reason == 'combat' then msg = 'You cannot shop while in combat.'
        elseif res and res.reason == 'vehicle' then msg = 'You cannot shop from inside a vehicle.'
        elseif res and res.reason == 'dead' then msg = 'You cannot shop right now.' end
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('~r~' .. msg)
        EndTextCommandThefeedPostTicker(false, false)
        return
    end

    local toClerk = shop.clerk.coords.xyz - shop.interact
    session = { shop = shop, returnHeading = GetHeadingFromVector_2d(toClerk.x, toClerk.y) }

    fadeOut()
    ClearPedTasksImmediately(me)
    teleport(me, shop.dressing.xyz, shop.dressing.w)

    -- Let the engine's own collision response settle/depenetrate the ped onto
    -- the floor for a moment before locking them in place. Freezing the
    -- instant we teleport was leaving the ped visibly sunk into the floor
    -- whenever the captured dressing Z was even a few cm off -- the screen
    -- is still faded to black here so the brief settle is never seen.
    Wait(200)

    FreezeEntityPosition(me, true)
    if ClothCam and ClothCam.Start then
        ClothCam.Start(me, 'full')
    end
    Wait(150)
    DoScreenFadeIn(250)

    -- hook into UI open
    TriggerEvent('nv_cloth:client:openUI', shop.id)
end

function CloseStore()
    if not session then return end
    local shop = session.shop
    local me = PlayerPedId()

    fadeOut()
    if ClothCam and ClothCam.Stop then
        ClothCam.Stop()
    end
    FreezeEntityPosition(me, false)
    teleport(me, shop.interact, session.returnHeading)
    session = nil

    TriggerServerEvent('nv_cloth:server:leaveStore')
    -- drop any un-bought preview pieces
    TriggerEvent('cm-inventory:client:forceWearEquippedClothing')

    Wait(150)
    DoScreenFadeIn(250)
end

exports('OpenStore', function(shopId)
    if type(Config.Shops) ~= 'table' then return end
    for _, s in ipairs(Config.Shops) do
        if s.id == shopId and shopReady(s) then return OpenStore(s) end
    end
end)
exports('CloseStore', CloseStore)
exports('GetActiveShop', function() return session and session.shop.id or nil end)
RegisterNetEvent('nv_cloth:client:closeStore', CloseStore) -- server can force-close

-- call this from existing NUI 'close' callback
RegisterNUICallback('closeStore', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
    CloseStore()
end)

---------------------------------------------------------------- dialogue / interaction
RegisterNetEvent('nv_cloth:client:dialogueEnterStore', function(payload)
    local shopId = payload and payload.shopId
    if not shopId then return end
    for _, s in ipairs(Config.Shops or {}) do
        if s.id == shopId and shopReady(s) then
            OpenStore(s)
            return
        end
    end
end)

local isInteractShowing = false

local function hideStoreInteract()
    if isInteractShowing then
        isInteractShowing = false
        pcall(function() exports['cm-ui']:HideInteract() end)
    end
end

CreateThread(function()
    while true do
        local sleep = 500
        local me = PlayerPedId()

        if session then
            hideStoreInteract()
            sleep = 250
            if IsEntityDead(me) then
                SetNuiFocus(false, false)
                CloseStore()
            end
        else
            local shop = nearestShop(GetEntityCoords(me))
            if shop and not IsPedInAnyVehicle(me, false) and not IsEntityDead(me) then
                sleep = 0
                if not isInteractShowing then
                    isInteractShowing = true
                    local clerkName = shop.clerk and shop.clerk.name or shop.label or 'Clothing Store'
                    pcall(function()
                        exports['cm-ui']:ShowInteract({
                            key = 'E',
                            label = 'TALK TO CLERK',
                            name = clerkName,
                            role = 'STORE CLERK'
                        })
                    end)
                end

                if IsControlJustReleased(0, 38) then -- INPUT_CONTEXT (E)
                    hideStoreInteract()
                    local npc = clerks[shop.id]
                    if npc and DoesEntityExist(npc) and GetResourceState('cm-ui') == 'started' then
                        local clerkName = shop.clerk and shop.clerk.name or shop.label or 'Store Clerk'
                        local opened = false
                        pcall(function()
                            opened = exports['cm-ui']:OpenNpcDialogue(npc, {
                                name = clerkName,
                                role = 'CLOTHING STORE',
                                quote = 'Welcome! Looking to update your style or try on something new today?',
                                serviceLabel = 'Store Services',
                                choices = {
                                    {
                                        id = 'browse',
                                        label = 'Browse Clothing Catalog',
                                        description = 'Step into the dressing room and try on pieces from our collection.',
                                        event = 'nv_cloth:client:dialogueEnterStore',
                                        payload = { shopId = shop.id }
                                    }
                                },
                                closeEvent = 'nv_cloth:client:dialogueClosed'
                            })
                        end)
                        if not opened then
                            OpenStore(shop)
                        end
                    else
                        OpenStore(shop)
                    end
                end
            else
                hideStoreInteract()
            end
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------- cleanup
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    hideStoreInteract()
    for id in pairs(clerks) do deleteClerk(id) end
    if session then
        if ClothCam and ClothCam.Stop then ClothCam.Stop() end
        local me = PlayerPedId()
        FreezeEntityPosition(me, false)
        SetEntityCoordsNoOffset(me, session.shop.interact.x, session.shop.interact.y, session.shop.interact.z, false, false, false)
        SetNuiFocus(false, false)
        DoScreenFadeIn(0)
    end
end)
