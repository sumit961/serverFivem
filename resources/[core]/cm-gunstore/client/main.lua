local isOpen = false
local currentMode = 'store'
local shopPeds = {}
local targetIds = {}
local targetRegistered = {}
local targetZones = {}
local activeShop = nil
local interactionVisible = false
local interactionKey = ''
local setOpen
local requestCatalog

math.randomseed(GetGameTimer())

local function dbg(msg)
    if Config.Debug then print(('[cm-gunstore] %s'):format(tostring(msg))) end
end

local function nui(action, payload)
    SendNUIMessage({ action = action, data = payload or {} })
end

local function setScreenInteraction(show, payload)
    payload = payload or {}
    local key = show and ((payload.clerkName or '') .. '|' .. (payload.title or '') .. '|' .. (payload.subtitle or '')) or ''
    if interactionVisible == show and interactionKey == key then return end
    interactionVisible = show == true
    interactionKey = key
    nui('interaction', { show = interactionVisible, clerkName = payload.clerkName, title = payload.title, subtitle = payload.subtitle, key = payload.key or 'E' })
end

local function showHelp(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function drawText3D(coords, lines)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    if type(lines) == 'string' then
        lines = { { text = lines, r = 235, g = 252, b = 255, a = 235 } }
    end

    if type(lines) ~= 'table' or #lines == 0 then return end

    local camCoords = GetGameplayCamCoords()
    local dist = #(camCoords - coords)
    local baseScale = math.max(0.28, math.min(0.46, 0.50 / math.max(dist * 0.24, 1.0)))
    local lineGap = 0.028
    local totalHeight = (#lines - 1) * lineGap
    local startY = y - (totalHeight * 0.5)

    for i, line in ipairs(lines) do
        local text = type(line) == 'table' and tostring(line.text or '') or tostring(line or '')
        if text ~= '' then
            local r = type(line) == 'table' and (line.r or 235) or 235
            local g = type(line) == 'table' and (line.g or 252) or 252
            local b = type(line) == 'table' and (line.b or 255) or 255
            local a = type(line) == 'table' and (line.a or 245) or 245
            local scale = baseScale * (type(line) == 'table' and (line.scale or 1.0) or 1.0)
            local yy = startY + ((i - 1) * lineGap)

            if Config.Ped and Config.Ped.speechBackground ~= false and (type(line) == 'table' and line.box) then
                local width = math.min(0.36, math.max(0.09, (#text * 0.0048) * scale))
                DrawRect(x, yy + 0.012, width, 0.030, 0, 0, 0, 105)
            end

            SetTextScale(scale, scale)
            SetTextFont(4)
            SetTextProportional(1)
            SetTextColour(r, g, b, a)
            SetTextCentre(true)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(text)
            EndTextCommandDisplayText(x, yy)
        end
    end
end

local function getRandomClerkName(index)
    local pedConfig = Config.Ped or {}
    local names = pedConfig.names or {}
    if #names == 0 then return 'Gun Store Clerk' end

    local seed = GetGameTimer() + (index * 971)
    math.randomseed(seed)
    return names[math.random(1, #names)]
end

local function randomFrom(list, fallback)
    if type(list) ~= 'table' or #list == 0 then return fallback end
    return list[math.random(1, #list)] or fallback
end

local function playNpcVoice(shop, kind)
    local pedConfig = Config.Ped or {}
    if pedConfig.voiceEnabled == false then return end
    if not shop or not shop._ped or not DoesEntityExist(shop._ped) then return end

    local voices = kind == 'farewell' and pedConfig.farewellVoices or pedConfig.greetingVoices
    local speechName = randomFrom(voices, kind == 'farewell' and 'GENERIC_BYE' or 'GENERIC_HI')

    -- GTA cannot voice custom written text, but this plays a native NPC voice bark
    -- at the same time as the custom text bubble above the clerk.
    pcall(function()
        StopCurrentPlayingAmbientSpeech(shop._ped)
        PlayPedAmbientSpeechNative(shop._ped, speechName, 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR')
    end)
end

local function setNpcSpeech(shop, text, duration)
    if not shop then return end
    local pedConfig = Config.Ped or {}
    shop._speechText = text or ''
    shop._speechUntil = GetGameTimer() + (tonumber(duration or pedConfig.speechDuration) or 4200)
end

local function clearNpcSpeech(shop)
    if not shop then return end
    shop._speechText = nil
    shop._speechUntil = 0
end

local function playGreetingIfNeeded(shop)
    if not shop then return end
    local pedConfig = Config.Ped or {}
    local now = GetGameTimer()
    local nextAt = tonumber(shop._nextGreetingAt or 0) or 0

    if now < nextAt then return end

    local line = randomFrom(pedConfig.greetings, 'How can I help you today?')
    setNpcSpeech(shop, line, pedConfig.speechDuration)
    playNpcVoice(shop, 'greeting')
    shop._nextGreetingAt = now + (tonumber(pedConfig.speechCooldown) or 12000)
end

local function playFarewell(shop)
    local pedConfig = Config.Ped or {}
    local line = randomFrom(pedConfig.farewells, 'Alright, see you around.')
    setNpcSpeech(shop, line, pedConfig.speechDuration)
    playNpcVoice(shop, 'farewell')
end

local function openNpcDialog(shop)
    if isOpen then return end

    setScreenInteraction(false)
    activeShop = shop
    currentMode = 'dialog'
    setOpen(true)

    local pedConfig = Config.Ped or {}
    local dialog = pedConfig.dialog or {}
    nui('dialog', {
        clerkName = shop and shop._clerkName or 'Gun Store Clerk',
        title = dialog.title or 'How can I help you today?',
        optionStore = dialog.optionStore or 'Show me what you have got',
        optionClose = dialog.optionClose or 'No thanks'
    })
end


local function getTargetResource()
    local t = Config.Target or {}
    return tostring(t.resource or 'ox_target')
end

local function oxTargetEnabled()
    -- Gunstore now uses custom screen interaction + E key, not ox_target.
    return false
end

local function targetDebugState()
    local res = getTargetResource()
    return ('resource=%s state=%s enabled=%s'):format(res, tostring(GetResourceState(res)), tostring((Config.Target or {}).enabled ~= false))
end


local function buildTargetOptions(shop, index)
    local t = Config.Target or {}
    local options = {
        {
            name = ('cm_gunstore_open_%s'):format(index),
            icon = t.iconStore or 'fa-solid fa-gun',
            label = t.labelStore or 'Talk to clerk',
            distance = tonumber(t.distance) or 2.4,
            onSelect = function()
                openNpcDialog(shop)
            end
        }
    }

    if Config.AdminCommand and Config.AdminCommand ~= '' then
        options[#options + 1] = {
            name = ('cm_gunstore_admin_%s'):format(index),
            icon = t.iconAdmin or 'fa-solid fa-screwdriver-wrench',
            label = t.labelAdmin or 'Gun Store Admin',
            distance = tonumber(t.distance) or 2.4,
            onSelect = function()
                requestCatalog('admin')
            end
        }
    end

    return options
end

local function addShopZoneTarget(shop, index)
    if not oxTargetEnabled() then return false end
    if targetZones[index] then return true end

    local coords = nil
    if shop.pedCoords then
        coords = vec3(shop.pedCoords.x, shop.pedCoords.y, shop.pedCoords.z)
    elseif shop.coords then
        coords = shop.coords
    end
    if not coords then return false end

    local t = Config.Target or {}
    local res = getTargetResource()
    local ok, idOrErr = pcall(function()
        return exports[res]:addSphereZone({
            coords = coords,
            radius = tonumber(t.zoneRadius) or 1.35,
            debug = t.debugZones == true,
            options = buildTargetOptions(shop, index)
        })
    end)

    if ok then
        targetZones[index] = idOrErr or true
        dbg(('ox_target zone added index=%s id=%s'):format(index, tostring(idOrErr)))
        return true
    end

    dbg(('ox_target addSphereZone failed index=%s err=%s'):format(index, tostring(idOrErr)))
    return false
end

local function addPedTarget(ped, shop, index)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if not oxTargetEnabled() then
        dbg(('ox_target not ready, fallback E active (%s)'):format(targetDebugState()))
        return false
    end
    if targetRegistered[ped] then return true end

    local res = getTargetResource()
    local options = buildTargetOptions(shop, index)

    local ok, err = pcall(function()
        -- ox_target addLocalEntity usually returns nil on success, so do not depend on an id.
        exports[res]:addLocalEntity(ped, options)
    end)

    if ok then
        targetRegistered[ped] = true
        targetIds[ped] = true
        dbg(('ox_target added to npc index=%s ped=%s (%s)'):format(index, ped, targetDebugState()))
        -- Zone backup makes the interaction visible even if ox_target raycast misses frozen/interior NPCs.
        addShopZoneTarget(shop, index)
        return true
    end

    dbg(('ox_target addLocalEntity failed npc index=%s ped=%s err=%s (%s)'):format(index, ped, tostring(err), targetDebugState()))
    return addShopZoneTarget(shop, index)
end

local function removePedTarget(ped)
    if not ped or not targetRegistered[ped] then return end
    local res = getTargetResource()
    if GetResourceState(res) == 'started' then
        pcall(function() exports[res]:removeLocalEntity(ped) end)
    end
    targetRegistered[ped] = nil
    targetIds[ped] = nil
end

local function registerAllPedTargets()
    for index, shop in ipairs(Config.Shops or {}) do
        if shop._ped and DoesEntityExist(shop._ped) then
            addPedTarget(shop._ped, shop, index)
        else
            addShopZoneTarget(shop, index)
        end
    end
end

local function drawMarkerAt(coords)
    DrawMarker(
        Config.Interact.markerType or 2,
        coords.x, coords.y, coords.z + 0.12,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.35, 0.35, 0.25,
        39, 215, 255, 135,
        false, true, 2, false, nil, nil, false
    )
end

function setOpen(value)
    isOpen = value == true
    SetNuiFocus(isOpen, isOpen)
    SetNuiFocusKeepInput(false)
end

function requestCatalog(mode)
    currentMode = mode or 'store'
    TriggerServerEvent('cm-gunstore:server:requestCatalog', currentMode)
end

local function closeUi()
    activeShop = nil
    setScreenInteraction(false)
    setOpen(false)
    nui('close', {})
end

local function getShopCoordsAndHeading(shop)
    shop = shop or {}
    local coords = shop.pedCoords or shop.npcCoords or shop.coords
    local heading = tonumber(shop.heading or shop.pedHeading or shop.npcHeading) or 0.0

    if coords and coords.w then
        heading = tonumber(coords.w) or heading
        coords = vec3(coords.x, coords.y, coords.z)
    end

    return coords, heading
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then
        dbg(('invalid ped model: %s'):format(tostring(model)))
        return nil
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 6000
    while not HasModelLoaded(hash) do
        Wait(20)
        if GetGameTimer() > timeout then
            dbg(('ped model load timeout: %s'):format(tostring(model)))
            return nil
        end
    end

    return hash
end

local function spawnShopPeds()
    if Config.Ped and Config.Ped.enabled == false then return end

    local pedConfig = Config.Ped or {}
    local model = pedConfig.model or 's_m_y_ammucity_01'
    local hash = loadModel(model)
    if not hash then return end

    for index, shop in ipairs(Config.Shops or {}) do
        local coords, heading = getShopCoordsAndHeading(shop)
        if coords then
            shop._clerkName = shop.name or shop.clerkName or getRandomClerkName(index)
            local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, heading, false, true)
            if ped and ped ~= 0 then
                SetEntityAsMissionEntity(ped, true, true)
                SetEntityHeading(ped, heading)
                SetBlockingOfNonTemporaryEvents(ped, pedConfig.blockEvents ~= false)
                SetPedCanRagdoll(ped, false)
                SetPedDiesWhenInjured(ped, false)
                SetPedFleeAttributes(ped, 0, false)
                SetPedCombatAttributes(ped, 46, true)

                if pedConfig.invincible ~= false then
                    SetEntityInvincible(ped, true)
                end

                if pedConfig.freeze ~= false then
                    FreezeEntityPosition(ped, true)
                end

                if pedConfig.scenario and pedConfig.scenario ~= '' then
                    TaskStartScenarioInPlace(ped, pedConfig.scenario, 0, true)
                end

                shopPeds[index] = ped
                shop._ped = ped
                dbg(('spawned gun store npc index=%s'):format(index))
            end
        end
    end

    SetModelAsNoLongerNeeded(hash)
end

local function cleanupShopPeds()
    for _, ped in pairs(shopPeds) do
        if ped and DoesEntityExist(ped) then
            removePedTarget(ped)
            DeleteEntity(ped)
        end
    end
    shopPeds = {}

    local res = getTargetResource()
    if GetResourceState(res) == 'started' then
        for _, zoneId in pairs(targetZones) do
            pcall(function() exports[res]:removeZone(zoneId) end)
        end
    end
    targetZones = {}
end

RegisterNetEvent('cm-gunstore:client:openCatalog', function(mode, catalog)
    currentMode = mode or 'store'
    setOpen(true)
    nui('open', {
        mode = currentMode,
        catalog = catalog or {},
        title = currentMode == 'admin' and 'Gun Store Admin' or 'Gun Store'
    })
end)

-- Weapon picker: server sends the full firearm list + status; relay to NUI.
RegisterNetEvent('cm-gunstore:client:weaponPicker', function(list, groups)
    nui('weaponPicker', { list = list or {}, groups = groups or {} })
end)

RegisterNUICallback('adminRequestWeaponPicker', function(_, cb)
    TriggerServerEvent('cm-gunstore:server:requestWeaponPicker')
    cb({ ok = true })
end)

RegisterNUICallback('adminCreateWeapon', function(data, cb)
    TriggerServerEvent('cm-gunstore:server:createWeaponFromPicker', data or {})
    cb({ ok = true })
end)

RegisterNetEvent('cm-gunstore:client:openAdmin', function()
    requestCatalog('admin')
end)

-- Apply a wearable vest when the armor item is used from inventory.
RegisterNetEvent('cm-gunstore:client:wearVest', function(meta)
    meta = type(meta) == 'table' and meta or {}
    local ped = PlayerPedId()
    local component = tonumber(meta.componentIndex or meta.componentId or meta.component_id) or 9
    local drawable = tonumber(meta.drawableId or meta.drawable or meta.drawable_id)
    local texture = tonumber(meta.textureId or meta.texture or meta.texture_id) or 0
    local armor = tonumber(meta.armorValue or meta.armor_value) or 0

    if drawable ~= nil and drawable >= 0 then
        SetPedComponentVariation(ped, component, drawable, texture, 0)
    end
    if armor > 0 then
        SetPedArmour(ped, math.max(0, math.min(100, math.floor(armor))))
    end

    -- Persist the look through cm-characters if present so it survives respawn/relog.
    if GetResourceState('cm-characters') == 'started' then
        pcall(function() exports['cm-characters']:SaveAppearance() end)
    end
    TriggerServerEvent('cm-gunstore:server:vestUsed')
end)

-- nv_cloth finished capturing a vest PNG; pre-fill the gun create form.
RegisterNetEvent('cm-gunstore:client:prefillArmor', function(payload)
    payload = type(payload) == 'table' and payload or {}
    -- Make sure the admin panel is open so the form exists, then prefill via NUI.
    if not isOpen then requestCatalog('admin') end
    CreateThread(function()
        Wait(300)
        nui('prefillArmor', payload)
    end)
end)

RegisterNetEvent('cm-gunstore:client:purchaseResult', function(ok)
    nui('purchaseResult', { ok = ok == true })
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb({ ok = true })
end)

RegisterNUICallback('buyItem', function(data, cb)
    TriggerServerEvent('cm-gunstore:server:buyItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('adminSaveItem', function(data, cb)
    TriggerServerEvent('cm-gunstore:server:adminSaveItem', data or {})
    cb({ ok = true })
end)


RegisterNUICallback('adminCreateItem', function(data, cb)
    TriggerServerEvent('cm-gunstore:server:adminCreateItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('adminSaveImage', function(data, cb)
    TriggerServerEvent('cm-gunstore:server:adminSaveImage', data or {})
    cb({ ok = true })
end)


local function getFreemodeGender()
    local model = GetEntityModel(PlayerPedId())
    if model == joaat('mp_f_freemode_01') then return 'female' end
    if model == joaat('mp_m_freemode_01') then return 'male' end
    return 'both'
end

local function getVestList()
    local ped = PlayerPedId()
    local component = 9 -- GTA freemode body armor / vest component
    local maxDrawables = GetNumberOfPedDrawableVariations(ped, component) or 0
    local list = {}
    for drawable = 0, math.max(0, maxDrawables - 1) do
        local maxTextures = GetNumberOfPedTextureVariations(ped, component, drawable) or 0
        if maxTextures <= 0 then maxTextures = 1 end
        for texture = 0, math.max(0, maxTextures - 1) do
            list[#list + 1] = {
                component_id = component,
                drawable_id = drawable,
                texture_id = texture,
                gender = getFreemodeGender(),
                label = ('Vest %s / Texture %s'):format(drawable, texture)
            }
        end
    end
    return list
end

-- Vest capture is handled by nv_cloth's armor studio (clean transparent PNG).
-- This just hands off to it; nv_cloth saves the PNG into cm-gunstore and
-- pre-fills this form via cm-gunstore:client:prefillArmor.
RegisterNUICallback('adminOpenVestCapture', function(_, cb)
    closeUi() -- close gun UI so the clothing studio camera/controls take over
    TriggerServerEvent('cm-gunstore:server:openArmorCapture')
    cb({ ok = true })
end)

RegisterNUICallback('refreshCatalog', function(_, cb)
    requestCatalog(currentMode == 'dialog' and 'store' or currentMode)
    cb({ ok = true })
end)

RegisterNUICallback('dialogOpenStore', function(_, cb)
    requestCatalog('store')
    cb({ ok = true })
end)

RegisterNUICallback('dialogClose', function(_, cb)
    local shop = activeShop
    closeUi()
    playFarewell(shop)
    cb({ ok = true })
end)

CreateThread(function()
    for _, shop in ipairs(Config.Shops or {}) do
        if shop.blip and shop.coords then
            local blip = AddBlipForCoord(shop.coords.x, shop.coords.y, shop.coords.z)
            SetBlipSprite(blip, shop.blip.sprite or 110)
            SetBlipColour(blip, shop.blip.color or 1)
            SetBlipScale(blip, shop.blip.scale or 0.65)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(shop.label or 'Gun Store')
            EndTextCommandSetBlipName(blip)
        end
    end
end)

CreateThread(function()
    Wait(800)
    spawnShopPeds()
end)


AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == getTargetResource() then
        Wait(500)
        registerAllPedTargets()
    end
end)

RegisterCommand('guntargetdebug', function()
    print(('[cm-gunstore] target %s'):format(targetDebugState()))
    for index, shop in ipairs(Config.Shops or {}) do
        print(('[cm-gunstore] npc index=%s exists=%s targetRegistered=%s zoneRegistered=%s'):format(index, tostring(shop._ped and DoesEntityExist(shop._ped)), tostring(shop._ped and targetRegistered[shop._ped] == true), tostring(targetZones[index] ~= nil)))
    end
    registerAllPedTargets()
end, false)

CreateThread(function()
    -- If ox_target starts after this resource, keep trying for a short time.
    for _ = 1, 20 do
        Wait(1000)
        if oxTargetEnabled() then
            registerAllPedTargets()
            return
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 800
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local markerDistance = tonumber(Config.Interact.markerDistance) or 18.0
        local interactDistance = tonumber(Config.Interact.distance) or 2.2
        local drawMarker = Config.Interact.drawMarker == true

        local now = GetGameTimer()

        for _, shop in ipairs(Config.Shops or {}) do
            local coords = nil
            if shop._ped and DoesEntityExist(shop._ped) then
                coords = GetEntityCoords(shop._ped)
            else
                coords = (getShopCoordsAndHeading(shop))
            end

            if coords then
                local dist = #(pos - coords)
                if dist <= markerDistance then
                    sleep = 0

                    if drawMarker then
                        drawMarkerAt(coords)
                    end

                    local pedConfig = Config.Ped or {}
                    local clerkName = shop._clerkName or 'Gun Store Clerk'
                    local nameDistance = tonumber(pedConfig.nameDistance or 7.0) or 7.0
                    local speechDistance = tonumber(pedConfig.speechDistance or 5.0) or 5.0

                    if dist <= speechDistance and not isOpen then
                        if shop._wasNear ~= true then
                            shop._wasNear = true
                            -- Speak immediately when the player enters the NPC area.
                            shop._nextGreetingAt = 0
                        end

                        -- Repeat politely on cooldown while the player stays nearby.
                        playGreetingIfNeeded(shop)
                    elseif shop._wasNear == true and dist > (speechDistance + 1.5) then
                        shop._wasNear = false
                        clearNpcSpeech(shop)
                    end

                    if dist <= nameDistance and not isOpen then
                        -- Only the clerk name is drawn over the NPC. No prompt/greeting text above head.
                        if Config.Ped == nil or Config.Ped.showName ~= false then
                            drawText3D(vec3(coords.x, coords.y, coords.z + (pedConfig.nameHeight or 1.28)), {
                                {
                                    text = clerkName,
                                    r = 93, g = 232, b = 255, a = 245,
                                    scale = 1.0,
                                    box = false
                                }
                            })
                        end
                    end

                    if dist <= interactDistance and not isOpen then
                        setScreenInteraction(true, {
                            clerkName = clerkName,
                            title = Config.Interact.title or 'Talk to Clerk',
                            subtitle = Config.Interact.subtitle or 'Browse weapons, ammo, and armor',
                            key = Config.Interact.keyLabel or 'E'
                        })

                        if IsControlJustPressed(0, Config.Interact.key or 38) then
                            openNpcDialog(shop)
                            Wait(350)
                        end
                    elseif interactionVisible and not isOpen then
                        setScreenInteraction(false)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        if isOpen then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 200, true)
            if IsControlJustPressed(0, 200) then
                closeUi()
            end
            Wait(0)
        else
            Wait(300)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    closeUi()
    cleanupShopPeds()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)
