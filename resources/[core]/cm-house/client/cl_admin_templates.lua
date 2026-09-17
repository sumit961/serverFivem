-- ============================================================
--  cm-house | cl_admin_templates.lua
--  cm-admin Developer > House Admin > Layouts / Garages > "+ Walk new" or "Re-walk".
--
--  Standalone template capture: the admin stands wherever the layout should
--  live (any MLO, shell or world GPS location) and places
--  every point on foot. No property wizard, no house required.
--
--    E          place the current point
--    G          finish a multi-point step (weapon lockers / stashes / slots)
--    BACKSPACE  skip an optional step
--    X          cancel everything
--
--  Interior:  entry -> exit -> weapon lockers (multi) -> stashes (multi) -> name
--  Garage:    player entry -> vehicle exits -> car slots (multi) -> name
-- ============================================================

local Cap = nil   -- { kind, editId, points = {...}, step }

-- Dedicated mappings make the 3D editor independent from GTA movement
-- controls and from Num Lock/control-disable behaviour.
local EditInput = {
    forward = false, back = false, left = false, right = false,
    up = false, down = false, rotateLeft = false, rotateRight = false,
    next = false, previous = false, save = false,
}

local function editingLayout()
    return Cap and Cap.editId ~= nil
end

local function bindHeldEditorKey(action, command, key, description)
    RegisterCommand('+' .. command, function()
        if editingLayout() then EditInput[action] = true end
    end, false)
    RegisterCommand('-' .. command, function()
        EditInput[action] = false
    end, false)
    RegisterKeyMapping('+' .. command, description, 'keyboard', key)
end

local function bindEditorPress(action, command, key, description)
    RegisterCommand('+' .. command, function()
        if editingLayout() then EditInput[action] = true end
    end, false)
    RegisterCommand('-' .. command, function() end, false)
    RegisterKeyMapping('+' .. command, description, 'keyboard', key)
end

bindHeldEditorKey('forward', 'cmhouse_edit_forward', 'NUMPAD8', 'CM House editor: move forward')
bindHeldEditorKey('back', 'cmhouse_edit_back', 'NUMPAD2', 'CM House editor: move backward')
bindHeldEditorKey('left', 'cmhouse_edit_left', 'NUMPAD4', 'CM House editor: move left')
bindHeldEditorKey('right', 'cmhouse_edit_right', 'NUMPAD6', 'CM House editor: move right')
bindHeldEditorKey('up', 'cmhouse_edit_up', 'NUMPAD9', 'CM House editor: move up')
bindHeldEditorKey('down', 'cmhouse_edit_down', 'NUMPAD3', 'CM House editor: move down')
bindHeldEditorKey('rotateLeft', 'cmhouse_edit_rotate_left', 'NUMPAD7', 'CM House editor: rotate left')
bindHeldEditorKey('rotateRight', 'cmhouse_edit_rotate_right', 'NUMPAD1', 'CM House editor: rotate right')
bindEditorPress('next', 'cmhouse_edit_next', 'NUMPAD5', 'CM House editor: select next point')
bindEditorPress('previous', 'cmhouse_edit_previous', 'NUMPAD0', 'CM House editor: select previous point')
bindEditorPress('save', 'cmhouse_edit_save', 'NUMPADENTER', 'CM House editor: save layout')

local function resetEditInput()
    for key in pairs(EditInput) do EditInput[key] = false end
end

local function here()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    return { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0, h = GetEntityHeading(ped) + 0.0 }
end

local function draw3dText(x, y, z, text)
    local on, sx, sy = World3dToScreen2d(x, y, z)
    if not on then return end
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 255)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(sx, sy)
end

local function mark(p, r, g, b, label)
    DrawMarker(1, p.x, p.y, p.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.55, 0.55, 0.35, r, g, b, 160, false, false, 2, false, nil, nil, false)
    if label then draw3dText(p.x, p.y, p.z + 0.35, label) end
end

local function carMark(p, label)
    -- A car-sized floor box so slot spacing is visible before anything spawns.
    DrawMarker(43, p.x, p.y, p.z - 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, p.h,
        2.3, 5.0, 1.2, 0, 229, 255, 90, false, false, 2, false, nil, nil, false)
    if label then draw3dText(p.x, p.y, p.z + 0.55, label) end
end

local function banner(title, sub)
    SetTextFont(4)
    SetTextScale(0.0, 0.5)
    SetTextColour(0, 229, 255, 255)
    SetTextEntry('STRING')
    AddTextComponentString(title)
    DrawText(0.015, 0.015)
    SetTextFont(4)
    SetTextScale(0.0, 0.33)
    SetTextColour(255, 255, 255, 220)
    SetTextEntry('STRING')
    AddTextComponentString(sub)
    DrawText(0.015, 0.055)
end

local function drawPlaced()
    if not Cap then return end
    local P = Cap.points
    if P.entry then mark(P.entry, 0, 255, 140, 'ENTRY') end
    if P.exitPoint then mark(P.exitPoint, 255, 170, 0, 'EXIT') end
    if P.playerEntry then mark(P.playerEntry, 0, 255, 140, 'PLAYER ENTRY') end
    for i, exit in ipairs(P.vehicleExits or {}) do carMark(exit, ('VEHICLE EXIT %d'):format(i)) end
    for i, w in ipairs(P.weaponStorages or {}) do mark(w, 0, 220, 255, ('WEAPON LOCKER %d'):format(i)) end
    for i, s in ipairs(P.stashes or {}) do mark(s, 255, 120, 200, ('STORAGE %d'):format(i)) end
    for i, s in ipairs(P.slots or {}) do carMark(s, ('SLOT %d'):format(i)) end
end

-- E / G / BACKSPACE / X (raw keys so no control rebinding can eat them)
local function kPlace()  return IsControlJustReleased(0, 38)  end -- E
local function kFinish() return IsControlJustReleased(0, 47)  end -- G
local function kSkip()   return IsControlJustReleased(0, 194) end -- BACKSPACE
local function kCancel() return IsControlJustReleased(0, 73)  end -- X

local INTERIOR_STEPS = {
    { key = 'entry',     title = 'ENTRY',      hint = 'Stand where players APPEAR when they walk in. Face the room. [E] set  [X] cancel' },
    { key = 'exitPoint', title = 'EXIT DOOR',  hint = 'Stand at the door players use to LEAVE (also serves the garage door). [E] set  [X] cancel' },
    { key = 'weaponStorages', title = 'WEAPON STORAGE', hint = '[E] add a secure weapon locker here   [G] done   [X] cancel', multi = true },
    { key = 'stashes',   title = 'STORAGE',    hint = '[E] add a storage point   [G] done   [X] cancel', multi = true },
}

local GARAGE_STEPS = {
    { key = 'playerEntry', title = 'PLAYER ENTRY', hint = 'Stand where players APPEAR inside the garage. [E] set  [X] cancel' },
    { key = 'vehicleExits', title = 'VEHICLE EXITS', hint = '[E] add an exit here (face outward)   [G] done   [BACKSPACE] undo   [X] cancel', multi = true, min = 1, max = (Config.GarageTemplate and Config.GarageTemplate.maxVehicleExits) or 8 },
    { key = 'slots', title = 'CAR SLOTS', hint = 'Drive the cyan placement car into each space. [E] save   [G] finish   [BACKSPACE] undo   [X] cancel', multi = true, min = 1, car = true, max = (Config.GarageTemplate and Config.GarageTemplate.maxVehicleSlots) or 24 },
}

local function reopenAdminPanel(tab)
    SetTimeout(300, function()
        TriggerEvent('cm-house:client:openAdmin', tab or 'houses')
    end)
end

local function clearEditPreview()
    if not Cap or not Cap.previewCars then return end
    for _, vehicle in ipairs(Cap.previewCars) do
        if DoesEntityExist(vehicle) then
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteVehicle(vehicle)
            DeleteEntity(vehicle)
        end
    end
    Cap.previewCars = nil
end

local function stopCapture(msg, kind, reopen)
    local tab = Cap and (Cap.kind == 'garage' and 'garages' or 'interiors') or 'houses'
    clearEditPreview()
    resetEditInput()
    Cap = nil
    if msg then CMNotify(msg, kind or 'inform') end
    if reopen ~= false then reopenAdminPanel(tab) end
end

local function askTemplateDetails(defaultLabel)
    local input = CMInputDialog(
        Cap.kind == 'garage' and 'Save garage template' or 'Save interior template', {
            { type = 'input', label = 'Template name', default = defaultLabel or '', required = true, max = 64 },
            {
                type = 'select', label = 'Coordinate source', required = true, default = 'world',
                options = {
                    { value = 'world', label = 'World / MLO coordinates' },
                    { value = 'ipl', label = 'IPL coordinates' },
                },
            },
            Cap.kind == 'interior' and {
                type = 'number', label = 'Slots per storage point', default = 30,
                min = 1, max = 100, required = true,
            } or nil,
        })
    if not input or not input[1] or tostring(input[1]):gsub('%s+', '') == '' then return nil end

    local details = {
        label = tostring(input[1]),
        sourceKind = tostring(input[2] or 'world'),
        stashSlots = Cap.kind == 'interior' and math.max(1, math.min(100, tonumber(input[3]) or 30)) or nil,
    }

    if details.sourceKind == 'ipl' then
        local ref = CMInputDialog('IPL source', {
            {
                type = 'input', label = 'IPL name', required = true, max = 64,
                description = 'Exact IPL name requested when a player enters this template.',
            },
        })
        if not ref or not ref[1] or tostring(ref[1]):gsub('%s+', '') == '' then return nil end
        details.sourceRef = tostring(ref[1])
    end

    return details
end

local function submit()
    local P = Cap.points
    local editId = Cap.editId

    if Cap.kind == 'interior' then
        if editId then
            local ok, msg = lib.callback.await('cm-house:server:updateInteriorTemplate', false, editId, {
                entry = P.entry, exitPoint = P.exitPoint,
                weaponStorages = P.weaponStorages, wardrobes = P.weaponStorages, stashes = P.stashes,
            })
            stopCapture(msg, ok and 'success' or 'error')
            return
        end

        local details = askTemplateDetails()
        if not details then stopCapture('Cancelled. Nothing saved.') return end
        for i, stash in ipairs(P.stashes or {}) do
            stash.label = #P.stashes > 1 and ('Storage %d'):format(i) or 'Storage'
            stash.slots = details.stashSlots
        end

        -- signature '' = universal. FindInteriorTemplates intentionally offers
        -- standalone layouts to every property type.
        local ok, msg = lib.callback.await('cm-house:server:saveInteriorTemplate', false, {
            label = details.label, signature = '',
            sourceKind = details.sourceKind, sourceRef = details.sourceRef,
            entry = P.entry, exitPoint = P.exitPoint,
            weaponStorages = P.weaponStorages, wardrobes = P.weaponStorages, stashes = P.stashes,
        })
        stopCapture(msg, ok and 'success' or 'error')
        return
    end

    if editId then
        local ok, msg = lib.callback.await('cm-house:server:updateGarageTemplate', false, editId, {
            playerEntry = P.playerEntry, vehicleExit = P.vehicleExits[1], vehicleExits = P.vehicleExits,
            slots = P.slots,
        })
        stopCapture(msg, ok and 'success' or 'error')
        return
    end

    local details = askTemplateDetails()
    if not details then stopCapture('Cancelled. Nothing saved.') return end
    local ok, msg = lib.callback.await('cm-house:server:saveGarageTemplate', false, {
        label = details.label,
        sourceKind = details.sourceKind, sourceRef = details.sourceRef,
        playerEntry = P.playerEntry, vehicleExit = P.vehicleExits[1], vehicleExits = P.vehicleExits,
        slots = P.slots,
    })
    stopCapture(msg, ok and 'success' or 'error')
end

local function captureList(step)
    return Cap.points[step.key]
end

local function runSteps(steps)
    CreateThread(function()
        local i = 1
        while Cap and i <= #steps do
            local step = steps[i]
            local advanced = false

            if step.car and CMHouseGaragePlacer and not CMHouseGaragePlacer.Exists() then
                if not CMHouseGaragePlacer.Spawn(nil) then
                    stopCapture('The placement car could not be created.', 'error')
                    return
                end
                CMNotify(CMHouseGaragePlacer.IsLocal()
                    and 'Network spawn was unavailable. Nudge the cyan car with arrow keys.'
                    or 'Drive the cyan car into each space. Press E to save; G when all spaces are placed.', 'inform')
            end

            while Cap and not advanced do
                local list = step.multi and captureList(step) or nil
                local count = list and #list or nil
                banner(('LAYOUT  %s  %d/%d'):format(step.title, i, #steps),
                    step.multi and ('%s      %d placed'):format(step.hint, count) or step.hint)
                drawPlaced()

                if step.car and CMHouseGaragePlacer and CMHouseGaragePlacer.IsLocal() and CMHouseGaragePlacer.Exists() then
                    CMHouseGaragePlacer.Nudge()
                end

                if kPlace() then
                    if step.car then
                        if not CMHouseGaragePlacer or not CMHouseGaragePlacer.Exists() then
                            CMNotify('The placement car is missing.', 'error')
                        elseif not CMHouseGaragePlacer.IsLocal()
                            and GetVehiclePedIsIn(PlayerPedId(), false) ~= CMHouseGaragePlacer.Entity() then
                            CMNotify('Sit in the placement car before saving the slot.', 'error')
                        elseif #list >= (step.max or 24) then
                            CMNotify('Maximum slot count reached. Press G to continue.', 'error')
                        else
                            local pos = GetEntityCoords(CMHouseGaragePlacer.Entity())
                            local clash
                            for index, old in ipairs(list) do
                                if #(pos - vector3(old.x, old.y, old.z)) < 3.2 then clash = index break end
                            end
                            if clash then
                                CMNotify(('Too close to slot %d.'):format(clash), 'error')
                            else
                                local saved = CMHouseGaragePlacer.Freeze()
                                if saved then
                                    list[#list + 1] = saved
                                    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                                    Wait(250)
                                    if not CMHouseGaragePlacer.Spawn(nil) then
                                        stopCapture('The next placement car could not be created.', 'error')
                                        return
                                    end
                                end
                            end
                        end
                    elseif step.multi then
                        if #list >= (step.max or 24) then
                            CMNotify('Maximum point count reached. Press G to continue.', 'error')
                        else
                            list[#list + 1] = here()
                            PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                        end
                    else
                        Cap.points[step.key] = here()
                        PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                        advanced = true
                    end
                elseif step.multi and kFinish() then
                    if (step.min or 0) > #list then
                        CMNotify(('Place at least %d.'):format(step.min), 'error')
                    else
                        if step.car and CMHouseGaragePlacer and CMHouseGaragePlacer.DiscardCurrent then
                            -- The last spawned car has not been saved as a slot. Remove only that
                            -- unused car while keeping the frozen slot examples for the final preview.
                            CMHouseGaragePlacer.DiscardCurrent()
                        end
                        PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                        advanced = true
                    end
                elseif step.multi and kSkip() then
                    if #list > 0 then
                        if step.car and CMHouseGaragePlacer then CMHouseGaragePlacer.Undo() end
                        table.remove(list)
                        PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                    elseif (step.min or 0) == 0 then
                        advanced = true
                    end
                elseif kCancel() then
                    if CMHouseGaragePlacer then CMHouseGaragePlacer.Clear() end
                    stopCapture('Cancelled. Nothing saved.')
                    return
                end
                Wait(0)
            end
            i = i + 1
        end
        if Cap then
            submit()
            if CMHouseGaragePlacer then CMHouseGaragePlacer.Clear() end
        end
    end)
end

local function editPoint(target)
    if target.list == 'single' then return Cap.points[target.key] end
    return Cap.points[target.list][target.index]
end

local function setEditPoint(target, point)
    if target.list == 'single' then Cap.points[target.key] = point
    else Cap.points[target.list][target.index] = point end
end

local function copyPoint(point)
    return {
        x = tonumber(point.x) or 0.0, y = tonumber(point.y) or 0.0,
        z = tonumber(point.z) or 0.0, h = tonumber(point.h or point.w) or 0.0,
        icon = point.icon,
    }
end

local function requestEditVehicleModel()
    local model = joaat((Config.GarageTemplate and Config.GarageTemplate.editPreviewModel) or 'blista')
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then model = joaat('blista') end
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(model) and model or nil
end

local function spawnEditCars()
    if Cap.kind ~= 'garage' then return end
    local model = requestEditVehicleModel()
    if not model then
        CMNotify('The garage preview cars could not be loaded.', 'error')
        return
    end
    Cap.previewCars = {}
    for index, point in ipairs(Cap.points.slots or {}) do
        local vehicle = CreateVehicle(model, point.x, point.y, point.z + 0.15, point.h or 0.0, false, false)
        if DoesEntityExist(vehicle) then
            SetEntityAsMissionEntity(vehicle, true, true)
            SetVehicleOnGroundProperly(vehicle)
            FreezeEntityPosition(vehicle, true)
            SetEntityInvincible(vehicle, true)
            SetVehicleDoorsLocked(vehicle, 2)
            SetVehicleEngineOn(vehicle, false, true, false)
            SetVehicleDirtLevel(vehicle, 0.0)
            Cap.previewCars[index] = vehicle
        end
    end
    SetModelAsNoLongerNeeded(model)
end

local function updateEditCar(index, point)
    local vehicle = Cap and Cap.previewCars and Cap.previewCars[index]
    if vehicle and DoesEntityExist(vehicle) then
        SetEntityCoordsNoOffset(vehicle, point.x, point.y, point.z + 0.15, false, false, false)
        SetEntityHeading(vehicle, point.h or 0.0)
    end
end

local function refreshEditCarSelection(selected)
    for index, vehicle in ipairs((Cap and Cap.previewCars) or {}) do
        if DoesEntityExist(vehicle) then
            SetEntityAlpha(vehicle, index == selected and 255 or 145, false)
        end
    end
end

local function teleportToEditLayout(point)
    if not point then return end
    local ped = PlayerPedId()
    DoScreenFadeOut(250)
    local deadline = GetGameTimer() + 1500
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end
    RequestCollisionAtCoord(point.x, point.y, point.z)
    SetEntityCoordsNoOffset(ped, point.x, point.y, point.z, false, false, false)
    SetEntityHeading(ped, point.h or 0.0)
    local collisionDeadline = GetGameTimer() + 8000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < collisionDeadline do
        RequestCollisionAtCoord(point.x, point.y, point.z)
        Wait(25)
    end
    DoScreenFadeIn(250)
end

local function editorTargets()
    local P = Cap.points
    local targets = {}
    local function addSingle(key, label)
        if P[key] then targets[#targets + 1] = { list = 'single', key = key, label = label } end
    end
    local function addList(key, label)
        for index = 1, #(P[key] or {}) do
            targets[#targets + 1] = { list = key, index = index, label = label .. ' ' .. index }
        end
    end
    if Cap.kind == 'garage' then
        addSingle('playerEntry', 'PLAYER ENTRY')
        addList('vehicleExits', 'VEHICLE EXIT')
        addList('slots', 'CAR SLOT')
    else
        addSingle('entry', 'ENTRY')
        addSingle('exitPoint', 'EXIT DOOR')
        addList('weaponStorages', 'WEAPON LOCKER')
        addList('stashes', 'STORAGE')
    end
    return targets
end

local function runLayoutEdit()
    CreateThread(function()
        local sequence = editorTargets()
        if #sequence == 0 then
            stopCapture('This garage has no saved points to edit.', 'error')
            return
        end

        local current = 1
        refreshEditCarSelection(current)
        while Cap do
            local target = sequence[current]
            local point = editPoint(target)
            if not point then break end
            local selected = target.list == 'slots' and target.index or nil
            banner(('3D EDIT  %d/%d  %s'):format(current, #sequence, target.label),
                'NUM 8/2 forward/back   4/6 left/right   9/3 height   7/1 rotate   5 next   0 previous   ENTER save')
            drawPlaced()
            DrawMarker(28, point.x, point.y, point.z + 0.45, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.45, 0.45, 0.45, 255, 209, 102, 230, false, false, 2, false, nil, nil, false)
            draw3dText(point.x, point.y, point.z + 0.9, 'SELECTED  ' .. target.label)
            if selected then refreshEditCarSelection(selected) end

            DisableControlAction(0, 30, true); DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true); DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true); DisableControlAction(0, 35, true)
            DisableControlAction(0, 44, true); DisableControlAction(0, 38, true)

            local moved = copyPoint(point)
            local step = IsControlPressed(0, 21) and 0.12 or 0.035
            local radians = math.rad(moved.h or 0.0)
            local forwardX, forwardY = -math.sin(radians), math.cos(radians)
            local rightX, rightY = math.cos(radians), math.sin(radians)

            -- Numpad is authoritative. Fixed WASD/Q/E checks remain as a
            -- secondary option and must use the disabled-control natives.
            local goForward = EditInput.forward or IsDisabledControlPressed(0, 32)
            local goBack = EditInput.back or IsDisabledControlPressed(0, 33)
            local goLeft = EditInput.left or IsDisabledControlPressed(0, 34)
            local goRight = EditInput.right or IsDisabledControlPressed(0, 35)
            local goUp = EditInput.up or IsDisabledControlPressed(0, 44)
            local goDown = EditInput.down or IsDisabledControlPressed(0, 38)
            if goForward then moved.x = moved.x + forwardX * step; moved.y = moved.y + forwardY * step end
            if goBack then moved.x = moved.x - forwardX * step; moved.y = moved.y - forwardY * step end
            if goLeft then moved.x = moved.x - rightX * step; moved.y = moved.y - rightY * step end
            if goRight then moved.x = moved.x + rightX * step; moved.y = moved.y + rightY * step end
            if goUp then moved.z = moved.z + step end
            if goDown then moved.z = moved.z - step end
            if EditInput.rotateLeft or IsControlPressed(0, 20) then moved.h = moved.h - 1.0 end
            if EditInput.rotateRight or IsControlPressed(0, 74) then moved.h = moved.h + 1.0 end
            if moved.x ~= point.x or moved.y ~= point.y or moved.z ~= point.z or moved.h ~= point.h then
                setEditPoint(target, moved)
                if selected then updateEditCar(selected, moved) end
            end

            if EditInput.previous or IsControlJustPressed(0, 174) then
                EditInput.previous = false
                current = current - 1; if current < 1 then current = #sequence end
                PlaySoundFrontend(-1, 'NAV_LEFT_RIGHT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            elseif EditInput.next or IsControlJustPressed(0, 175) then
                EditInput.next = false
                current = current + 1; if current > #sequence then current = 1 end
                PlaySoundFrontend(-1, 'NAV_LEFT_RIGHT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            elseif EditInput.save or kFinish() then
                EditInput.save = false
                submit()
                return
            elseif kCancel() then
                stopCapture('Cancelled. Nothing was changed.', 'inform')
                return
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('cm-house:client:adminCaptureTemplate', function(kind, editId, seed)
    if Cap then
        CMNotify('You are already walking a layout. Finish or press X first.', 'error')
        return
    end
    if kind ~= 'interior' and kind ~= 'garage' then return end

    Cap = {
        kind = kind,
        editId = tonumber(editId),
        points = type(seed) == 'table' and seed or (kind == 'interior'
            and { entry = nil, exitPoint = nil, weaponStorages = {}, stashes = {} }
            or  { playerEntry = nil, vehicleExits = {}, slots = {} }),
    }

    CMNotify(editId and kind == 'garage'
        and 'Teleported to the garage. All parking cars are visible; select a car and move it with the keyboard.'
        or 'You are at the selected GPS location. Set each point for this reusable layout.', 'inform')
    if editId then
        local destination = kind == 'garage' and Cap.points.playerEntry or Cap.points.entry
        teleportToEditLayout(destination)
        if kind == 'garage' then spawnEditCars() end
        runLayoutEdit()
    else runSteps(kind == 'interior' and INTERIOR_STEPS or GARAGE_STEPS) end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        clearEditPreview()
        resetEditInput()
        if CMHouseGaragePlacer then CMHouseGaragePlacer.Clear() end
        Cap = nil
    end
end)
