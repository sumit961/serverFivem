-- cm-law/client/laptop_terminal.lua
-- In-world dashboard MDT glance, modeled on cm-gang/client/graffiti.lua's DUI
-- pipeline (CreateRuntimeTxd -> CreateDui -> poll IsDuiAvailable ->
-- CreateRuntimeTextureFromDuiHandle -> DrawSpritePoly quad in world space).
-- One DUI is created once and repositioned every frame onto whatever vehicle
-- the on-duty member is currently driving, rather than one per vehicle.
--
-- See shared/config.lua's Config.LaptopTerminal comment for why this is a
-- read-only glance rather than a fully interactive panel: FiveM DUIs only
-- forward mouse input, not keyboard, so citizen search/notes/reports still
-- open through the existing fullscreen MDT (OpenLawMenu('mdt')).

local dict = 'cm_law_laptop'
local dui, txd, texture, textureReady = nil, nil, nil, false
local propObject, propVehicle = nil, nil

local function removeProp()
    if propObject and DoesEntityExist(propObject) then DeleteEntity(propObject) end
    propObject, propVehicle = nil, nil
end

-- Vanilla prop (Config.LaptopTerminal.PropModel), attached under the DUI
-- quad so there's a physical laptop shape on the dash, not just a floating
-- texture. Placement is a best-effort approximation, not a verified UV-mapped
-- fit -- see shared/config.lua's comment; nudge PropOffsetZ/rotation to taste.
local function ensureProp(vehicle)
    local modelName = (Config.LaptopTerminal or {}).PropModel
    if not modelName then return end
    if propVehicle == vehicle and propObject and DoesEntityExist(propObject) then return end
    removeProp()
    local hash = GetHashKey(modelName)
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then return end
    local cfg = Config.LaptopTerminal or {}
    local ox, oy, oz = tonumber(cfg.OffsetX) or 0.0, tonumber(cfg.OffsetY) or 0.35, tonumber(cfg.OffsetZ) or 0.62
    local propZ = oz + (tonumber(cfg.PropOffsetZ) or -0.05)
    local coords = GetEntityCoords(vehicle)
    propObject = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if propObject == 0 then propObject = nil; return end
    AttachEntityToEntity(propObject, vehicle, 0, ox, oy, propZ, -12.0, 0.0, 0.0, false, false, false, false, 2, true)
    SetEntityCollision(propObject, false, false)
    propVehicle = vehicle
end

local function ensureDui()
    if dui then return end
    txd = CreateRuntimeTxd(dict)
    if not txd then return end
    dui = CreateDui(('https://cfx-nui-%s/html/law.html?embedded=laptop'):format(GetCurrentResourceName()), 512, 320)
    CreateThread(function()
        local deadline = GetGameTimer() + 15000
        while not IsDuiAvailable(dui) and GetGameTimer() < deadline do Wait(50) end
        if not IsDuiAvailable(dui) then return end
        texture = CreateRuntimeTextureFromDuiHandle(txd, 'art', GetDuiHandle(dui))
        textureReady = texture ~= nil
    end)
end

local function legalState()
    local state = LocalPlayer.state.cmLegalOrg
    return type(state) == 'table' and state or nil
end

local function eligible()
    local state = legalState()
    return type(state) == 'table' and state.onDuty == true and state.suspended ~= true
end

local function panelCorners(vehicle)
    local cfg = Config.LaptopTerminal or {}
    local ox, oy, oz = tonumber(cfg.OffsetX) or 0.0, tonumber(cfg.OffsetY) or 0.35, tonumber(cfg.OffsetZ) or 0.62
    local hw, hh = (tonumber(cfg.Width) or 0.26) * 0.5, (tonumber(cfg.Height) or 0.15) * 0.5
    local a = GetOffsetFromEntityInWorldCoords(vehicle, ox - hw, oy, oz - hh)
    local b = GetOffsetFromEntityInWorldCoords(vehicle, ox + hw, oy, oz - hh)
    local c = GetOffsetFromEntityInWorldCoords(vehicle, ox + hw, oy, oz + hh)
    local d = GetOffsetFromEntityInWorldCoords(vehicle, ox - hw, oy, oz + hh)
    local center = GetOffsetFromEntityInWorldCoords(vehicle, ox, oy, oz)
    return a, b, c, d, center
end

local function drawPanel(a, b, c, d)
    if not textureReady then return end
    DrawSpritePoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, 255, 255, 255, 255, dict, 'art', 0.0, 1.0, 1.0, 1.0, 1.0, 0.0)
    DrawSpritePoly(a.x, a.y, a.z, c.x, c.y, c.z, d.x, d.y, d.z, 255, 255, 255, 255, dict, 'art', 0.0, 1.0, 1.0, 0.0, 0.0, 0.0)
end

local function drawPrompt()
    SetTextFont(4); SetTextScale(0.0, 0.30); SetTextCentre(true); SetTextOutline(); SetTextColour(255, 255, 255, 235)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName('[E] Open MDT')
    EndTextCommandDisplayText(0.5, 0.82)
end

CreateThread(function()
    while true do
        local wait = 750
        if (Config.LaptopTerminal or {}).Enabled ~= false and eligible() then
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                    ensureDui()
                    ensureProp(vehicle)
                    local a, b, c, d, center = panelCorners(vehicle)
                    local distance = #(GetEntityCoords(ped) - center)
                    local renderDistance = tonumber((Config.LaptopTerminal or {}).RenderDistance) or 8.0
                    if distance <= renderDistance then
                        wait = 0
                        drawPanel(a, b, c, d)
                        local interactDistance = tonumber((Config.LaptopTerminal or {}).InteractDistance) or 2.0
                        if distance <= interactDistance then
                            drawPrompt()
                            if IsControlJustPressed(0, 38) and not (CmLawMenuOpen and CmLawMenuOpen()) then
                                OpenLawMenu('mdt')
                            end
                        end
                    end
                else
                    removeProp()
                end
            else
                removeProp()
            end
        else
            removeProp()
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if dui then DestroyDui(dui) end
    removeProp()
end)
