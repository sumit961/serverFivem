local Config = CMVehicleStore.Config
local Peds = {}
local IsOpen = false
local CurrentDealer = nil

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg or '')
    EndTextCommandThefeedPostTicker(false, false)
    SendNUIMessage({ action = 'toast', message = msg or '' })
end

RegisterNetEvent('cm-vehiclestore:client:notify', function(msg)
    notify(msg)
end)

local function drawText3D(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextScale(0.34, 0.34)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(245, 245, 245, 235)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(sx, sy)
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 7000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function spawnDealerPed(dealer)
    local hash = loadModel(dealer.ped or 'a_m_y_business_03')
    if not hash then return end
    local c = dealer.coords
    local ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    Peds[#Peds + 1] = ped
    SetModelAsNoLongerNeeded(hash)
end

local function openDealer(dealer)
    IsOpen = true
    CurrentDealer = dealer
    SetNuiFocus(true, true)
    local payload = {
        id = dealer.id,
        label = dealer.label,
        npcName = dealer.npcName,
        vehicles = dealer.vehicles or {}
    }
    SendNUIMessage({ action = 'open', dealership = payload })
end

local function closeDealer()
    IsOpen = false
    CurrentDealer = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

CreateThread(function()
    Wait(1000)
    for _, dealer in ipairs(Config.Dealerships or {}) do
        spawnDealerPed(dealer)
    end
end)

CreateThread(function()
    while true do
        local sleep = 700
        if not IsOpen then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            for _, dealer in ipairs(Config.Dealerships or {}) do
                local c = vector3(dealer.coords.x, dealer.coords.y, dealer.coords.z)
                local dist = #(coords - c)
                if dist <= 12.0 then
                    sleep = 0
                    drawText3D(c.x, c.y, c.z + 1.1, dealer.npcName or dealer.label or 'Vehicle Dealer')
                    if dist <= (Config.InteractionDistance or 2.4) then
                        drawText3D(c.x, c.y, c.z + 0.9, '[E] Open dealership')
                        if IsControlJustPressed(0, 38) then
                            openDealer(dealer)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNUICallback('close', function(_, cb)
    closeDealer()
    cb({ ok = true })
end)

RegisterNUICallback('buyVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    if CurrentDealer and data.model then
        TriggerServerEvent('cm-vehiclestore:server:buyVehicle', CurrentDealer.id, data.model)
    end
    cb({ ok = true })
end)

RegisterCommand('vehiclestore', function()
    if IsOpen then closeDealer() return end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local best, dist = nil, 9999.0
    for _, dealer in ipairs(Config.Dealerships or {}) do
        local d = #(coords - vector3(dealer.coords.x, dealer.coords.y, dealer.coords.z))
        if d < dist then best, dist = dealer, d end
    end
    if best and dist < 10.0 then openDealer(best) else notify('No dealership nearby.') end
end, false)
