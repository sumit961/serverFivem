if not Config or not Config.Wardrobe or not Config.Wardrobe.Enabled then
    return
end

local PREVIEW_COORDS = vector4(0.0, 0.0, -100.0, 0.0)

Wardrobe = {
    isOpen = false,
    previewPed = nil,
    previewCam = nil,
    currentGender = nil,
    previewActive = false,
}

function Wardrobe.startPreview(self)
    if not self.previewPed or not DoesEntityExist(self.previewPed) then
        return
    end
    self.previewActive = true
    local camOffset = vector3(0.0, 1.8, 0.1)
    local camCoords = vector3(
        PREVIEW_COORDS.x + camOffset.x,
        PREVIEW_COORDS.y + camOffset.y,
        PREVIEW_COORDS.z + camOffset.z
    )
    self.previewCam = CreateCamWithParams(
        "DEFAULT_SCRIPTED_CAMERA",
        camCoords.x, camCoords.y, camCoords.z,
        0.0, 0.0, 0.0, 30.0, false, 0
    )
    PointCamAtEntity(self.previewCam, self.previewPed, 0.0, 0.0, 0.2, true)
    SetCamActive(self.previewCam, true)
    RenderScriptCams(true, false, 0, true, true)
    Citizen.CreateThread(function()
        local heading = 0.0
        while self.previewActive do
            if not self.previewPed or not DoesEntityExist(self.previewPed) then
                break
            end
            heading = heading + 0.5
            if heading > 360.0 then
                heading = 0.0
            end
            SetEntityHeading(self.previewPed, heading)
            Citizen.Wait(0)
        end
    end)
end

function Wardrobe.deletePreviewPed(self)
    self.previewActive = false
    if self.previewCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(self.previewCam, false)
        self.previewCam = nil
    end
    if self.previewPed and DoesEntityExist(self.previewPed) then
        DeleteEntity(self.previewPed)
    end
    self.previewPed = nil
end

function Wardrobe.destroyPreview(self)
    self:deletePreviewPed()
end

function Wardrobe.open(self)
    if self.isOpen then
        return
    end
    local config = lib.callback.await("p_policejob/wardrobe/getConfig", false)
    if not config then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return
    end
    self.currentGender = Editable.getPlayerGender()
    local outfits = lib.callback.await("p_policejob/wardrobe/getOutfits", false, self.currentGender)
    self.isOpen = true
    SendNUIMessage({
        action = "setWardrobeConfig",
        data = config,
    })
    SendNUIMessage({
        action = "setWardrobeOutfits",
        data = outfits or {},
    })
    SendNUIMessage({
        action = "setVisibleWardrobe",
        data = true,
    })
    SetNuiFocus(true, true)
end

function Wardrobe.close(self)
    if not self.isOpen then
        return
    end
    self.isOpen = false
    self:destroyPreview()
    SendNUIMessage({
        action = "setVisibleWardrobe",
        data = false,
    })
    SetNuiFocus(false, false)
end

RegisterNUICallback("hideFrame", function(data, cb)
    if data and data.name == "setVisibleWardrobe" then
        Wardrobe:close()
    end
    cb("ok")
end)

RegisterNUICallback("wardrobe:create", function(data, cb)
    local success, skin = pcall(function()
        return Bridge.Appearance.fetchCurrentSkin()
    end)
    if not success or not skin then
        cb({ success = false, error = "Could not get player skin" })
        Bridge.Notify.showNotify(locale("skin_error"), "error")
        return
    end
    data.skin = skin
    local result = lib.callback.await("p_policejob/wardrobe/create", false, data)
    if not result or not result.success then
        Bridge.Notify.showNotify(result and result.error or locale("no_access"), "error")
    end
    cb(result or { success = false })
end)

RegisterNUICallback("wardrobe:delete", function(data, cb)
    local result = lib.callback.await("p_policejob/wardrobe/delete", false, data)
    if not result or not result.success then
        Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    cb(result or { success = false })
end)

exports("OpenWardrobe", function()
    Wardrobe:open()
end)

RegisterCommand("wardrobe", function()
    Wardrobe:open()
end, false)
