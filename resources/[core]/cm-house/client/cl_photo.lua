-- ============================================================
--  cm-house | cl_photo.lua
--  Frame the shot; the server captures and saves the rendered frame locally.
--
--  The client owns the scripted camera and hides local UI/ped. screenshot-basic
--  is invoked from the server and writes the approved frame under
--  cm-house/html/img/houses. No webhook or client-supplied file path is used.
-- ============================================================

local Cam = {
    handle = nil,
    active = false,
    onDone = nil,     -- called with (camTable) when H is pressed
}

-- ------------------------------------------------------------
--  Free-fly camera
-- ------------------------------------------------------------
function StartPhotoCam(startCam, door, onDone)
    if Cam.active then return end

    local h = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    if startCam then
        -- A retake starts where it was last framed.
        SetCamCoord(h, startCam.x, startCam.y, startCam.z)
        SetCamRot(h, startCam.rx or -10.0, 0.0, startCam.rz or 0.0, 2)
        SetCamFov(h, startCam.fov or 55.0)
    else
        -- A first capture starts backed off from the front door, looking at it.
        local d = door
        local rad = math.rad((d.h or 0.0) + 180.0)
        SetCamCoord(h, d.x + math.sin(rad) * -8.0, d.y + math.cos(rad) * -8.0, d.z + 3.0)
        PointCamAtCoord(h, d.x, d.y, d.z + 1.0)
        SetCamFov(h, 55.0)
    end

    RenderScriptCams(true, false, 0, true, true)

    Cam.handle = h
    Cam.active = true
    Cam.onDone = onDone

    CreateThread(function()
        while Cam.active do
            local c   = GetCamCoord(h)
            local rot = GetCamRot(h, 2)
            local fov = GetCamFov(h)

            -- The world must be streamed in around the CAMERA, not the player,
            -- or you photograph a void where the house should be.
            SetFocusPosAndVel(c.x, c.y, c.z, 0.0, 0.0, 0.0)

            -- look
            local mx = GetDisabledControlNormal(0, 1) * 8.0
            local my = GetDisabledControlNormal(0, 2) * 8.0
            local nz = rot.z - mx
            local nx = math.max(-89.0, math.min(89.0, rot.x - my))
            SetCamRot(h, nx, 0.0, nz, 2)

            -- move, relative to where the camera is pointing
            local rad = math.rad(nz)
            local fwd = vector3(-math.sin(rad), math.cos(rad), 0.0)
            local rgt = vector3(math.cos(rad), math.sin(rad), 0.0)
            local speed = IsDisabledControlPressed(0, 21) and 1.1 or 0.3

            local mv = vector3(0.0, 0.0, 0.0)
            if IsDisabledControlPressed(0, 32) then mv = mv + fwd end
            if IsDisabledControlPressed(0, 33) then mv = mv - fwd end
            if IsDisabledControlPressed(0, 34) then mv = mv - rgt end
            if IsDisabledControlPressed(0, 35) then mv = mv + rgt end
            if IsDisabledControlPressed(0, 44) then mv = mv + vector3(0.0, 0.0, 1.0) end
            if IsDisabledControlPressed(0, 38) then mv = mv - vector3(0.0, 0.0, 1.0) end

            if #mv > 0.0 then
                SetCamCoord(h, c.x + mv.x * speed, c.y + mv.y * speed, c.z + mv.z * speed)
            end

            if IsDisabledControlJustPressed(0, 241) then SetCamFov(h, math.max(20.0, fov - 4.0)) end
            if IsDisabledControlJustPressed(0, 242) then SetCamFov(h, math.min(90.0, fov + 4.0)) end

            -- UI
            SetTextFont(4) SetTextScale(0.0, 0.55) SetTextColour(0, 220, 255, 255)
            SetTextCentre(true) SetTextEntry('STRING')
            AddTextComponentString('PROPERTY PHOTO')
            DrawText(0.5, 0.045)

            SetTextFont(4) SetTextScale(0.0, 0.38) SetTextColour(225, 240, 248, 210)
            SetTextCentre(true) SetTextEntry('STRING')
            AddTextComponentString('WASD move  ~c~|~s~  Q/E up-down  ~c~|~s~  SHIFT faster  ~c~|~s~  SCROLL zoom')
            DrawText(0.5, 0.088)

            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('~b~H~s~ take the photo   ~r~ESC~s~ cancel')
            EndTextCommandDisplayHelp(0, false, true, -1)

            HideHudAndRadarThisFrame()

            DisableAllControlActions(0)
            for _, ctrl in ipairs({ 1, 2, 21, 32, 33, 34, 35, 38, 44, 241, 242 }) do
                EnableControlAction(0, ctrl, true)
            end

            -- H
            local shoot = IsRawKeyReleased and IsRawKeyReleased(72)
                          or IsControlJustReleased(0, 74)
            if shoot then
                local fc = GetCamCoord(h)
                local fr = GetCamRot(h, 2)
                local cam = {
                    x  = tonumber(('%.3f'):format(fc.x)),
                    y  = tonumber(('%.3f'):format(fc.y)),
                    z  = tonumber(('%.3f'):format(fc.z)),
                    rx = tonumber(('%.2f'):format(fr.x)),
                    ry = 0.0,
                    rz = tonumber(('%.2f'):format(fr.z)),
                    fov = tonumber(('%.1f'):format(GetCamFov(h))),
                }
                local cb = Cam.onDone
                StopPhotoCam(true)   -- keep rendering: we are about to shoot
                if cb then cb(cam) end
                return
            end

            -- ESC
            local cancel = IsRawKeyReleased and IsRawKeyReleased(27)
                           or IsControlJustReleased(0, 322)
            if cancel then
                local cb = Cam.onDone
                StopPhotoCam(false)
                if cb then cb(nil) end
                return
            end

            Wait(0)
        end
    end)
end

--- keepRendering: leave the scripted cam up so the actual screenshot is taken
--- through it. The caller drops it once the frame is grabbed.
function StopPhotoCam(keepRendering)
    if not Cam.active then return end
    Cam.active = false

    if not keepRendering then
        DropPhotoCam()
    end
end

function DropPhotoCam()
    if Cam.handle then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(Cam.handle, false)
        Cam.handle = nil
    end
    ClearFocus()
    DisplayRadar(true)
end

-- ------------------------------------------------------------
--  Ask the server to capture and save the current rendered frame locally.
-- ------------------------------------------------------------
--- @param cfg { token, quality }
--- @param cam table
--- @param onDone fun(url:string|nil, err:string|nil)
function CaptureAndSave(cfg, cam, onDone)
    if GetResourceState('screenshot-basic') ~= 'started' then
        DropPhotoCam()
        onDone(nil, 'screenshot-basic is not running.')
        return
    end

    local ped = PlayerPedId()
    SetEntityVisible(ped, false, false)
    SetEntityLocallyInvisible(ped)
    DisplayRadar(false)

    for _ = 1, 6 do
        HideHudAndRadarThisFrame()
        Wait(0)
    end

    local capturePending = true
    CreateThread(function()
        while capturePending do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)

    -- The client sends only the one-shot token and sanitized camera framing.
    -- screenshot-basic writes the resulting frame directly into cm-house files.
    local callOk, ok, result = pcall(lib.callback.await,
        'cm-house:server:capturePhoto', false, cfg.token, cam)

    capturePending = false
    SetEntityVisible(ped, true, false)
    DisplayRadar(true)
    DropPhotoCam()

    if not callOk then
        onDone(nil, tostring(ok or 'Photo capture callback failed.'))
        return
    end
    if not ok then
        onDone(nil, tostring(result or 'Photo capture failed.'))
        return
    end
    onDone(result, nil)
end

-- Compatibility alias for older cm-house files that still call the previous
-- function name. New integrations should use CaptureAndSave.
CaptureAndUpload = CaptureAndSave
