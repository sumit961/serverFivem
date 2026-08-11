Base = {
    tabletState = false,
    antiSpam = GetGameTimer(),
    tabletObjects = {},
}

function Base.exportHandler(self, resourceName, exportName, handler)
    AddEventHandler(("__cfx_export_%s_%s"):format(resourceName, exportName), function(setCB)
        setCB(handler)
    end)
end

exports("isOpen", function()
    return Base.tabletState
end)

Base:exportHandler("piotreq_gpt", "OpenGPT", function()
    Base:OpenMDT()
end)

RegisterNetEvent("piotreq_gpt:OpenGPT", function()
    Base:OpenMDT()
end)

RegisterNUICallback("loaded", function(_, cb)
    CreateThread(function()
        Wait(1000)
        while not (Bridge and Bridge.Config and Bridge.Config.Language and locale) do
            Wait(100)
        end
        local uiLocales = {}
        for key, value in pairs(lib.getLocales()) do
            if key:find("ui_") then
                uiLocales[key:gsub("ui_", "")] = value
            end
        end
        for key, value in pairs(Config.Dispatch.keybinds) do
            uiLocales["keybind_" .. key] = value
        end
        SendNUIMessage({
            action = "init",
            data = { locales = uiLocales },
        })
    end)
    cb(1)
end)

AddStateBagChangeHandler("isMdtOpen", nil, function(bagName, _, value, _, replicated)
    if replicated then
        return
    end
    local playerId = GetPlayerFromStateBagName(bagName)
    if playerId == 0 then
        return
    end
    local ped = GetPlayerPed(playerId)
    local serverId = GetPlayerServerId(playerId)
    if not value then
        local tabletObject = Base.tabletObjects[serverId]
        if tabletObject and DoesEntityExist(tabletObject) then
            DeleteEntity(tabletObject)
            Base.tabletObjects[serverId] = nil
        end
        if cache.serverId == serverId then
            StopAnimTask(ped, "amb@world_human_seat_wall_tablet@female@base", "base", 2.0, 2.0, -1, 50, 0, false, false, false)
        end
        return
    end
    Wait(1)
    local model = lib.requestModel("prop_cs_tablet")
    local tabletObject = CreateObject(model, GetEntityCoords(ped), false, false, false)
    local boneIndex = GetPedBoneIndex(ped, 57005)
    AttachEntityToEntity(
        tabletObject, ped, boneIndex,
        0.17, 0.1, -0.13, 20.0, 180.0, 180.0,
        true, true, false, true, 1, true
    )
    SetModelAsNoLongerNeeded(model)
    Base.tabletObjects[serverId] = tabletObject
    if serverId == cache.serverId then
        local animDict = lib.requestAnimDict("amb@world_human_seat_wall_tablet@female@base")
        TaskPlayAnim(ped, animDict, "base", 2.0, 2.0, -1, 50, 0, false, false, false)
        RemoveAnimDict(animDict)
    end
end)

function Base.ensureBridge()
    if Bridge and Bridge.Framework then
        return Bridge
    end

    while GetResourceState('p_bridge') ~= 'started' do
        Wait(100)
    end

    while not (Bridge and Bridge.Framework) do
        local ok, bridge = pcall(function()
            return exports.p_bridge:getObject()
        end)

        if ok and bridge then
            Bridge = bridge
        end

        if Bridge and Bridge.Framework then
            break
        end

        Wait(100)
    end

    return Bridge
end

function Base.getMdtTheme(self)
    local bridge = self:ensureBridge()
    if not bridge or not bridge.Framework then
        return nil
    end

    local job = bridge.Framework.fetchPlayerJob()
    local departmentKey = job and job.name or nil
    return Config.Departments[departmentKey] or nil
end

function Base.OpenMDT(self)
    local bridge = self:ensureBridge()
    if not bridge or not bridge.Framework then
        print('^1[p_mdt] Bridge is not loaded. Ensure p_bridge starts before p_mdt.^0')
        return
    end

    if bridge and bridge.Config and bridge.Config.Debug then
        lib.print.info("Attempting to open MDT", self.tabletState, self.antiSpam, GetGameTimer())
    end
    if self.tabletState or self.antiSpam > GetGameTimer() then
        return
    end
    if Bridge and Bridge.Config and Bridge.Config.Debug then
        lib.print.info("Passed initial checks for opening MDT", Config.MDT.canOpenMDT())
    end
    if not Config.MDT.canOpenMDT() then
        Bridge.Notify.showNotify(locale("you_cant_open_mdt"), "error")
        return
    end
    self.antiSpam = GetGameTimer() + 1000
    local theme = self:getMdtTheme()
    if Bridge and Bridge.Config and Bridge.Config.Debug then
        lib.print.info("Fetched MDT theme for opening MDT", theme)
    end
    if not theme then
        Bridge.Notify.showNotify(locale("you_are_not_allowed"), "error")
        return
    end
    local mdtData = lib.callback.await("p_mdt/server/getMDTData", false, "dashboard")
    if Bridge and Bridge.Config and Bridge.Config.Debug then
        lib.print.info("MDT data fetched for opening MDT", mdtData)
    end
    self.tabletState = true
    LocalPlayer.state:set("isMdtOpen", true, true)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "setVisibleApp", data = true })
    mdtData.theme = theme
    if mdtData.units then
        local sanitizedUnits = {}
        for index, unit in pairs(mdtData.units) do
            local location
            if unit.coords then
                location = GetStreetNameFromHashKey(GetStreetNameAtCoord(unit.coords.x, unit.coords.y, unit.coords.z))
            end
            if not location then
                location = locale("no_data")
            end
            sanitizedUnits[index] = {
                id = unit.id,
                name = unit.name,
                grade = unit.grade,
                callsign = unit.callsign,
                status = unit.status,
                coords = unit.coords,
                avatarUrl = unit.avatarUrl,
                location = location,
            }
        end
        mdtData.units = sanitizedUnits
    end
    mdtData.chargeTypes = Config.MDT.chargeTypes
    mdtData.dojAvailable = mdtData.dojAvailable or false
    SendNUIMessage({ action = "mdt/load", data = mdtData })
    CreateThread(function()
        while self.tabletState do
            Wait(2500)
            InvalidateIdleCam()
            if not Config.MDT.canOpenMDT() then
                self:CloseMDT()
                break
            end
        end
    end)
end

exports("OpenMDT", function()
    Base:OpenMDT()
end)

RegisterNetEvent("p_mdt/openMDT", function()
    Base:OpenMDT()
end)

CreateThread(function()
    while not Config do
        Wait(100)
    end
    if type(Config.MDT.commandName) == "string" then
        RegisterCommand(Config.MDT.commandName, function()
            Base:OpenMDT()
        end, false)
    end
end)

function Base.CloseMDT(self)
    if not self.tabletState then
        return
    end
    self.antiSpam = GetGameTimer() + 1000
    SendNUIMessage({ action = "setVisibleApp", data = false })
    self.tabletState = false
    LocalPlayer.state:set("isMdtOpen", false, true)
    SetNuiFocus(false, false)
end

exports("CloseMDT", function()
    Base:CloseMDT()
end)

RegisterNetEvent("p_mdt/closeMDT", function()
    Base:CloseMDT()
end)

RegisterNUICallback("mdt/main/updatePlayerData", function(data, cb)
    TriggerServerEvent("p_mdt/server/updatePlayerData", data)
    cb(1)
end)

RegisterNUICallback("mdt/setClipboard", function(data, cb)
    lib.setClipboard(data)
    cb(1)
end)

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleApp" then
        Base:CloseMDT()
    end
    cb(1)
end)

RegisterNUICallback("mdt/bodycams/fetch", function(_, cb)
    local bodycams = lib.callback.await("p_mdt/server/getMDTData", false, "bodycams")
    for _, bodycam in pairs(bodycams or {}) do
        bodycam.location = GetStreetNameFromHashKey(
            GetStreetNameAtCoord(bodycam.coords.x, bodycam.coords.y, bodycam.coords.z)
        )
    end
    cb(bodycams)
end)

RegisterNUICallback("mdt/bodycam/view", function(data, cb)
    if data.id == cache.serverId then
        Bridge.Notify.showNotify(locale("cannot_view_own_bodycam"), "error")
        cb(1)
        return
    end
    if Base.antiSpam > GetGameTimer() then
        cb(1)
        return
    end
    Base:CloseMDT()
    Wait(500)
    exports.p_policejob:StartWatchBodyCam(data.id)
    cb(1)
end)

RegisterNUICallback("mdt/base/search", function(data, cb)
    local results = lib.callback.await("p_mdt/server/base/globalSearch", false, data)
    for _, vehicle in pairs(results.vehicles or {}) do
        local displayName = GetDisplayNameFromVehicleModel(vehicle.model)
        local labelText = GetLabelText(displayName)
        vehicle.title = (labelText ~= "NULL" and labelText) or displayName
        vehicle.fields[#vehicle.fields + 1] = ("Model: %s"):format(vehicle.title)
    end
    cb(results)
end)

RegisterNUICallback("mdt/bulletin/create", function(data, cb)
    TriggerServerEvent("p_mdt/server/bulletin/create", data)
    cb(1)
end)

RegisterNUICallback("mdt/bulletin/edit", function(data, cb)
    TriggerServerEvent("p_mdt/server/bulletin/edit", data)
    cb(1)
end)

RegisterNUICallback("mdt/bulletin/delete", function(data, cb)
    TriggerServerEvent("p_mdt/server/bulletin/delete", data)
    cb(1)
end)

exports("GetConfig", function()
    return Config
end)

function Base.sanitizeForNui(self, data, convertNumericKeys)
    if type(data) ~= "table" then
        return data
    end
    local sanitized = {}
    for key, value in pairs(data) do
        if convertNumericKeys and type(key) == "number" then
            key = tostring(key)
        end
        if value == nil then
            sanitized[key] = ""
        elseif type(value) == "table" then
            sanitized[key] = self:sanitizeForNui(value, convertNumericKeys)
        else
            sanitized[key] = value
        end
    end
    return sanitized
end
