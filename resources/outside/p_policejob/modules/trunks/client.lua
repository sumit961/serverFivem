if not Config.Trunks.enabled then
    return
end

Trunks = {
    isActive = false,
    entity = nil,
    cam = nil,
    angle = 0,
}

exports("inTrunk", function()
    return Trunks.isActive
end)

exports("enterTrunk", function(vehicle)
    Trunks:enter(vehicle)
end)

exports("exitTrunk", function()
    Trunks:exit()
end)

exports("TrunkEditor", function()
    Trunks:openEditor()
end)

function playTrunkAnim()
    local animDict = lib.requestAnimDict("fin_ext_p1-7")
    TaskPlayAnim(cache.ped, animDict, "cs_devin_dual-7", -8.0, 8.0, -1, 0, 0, false, false, false)
    RemoveAnimDict(animDict)
end

function Trunks.createCamera(self)
    self.cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamActive(self.cam, true)
    RenderScriptCams(true, true, 500, true, false)
    SetCamFov(self.cam, 60.0)
    ClearPedTasks(cache.ped)
    if Config.Trunks.cameraType == "dynamic" then
        self:dynamicCameraLoop()
    elseif Config.Trunks.cameraType == "static" then
        self:staticCameraLoop()
    end
end

function Trunks.destroyCamera(self)
    if not self.cam or not DoesCamExist(self.cam) then
        return
    end
    DestroyCam(self.cam, false)
    RenderScriptCams(false, true, 500, true, false)
    self.cam = nil
end

function Trunks.dynamicCameraLoop(self)
    CreateThread(function()
        while self.isActive do
            if not self.entity or not DoesEntityExist(self.entity) then
                self:destroyCamera()
                break
            end
            DisableAllControlActions(0)
            if not IsEntityPlayingAnim(cache.ped, "fin_ext_p1-7", "cs_devin_dual-7", 3) then
                playTrunkAnim()
            end
            if IsDisabledControlJustReleased(0, 73) then
                self:exit()
                break
            end
            local lookInput = GetDisabledControlNormal(0, 1)
            self.angle = self.angle + lookInput * 2.5
            local entityCoords = GetEntityCoords(self.entity)
            local radius = 4.0
            local offsetX = math.cos(math.rad(self.angle)) * radius
            local offsetY = math.sin(math.rad(self.angle)) * radius
            SetCamCoord(self.cam, entityCoords.x + offsetX, entityCoords.y + offsetY, entityCoords.z + 1.25)
            PointCamAtCoord(self.cam, entityCoords.x, entityCoords.y, entityCoords.z + 0.5)
            Wait(0)
        end
    end)
end

function Trunks.staticCameraLoop(self)
    CreateThread(function()
        while self.isActive do
            if not self.entity or not DoesEntityExist(self.entity) then
                self:destroyCamera()
                break
            end
            DisableAllControlActions(0)
            if not IsEntityPlayingAnim(cache.ped, "fin_ext_p1-7", "cs_devin_dual-7", 3) then
                playTrunkAnim()
            end
            if IsDisabledControlJustReleased(0, 73) then
                self:exit()
                break
            end
            local entityCoords = GetEntityCoords(self.entity)
            local camCoords = GetOffsetFromEntityInWorldCoords(self.entity, 0.0, -4.5, 1.25)
            SetCamCoord(self.cam, camCoords)
            PointCamAtCoord(self.cam, entityCoords.x, entityCoords.y, entityCoords.z + 0.5)
            Wait(0)
        end
    end)
end

function Trunks.canInteract(self, vehicle, forEnter)
    if cache.vehicle then
        return false
    end
    if not NetworkGetEntityIsNetworked(vehicle) then
        return false
    end
    if not forEnter then
        if not self.isActive or not self.entity then
            return false
        end
        return vehicle == self.entity
    end
    if self.isActive then
        return false
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local occupied = GlobalState["p_policejob:occupiedTrunks"]
    if occupied and occupied[netId] then
        return false
    end
    if Config.Trunks.checkVehicleLocks and GetVehicleDoorLockStatus(vehicle) >= 2 then
        return false
    end
    if Config.Trunks.checkTrunkState and GetVehicleDoorAngleRatio(vehicle, 5) < 0.1 then
        return false
    end
    return true
end

function Trunks.enter(self, vehicle)
    if self.isActive then
        return
    end
    if not vehicle then
        vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 3.5, true)
    end
    if not vehicle or vehicle == 0 then
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerServerEvent("p_policejob/server/trunks/setOccupied", netId, true)
    self.isActive = true
    self.entity = vehicle
    local ped = cache.ped
    local modelName = string.lower(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
    local offset = Config.Trunks.offsets[modelName] or Config.Trunks.defaultOffset
    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    AttachEntityToEntity(
        ped, vehicle, 0,
        offset.coords.x, minDim.y + offset.coords.y, maxDim.z + offset.coords.z,
        offset.rotation.x, offset.rotation.y, offset.rotation.z,
        true, true, true, true, 1, true
    )
    playTrunkAnim()
    Config.Trunks.onEnter()
    if Config.Trunks.cameraType ~= "game" then
        self:createCamera()
    end
    SendNUIMessage({ action = "setVisibleTrunk", data = true })
end

function Trunks.exit(self)
    if not self.entity then
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(self.entity)
    TriggerServerEvent("p_policejob/server/trunks/setOccupied", netId, false)
    local exitCoords = GetOffsetFromEntityInWorldCoords(self.entity, 0.0, -3.25, 0.0)
    self:destroyCamera()
    DetachEntity(cache.ped)
    ClearPedTasks(cache.ped)
    SetEntityCoords(cache.ped, exitCoords)
    self.isActive = false
    self.entity = nil
    Config.Trunks.onExit()
    SendNUIMessage({ action = "setVisibleTrunk", data = false })
end

RegisterNetEvent("p_policejob/client/trunks/enter", function(vehicle)
    Trunks:enter(vehicle)
end)

RegisterNetEvent("p_policejob/client/trunks/exit", function()
    Trunks:exit()
end)

RegisterNetEvent("p_policejob/client/trunks/refreshOffsets", function(offsets)
    for model, offset in pairs(offsets) do
        Config.Trunks.offsets[model] = offset
    end
end)

CreateThread(function()
    Wait(1000)
    local fileContents = LoadResourceFile(GetCurrentResourceName(), "trunks.json")
    if not fileContents then
        return
    end
    local offsets = json.decode(fileContents)
    if not offsets then
        return
    end
    for model, offset in pairs(offsets) do
        Config.Trunks.offsets[model] = offset
    end
end)

CreateThread(function()
    Bridge.Target.addVehicle({
        {
            name = "p_policejob/trunks/enter",
            label = locale("get_in_trunk"),
            icon = "fa-solid fa-car",
            distance = 2,
            onSelect = function(target)
                local vehicle = type(target) == "number" and target or target.entity
                Trunks:enter(vehicle)
            end,
            canInteract = function(vehicle)
                return Trunks:canInteract(vehicle, true)
            end,
        },
        {
            name = "p_policejob/trunks/exit",
            label = locale("get_out_trunk"),
            icon = "fa-solid fa-car",
            distance = 2,
            onSelect = function()
                Trunks:exit()
            end,
            canInteract = function(vehicle)
                return Trunks:canInteract(vehicle, false)
            end,
        },
        {
            name = "p_policejob/trunks/takeOut",
            label = locale("take_player_out_trunk"),
            icon = "fa-solid fa-car",
            distance = 2,
            onSelect = function(target)
                local vehicle = type(target) == "number" and target or target.entity
                if not NetworkGetEntityIsNetworked(vehicle) then
                    return
                end
                TriggerServerEvent("p_policejob/server/trunks/takeOut", NetworkGetNetworkIdFromEntity(vehicle))
            end,
            canInteract = function(vehicle)
                if not NetworkGetEntityIsNetworked(vehicle) then
                    return false
                end
                local netId = NetworkGetNetworkIdFromEntity(vehicle)
                local occupied = GlobalState["p_policejob:occupiedTrunks"]
                if occupied and occupied[netId] then
                    return occupied[netId] ~= cache.serverId
                end
                return false
            end,
        },
    })
end)

function Trunks.openEditor(self)
    local playerCoords = GetEntityCoords(cache.ped)
    local vehicle = lib.getClosestVehicle(playerCoords, 10.0, true)
    if not vehicle or vehicle == 0 then
        Bridge.Notify.showNotify(locale("no_closest_vehicle"), "error")
        return
    end
    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local vehicleCoords = GetEntityCoords(vehicle)
    local offsetCoords = Config.Trunks.defaultOffset.coords
    local offsetRotation = Config.Trunks.defaultOffset.rotation
    local editorActive = true
    local editorCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamActive(editorCam, true)
    RenderScriptCams(true, true, 500, true, false)
    SetCamFov(editorCam, 60.0)
    local camCoords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -4.5, 1.25)
    SetCamCoord(editorCam, camCoords)
    PointCamAtCoord(editorCam, vehicleCoords.x, vehicleCoords.y, vehicleCoords.z + 0.5)
    AttachEntityToEntity(
        cache.ped, vehicle, 0,
        offsetCoords.x, minDim.y + offsetCoords.y, maxDim.z + offsetCoords.z,
        offsetRotation.x, offsetRotation.y, offsetRotation.z,
        true, true, true, true, 1, true
    )
    SendNUIMessage({ action = "setVisibleTrunkEditor", data = true })

    function reattachPed()
        AttachEntityToEntity(
            cache.ped, vehicle, 0,
            offsetCoords.x, minDim.y + offsetCoords.y, maxDim.z + offsetCoords.z,
            offsetRotation.x, offsetRotation.y, offsetRotation.z,
            true, true, true, true, 1, true
        )
    end

    function closeEditor()
        editorActive = false
        Wait(10)
        DetachEntity(cache.ped)
        SetEntityCoords(cache.ped, camCoords.x, camCoords.y, camCoords.z - 1.0)
        ClearPedTasks(cache.ped)
        RenderScriptCams(false, true, 500, true, false)
        DestroyCam(editorCam)
        SendNUIMessage({ action = "setVisibleTrunkEditor", data = false })
    end

    local controls = {
        { key = 34, get = function() offsetCoords = vector3(offsetCoords.x - 0.1, offsetCoords.y, offsetCoords.z) end },
        { key = 35, get = function() offsetCoords = vector3(offsetCoords.x + 0.1, offsetCoords.y, offsetCoords.z) end },
        { key = 244, get = function() offsetCoords = vector3(offsetCoords.x, offsetCoords.y - 0.1, offsetCoords.z) end },
        { key = 249, get = function() offsetCoords = vector3(offsetCoords.x, offsetCoords.y + 0.1, offsetCoords.z) end },
        { key = 32, get = function() offsetCoords = vector3(offsetCoords.x, offsetCoords.y, offsetCoords.z + 0.1) end },
        { key = 33, get = function() offsetCoords = vector3(offsetCoords.x, offsetCoords.y, offsetCoords.z - 0.1) end },
        { key = 44, get = function() offsetRotation = vector3(offsetRotation.x - 10.0, offsetRotation.y, offsetRotation.z) end },
        { key = 45, get = function() offsetRotation = vector3(offsetRotation.x + 10.0, offsetRotation.y, offsetRotation.z) end },
        { key = 23, get = function() offsetRotation = vector3(offsetRotation.x, offsetRotation.y - 10.0, offsetRotation.z) end },
        { key = 47, get = function() offsetRotation = vector3(offsetRotation.x, offsetRotation.y + 10.0, offsetRotation.z) end },
        { key = 26, get = function() offsetRotation = vector3(offsetRotation.x, offsetRotation.y, offsetRotation.z - 10.0) end },
        { key = 236, get = function() offsetRotation = vector3(offsetRotation.x, offsetRotation.y, offsetRotation.z + 10.0) end },
    }

    CreateThread(function()
        while editorActive do
            DisableAllControlActions(0)
            if not IsEntityPlayingAnim(cache.ped, "fin_ext_p1-7", "cs_devin_dual-7", 3) then
                playTrunkAnim()
            end
            if IsDisabledControlJustReleased(0, 73) then
                closeEditor()
                break
            end
            if IsDisabledControlJustReleased(0, 38) then
                TriggerServerEvent("p_policejob/server/trunks/save", {
                    coords = offsetCoords,
                    rotation = offsetRotation,
                    model = string.lower(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))),
                })
                Wait(1000)
                closeEditor()
                break
            end
            for _, control in ipairs(controls) do
                if IsDisabledControlJustReleased(0, control.key) then
                    control.get()
                    reattachPed()
                end
            end
            Wait(0)
        end
    end)
end

RegisterCommand("trunk_editor", function()
    Trunks:openEditor()
end)

RegisterCommand("entertrunk", function()
    local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 5.0, true)
    if not vehicle or vehicle == 0 then
        return
    end
    if not Trunks:canInteract(vehicle, true) then
        return
    end
    Trunks:enter(vehicle)
end)

RegisterCommand("exittrunk", function()
    if not Trunks.isActive then
        return
    end
    Trunks:exit()
end)
