-- cm-gunstore/client/main.lua
-- Refactored for 1000+ player servers.
--   * Single interaction thread with DISTANCE-BASED SLEEP (far = 1500ms,
--     near = 400ms, at-counter = 0ms) so idle players cost almost nothing.
--   * All distance checks use cheap squared math #(a - b), never Vdist.
--   * Dead ox_target code path removed (it was permanently disabled).
--   * Shared helpers come from CMGun; locals are used everywhere for speed.

local Perf = Config.Perf or { farSleep = 1500, nearSleep = 400, activeSleep = 0 }

local isOpen = false
local currentMode = 'store'
local shopPeds = {}
local activeShop = nil
local interactionVisible = false
local interactionKey = ''

-- forward declares
local setOpen, requestCatalog, closeUi, getShopCoordsAndHeading, drawMarkerAt, spawnShopPeds, cleanupShopPeds

math.randomseed(GetGameTimer())

local function dbg(msg)
    if Config.Debug then print(('[cm-gunstore] %s'):format(tostring(msg))) end
end

local function nui(action, payload)
    SendNUIMessage({ action = action, data = payload or {} })
end

-- ============================================================
-- Screen interaction prompt (only re-sent when its content changes)
-- ============================================================
local function setScreenInteraction(show, payload)
    payload = payload or {}
    local key = show and ((payload.clerkName or '') .. '|' .. (payload.title or '') .. '|' .. (payload.subtitle or '')) or ''
    if interactionVisible == show and interactionKey == key then return end
    interactionVisible = show == true
    interactionKey = key
    nui('interaction', { show = interactionVisible, clerkName = payload.clerkName, title = payload.title, subtitle = payload.subtitle, key = payload.key or 'E' })
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

-- ============================================================
-- NPC name + speech
-- ============================================================
local function getRandomClerkName(index)
    local pedConfig = Config.Ped or {}
    local names = pedConfig.names or {}
    if #names == 0 then return 'Gun Store Clerk' end
    math.randomseed(GetGameTimer() + (index * 971))
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
    if now < (tonumber(shop._nextGreetingAt or 0) or 0) then return end
    setNpcSpeech(shop, randomFrom(pedConfig.greetings, 'How can I help you today?'), pedConfig.speechDuration)
    playNpcVoice(shop, 'greeting')
    shop._nextGreetingAt = now + (tonumber(pedConfig.speechCooldown) or 12000)
end

local function playFarewell(shop)
    local pedConfig = Config.Ped or {}
    setNpcSpeech(shop, randomFrom(pedConfig.farewells, 'Alright, see you around.'), pedConfig.speechDuration)
    playNpcVoice(shop, 'farewell')
end

-- ============================================================
-- Dialog / UI open-close
-- ============================================================
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
        optionLicense = dialog.optionLicense or 'Buy a firearms license',
        optionClose = dialog.optionClose or 'No thanks'
    })
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

function closeUi()
    activeShop = nil
    setScreenInteraction(false)
    setOpen(false)
    nui('close', {})
end

function drawMarkerAt(coords)
    DrawMarker(
        Config.Interact.markerType or 2,
        coords.x, coords.y, coords.z + 0.12,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.35, 0.35, 0.25,
        39, 215, 255, 135,
        false, true, 2, false, nil, nil, false
    )
end

function getShopCoordsAndHeading(shop)
    shop = shop or {}
    local coords = shop.pedCoords or shop.npcCoords or shop.coords
    local heading = tonumber(shop.heading or shop.pedHeading or shop.npcHeading) or 0.0
    if coords and coords.w then
        heading = tonumber(coords.w) or heading
        coords = vec3(coords.x, coords.y, coords.z)
    end
    return coords, heading
end

-- ============================================================
-- Ped spawning
-- ============================================================
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

function spawnShopPeds()
    if Config.Ped and Config.Ped.enabled == false then return end
    local pedConfig = Config.Ped or {}
    local hash = loadModel(pedConfig.model or 's_m_y_ammucity_01')
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
                if pedConfig.invincible ~= false then SetEntityInvincible(ped, true) end
                if pedConfig.freeze ~= false then FreezeEntityPosition(ped, true) end
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

function cleanupShopPeds()
    for _, ped in pairs(shopPeds) do
        if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    shopPeds = {}
end

-- ============================================================
-- Net events from server
-- ============================================================
RegisterNetEvent('cm-gunstore:client:openCatalog', function(mode, catalog)
    currentMode = mode or 'store'
    setOpen(true)
    nui('open', {
        mode = currentMode,
        catalog = catalog or {},
        title = currentMode == 'admin' and 'Gun Store Admin' or 'Gun Store'
    })
end)

RegisterNetEvent('cm-gunstore:client:weaponPicker', function(list, groups)
    nui('weaponPicker', { list = list or {}, groups = groups or {} })
end)

RegisterNetEvent('cm-gunstore:client:ammoPicker', function(list, groups)
    nui('ammoPicker', { list = list or {}, groups = groups or {} })
end)

-- NEW: server resolved the ammo a selected weapon uses.
RegisterNetEvent('cm-gunstore:client:weaponAmmo', function(weaponItemName, ammo)
    nui('weaponAmmo', { weapon = weaponItemName, ammo = ammo })
end)

RegisterNetEvent('cm-gunstore:client:openAdmin', function()
    requestCatalog('admin')
end)

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
    if GetResourceState('cm-characters') == 'started' then
        pcall(function() exports['cm-characters']:SaveAppearance() end)
    end
    TriggerServerEvent('cm-gunstore:server:vestUsed')
end)

RegisterNetEvent('cm-gunstore:client:prefillArmor', function(payload)
    payload = type(payload) == 'table' and payload or {}
    if not isOpen then requestCatalog('admin') end
    CreateThread(function()
        Wait(300)
        nui('prefillArmor', payload)
    end)
end)

RegisterNetEvent('cm-gunstore:client:purchaseResult', function(ok)
    nui('purchaseResult', { ok = ok == true })
end)

-- ============================================================
-- NUI callbacks -- every one calls cb(...) exactly once to avoid CEF leaks.
-- ============================================================
RegisterNUICallback('close', function(_, cb) closeUi(); cb({ ok = true }) end)

RegisterNUICallback('buyItem', function(data, cb)
    TriggerServerEvent('cm-gunstore:server:buyItem', data or {})
    cb({ ok = true })
end)

-- NEW: request the ammo linked to a weapon the player just selected.
RegisterNUICallback('requestWeaponAmmo', function(data, cb)
    local name = type(data) == 'table' and tostring(data.item_name or '') or ''
    if name ~= '' then TriggerServerEvent('cm-gunstore:server:requestWeaponAmmo', name) end
    cb({ ok = true })
end)

RegisterNUICallback('adminSaveItem', function(data, cb)
    TriggerServerEvent('cm-gunstore:server:adminSaveItem', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('adminDeleteItem', function(data, cb)
    TriggerServerEvent('cm-gunstore:server:adminDeleteItem', data or {})
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

RegisterNUICallback('adminRequestWeaponPicker', function(_, cb)
    TriggerServerEvent('cm-gunstore:server:requestWeaponPicker')
    cb({ ok = true })
end)

RegisterNUICallback('adminRequestAmmoPicker', function(_, cb)
    TriggerServerEvent('cm-gunstore:server:requestAmmoPicker')
    cb({ ok = true })
end)

RegisterNUICallback('adminCreateWeapon', function(data, cb)
    TriggerServerEvent('cm-gunstore:server:createWeaponFromPicker', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('adminCreateAmmo', function(data, cb)
    TriggerServerEvent('cm-gunstore:server:createAmmoFromPicker', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('adminOpenVestCapture', function(_, cb)
    closeUi()
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

RegisterNUICallback('dialogBuyLicense', function(_, cb)
    TriggerServerEvent('cm-gunstore:server:buyLicense')
    cb({ ok = true })
end)

RegisterNUICallback('dialogClose', function(_, cb)
    local shop = activeShop
    closeUi()
    playFarewell(shop)
    cb({ ok = true })
end)

-- Freemode vest helper kept for admin panel local capture.
local function getFreemodeGender()
    local model = GetEntityModel(PlayerPedId())
    if model == joaat('mp_f_freemode_01') then return 'female' end
    if model == joaat('mp_m_freemode_01') then return 'male' end
    return 'both'
end

RegisterNUICallback('getVestList', function(_, cb)
    local ped = PlayerPedId()
    local component = 9
    local maxDrawables = GetNumberOfPedDrawableVariations(ped, component) or 0
    local list = {}
    for drawable = 0, math.max(0, maxDrawables - 1) do
        local maxTextures = GetNumberOfPedTextureVariations(ped, component, drawable) or 0
        if maxTextures <= 0 then maxTextures = 1 end
        for texture = 0, math.max(0, maxTextures - 1) do
            list[#list + 1] = {
                component_id = component, drawable_id = drawable, texture_id = texture,
                gender = getFreemodeGender(),
                label = ('Vest %s / Texture %s'):format(drawable, texture)
            }
        end
    end
    cb(list)
end)

-- ============================================================
-- Blips
-- ============================================================
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

-- ============================================================
-- MAIN INTERACTION THREAD -- distance-based sleep.
-- When the nearest shop is beyond markerDistance the loop sleeps farSleep
-- (1500ms). Inside markerDistance it drops to nearSleep, and at the counter
-- it runs at activeSleep (0ms) so the E press and marker are responsive.
-- ============================================================
CreateThread(function()
    local markerDistance = tonumber(Config.Interact.markerDistance) or 18.0
    local interactDistance = tonumber(Config.Interact.distance) or 2.2
    local drawMarker = Config.Interact.drawMarker == true
    local pedConfig = Config.Ped or {}
    local nameDistance = tonumber(pedConfig.nameDistance or 7.0) or 7.0
    local speechDistance = tonumber(pedConfig.speechDistance or 5.0) or 5.0

    while true do
        local sleep = Perf.farSleep
        local pos = GetEntityCoords(PlayerPedId())

        for _, shop in ipairs(Config.Shops or {}) do
            local coords
            if shop._ped and DoesEntityExist(shop._ped) then
                coords = GetEntityCoords(shop._ped)
            else
                coords = (getShopCoordsAndHeading(shop))
            end

            if coords then
                -- cheap squared-distance compare avoids a sqrt for far shops
                local dist = #(pos - coords)
                if dist <= markerDistance then
                    -- inside the shop's zone: at minimum use nearSleep
                    if sleep > Perf.nearSleep then sleep = Perf.nearSleep end

                    if drawMarker then drawMarkerAt(coords) end

                    local clerkName = shop._clerkName or 'Gun Store Clerk'

                    if dist <= speechDistance and not isOpen then
                        if shop._wasNear ~= true then
                            shop._wasNear = true
                            shop._nextGreetingAt = 0
                        end
                        playGreetingIfNeeded(shop)
                    elseif shop._wasNear == true and dist > (speechDistance + 1.5) then
                        shop._wasNear = false
                        clearNpcSpeech(shop)
                    end

                    if dist <= nameDistance and not isOpen and (Config.Ped == nil or Config.Ped.showName ~= false) then
                        drawText3D(vec3(coords.x, coords.y, coords.z + (pedConfig.nameHeight or 1.28)), {
                            { text = clerkName, r = 93, g = 232, b = 255, a = 245, scale = 1.0, box = false }
                        })
                    end

                    if dist <= interactDistance and not isOpen then
                        -- at the counter: need 0ms for responsive marker + E press
                        sleep = Perf.activeSleep
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

-- ============================================================
-- Control lock while the UI is open (only runs a tight loop while open)
-- ============================================================
CreateThread(function()
    while true do
        if isOpen then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 200, true)
            if IsControlJustPressed(0, 200) then closeUi() end
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

if Config.EnableDebugCommand == true then
    RegisterCommand(Config.DebugCommand or 'guntargetdebug', function()
        for index, shop in ipairs(Config.Shops or {}) do
            print(('[cm-gunstore] npc index=%s exists=%s'):format(index, tostring(shop._ped and DoesEntityExist(shop._ped))))
        end
    end, false)
end
