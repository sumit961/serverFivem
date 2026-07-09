-- cm-store/client/main.lua
-- Store clerk NPCs + blips, E-to-open interaction, and the NUI bridge.

local uiOpen = false
local peds = {}
local currentMode = 'store'

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do Wait(20); tries = tries + 1 end
    return HasModelLoaded(hash) and hash or nil
end

-- ============================================================
-- Peds + blips
-- ============================================================
CreateThread(function()
    for _, shop in ipairs(Config.Shops or {}) do
        local b = shop.blip
        if b and b.sprite then
            local c = shop.coords or shop.pedCoords
            if c then
                local blip = AddBlipForCoord(tonumber(c.x) or c[1], tonumber(c.y) or c[2], tonumber(c.z) or c[3])
                SetBlipSprite(blip, b.sprite)
                SetBlipColour(blip, b.color or 0)
                SetBlipScale(blip, b.scale or 0.7)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(shop.label or 'Store')
                EndTextCommandSetBlipName(blip)
            end
        end
    end

    local pedCfg = Config.Ped or {}
    if pedCfg.enabled == false then return end
    local hash = loadModel(pedCfg.model or 'mp_m_shopkeep_01')
    if not hash then return end

    for _, shop in ipairs(Config.Shops or {}) do
        local p = shop.pedCoords
        if p then
            local px, py, pz, pw = tonumber(p.x) or p[1], tonumber(p.y) or p[2], tonumber(p.z) or p[3], tonumber(p.w) or p[4] or 0.0
            local ped = CreatePed(4, hash, px, py, pz - 1.0, pw, false, true)
            if ped and ped ~= 0 then
                SetEntityAsMissionEntity(ped, true, true)
                if pedCfg.freeze ~= false then FreezeEntityPosition(ped, true) end
                if pedCfg.invincible ~= false then SetEntityInvincible(ped, true) end
                if pedCfg.blockEvents ~= false then SetBlockingOfNonTemporaryEvents(ped, true) end
                if pedCfg.scenario then TaskStartScenarioInPlace(ped, pedCfg.scenario, 0, true) end
                peds[#peds + 1] = { entity = ped, coords = vector3(px, py, pz) }
            end
        end
    end
    SetModelAsNoLongerNeeded(hash)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, p in ipairs(peds) do if p.entity and DoesEntityExist(p.entity) then DeleteEntity(p.entity) end end
    if uiOpen then SetNuiFocus(false, false) end
end)

-- ============================================================
-- Interaction
-- ============================================================
local function openStore()
    TriggerServerEvent('cm-store:server:requestCatalog')
end

CreateThread(function()
    local key = (Config.Interact and Config.Interact.key) or 38
    local dist = (Config.Interact and Config.Interact.distance) or 2.2
    while true do
        local sleep = 750
        if not uiOpen and #peds > 0 then
            local pcoords = GetEntityCoords(PlayerPedId())
            local near = nil
            for _, p in ipairs(peds) do
                if #(pcoords - p.coords) <= dist then near = p break end
            end
            if near then
                sleep = 0
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName((Config.Interact and Config.Interact.prompt) or 'Press ~INPUT_CONTEXT~ to open Store')
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, key) then
                    openStore()
                end
            end
        end
        Wait(sleep)
    end
end)

-- ============================================================
-- NUI bridge
-- ============================================================
RegisterNetEvent('cm-store:client:openCatalog', function(mode, catalog, categories)
    currentMode = mode or 'store'
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        mode = currentMode,
        catalog = catalog or {},
        categories = categories or {},
        accounts = Config.Accounts or { cash = 'cash', bank = 'bank' },
    })
end)

RegisterNetEvent('cm-store:client:purchaseResult', function(success)
    SendNUIMessage({ action = 'purchaseResult', success = success == true })
end)

local function closeUI()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb) closeUI(); cb({}) end)

RegisterNUICallback('buy', function(data, cb)
    data = data or {}
    TriggerServerEvent('cm-store:server:buyItem', { item_name = data.item_name, method = data.method })
    cb({ ok = true })
end)
