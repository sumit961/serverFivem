-- ============================================================
--  cm-house | cl_admin_templates.lua
--  /cmadminhouse -> Layouts / Garages -> "+ Walk new" or "Re-walk".
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

local function stopCapture(msg, kind, reopen)
    local tab = Cap and (Cap.kind == 'garage' and 'garages' or 'interiors') or 'houses'
    Cap = nil
    if msg then lib.notify({ description = msg, type = kind or 'inform' }) end
    if reopen ~= false then reopenAdminPanel(tab) end
end

local function askTemplateDetails(defaultLabel)
    local input = lib.inputDialog(
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
        local ref = lib.inputDialog('IPL source', {
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
                lib.notify({
                    title = 'Real parking-space placement',
                    description = CMHouseGaragePlacer.IsLocal()
                        and 'Network spawn was unavailable. Nudge the cyan car with arrow keys.'
                        or 'Drive the cyan car into each space. Press E to save; G when all spaces are placed.',
                    type = 'inform', duration = 8000,
                })
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
                            lib.notify({ description = 'The placement car is missing.', type = 'error' })
                        elseif not CMHouseGaragePlacer.IsLocal()
                            and GetVehiclePedIsIn(PlayerPedId(), false) ~= CMHouseGaragePlacer.Entity() then
                            lib.notify({ description = 'Sit in the placement car before saving the slot.', type = 'error' })
                        elseif #list >= (step.max or 24) then
                            lib.notify({ description = 'Maximum slot count reached. Press G to continue.', type = 'error' })
                        else
                            local pos = GetEntityCoords(CMHouseGaragePlacer.Entity())
                            local clash
                            for index, old in ipairs(list) do
                                if #(pos - vector3(old.x, old.y, old.z)) < 3.2 then clash = index break end
                            end
                            if clash then
                                lib.notify({ description = ('Too close to slot %d.'):format(clash), type = 'error' })
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
                            lib.notify({ description = 'Maximum point count reached. Press G to continue.', type = 'error' })
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
                        lib.notify({ description = ('Place at least %d.'):format(step.min), type = 'error' })
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

RegisterNetEvent('cm-house:client:adminCaptureTemplate', function(kind, editId)
    if Cap then
        lib.notify({ description = 'You are already walking a layout. Finish or press X first.', type = 'error' })
        return
    end
    if kind ~= 'interior' and kind ~= 'garage' then return end

    Cap = {
        kind = kind,
        editId = tonumber(editId),
        points = kind == 'interior'
            and { entry = nil, exitPoint = nil, weaponStorages = {}, stashes = {} }
            or  { playerEntry = nil, vehicleExits = {}, slots = {} },
    }

    lib.notify({
        title = editId and 'Re-walking layout' or 'New layout',
        description = 'You are at the selected GPS location. Set each point for this reusable layout.',
        type = 'inform', duration = 7000,
    })
    runSteps(kind == 'interior' and INTERIOR_STEPS or GARAGE_STEPS)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then if CMHouseGaragePlacer then CMHouseGaragePlacer.Clear() end Cap = nil end
end)
