while not Config or not Config.Traffic do
    Citizen.Wait(500)
end

if not Config.Traffic.enabled then
    return
end

Traffic = {
    activeZones = {},
    editing = false,
    markerData = {},
}

function hasTrafficAccess()
    local job = Bridge.Framework.fetchPlayerJob()
    if not job or not Config.Jobs[job.name] then
        return false
    end
    if job.grade < Config.Jobs[job.name] then
        return false
    end
    return true
end

function cleanupNearbyZones(coords)
    for zoneId, zone in pairs(Traffic.activeZones) do
        if zone and #(coords - zone.coords) <= zone.radius then
            RemoveSpeedZone(zone.speedZone)
            RemoveBlip(zone.blip)
            if zone.radiusBlip then
                RemoveBlip(zone.radiusBlip)
            end
            Traffic.activeZones[zoneId] = nil
        end
    end
end

function createTrafficBlips(coords, name, radius)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.Traffic.BlipSettings.sprite)
    SetBlipColour(blip, Config.Traffic.BlipSettings.color)
    SetBlipScale(blip, Config.Traffic.BlipSettings.scale)
    SetBlipRoute(blip, false)
    if Config.Traffic.BlipSettings.showLabel then
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(name)
        EndTextCommandSetBlipName(blip)
    end
    local radiusBlip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
    SetBlipColour(radiusBlip, Config.Traffic.BlipSettings.color)
    SetBlipAlpha(radiusBlip, 50)
    return blip, radiusBlip
end

function drawTrafficMarker(coords, radius)
    local marker = Config.Traffic.MarkerSettings
    DrawMarker(
        marker.type,
        coords.x, coords.y, coords.z,
        0.0, 0.0, 0.0,
        0.0, 180.0, 0.0,
        radius * 2, radius * 2, 10.0,
        marker.color.r, marker.color.g, marker.color.b, marker.color.a,
        false, true, 2, nil, nil, false
    )
end

function Traffic.createZone(self, _, radius)
    if not hasTrafficAccess() then
        Bridge.Notify.showNotify(locale("traffic_no_access"), "error")
        return
    end
    radius = radius or Config.Traffic.DefaultRadius
    local input = lib.inputDialog(locale("traffic_dialog_create_zone"), {
        {
            type = "input",
            label = locale("traffic_dialog_name"),
            required = true,
            default = "Zone_" .. tostring(math.floor(GetGameTimer() % 10000)),
        },
        {
            type = "number",
            label = locale("traffic_dialog_speed"),
            min = 0,
            default = 30,
            required = true,
        },
    })
    if not input then
        return
    end
    local zoneName = input[1]
    local speedLimit = input[2]
    local coords = GetEntityCoords(cache.ped)
    cleanupNearbyZones(coords)
    local zoneId = #self.activeZones + 1
    local speedZone = AddSpeedZoneForCoord(coords.x, coords.y, coords.z, radius, speedLimit, false)
    local blip, radiusBlip = createTrafficBlips(coords, zoneName, radius)
    self.activeZones[zoneId] = {
        id = zoneId,
        name = zoneName,
        coords = coords,
        radius = radius,
        speedLimit = speedLimit,
        speedZone = speedZone,
        blip = blip,
        radiusBlip = radiusBlip,
        createdAt = GetGameTimer(),
    }
    Bridge.Notify.showNotify(locale("traffic_zone_created", zoneName), "success")
    return zoneId
end

function Traffic.editZoneRadius(self, zoneId)
    if not hasTrafficAccess() then
        Bridge.Notify.showNotify(locale("traffic_no_access"), "error")
        return
    end
    local zone = self.activeZones[zoneId]
    if not zone then
        Bridge.Notify.showNotify(locale("traffic_zone_not_found"), "error")
        return
    end
    local input = lib.inputDialog(locale("traffic_edit_radius"), {
        {
            type = "number",
            label = locale("traffic_dialog_radius"),
            min = Config.Traffic.MinRadius,
            max = Config.Traffic.MaxRadius,
            default = zone.radius,
            required = true,
        },
    })
    if not input then
        return
    end
    RemoveSpeedZone(zone.speedZone)
    Citizen.Wait(10)
    local newRadius = input[1]
    zone.speedZone = AddSpeedZoneForCoord(
        zone.coords.x, zone.coords.y, zone.coords.z,
        newRadius, zone.speedLimit, false
    )
    zone.radius = newRadius
    if zone.radiusBlip then
        RemoveBlip(zone.radiusBlip)
        local _, radiusBlip = createTrafficBlips(zone.coords, zone.name, newRadius)
        zone.radiusBlip = radiusBlip
    end
    Bridge.Notify.showNotify(locale("traffic_radius_updated", newRadius), "success")
end

function Traffic.editZoneSpeed(self, zoneId)
    if not hasTrafficAccess() then
        Bridge.Notify.showNotify(locale("traffic_no_access"), "error")
        return
    end
    local zone = self.activeZones[zoneId]
    if not zone then
        Bridge.Notify.showNotify(locale("traffic_zone_not_found"), "error")
        return
    end
    local input = lib.inputDialog(locale("traffic_edit_speed"), {
        {
            type = "number",
            label = locale("traffic_dialog_speed"),
            min = 0,
            default = zone.speedLimit,
            required = true,
        },
    })
    if not input then
        return
    end
    RemoveSpeedZone(zone.speedZone)
    Citizen.Wait(10)
    local newSpeed = input[1]
    zone.speedZone = AddSpeedZoneForCoord(
        zone.coords.x, zone.coords.y, zone.coords.z,
        zone.radius, newSpeed, false
    )
    zone.speedLimit = newSpeed
    Bridge.Notify.showNotify(locale("traffic_speed_updated", newSpeed), "success")
end

function Traffic.removeZone(self, zoneId)
    if not hasTrafficAccess() then
        Bridge.Notify.showNotify(locale("traffic_no_access"), "error")
        return
    end
    local zone = self.activeZones[zoneId]
    if not zone then
        Bridge.Notify.showNotify(locale("traffic_zone_not_found"), "error")
        return
    end
    RemoveSpeedZone(zone.speedZone)
    RemoveBlip(zone.blip)
    if zone.radiusBlip then
        RemoveBlip(zone.radiusBlip)
    end
    self.activeZones[zoneId] = nil
    Bridge.Notify.showNotify(locale("traffic_zone_removed", zone.name), "success")
end

function Traffic.listZones(self)
    if not hasTrafficAccess() then
        Bridge.Notify.showNotify(locale("traffic_no_access"), "error")
        return
    end
    local options = {}
    for zoneId, zone in pairs(self.activeZones) do
        if zone then
            options[#options + 1] = {
                title = zone.name,
                description = locale("traffic_zone_desc"):format(zone.speedLimit, zone.radius),
                args = { zoneId = zoneId },
                icon = "fa-solid fa-road",
            }
        end
    end
    if #options == 0 then
        Bridge.Notify.showNotify(locale("traffic_no_zones"), "warning")
        return
    end
    lib.registerContext({
        id = "traffic_zones_list",
        title = locale("traffic_active_zones"),
        options = options,
        onSelect = function(selected)
            self:showZoneMenu(selected.args.zoneId)
        end,
    })
    lib.showContext("traffic_zones_list")
end

function Traffic.showZoneMenu(self, zoneId)
    local zone = self.activeZones[zoneId]
    if not zone then
        return
    end
    lib.registerContext({
        id = "traffic_zone_menu_" .. zoneId,
        title = zone.name,
        menu = "traffic_zones_list",
        options = {
            {
                title = locale("traffic_edit_radius"),
                description = locale("traffic_edit_radius_desc"):format(zone.radius),
                icon = "fa-solid fa-expand",
                onSelect = function()
                    self:editZoneRadius(zoneId)
                    Citizen.Wait(500)
                    self:showZoneMenu(zoneId)
                end,
            },
            {
                title = locale("traffic_edit_speed"),
                description = locale("traffic_edit_speed_desc"):format(zone.speedLimit),
                icon = "fa-solid fa-gauge",
                onSelect = function()
                    self:editZoneSpeed(zoneId)
                    Citizen.Wait(500)
                    self:showZoneMenu(zoneId)
                end,
            },
            {
                title = locale("traffic_goto_zone"),
                icon = "fa-solid fa-map-pin",
                onSelect = function()
                    local heading = GetEntityHeading(cache.ped)
                    SetEntityCoords(cache.ped, zone.coords.x, zone.coords.y, zone.coords.z, false, false, false, false)
                    SetEntityHeading(cache.ped, heading)
                    Bridge.Notify.showNotify(locale("traffic_zone_teleported"):format(zone.name), "success")
                end,
            },
            {
                title = locale("traffic_delete_zone"),
                description = locale("traffic_delete_zone_desc"),
                icon = "fa-solid fa-trash",
                onSelect = function()
                    self:removeZone(zoneId)
                    lib.hideContext()
                end,
            },
        },
    })
    lib.showContext("traffic_zone_menu_" .. zoneId)
end

function Traffic.applyPreset(self, presetIndex)
    if not hasTrafficAccess() then
        Bridge.Notify.showNotify(locale("traffic_no_access"), "error")
        return
    end
    local preset = Config.Traffic.Presets[presetIndex]
    if not preset then
        Bridge.Notify.showNotify(locale("traffic_preset_not_found"), "error")
        return
    end
    local zoneName = preset.label .. "_" .. tostring(math.floor(GetGameTimer() % 10000))
    local coords = GetEntityCoords(cache.ped)
    cleanupNearbyZones(coords)
    local zoneId = #self.activeZones + 1
    local speedZone = AddSpeedZoneForCoord(coords.x, coords.y, coords.z, preset.radius, preset.speed, false)
    local blip, radiusBlip = createTrafficBlips(coords, zoneName, preset.radius)
    self.activeZones[zoneId] = {
        id = zoneId,
        name = zoneName,
        coords = coords,
        radius = preset.radius,
        speedLimit = preset.speed,
        speedZone = speedZone,
        blip = blip,
        radiusBlip = radiusBlip,
        createdAt = GetGameTimer(),
    }
    Bridge.Notify.showNotify(locale("traffic_preset_applied", preset.label), "success")
    return zoneId
end

function Traffic.showPresetsMenu(self)
    if not hasTrafficAccess() then
        Bridge.Notify.showNotify(locale("traffic_no_access"), "error")
        return
    end
    local options = {}
    for presetIndex, preset in ipairs(Config.Traffic.Presets) do
        options[#options + 1] = {
            title = preset.label,
            description = locale("traffic_zone_desc"):format(preset.speed, preset.radius),
            icon = "fa-solid fa-sliders",
            onSelect = function()
                self:applyPreset(presetIndex)
            end,
        }
    end
    lib.registerContext({
        id = "traffic_presets_menu",
        title = locale("traffic_presets_title"),
        options = options,
    })
    lib.showContext("traffic_presets_menu")
end

function Traffic.showMainMenu(self)
    if not hasTrafficAccess() then
        Bridge.Notify.showNotify(locale("traffic_no_access"), "error")
        return
    end
    lib.registerContext({
        id = "traffic_main_menu",
        title = locale("traffic_menu_title"),
        options = {
            {
                title = locale("traffic_create_zone"),
                description = locale("traffic_create_zone_desc"),
                icon = "fa-solid fa-plus",
                onSelect = function()
                    self:createZone()
                end,
            },
            {
                title = locale("traffic_apply_preset"),
                description = locale("traffic_apply_preset_desc"),
                icon = "fa-solid fa-star",
                onSelect = function()
                    self:showPresetsMenu()
                end,
            },
            {
                title = locale("traffic_manage_zones"),
                description = locale("traffic_manage_zones_desc"),
                icon = "fa-solid fa-sliders",
                onSelect = function()
                    self:listZones()
                end,
            },
            {
                title = locale("traffic_clear_all"),
                description = locale("traffic_clear_all_desc"),
                icon = "fa-solid fa-ban",
                onSelect = function()
                    for zoneId in pairs(self.activeZones) do
                        self:removeZone(zoneId)
                    end
                    Bridge.Notify.showNotify(locale("traffic_zones_cleared"), "success")
                    lib.hideContext()
                end,
            },
        },
    })
    lib.showContext("traffic_main_menu")
end

RegisterCommand("trafficmenu", function()
    Traffic:showMainMenu()
end, false)

TriggerEvent("chat:addSuggestion", "/trafficmenu", "Open traffic management menu", {})

exports("createTrafficZone", function(name, radius, speedLimit)
    if not hasTrafficAccess() then
        return nil
    end
    local coords = GetEntityCoords(cache.ped)
    radius = radius or Config.Traffic.DefaultRadius
    speedLimit = speedLimit or 0.0
    local zoneId = #Traffic.activeZones + 1
    local speedZone = AddSpeedZoneForCoord(coords.x, coords.y, coords.z, radius, speedLimit, false)
    local blip, radiusBlip = createTrafficBlips(coords, name or "Zone", radius)
    Traffic.activeZones[zoneId] = {
        id = zoneId,
        name = name or ("Zone_" .. zoneId),
        coords = coords,
        radius = radius,
        speedLimit = speedLimit,
        speedZone = speedZone,
        blip = blip,
        radiusBlip = radiusBlip,
        createdAt = GetGameTimer(),
    }
    return zoneId
end)

exports("removeTrafficZone", function(zoneId)
    Traffic:removeZone(zoneId)
end)

exports("updateTrafficZone", function(zoneId, updateRadius, updateSpeed)
    if not Traffic.activeZones[zoneId] then
        return false
    end
    if updateRadius then
        Traffic:editZoneRadius(zoneId)
    end
    if updateSpeed then
        Traffic:editZoneSpeed(zoneId)
    end
    return true
end)

exports("getActiveZones", function()
    return Traffic.activeZones
end)

exports("getZoneInfo", function(zoneId)
    return Traffic.activeZones[zoneId]
end)

exports("applyTrafficPreset", function(presetIndex)
    return Traffic:applyPreset(presetIndex)
end)
