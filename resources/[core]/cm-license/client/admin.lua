-- CM License System — Client Admin Setup

local Constants = require 'shared.constants'

local Admin = {}

Admin.Mode = nil  -- 'none', 'vehicle_spawn', 'npc_setup', 'route_creator'
Admin.RouteCheckpoints = {}
Admin.PreviewVehicle = nil

function Admin.OpenMenu()
    -- Open admin menu via NUI
    SendNuiMessage(json.encode({
        type = 'openAdminMenu'
    }))

    SetNuiFocus(true, true)
end

-- Enter vehicle spawn positioning mode
function Admin.EnterVehicleSpawnMode(vehicleModel, spawnCoords)
    Admin.Mode = 'vehicle_spawn'

    -- Load and spawn vehicle preview
    local modelHash = GetHashKey(vehicleModel)
    RequestModel(modelHash)

    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if HasModelLoaded(modelHash) then
        Admin.PreviewVehicle = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.heading or 0.0, true, false)
        SetEntityAsNoLongerNeeded(Admin.PreviewVehicle)
    end

    print('^2[CM-License Admin]^7 Vehicle spawn positioning mode active. Use WASD to move, QE to rotate, E to save.')
end

-- Enter route creator mode
function Admin.EnterRouteCreatorMode(vehicleModel, spawnCoords)
    Admin.Mode = 'route_creator'
    Admin.RouteCheckpoints = {}

    -- Spawn vehicle for route planning
    local modelHash = GetHashKey(vehicleModel)
    RequestModel(modelHash)

    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if HasModelLoaded(modelHash) then
        Admin.PreviewVehicle = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.heading or 0.0, true, false)
        SetEntityAsNoLongerNeeded(Admin.PreviewVehicle)

        -- Warp admin into vehicle
        local ped = PlayerPedId()
        TaskWarpPedIntoVehicle(ped, Admin.PreviewVehicle, -1)
    end

    print('^2[CM-License Admin]^7 Route creator mode active. Drive to route points and press E to add checkpoint.')
end

-- Check for route finish
function Admin.CheckRouteFinish()
    if Admin.Mode ~= 'route_creator' then return end

    -- Finish route creator
    Admin.ExitRouteCreatorMode()
end

-- Add checkpoint to route
function Admin.AddCheckpoint()
    if Admin.Mode ~= 'route_creator' then return end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        TriggerEvent('chat:addMessage', {
            args = { 'Error', 'You must be in a vehicle to add checkpoints' }
        })
        return
    end

    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    table.insert(Admin.RouteCheckpoints, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = heading,
        sequence = #Admin.RouteCheckpoints + 1
    })

    print('^2[CM-License Admin]^7 Checkpoint ' .. #Admin.RouteCheckpoints .. ' added')

    TriggerEvent('chat:addMessage', {
        args = { 'Route', 'Checkpoint ' .. #Admin.RouteCheckpoints .. ' added' }
    })
end

-- Exit route creator mode
function Admin.ExitRouteCreatorMode()
    if Admin.PreviewVehicle and DoesEntityExist(Admin.PreviewVehicle) then
        DeleteEntity(Admin.PreviewVehicle)
    end

    Admin.Mode = 'none'
    Admin.PreviewVehicle = nil

    print('^3[CM-License Admin]^7 Route creator mode exited')

    -- Show route summary
    SendNuiMessage(json.encode({
        type = 'showRouteSummary',
        checkpoints = Admin.RouteCheckpoints
    }))
end

-- Delete preview vehicle
function Admin.DeletePreview()
    if Admin.PreviewVehicle and DoesEntityExist(Admin.PreviewVehicle) then
        DeleteEntity(Admin.PreviewVehicle)
    end
    Admin.PreviewVehicle = nil
end

-- Position vehicle with WASD controls (admin mode)
Citizen.CreateThread(function()
    while true do
        Wait(0)

        if Admin.Mode == 'vehicle_spawn' and Admin.PreviewVehicle and DoesEntityExist(Admin.PreviewVehicle) then
            local moved = false
            local speed = 0.1

            if IsControlPressed(0, 32) then  -- W
                local forward = GetEntityForwardVector(Admin.PreviewVehicle)
                local pos = GetEntityCoords(Admin.PreviewVehicle)
                SetEntityCoords(Admin.PreviewVehicle, pos.x + forward.x * speed, pos.y + forward.y * speed, pos.z)
                moved = true
            end

            if IsControlPressed(0, 33) then  -- S
                local forward = GetEntityForwardVector(Admin.PreviewVehicle)
                local pos = GetEntityCoords(Admin.PreviewVehicle)
                SetEntityCoords(Admin.PreviewVehicle, pos.x - forward.x * speed, pos.y - forward.y * speed, pos.z)
                moved = true
            end

            if IsControlPressed(0, 34) then  -- A
                local heading = GetEntityHeading(Admin.PreviewVehicle)
                SetEntityHeading(Admin.PreviewVehicle, heading + 1.0)
                moved = true
            end

            if IsControlPressed(0, 35) then  -- D
                local heading = GetEntityHeading(Admin.PreviewVehicle)
                SetEntityHeading(Admin.PreviewVehicle, heading - 1.0)
                moved = true
            end
        end
    end
end)

return Admin
