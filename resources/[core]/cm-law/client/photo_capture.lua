-- cm-law/client/photo_capture.lua
-- Freeze + close-up camera used while server/photos.lua's LawCapturePhoto
-- screenshots THIS client's own screen. Modeled on
-- embedded/police/client/cinematics.lua's booking-mugshot freeze/camera
-- handling, simplified and generalized (no cinematic banner UI) since this
-- also runs for a self-capture (officer duty photo, incident scene photo)
-- and not only the arrest flow.

local active, camera, wasFrozen = false, nil, false

local function endCapture()
    if not active then return end
    active = false
    if camera then RenderScriptCams(false, false, 0, true, true); DestroyCam(camera, false); camera = nil end
    local ped = PlayerPedId()
    if not wasFrozen then FreezeEntityPosition(ped, false) end
    DisplayRadar(true)
end

RegisterNetEvent('cm-law:client:preparePhotoCapture', function(duration)
    local ped = PlayerPedId()
    if active or IsEntityDead(ped) then return end
    active = true
    local ok, frozen = pcall(IsEntityPositionFrozen, ped); wasFrozen = ok and frozen == true
    FreezeEntityPosition(ped, true)
    DisplayRadar(false)
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.04)
    local forward = GetEntityForwardVector(ped)
    camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(camera, head.x + forward.x * 1.1, head.y + forward.y * 1.1, head.z + 0.02)
    PointCamAtCoord(camera, head.x, head.y, head.z)
    SetCamFov(camera, 32.0)
    SetCamActive(camera, true)
    RenderScriptCams(true, false, 0, true, true)
    local deadline = GetGameTimer() + math.min(5000, math.max(1000, tonumber(duration) or 3000))
    CreateThread(function()
        while active and GetGameTimer() < deadline do HideHudAndRadarThisFrame(); Wait(0) end
    end)
end)

RegisterNetEvent('cm-law:client:endPhotoCapture', endCapture)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then endCapture() end
end)
