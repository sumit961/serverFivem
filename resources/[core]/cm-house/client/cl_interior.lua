-- ============================================================
--  cm-house | cl_interior.lua   |  PHASE 1 (rewritten)
--
--  Every coordinate comes from the TEMPLATE, served by the server.
--  The client stores no layout and decides no permission -- it renders what
--  it is given and asks before it acts.
-- ============================================================

local In = nil   -- { houseId, kind='house'|'garage', ... }

--- The prompt loop runs EVERY FRAME, and every action below awaits the server.
--- Without a guard the loop keeps spinning while the await is in flight, re-reads
--- E, and fires the action again -- several times for one key press. Each one
--- teleports, so the player ends up bounced between rooms.
local busy = false
local doorChoiceOpen = false

local function goTo(p, heading)
    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(0) end

    local ped = PlayerPedId()
    SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, false)
    SetEntityHeading(ped, heading or p.h or 0.0)

    -- Wait for the world, or the player drops through the floor into the void.
    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() - t < 8000 do
        Wait(10)
    end
    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(400)
end

local function draw3d(x, y, z, text)
    if CMHouseInteraction and CMHouseInteraction.Request then
        CMHouseInteraction.Request(('interior:%s:%s'):format(tostring(In and In.houseId or 0), text),
            text, nil, 70)
    end
end

local function prompt(p, label)
    draw3d(p.x, p.y, p.z + 0.5, label == 'Door' and 'Open door' or ('Open ' .. tostring(label)))
end

local function nearTo(pc, p)
    return #(pc - vector3(p.x, p.y, p.z)) <= Config.Prompt.distance
end

local interiorDoorRequestId = nil
local interiorDoorRendered = false
local interiorDoorNuiReady = false

local function closeDoorChoice()
    doorChoiceOpen = false
    interiorDoorRequestId = nil
    interiorDoorRendered = false
    SendNUIMessage({ action = 'closeInteriorDoor' })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

--- Interior navigation uses a dedicated CM cyan NUI. It deliberately does not
--- call lib.registerContext: the player sees the same server-branded interface
--- at the house door and at the garage door.
local function openDoorChoice(origin)
    if doorChoiceOpen or not In then return end

    local insideGarage = origin == 'garage' and In.kind == 'garage'
    local insideHouse  = origin == 'house' and In.kind == 'house'
    if not insideGarage and not insideHouse then
        busy = false
        return
    end

    doorChoiceOpen = true
    interiorDoorRendered = false
    interiorDoorRequestId = ('%s:%s:%s:%s'):format(
        tostring(GetPlayerServerId(PlayerId())),
        tostring(In.houseId or 0),
        tostring(origin),
        tostring(GetGameTimer())
    )

    local payload = {
        requestId = interiorDoorRequestId,
        houseId = tonumber(In.houseId) or 0,
        kind = insideGarage and 'garage' or 'house',
        hasGarage = insideHouse and In.hasGarage == true or false,
    }

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'openInteriorDoor', data = payload })

    -- Retry while Chromium is finishing startup. There is no ox_lib fallback:
    -- if the branded UI genuinely cannot render, release focus and tell the
    -- player rather than silently replacing it with the core context menu.
    CreateThread(function()
        local token = interiorDoorRequestId
        local deadline = GetGameTimer() + 2400
        while doorChoiceOpen and interiorDoorRequestId == token
              and not interiorDoorRendered and GetGameTimer() < deadline do
            Wait(300)
            if doorChoiceOpen and interiorDoorRequestId == token and not interiorDoorRendered then
                SendNUIMessage({ action = 'openInteriorDoor', data = payload })
            end
        end

        if doorChoiceOpen and interiorDoorRequestId == token and not interiorDoorRendered then
            closeDoorChoice()
            lib.notify({ description = 'The CM door menu could not open. Try again.', type = 'error' })
            print(('[cm-house] custom interior door UI did not render. ready=%s origin=%s house=%s')
                :format(tostring(interiorDoorNuiReady), tostring(origin), tostring(payload.houseId)))
        end
    end)
end

RegisterNUICallback('interiorDoor:ready', function(data, cb)
    interiorDoorNuiReady = data and data.rootFound == true
    if Config.Debug then
        print(('[cm-house] Interior door NUI ready (v%s, root=%s).')
            :format(tostring(data and data.version or 'unknown'), tostring(interiorDoorNuiReady)))
    end
    cb({ ok = true })
end)

RegisterNUICallback('interiorDoor:rendered', function(data, cb)
    local token = data and tostring(data.requestId or '') or ''
    local matches = doorChoiceOpen
        and interiorDoorRequestId ~= nil
        and token == interiorDoorRequestId
    if matches and data.visible == true then
        interiorDoorRendered = true
    end
    cb({ ok = true, accepted = matches and data.visible == true })
end)

RegisterNUICallback('interiorDoor:error', function(data, cb)
    print(('[cm-house] Interior door NUI error: %s')
        :format(tostring(data and data.message or 'unknown error')))
    cb({ ok = true })
end)

RegisterNUICallback('interiorDoor:close', function(_, cb)
    closeDoorChoice()
    cb({ ok = true })
end)

RegisterNUICallback('interiorDoor:select', function(data, cb)
    local action = data and tostring(data.action or '') or ''
    if not doorChoiceOpen or not In then
        closeDoorChoice()
        cb({ ok = false })
        return
    end

    local allowed = action == 'exit'
        or (action == 'garage' and In.kind == 'house' and In.hasGarage == true)
        or (action == 'house' and In.kind == 'garage')

    if not allowed then
        cb({ ok = false })
        return
    end

    closeDoorChoice()
    cb({ ok = true })

    if action == 'exit' then
        TriggerEvent('cm-house:client:leave')
    elseif action == 'garage' then
        TriggerEvent('cm-house:client:toGarage')
    elseif action == 'house' then
        TriggerEvent('cm-house:client:toHouse')
    end
end)

-- ------------------------------------------------------------
--  One prompt loop, alive only while actually inside.
-- ------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 700

        -- `busy` is what stops the loop firing an action several times for a
        -- single key press: every action below awaits the server, and an await
        -- yields, so without this the loop keeps spinning and re-reading E
        -- while the first one is still in flight.
        if In and not busy and not doorChoiceOpen then
            sleep = 0
            local pc = GetEntityCoords(PlayerPedId())
            local pressed = IsControlJustReleased(0, Config.Prompt.key)

            if In.kind == 'house' then
                -- ONE door. It offers to leave, and -- if this property has a
                -- garage -- to walk through into it.
                if In.exitPoint and nearTo(pc, In.exitPoint) then
                    prompt(In.exitPoint, In.hasGarage and 'Door' or 'Leave')
                    if pressed then
                        busy = true
                        openDoorChoice('house')
                        busy = false              -- a menu, not an await
                    end
                end

                for _, w in ipairs(In.weaponStorages or In.wardrobes or {}) do
                    if nearTo(pc, w.coords) then
                        prompt(w.coords, 'Weapon storage')
                        if pressed then
                            busy = true
                            if CMHouseInteraction and CMHouseInteraction.BlockFor then CMHouseInteraction.BlockFor(1200) end
                            TriggerEvent('cm-house:client:openWeaponStorageRequested', In.houseId, w.index)
                            -- A server event, not an await. Release after a beat
                            -- so a held key cannot machine-gun the request.
                            SetTimeout(600, function() busy = false end)
                        end
                    end
                end

                for _, st in ipairs(In.stashes or {}) do
                    if nearTo(pc, st.coords) then
                        prompt(st.coords, st.label or 'Storage')
                        if pressed then
                            busy = true
                            SetTimeout(600, function() busy = false end)
                            if CMHouseInteraction and CMHouseInteraction.BlockFor then CMHouseInteraction.BlockFor(1200) end
                            TriggerServerEvent('cm-house:server:openStash', In.houseId, st.index)
                        end
                    end
                end

            elseif In.kind == 'garage' then
                -- Same door you arrived through: leave, or go back inside.
                if In.entry and nearTo(pc, In.entry) then
                    prompt(In.entry, 'Door')
                    if pressed then
                        busy = true
                        openDoorChoice('garage')
                        busy = false          -- a menu, not an await
                    end
                end

                -- The slots themselves are handled by cl_garage, which owns
                -- the networked parked vehicles and the slot menu.
            end
        end

        Wait(sleep)
    end
end)

-- ------------------------------------------------------------
--  Enter / leave
-- ------------------------------------------------------------
local function loadSource(kind, ref)
    if kind == 'ipl' and ref and not IsIplActive(ref) then
        RequestIpl(ref)
        Wait(600)
    end
end

RegisterNetEvent('cm-house:client:enterHome', function(houseId)
    if In then
        lib.notify({ description = 'You are already inside.', type = 'error' })
        return
    end

    local ok, res = lib.callback.await('cm-house:server:enterHome', false, houseId)
    if not ok then
        lib.notify({ description = res, type = 'error' })
        return
    end

    loadSource(res.sourceKind, res.sourceRef)
    goTo(res.entry, res.entry.h)

    In = {
        houseId   = houseId,
        kind      = 'house',
        exitPoint = res.exitPoint,
        hasGarage = res.hasGarage,
        weaponStorages = res.weaponStorages or res.wardrobes or {},
        wardrobes = res.weaponStorages or res.wardrobes or {},
        stashes   = res.stashes or {},
    }

    lib.notify({ description = ('Inside %s.'):format(res.label), type = 'success' })
end)

RegisterNetEvent('cm-house:client:leave', function(exitIndex)
    if not In then return end
    busy = true

    local door = lib.callback.await('cm-house:server:leaveProperty', false, In.houseId, exitIndex)
    if not door then
        busy = false
        lib.notify({ description = 'Something went wrong. Try /houseexit.', type = 'error' })
        return
    end

    -- Face away from the door: you are looking at the street, not the wood.
    TriggerEvent('cm-house:client:leaveGarageState')
    closeDoorChoice()
    goTo(door, (door.h or 0.0) + 180.0)
    In = nil
    busy = false
end)

-- ------------------------------------------------------------
--  House <-> garage, on foot
-- ------------------------------------------------------------
RegisterNetEvent('cm-house:client:toGarage', function()
    if not In or In.kind ~= 'house' then return end
    local houseId = In.houseId
    busy = true

    local ok, res = lib.callback.await('cm-house:server:houseToGarage', false, houseId)
    if not ok then
        busy = false
        lib.notify({ description = res, type = 'error' })
        return
    end

    loadSource(res.sourceKind, res.sourceRef)
    goTo(res.entry, res.entry.h)

    In = {
        houseId     = houseId,
        kind        = 'garage',
        entry       = res.entry,
        vehicleExit = res.vehicleExit,
        vehicleExits = res.vehicleExits or (res.vehicleExit and { res.vehicleExit } or {}),
        capacity    = res.capacity,
    }

    -- cl_garage takes it from here: networked parked cars, slot prompts, and the menu.
    TriggerEvent('cm-house:client:enterGarageState', houseId)
    busy = false
end)

RegisterNetEvent('cm-house:client:toHouse', function()
    if not In or In.kind ~= 'garage' then return end
    local houseId = In.houseId
    busy = true

    -- EVERY exit releases the lock. A leaked one freezes the interior for good,
    -- which is worse than the double-fire it exists to prevent.
    local ok, res = lib.callback.await('cm-house:server:garageToHouse', false, houseId)
    if not ok then
        busy = false
        lib.notify({ description = res, type = 'error' })
        return
    end

    TriggerEvent('cm-house:client:leaveGarageState')
    loadSource(res.sourceKind, res.sourceRef)
    goTo(res.entry, res.entry.h)

    In = {
        houseId   = houseId,
        kind      = 'house',
        exitPoint = res.exitPoint,
        hasGarage = res.hasGarage,
        weaponStorages = res.weaponStorages or res.wardrobes or {},
        wardrobes = res.weaponStorages or res.wardrobes or {},
        stashes   = res.stashes or {},
    }
    busy = false
end)

-- Exterior return-zone parking has already been authorised, committed and
-- moved into the garage routing bucket by the server. Use the server-supplied
-- template snapshot directly instead of making a second callback that could
-- fail after the vehicle has already disappeared and leave a black screen.
RegisterNetEvent('cm-house:client:completeGarageStoreTransition', function(res)
    busy = true
    if type(res) ~= 'table' or res.enterGarage ~= true or type(res.entry) ~= 'table' then
        busy = false
        DoScreenFadeIn(250)
        lib.notify({ description = 'The vehicle was parked, but the garage transition data was incomplete.', type = 'error' })
        return
    end

    if In then
        busy = false
        DoScreenFadeIn(250)
        lib.notify({ description = 'The vehicle was parked, but you are already inside another property.', type = 'error' })
        return
    end

    local houseId = tonumber(res.houseId)
    if not houseId then
        busy = false
        DoScreenFadeIn(250)
        lib.notify({ description = 'The vehicle was parked, but the garage identifier was invalid.', type = 'error' })
        return
    end

    loadSource(res.sourceKind, res.sourceRef)
    goTo(res.entry, res.entry.h)

    In = {
        houseId = houseId,
        kind = 'garage',
        entry = res.entry,
        vehicleExit = res.vehicleExit,
        vehicleExits = res.vehicleExits or (res.vehicleExit and { res.vehicleExit } or {}),
        capacity = tonumber(res.capacity) or 0,
    }

    TriggerEvent('cm-house:client:enterGarageState', houseId)
    busy = false
end)

-- ------------------------------------------------------------
--  Rejoin restore. cm-playerdata/cm-spawn already put us back at our exact
--  last coordinates -- we only need to (re)load the IPL room for an 'ipl'
--  interior and rebuild the local In table so the E-prompt loop above and
--  the door menu work again. No goTo(): moving the player is not our job
--  here, only making the room they are already standing in actually render.
-- ------------------------------------------------------------
RegisterNetEvent('cm-house:client:restoreInterior', function(kind, res)
    if In or type(res) ~= 'table' then return end

    loadSource(res.sourceKind, res.sourceRef)

    if kind == 'garage' then
        In = {
            houseId = res.houseId,
            kind = 'garage',
            entry = res.entry,
            vehicleExit = res.vehicleExit,
            vehicleExits = res.vehicleExits or (res.vehicleExit and { res.vehicleExit } or {}),
            capacity = res.capacity,
        }

        -- Every other path into a garage calls goTo() first, which blocks on
        -- HasCollisionLoadedAroundEntity before anything else happens. This is
        -- the one path that skips goTo() (the player is already there), so it
        -- must wait for the same thing here -- otherwise this can ask the
        -- server to spawn networked vehicles before the client's world has
        -- actually streamed in on a fresh rejoin, and the engine culls them
        -- mid-initialization ("entity deleted during initialization").
        CreateThread(function()
            local ped = PlayerPedId()
            local deadline = GetGameTimer() + 8000
            while (ped == 0 or not DoesEntityExist(ped) or not HasCollisionLoadedAroundEntity(ped))
                  and GetGameTimer() < deadline do
                Wait(100)
                ped = PlayerPedId()
            end
            if In and In.houseId == res.houseId and In.kind == 'garage' then
                TriggerEvent('cm-house:client:enterGarageState', res.houseId)
            end
        end)
    elseif kind == 'house' then
        In = {
            houseId   = res.houseId,
            kind      = 'house',
            exitPoint = res.exitPoint,
            hasGarage = res.hasGarage,
            weaponStorages = res.weaponStorages or res.wardrobes or {},
            wardrobes = res.weaponStorages or res.wardrobes or {},
            stashes   = res.stashes or {},
        }
    end
end)

RegisterNetEvent('cm-house:client:openGarage', function(houseId)
    -- From the front door, walking straight into the garage.
    if In then return end

    local ok, res = lib.callback.await('cm-house:server:enterGarage', false, houseId)
    if not ok then
        lib.notify({ description = res, type = 'error' })
        return
    end

    loadSource(res.sourceKind, res.sourceRef)
    goTo(res.entry, res.entry.h)

    In = {
        houseId = houseId, kind = 'garage',
        entry = res.entry, vehicleExit = res.vehicleExit,
        vehicleExits = res.vehicleExits or (res.vehicleExit and { res.vehicleExit } or {}),
        capacity = res.capacity,
    }

    TriggerEvent('cm-house:client:enterGarageState', houseId)
end)

-- Backward-compatible wardrobe event. Old integrations now open the first
-- secure weapon-storage point instead of calling an unavailable clothing UI.
RegisterNetEvent('cm-house:client:openWardrobe', function(houseId, index)
    TriggerEvent('cm-house:client:openWeaponStorageRequested', tonumber(houseId), tonumber(index) or 1)
end)

-- ------------------------------------------------------------
--  Escape hatch. Stuck in a bucket with no way out is not acceptable.
-- ------------------------------------------------------------
RegisterCommand('houseexit', function()
    if not In then
        lib.notify({ description = 'You are not inside a property.', type = 'error' })
        return
    end
    TriggerEvent('cm-house:client:leave')
end, false)

RegisterNetEvent('cm-house:client:garageVehicleExited', function(netId, spawn)
    -- Server already moved both the network vehicle and this player to bucket 0.
    -- Wait for the entity to stream back, then guarantee the driver remains in it.
    TriggerEvent('cm-house:client:leaveGarageState')
    closeDoorChoice()
    In = nil
    busy = false

    local veh = nil
    local deadline = GetGameTimer() + 5000
    repeat
        if tonumber(netId) and NetworkDoesNetworkIdExist(tonumber(netId)) then
            veh = NetworkGetEntityFromNetworkId(tonumber(netId))
        end
        if not veh or veh == 0 or not DoesEntityExist(veh) then Wait(0) end
    until (veh and veh ~= 0 and DoesEntityExist(veh)) or GetGameTimer() >= deadline

    if veh and veh ~= 0 and DoesEntityExist(veh) then
        ResetEntityAlpha(veh)
        SetEntityVisible(veh, true, false)
        SetEntityCollision(veh, true, true)
        FreezeEntityPosition(veh, false)
        SetVehicleHandbrake(veh, false)
        if spawn then
            SetEntityCoordsNoOffset(veh, spawn.x + 0.0, spawn.y + 0.0, spawn.z + 0.0,
                false, false, false)
            SetEntityHeading(veh, (spawn.h or spawn.w or 0.0) + 0.0)
            SetVehicleOnGroundProperly(veh)
        end
        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) ~= veh then
            TaskWarpPedIntoVehicle(ped, veh, -1)
        end
    end

    DoScreenFadeIn(350)
end)

RegisterNetEvent('cm-house:client:forceExit', function()
    TriggerEvent('cm-house:client:leaveGarageState')
    closeDoorChoice()
    In = nil
    busy = false
    DoScreenFadeIn(200)
end)

--- A leaked lock would freeze the interior permanently. Nothing should take
--- more than a few seconds, so anything longer is a bug -- clear it rather than
--- stranding the player in a room whose door has stopped responding.
CreateThread(function()
    local heldSince = nil
    while true do
        Wait(1000)
        if busy then
            heldSince = heldSince or GetGameTimer()
            if GetGameTimer() - heldSince > 10000 then
                busy = false
                heldSince = nil
                print('[cm-house] released a stuck interior lock')
            end
        else
            heldSince = nil
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        closeDoorChoice()
        In = nil
    end
end)
