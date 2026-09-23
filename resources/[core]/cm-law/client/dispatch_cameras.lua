-- cm-law/client/dispatch_cameras.lua
-- Free-placement CCTV dispatch cameras: aim with the gameplay camera and a
-- world raycast (matches the reference resource's described mechanic, but
-- re-implemented cleanly rather than copied from that untrusted source), then
-- confirm to place. Viewing uses a scripted camera with mouse-look and
-- scroll-zoom -- pure native rendering, no NUI page needed for the feed
-- itself (matches cm-prison's own native-drawn jail HUD convention).

local function notify(message, kind)
    TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'inform')
end

local function legalState()
    local state = LocalPlayer.state.cmLegalOrg
    return type(state) == 'table' and state or nil
end

-- Client-side is a UX precheck only; server/dispatch_cameras.lua is the
-- authority on every permission and distance check.
local function canManageCameras()
    local state = legalState()
    return type(state) == 'table' and state.onDuty == true and state.suspended ~= true
end

local function raycastFromCamera(maxDistance)
    local camCoords, camRot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local radX, radZ = math.rad(camRot.x), math.rad(camRot.z)
    local direction = vector3(
        -math.sin(radZ) * math.abs(math.cos(radX)),
        math.cos(radZ) * math.abs(math.cos(radX)),
        math.sin(radX)
    )
    local destination = camCoords + direction * maxDistance
    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, destination.x, destination.y, destination.z, 1, PlayerPedId(), 0)
    local _, hit, endCoords = GetShapeTestResult(ray)
    return hit == 1 and endCoords or destination
end

local placing = false

local function placementMode()
    if placing then return end
    if not canManageCameras() then return notify('You must be on duty to place a dispatch camera.', 'error') end
    placing = true
    notify('Aim and press E to place, Backspace to cancel.', 'inform')
    CreateThread(function()
        while placing do
            DisableControlAction(0, 24, true) -- attack
            DisableControlAction(0, 25, true) -- aim
            local point = raycastFromCamera(40.0)
            DrawMarker(28, point.x, point.y, point.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.15, 0.15, 0.15, 60, 200, 255, 160, false, true, 2, false, nil, nil, false)
            if IsControlJustPressed(0, 38) then -- E
                placing = false
                local heading = GetGameplayCamRot(2).z
                local input = lib.inputDialog('Place Dispatch Camera', { { type = 'input', label = 'Camera label', required = false, max = 64 } })
                if input then
                    local ok, message = lib.callback.await('cm-law:server:createDispatchCamera', false, point.x, point.y, point.z, heading, input[1])
                    notify(message, ok and 'success' or 'error')
                end
            elseif IsControlJustPressed(0, 177) then -- Backspace
                placing = false
                notify('Camera placement cancelled.', 'inform')
            end
            Wait(0)
        end
    end)
end

RegisterCommand('lawplacecam', placementMode, false)

local viewing = false

local function exitCameraView()
    if not viewing then return end
    viewing = false
end

local function enterCameraView(camera)
    if viewing then return end
    viewing = true
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local fov, pitch, yaw = 50.0, 0.0, camera.heading or 0.0
    SetCamCoord(cam, camera.x, camera.y, camera.z + 0.3)
    SetCamRot(cam, 0.0, 0.0, yaw, 2)
    SetCamFov(cam, fov)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 300, true, true)
    DisplayRadar(false)
    CreateThread(function()
        while viewing do
            DisableAllControlActions(0)
            EnableControlAction(0, 177, true) -- allow Backspace/Esc to exit
            EnableControlAction(0, 200, true)
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) then exitCameraView() end
            local mouseX, mouseY = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
            yaw = yaw - mouseX * 4.0
            pitch = math.max(-70.0, math.min(70.0, pitch - mouseY * 3.0))
            local scrollUp, scrollDown = IsDisabledControlJustPressed(0, 241), IsDisabledControlJustPressed(0, 242)
            if scrollUp then fov = math.max(10.0, fov - 5.0) end
            if scrollDown then fov = math.min(80.0, fov + 5.0) end
            SetCamRot(cam, pitch, 0.0, yaw, 2)
            SetCamFov(cam, fov)
            SetTextFont(4); SetTextScale(0.0, 0.32); SetTextColour(60, 200, 255, 220); SetTextOutline()
            BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('CCTV · %s'):format(camera.label or 'Camera'))
            EndTextCommandDisplayText(0.015, 0.015)
            SetTextFont(4); SetTextScale(0.0, 0.24); SetTextColour(200, 220, 230, 200); SetTextOutline()
            BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName('Mouse to look · Scroll to zoom · Backspace to exit')
            EndTextCommandDisplayText(0.015, 0.045)
            Wait(0)
        end
    end)
    CreateThread(function()
        while viewing do Wait(200) end
        RenderScriptCams(false, true, 300, true, true)
        DisplayRadar(true)
        DestroyCam(cam, false)
    end)
end

RegisterCommand('lawviewcams', function()
    if not canManageCameras() then return notify('You must be on duty with dispatch access to view cameras.', 'error') end
    local cameras = lib.callback.await('cm-law:server:listDispatchCameras', false) or {}
    if #cameras == 0 then return notify('No dispatch cameras have been placed.', 'inform') end
    local options = {}
    for _, camera in ipairs(cameras) do
        options[#options + 1] = { title = camera.label, description = ('%s'):format(tostring(camera.organizationId or ''):upper()), onSelect = function() enterCameraView(camera) end }
    end
    lib.registerContext({ id = 'law_dispatch_cameras', title = 'Dispatch Cameras', options = options })
    lib.showContext('law_dispatch_cameras')
end, false)

RegisterCommand('lawremovecam', function()
    if not canManageCameras() then return end
    local cameras = lib.callback.await('cm-law:server:listDispatchCameras', false) or {}
    if #cameras == 0 then return notify('No dispatch cameras have been placed.', 'inform') end
    local options = {}
    for _, camera in ipairs(cameras) do
        options[#options + 1] = { title = camera.label, description = ('%s'):format(tostring(camera.organizationId or ''):upper()), onSelect = function()
            CreateThread(function()
                local ok, message = lib.callback.await('cm-law:server:deleteDispatchCamera', false, camera.id)
                notify(message, ok and 'success' or 'error')
            end)
        end }
    end
    lib.registerContext({ id = 'law_dispatch_cameras_remove', title = 'Remove Dispatch Camera', options = options })
    lib.showContext('law_dispatch_cameras_remove')
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    placing, viewing = false, false
end)
