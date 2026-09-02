-- CM License System — Client NPC Interaction

NPC = {}

-- NPC state tracking
NPC.LoadedModels = {}
NPC.Peds = {}
NPC.Definitions = {}
NPC.Camera = nil
NPC.NearbyPed = nil
NPC.Name = 'Alex Morgan'
NPC.Role = 'CM License Instructor'
NPC.PromptVisible = false

function NPC.Init()
    TriggerServerEvent('cm-license:server:requestNPCDefinitions')
    print('^2[CM-License NPC]^7 NPC system initialized')
end

RegisterNetEvent('cm-license:client:setNPCDefinitions', function(definitions)
    for _, ped in ipairs(NPC.Peds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    NPC.Peds = {}
    NPC.Definitions = {}
    for _, definition in ipairs(definitions or {}) do
        local coords = definition.coords
        local ped = coords and NPC.Spawn(definition.model, coords, coords.heading)
        if ped then
            NPC.Peds[#NPC.Peds + 1] = ped
            NPC.Definitions[ped] = definition
        end
    end
end)

-- Load NPC model
function NPC.LoadModel(modelName)
    if not modelName then return false end
    
    local modelHash = GetHashKey(modelName)
    if NPC.LoadedModels[modelHash] then
        return true
    end
    
    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    
    if HasModelLoaded(modelHash) then
        NPC.LoadedModels[modelHash] = true
        return true
    end
    
    print('^1[CM-License]^7 Failed to load NPC model: ' .. modelName)
    return false
end

-- Spawn NPC
function NPC.Spawn(model, coords, heading)
    if not NPC.LoadModel(model) then
        return nil
    end
    
    local modelHash = GetHashKey(model)
    local ped = CreatePed(4, modelHash, coords.x, coords.y, coords.z - 1.0, heading or 0.0, false, false)
    
    if not DoesEntityExist(ped) then
        return nil
    end
    
    -- Configure NPC
    SetBlockingOfNonTemporaryEvents(ped, true)
    if coords.scenario then TaskStartScenarioInPlace(ped, coords.scenario, 0, true) end
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    
    return ped
end

-- Check if player is near NPC and show interaction prompt
function NPC.CheckNPCInteraction()
    if not NPC.NearbyPed then return end
    if NPC.PromptVisible then SendNUIMessage({type='npcInteraction',visible=false}); NPC.PromptVisible=false end
    TriggerServerEvent('cm-license:server:getNPCLocations')
end

local function setCamera(position, target, fov, interpolate)
    local nextCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(nextCamera, position.x, position.y, position.z)
    PointCamAtCoord(nextCamera, target.x, target.y, target.z)
    SetCamFov(nextCamera, fov)
    if interpolate and NPC.Camera and DoesCamExist(NPC.Camera) then
        SetCamActiveWithInterp(nextCamera, NPC.Camera, 600, true, true)
        local old = NPC.Camera
        SetTimeout(700, function() if DoesCamExist(old) then DestroyCam(old, false) end end)
    else
        SetCamActive(nextCamera, true)
        RenderScriptCams(true, true, 450, true, true)
    end
    NPC.Camera = nextCamera
end

function NPC.OpenCamera()
    local ped = NPC.NearbyPed
    if not ped or not DoesEntityExist(ped) then return end
    local forward = GetEntityForwardVector(ped)
    local player, pedCoords = PlayerPedId(), GetEntityCoords(ped)
    local stageX, stageY = pedCoords.x + forward.x * 1.9, pedCoords.y + forward.y * 1.9
    RequestCollisionAtCoord(stageX, stageY, pedCoords.z)
    SetEntityCoordsNoOffset(player, stageX, stageY, pedCoords.z, false, false, false)
    SetEntityHeading(player, (GetEntityHeading(ped) + 180.0) % 360.0)
    FreezeEntityPosition(player, true)
    TriggerEvent('cm-hud:client:hideForUi', 'cm-license:npc-dialogue')
    setCamera(GetOffsetFromEntityInWorldCoords(ped, 2.4, 3.5, 1.45), pedCoords + vector3(0.0,0.0,0.65), 52.0, false)
    SetTimeout(950, function()
        if not NPC.Camera or not DoesEntityExist(ped) then return end
        local currentHead = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
        local currentForward = GetEntityForwardVector(ped)
        setCamera(vector3(currentHead.x + currentForward.x * 1.05, currentHead.y + currentForward.y * 1.05, currentHead.z + 0.08), currentHead, 38.0, true)
    end)
end

-- Show license menu via NUI
function NPC.ShowLicenseMenu(licenses)
    NPC.OpenCamera()
    local definition = NPC.NearbyPed and NPC.Definitions[NPC.NearbyPed] or {}
    SetNuiFocus(true, true)
    SendNuiMessage(json.encode({
        type = 'openLicenseMenu',
        licenses = licenses,
        instructorName = definition.name or NPC.Name,
        instructorRole = definition.role or NPC.Role
    }))
end

-- Show my licenses dialog via NUI
function NPC.ShowMyLicenses(licenses)
    SetNuiFocus(true, true)
    SendNuiMessage(json.encode({
        type = 'showMyLicenses',
        licenses = licenses
    }))
end

-- Show test confirmation dialog
function NPC.ShowTestConfirmation(licenseType, price)
    SetNuiFocus(true, true)
    SendNuiMessage(json.encode({
        type = 'showTestConfirmation',
        licenseType = licenseType,
        price = price
    }))
end

-- Request to start test
function NPC.RequestStartTest(licenseType)
    TriggerServerEvent(Constants.EVENTS.SERVER.REQUEST_START_TEST, licenseType)
end

-- Cancel test
function NPC.CancelTest()
    TriggerServerEvent(Constants.EVENTS.SERVER.CANCEL_TEST)
end

-- Close menu
function NPC.CloseMenu()
    SetNuiFocus(false, false)
    if NPC.Camera and DoesCamExist(NPC.Camera) then
        RenderScriptCams(false, true, 350, true, true)
        DestroyCam(NPC.Camera, false)
    end
    NPC.Camera = nil
    FreezeEntityPosition(PlayerPedId(), false)
    TriggerEvent('cm-hud:client:showAfterUi', 'cm-license:npc-dialogue')
end


CreateThread(function()
    while true do
        local wait, playerCoords = 750, GetEntityCoords(PlayerPedId())
        NPC.NearbyPed = nil
        for _, ped in ipairs(NPC.Peds) do
            if DoesEntityExist(ped) and #(playerCoords-GetEntityCoords(ped))<=3.0 then NPC.NearbyPed=ped; break end
        end
        if NPC.NearbyPed and not Client.IsInTest() then
            wait=0
            local definition=NPC.Definitions[NPC.NearbyPed] or {}
            local pedCoords=GetEntityCoords(NPC.NearbyPed)
            SetDrawOrigin(pedCoords.x,pedCoords.y,pedCoords.z+1.15,0)
            SetTextFont(4); SetTextScale(0.0,0.31); SetTextCentre(true); SetTextOutline(); SetTextColour(255,255,255,245)
            BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(definition.name or NPC.Name)
            EndTextCommandDisplayText(0.0,0.0); ClearDrawOrigin()
            if not NPC.PromptVisible then
                SendNUIMessage({type='npcInteraction',visible=true,name=definition.name or NPC.Name,role=definition.role or NPC.Role})
                NPC.PromptVisible=true
            end
        elseif NPC.PromptVisible then SendNUIMessage({type='npcInteraction',visible=false}); NPC.PromptVisible=false end
        Wait(wait)
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if NPC.PromptVisible then SendNUIMessage({type='npcInteraction',visible=false}) end
        NPC.CloseMenu()
    end
end)

return NPC
