-- ============================================================
--  cm-house | cl_admin.lua
--  /cmadmin -- manage every property, layout and garage.
--
--  Property photos are saved locally. The stored camera framing is also kept;
--  selecting a property can still preview or retake the exact exterior angle.
-- ============================================================

local open   = false
local cam    = nil
local preview = nil   -- layout points being previewed

local function parseGpsCoordinates(raw, heading)
    raw = tostring(raw or '')
    local values = {}
    for number in raw:gmatch('[-+]?%d+%.?%d*') do
        values[#values + 1] = tonumber(number)
    end
    if #values < 3 then return nil end
    local x, y, z = values[1], values[2], values[3]
    local h = tonumber(heading) or values[4] or 0.0
    if not x or not y or not z
        or math.abs(x) > 10000.0 or math.abs(y) > 10000.0
        or z < -1000.0 or z > 5000.0 then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0, h = h + 0.0 }
end

local function teleportToGps(coords)
    local ped = PlayerPedId()
    DoScreenFadeOut(250)
    local deadline = GetGameTimer() + 1500
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, coords.h or 0.0)

    local collisionDeadline = GetGameTimer() + 8000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < collisionDeadline do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(25)
    end
    DoScreenFadeIn(250)
end

local function askNewTemplateGps(kind)
    kind = kind == 'garage' and 'garage' or 'interior'
    local input = lib.inputDialog(kind == 'garage' and 'New garage location' or 'New interior location', {
        {
            type = 'input',
            label = 'GPS coordinates',
            description = 'Paste vector3(x, y, z), vector4(x, y, z, heading), or x, y, z.',
            placeholder = kind == 'garage' and '227.10, -998.10, -99.50, 180.0' or '152.11, -1004.32, -99.00, 165.0',
            required = true,
        },
        {
            type = 'number',
            label = 'Heading (optional)',
            description = 'Overrides the fourth pasted value.',
            required = false,
        },
    })
    if not input then return nil end
    return parseGpsCoordinates(input[1], input[2])
end

local function killCam()
    if not cam then return end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(cam, false)
    cam = nil
end

--- Fly the camera to a property's stored framing for preview/retake.
local function showPhoto(c)
    if not c then killCam() return end

    if not cam then
        cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    end
    SetCamCoord(cam, c.x, c.y, c.z)
    SetCamRot(cam, c.rx or -10.0, 0.0, c.rz or 0.0, 2)
    SetCamFov(cam, c.fov or 55.0)
    RenderScriptCams(true, true, 600, true, true)

    -- The house has to actually be streamed in, or the camera frames a void.
    SetFocusPosAndVel(c.x, c.y, c.z, 0.0, 0.0, 0.0)
end

local function closeAdmin()
    open = false
    killCam()
    ClearFocus()
    preview = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'adminClose' })
    DisplayRadar(true)
end

RegisterNetEvent('cm-house:client:openAdmin', function(openTab)
    if open then return end

    local data = lib.callback.await('cm-house:server:adminData', false)
    if not data then
        lib.notify({ description = 'You cannot manage properties.', type = 'error' })
        return
    end

    local allowedTabs = { houses = true, interiors = true, garages = true, recovery = true }
    data.openTab = allowedTabs[tostring(openTab or '')] and tostring(openTab) or 'houses'
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'adminOpen', data = data })
end)

--- Selecting a property in the list flies the camera to it.
RegisterNUICallback('admin:preview', function(d, cb)
    cb({})
    showPhoto(d.photoCam)
end)

RegisterNUICallback('admin:close', function(_, cb)
    cb({})
    closeAdmin()
end)

--- Add a new property: close the panel and hand straight to the wizard.
--- Layouts are not added here -- they are created by building the first
--- property of a kind, which is the whole point of the auto-template system.
RegisterNUICallback('admin:add', function(_, cb)
    cb({})
    closeAdmin()
    Wait(300)
    TriggerServerEvent('cm-house:server:startWizard')
end)

RegisterNUICallback('admin:action', function(d, cb)
    local ok, res = lib.callback.await('cm-house:server:adminAction', false,
        d.action, tonumber(d.houseId), d.arg)

    if d.action == 'goto' and ok then
        cb({ ok = true })
        closeAdmin()
        DoScreenFadeOut(400)
        while not IsScreenFadedOut() do Wait(0) end
        local ped = PlayerPedId()
        SetEntityCoords(ped, res.x, res.y, res.z, false, false, false, false)
        local t = GetGameTimer()
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() - t < 8000 do Wait(10) end
        DoScreenFadeIn(400)
        return
    end

    if ok then
        lib.notify({ description = type(res) == 'string' and res or 'Done.', type = 'success' })
        -- Refresh so the list never shows something that is no longer true.
        local data = lib.callback.await('cm-house:server:adminData', false)
        SendNUIMessage({ action = 'adminRefresh', data = data })
    else
        lib.notify({ description = res or 'That did not work.', type = 'error' })
    end

    cb({ ok = ok, message = res })
end)

RegisterNUICallback('admin:vehicleRecovery', function(d, cb)
    local ok, result = lib.callback.await('cm-house:server:adminVehicleRecovery', false,
        d.identity, d.action, d.data or {})
    if ok then
        lib.notify({ description = type(result) == 'string' and result or 'Recovery completed.', type = 'success' })
        local data = lib.callback.await('cm-house:server:adminData', false)
        SendNUIMessage({ action = 'adminRefresh', data = data })
    else
        lib.notify({ description = result or 'Recovery failed.', type = 'error' })
    end
    cb({ ok = ok, message = type(result) == 'string' and result or nil, data = result })
end)

-- ------------------------------------------------------------
--  Layouts
-- ------------------------------------------------------------
RegisterNUICallback('admin:template', function(d, cb)
    -- Walking points needs the game screen, not the panel. Close first, then
    -- the server fires cm-house:client:adminCaptureTemplate to start the walk.
    if d.action == 'create' or d.action == 'rewalk' then
        cb({ ok = true })
        closeAdmin()
        Wait(200)

        -- Every new standalone layout starts from explicit GPS coordinates.
        -- The admin is teleported there first, then the point-walking capture begins.
        if d.action == 'create' then
            local coords = askNewTemplateGps(d.kind)
            if not coords then
                local label = d.kind == 'garage' and 'Garage' or 'Interior'
                lib.notify({ description = label .. ' creation cancelled or the GPS coordinates were invalid.', type = 'inform' })
                TriggerEvent('cm-house:client:openAdmin', d.kind == 'garage' and 'garages' or 'interiors')
                return
            end
            teleportToGps(coords)
            Wait(350)
        end

        local ok, res = lib.callback.await('cm-house:server:adminTemplate', false,
            d.action, d.kind, tonumber(d.id), d.arg)
        if not ok then
            lib.notify({ description = res or 'The layout capture could not start.', type = 'error' })
            TriggerEvent('cm-house:client:openAdmin', d.kind == 'garage' and 'garages' or 'interiors')
        end
        return
    end

    local ok, res = lib.callback.await('cm-house:server:adminTemplate', false,
        d.action, d.kind, tonumber(d.id), d.arg)

    if d.action == 'preview' and ok then
        cb({ ok = true })
        closeAdmin()
        walkPreview(res)
        return
    end

    if ok then
        lib.notify({ description = type(res) == 'string' and res or 'Done.', type = 'success' })
        local data = lib.callback.await('cm-house:server:adminData', false)
        SendNUIMessage({ action = 'adminRefresh', data = data })
    else
        lib.notify({ description = res or 'That did not work.', type = 'error' })
    end

    cb({ ok = ok, message = res })
end)

--- Stand inside a layout and see every point drawn. This is how you check a
--- weapon locker is not inside a wall without building a house to find out.
function walkPreview(p)
    if p.sourceKind == 'ipl' and p.sourceRef and not IsIplActive(p.sourceRef) then
        RequestIpl(p.sourceRef)
        Wait(600)
    end

    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(0) end

    local ped = PlayerPedId()
    local e = p.entry
    SetEntityCoords(ped, e.x, e.y, e.z, false, false, false, false)
    SetEntityHeading(ped, e.h or 0.0)

    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() - t < 8000 do Wait(10) end
    DoScreenFadeIn(400)

    preview = p
    lib.notify({
        title = 'Layout preview',
        description = 'Every point is drawn. Press BACKSPACE to leave.',
        type = 'inform', duration = 7000,
    })
end

local function mk(pt, r, g, b, size, label)
    if not pt then return end
    size = size or 0.5
    DrawMarker(21, pt.x, pt.y, pt.z + 0.15, 0.0,0.0,0.0, 0.0,0.0,0.0,
        size, size, size, r, g, b, 160, true, false, 2, false, nil, nil, false)
    if label then
        local on, sx, sy = World3dToScreen2d(pt.x, pt.y, pt.z + 0.9)
        if on then
            SetTextScale(0.0, 0.34) SetTextFont(4)
            SetTextColour(r, g, b, 255) SetTextCentre(true)
            SetTextEntry('STRING') AddTextComponentString(label)
            DrawText(sx, sy)
        end
    end
end

CreateThread(function()
    while true do
        local sleep = 800

        if preview then
            sleep = 0
            local p = preview

            if p.kind == 'interior' then
                mk(p.entry, 120, 255, 150, 0.6, 'SPAWN')
                mk(p.exitPoint, 255, 110, 110, 0.6, 'DOOR')
                for i, w in ipairs(p.weaponStorages or p.wardrobes or {}) do
                    mk(w, 0, 220, 255, 0.4, ('WEAPON LOCKER %d'):format(i))
                end
                for i, s in ipairs(p.stashes or {}) do
                    mk(s, 255, 220, 120, 0.4, s.label or ('STORAGE %d'):format(i))
                end
            else
                mk(p.entry, 120, 255, 150, 0.6, 'DOOR')
                for i, exit in ipairs(p.vehicleExits or (p.vehicleExit and { p.vehicleExit } or {})) do
                    mk(exit, 255, 180, 60, 0.8, ('CAR EXIT %d'):format(i))
                end
                for i, s in ipairs(p.slots or {}) do
                    DrawMarker(1, s.x, s.y, s.z - 0.9, 0.0,0.0,0.0, 0.0,0.0,0.0,
                        2.6, 5.4, 0.25, 0, 220, 255, 90,
                        false, false, 2, false, nil, nil, false)
                    local on, sx, sy = World3dToScreen2d(s.x, s.y, s.z + 1.0)
                    if on then
                        SetTextScale(0.0, 0.42) SetTextFont(4)
                        SetTextColour(0, 220, 255, 255) SetTextCentre(true)
                        SetTextEntry('STRING') AddTextComponentString(('SLOT %d'):format(i))
                        DrawText(sx, sy)
                    end
                end
            end

            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('~y~BACKSPACE~s~ leave the preview')
            EndTextCommandDisplayHelp(0, false, true, -1)

            if IsControlJustReleased(0, 194) then
                preview = nil
                lib.notify({ description = 'Preview closed.', type = 'inform' })
            end
        end

        Wait(sleep)
    end
end)

--- Retake a property's photo. Starts the camera where it was last framed, so
--- this is a nudge rather than hunting for the house all over again.
RegisterNUICallback('admin:retake', function(d, cb)
    cb({})

    local houseId = tonumber(d.houseId)
    local ok, cfg = lib.callback.await('cm-house:server:retakePhoto', false, houseId)
    if not ok then
        lib.notify({ description = cfg, type = 'error' })
        return
    end

    closeAdmin()
    Wait(200)

    StartPhotoCam(cfg.cam, cfg.door, function(cam)
        if not cam then
            lib.notify({ description = 'Cancelled.', type = 'inform' })
            return
        end

        lib.notify({ description = 'Saving house photo…', type = 'inform' })

        CaptureAndSave(cfg, cam, function(url, err)
            if not url then
                lib.notify({
                    title = 'Photo save failed',
                    description = err or 'Unknown error.',
                    type = 'error', duration = 7000 })
                return
            end

            lib.notify({
                description = 'Photo updated.',
                type = 'success',
            })
        end)
    end)
end)

RegisterNUICallback('admin:pricing', function(d, cb)
    local ok, msg = lib.callback.await('cm-house:server:adminPricing', false, d.changes)
    lib.notify({ description = msg, type = ok and 'success' or 'error' })
    cb({ ok = ok, message = msg })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and open then closeAdmin() end
end)

RegisterNetEvent('cm-house:client:removeHouse', function(id)
    -- handled in cl_door's cache
end)


-- Button-ready client API. The server revalidates rank/ACL before opening.
exports('OpenAdminPanel', function(tab)
    TriggerServerEvent('cm-house:server:requestAdminPanel', tostring(tab or 'houses'))
end)

exports('OpenHouseCreator', function()
    TriggerServerEvent('cm-house:server:requestHouseCreator')
end)

exports('IsHouseAdminPanelOpen', function()
    return open == true
end)
