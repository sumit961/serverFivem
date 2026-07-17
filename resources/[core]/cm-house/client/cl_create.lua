-- ============================================================
--  cm-house | cl_create.lua   |  the whole wizard, one command
--
--  /cmhouse
--    1  FEATURES   type, garden, pool, helipad + saved garage template [UI]
--                  -> capacity comes from the template's placed cars
--    2  EXTERIOR   door -> garage zone -> vehicle exit -> helipad
--    3  PHOTO      frame the property; the camera is stored, not a PNG
--    4  INTERIOR   select an existing cm-admin template.
--    5  GARAGE     use the existing template selected in step 1
--    6  PUBLISH
--
--  Templates are created and edited only from cm-admin.
-- ============================================================

local W = nil    -- the whole wizard state, or nil when idle

local function blank()
    return {
        -- Where the admin was standing when they typed /cmhouse. The wizard
        -- teleports them into interiors and garages; cancelling halfway must
        -- put them back, not abandon them inside a motel room they cannot
        -- leave.
        origin = nil,
        step = nil,
        features = nil,       -- { houseType, hasGarden, hasPool, hasHelipad, garageTemplateId, garageCapacity }
        plan = nil,           -- what the server derived
        door = nil, garageZone = nil, vehicleExit = nil, helipad = nil,
        photoCam = nil, imageUrl = nil, photoToken = nil,
        interiorTemplateId = nil,
        garageTemplateId = nil,
        interior = nil,       -- walked points, when making a new template
        garage = nil,
    }
end

local raw = IsRawKeyReleased ~= nil
local function kPlace()  if raw then return IsRawKeyReleased(72) end return IsControlJustReleased(0, 74)  end
local function kSkip()   if raw then return IsRawKeyReleased(8)  end return IsControlJustReleased(0, 194) end
local function kFinish() if raw then return IsRawKeyReleased(71) end return IsControlJustReleased(0, 47) end
local function kCancel() if raw then return IsRawKeyReleased(27) end return IsControlJustReleased(0, 322) end

-- ------------------------------------------------------------
--  Drawing
-- ------------------------------------------------------------
local function banner(title, sub, coords)
    SetTextFont(4) SetTextScale(0.0, 0.55) SetTextColour(0, 220, 255, 255)
    SetTextCentre(true) SetTextEntry('STRING')
    AddTextComponentString(title) DrawText(0.5, 0.045)
    if sub then
        SetTextFont(4) SetTextScale(0.0, 0.40) SetTextColour(225, 240, 248, 220)
        SetTextCentre(true) SetTextEntry('STRING')
        AddTextComponentString(sub) DrawText(0.5, 0.088)
    end
    if coords then
        SetTextFont(4) SetTextScale(0.0, 0.32) SetTextColour(130, 180, 195, 190)
        SetTextCentre(true) SetTextEntry('STRING')
        AddTextComponentString(coords) DrawText(0.5, 0.122)
    end
end

local function help(msg)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function here()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local ent = (veh ~= 0) and veh or ped
    local c = GetEntityCoords(ent)
    return {
        x = tonumber(('%.3f'):format(c.x)),
        y = tonumber(('%.3f'):format(c.y)),
        z = tonumber(('%.3f'):format(c.z)),
        h = tonumber(('%.2f'):format(GetEntityHeading(ent))),
    }
end

local function marker(p, r, g, b, size)
    if not p then return end
    size = size or 0.6
    DrawMarker(21, p.x, p.y, p.z + 0.15, 0.0,0.0,0.0, 0.0,0.0,0.0,
        size, size, size, r, g, b, 150, true, false, 2, false, nil, nil, false)
end

--- Car-sized, because a spawn point in a hedge is only visible at scale.
local function carBox(p, r, g, b, label)
    if not p then return end
    DrawMarker(1, p.x, p.y, p.z - 0.9, 0.0,0.0,0.0, 0.0,0.0,0.0,
        2.6, 5.4, 0.3, r, g, b, 90, false, false, 2, false, nil, nil, false)
    if label then
        local on, sx, sy = World3dToScreen2d(p.x, p.y, p.z + 1.0)
        if on then
            SetTextScale(0.0, 0.4) SetTextFont(4)
            SetTextColour(r, g, b, 255) SetTextCentre(true)
            SetTextEntry('STRING') AddTextComponentString(label)
            DrawText(sx, sy)
        end
    end
end

local function drawExterior()
    marker(W.door, 0, 220, 255)
    carBox(W.garageZone, 255, 180, 60)
    carBox(W.vehicleExit, 120, 255, 150)
    marker(W.helipad, 200, 130, 255, 2.0)
end

local function drawInterior()
    if not W.interior then return end
    marker(W.interior.entry, 120, 255, 150)
    marker(W.interior.exitPoint, 255, 110, 110)
    for _, w in ipairs(W.interior.weaponStorages or {}) do marker(w, 0, 220, 255, 0.4) end
    for _, s in ipairs(W.interior.stashes or {})   do marker(s, 255, 220, 120, 0.4) end
end

local function drawGarage()
    if not W.garage then return end
    marker(W.garage.playerEntry, 120, 255, 150)
    for i, exit in ipairs(W.garage.vehicleExits or {}) do
        carBox(exit, 255, 180, 60, ('EXIT %d'):format(i))
    end
    for i, slot in ipairs(W.garage.slots or {}) do
        carBox(slot, 0, 220, 255, ('SLOT %d'):format(i))
    end
end

local function goTo(p, heading)
    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(0) end
    local ped = PlayerPedId()
    SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, false)
    SetEntityHeading(ped, heading or p.h or 0.0)
    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() - t < 8000 do Wait(10) end
    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(400)
end

--- Put the admin back where they typed the command.
--- Only when they actually LEFT: publishing already walks them to the front
--- door, and yanking them away from the house they just built is worse than
--- leaving them there.
local function goHome(origin)
    if not origin then
        DoScreenFadeIn(200)
        return
    end

    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)

    -- Already there? Do not fade the screen for a 2-metre trip.
    if #(at - vector3(origin.x, origin.y, origin.z)) < 3.0 then
        DoScreenFadeIn(200)
        return
    end

    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(0) end

    SetEntityCoords(ped, origin.x, origin.y, origin.z, false, false, false, false)
    SetEntityHeading(ped, origin.h or 0.0)

    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() - t < 8000 do
        Wait(10)
    end
    FreezeEntityPosition(ped, false)

    DoScreenFadeIn(400)
end

--- @param returnHome boolean  put them back where they started
local clearHelipadPlacer

local function reset(returnHome)
    local origin = W and W.origin or nil
    local pendingPhotoToken = W and W.photoToken or nil
    if pendingPhotoToken then
        TriggerServerEvent('cm-house:server:discardPendingPhoto', pendingPhotoToken)
    end

    -- Defined further down; a global, so it resolves at call time. Guarded
    -- because reset() can fire before the garage step is ever reached.
    if ClearGarageCars then ClearGarageCars() end
    clearHelipadPlacer()
    StopPhotoCam(false)
    W = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'wizardClose' })

    if returnHome then
        goHome(origin)
    else
        DoScreenFadeIn(200)
    end
end

-- forward decls
local stepExterior, stepPhoto, stepInterior, stepGarage, stepPublish, replan

-- ============================================================
--  1 -- FEATURES  (UI)
-- ============================================================
local function stepFeatures()
    W.step = 'features'

    local opts = lib.callback.await('cm-house:server:getFeatureOptions', false)
    if not opts then
        lib.notify({ description = 'You cannot create properties.', type = 'error' })
        reset(true)
        return
    end

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'wizardFeatures', data = opts })
end

--- Every toggle re-derives price, stars and garage size on the server, so the
--- UI never computes money and never has to be trusted.
function replan(f)
    local plan = lib.callback.await('cm-house:server:planProperty', false, f)
    if not plan then return nil end
    W.features = f
    W.plan     = plan
    return plan
end

RegisterNUICallback('wizard:replan', function(f, cb)
    local plan = replan(f)
    cb(plan or {})
end)

RegisterNUICallback('wizard:features', function(f, cb)
    cb({})
    local plan = replan(f)
    if not plan then
        lib.notify({ description = 'Could not price that property.', type = 'error' })
        reset(true)
        return
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'wizardClose' })

    lib.notify({
        title = 'Now place the exterior',
        description = 'Stand at the front door and press H.',
        type = 'inform', duration = 6000,
    })
    stepExterior(1)
end)

-- ============================================================
--  2 -- EXTERIOR
-- ============================================================
-- Helipad placement uses a real helicopter, just like garage slots use a real
-- car. The helicopter's final landed transform is the authoritative pad point.
local helipadPlacer = nil
local helipadPlacerPlate = nil

clearHelipadPlacer = function()
    if helipadPlacerPlate then
        TriggerServerEvent('cm-house:server:deletePlacer', helipadPlacerPlate)
    elseif helipadPlacer and DoesEntityExist(helipadPlacer) then
        DeleteEntity(helipadPlacer)
    end
    helipadPlacer = nil
    helipadPlacerPlate = nil
end

local function spawnHelipadPlacer()
    clearHelipadPlacer()
    local ped = PlayerPedId()
    local spawn = GetOffsetFromEntityInWorldCoords(ped, 0.0, 8.0, 1.5)
    local ok, res = lib.callback.await('cm-house:server:spawnPlacer', false, {
        kind = 'helicopter',
        coords = { x = spawn.x, y = spawn.y, z = spawn.z, h = GetEntityHeading(ped) },
    })
    if not ok then
        lib.notify({
            title = 'Cannot place helipad',
            description = res or 'The placement helicopter could not be created.',
            type = 'error', duration = 7000,
        })
        return false
    end

    local deadline = GetGameTimer() + 7000
    local entity = 0
    while GetGameTimer() < deadline do
        entity = NetworkGetEntityFromNetworkId(tonumber(res.netId) or 0)
        if entity ~= 0 and DoesEntityExist(entity) then break end
        Wait(25)
    end
    if entity == 0 or not DoesEntityExist(entity) then
        if res.plate then TriggerServerEvent('cm-house:server:deletePlacer', res.plate) end
        lib.notify({ description = 'The placement helicopter did not appear.', type = 'error' })
        return false
    end

    helipadPlacer = entity
    helipadPlacerPlate = res.plate
    SetEntityInvincible(entity, true)
    SetVehicleEngineOn(entity, true, true, false)
    SetHeliBladesFullSpeed(entity)
    SetVehicleDoorsLocked(entity, 1)
    SetVehicleCustomPrimaryColour(entity, 0, 220, 255)
    SetVehicleCustomSecondaryColour(entity, 0, 220, 255)
    SetPedIntoVehicle(ped, entity, -1)
    return true
end

local function landedHelipadTransform()
    if not helipadPlacer or not DoesEntityExist(helipadPlacer) then
        return nil, 'The placement helicopter is missing.'
    end
    local ped = PlayerPedId()
    if GetPedInVehicleSeat(helipadPlacer, -1) ~= ped then
        return nil, 'Sit in the pilot seat of the placement helicopter.'
    end
    if GetEntitySpeed(helipadPlacer) > 2.5 then
        return nil, 'Land and stop the helicopter before placing the helipad.'
    end
    if GetEntityHeightAboveGround(helipadPlacer) > 4.0 then
        return nil, 'The helicopter is still too high. Land on the intended pad.'
    end
    local c = GetEntityCoords(helipadPlacer)
    return {
        x = tonumber(('%.3f'):format(c.x)),
        y = tonumber(('%.3f'):format(c.y)),
        z = tonumber(('%.3f'):format(c.z)),
        h = tonumber(('%.2f'):format(GetEntityHeading(helipadPlacer))),
    }
end

local EXT = {
    { key='door', req=true, title='FRONT DOOR',
      sub='Where players press E to enter.',
      hint='~b~H~s~ place   ~r~ESC~s~ cancel' },
    -- REQUIRED whenever the property has a garage. It used to be skippable,
    -- and skipping it produced a property the server then refused to publish
    -- -- with the wizard already closed and the work lost.
    { key='garageZone', req=true, title='GARAGE RETURN ZONE',
      sub='Drive HERE to store a car. This property has a garage, so it needs one.',
      hint='~b~H~s~ place   ~r~ESC~s~ cancel' },
    { key='vehicleExit', req=true, title='VEHICLE EXIT',
      sub='Where a car APPEARS after driving out. Keep it clear of the return zone.',
      hint='~b~H~s~ place   ~r~ESC~s~ cancel' },
    { key='helipad', req=true, title='HELIPAD',
      sub='Fly the cyan helicopter to the pad, land, stop and press H.',
      hint='~b~H~s~ save landed helicopter   ~r~ESC~s~ cancel' },
}

stepExterior = function(i)
    local s = EXT[i]
    W.step = 'ext' .. i

    -- Skip steps the feature set says do not exist.
    local skip = false
    if s.key == 'garageZone'  and W.plan.derived.garageCapacity == 0 then skip = true end
    if s.key == 'vehicleExit' and not W.garageZone then skip = true end
    if s.key == 'helipad'     and not W.features.hasHelipad then skip = true end

    if skip then
        if i < #EXT then stepExterior(i + 1) else stepPhoto() end
        return
    end

    if s.key == 'helipad' and not helipadPlacer then
        if not spawnHelipadPlacer() then
            reset(true)
            return
        end
        lib.notify({
            title = 'Place the helipad',
            description = 'Fly the cyan helicopter to the intended pad, land fully, stop and press H.',
            type = 'inform', duration = 9000,
        })
    end

    CreateThread(function()
        while W and W.step == 'ext' .. i do
            local pt = here()
            banner(('EXTERIOR   %s'):format(s.title), s.sub,
                   ('%.1f, %.1f, %.1f'):format(pt.x, pt.y, pt.z))
            help(s.hint)
            drawExterior()

            DisableControlAction(0, 200, true)
            DisableControlAction(0, 199, true)

            if kPlace() then
                if s.key == 'helipad' then
                    local landed, why = landedHelipadTransform()
                    if not landed then
                        lib.notify({ description = why, type = 'error' })
                        goto skip
                    end
                    pt = landed
                end

                -- A car appearing on top of the return zone is a physics accident.
                if s.key == 'vehicleExit' and W.garageZone then
                    local d = #(vector3(pt.x, pt.y, pt.z)
                             - vector3(W.garageZone.x, W.garageZone.y, W.garageZone.z))
                    if d < 6.0 then
                        lib.notify({
                            description = 'Too close to the return zone. Cars would spawn on top of each other.',
                            type = 'error' })
                        goto skip
                    end
                end

                W[s.key] = pt
                if s.key == 'helipad' then clearHelipadPlacer() end
                PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                if i < #EXT then stepExterior(i + 1) else stepPhoto() end
                return
            end

            if not s.req and kSkip() then
                W[s.key] = nil
                PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                if i < #EXT then stepExterior(i + 1) else stepPhoto() end
                return
            end

            if kCancel() then
                if s.key == 'helipad' then clearHelipadPlacer() end
                lib.notify({ description = 'Cancelled. Back where you started.', type = 'inform' })
                reset(true)
                return
            end

            ::skip::
            Wait(0)
        end
    end)
end

-- ============================================================
--  3 -- PHOTO
--  A real screenshot saved into the cm-house files. The camera framing is
--  stored too, so staff can retake the same exterior view later.
-- ============================================================
stepPhoto = function()
    W.step = 'photo'

    local ok, cfg = lib.callback.await('cm-house:server:requestCapture', false, nil)

    if not ok then
        -- Photos are optional. If local file capture is unavailable, keep going and
        -- retain the saved camera framing -- a missing photo must never
        -- block someone from publishing a property.
        lib.notify({
            title = 'No photo',
            description = cfg .. ' Framing the camera instead.',
            type = 'inform', duration = 6000,
        })
        StartPhotoCam(nil, W.door, function(cam)
            if not cam then reset(true) return end
            W.photoCam = cam
            DropPhotoCam()
            stepInterior()
        end)
        return
    end

    StartPhotoCam(nil, W.door, function(cam)
        if not cam then
            lib.notify({ description = 'Cancelled.', type = 'inform' })
            reset(true)
            return
        end

        W.photoCam = cam
        lib.notify({ description = 'Saving property photo…', type = 'inform' })

        CaptureAndSave(cfg, cam, function(url, err)
            if url then
                W.imageUrl = url
                W.photoToken = cfg.token
                lib.notify({ description = 'Photo saved to the house files.', type = 'success' })
            else
                lib.notify({
                    title = 'Photo save failed',
                    description = (err or 'Unknown error') .. ' The live view will be used instead.',
                    type = 'error', duration = 7000,
                })
            end

            stepInterior()
        end)
    end)
end

-- ============================================================
--  4 -- INTERIOR
--  Templates are created only from cm-admin. The property wizard can only
--  select an existing reusable template.
-- ============================================================
stepInterior = function()
    W.step = 'interior'

    -- Re-ask, for the same reason as the garage: another admin may have built
    -- this layout while this wizard was open.
    local list = lib.callback.await(
        'cm-house:server:interiorsFor', false, W.plan.signature)

    if not list then
        lib.notify({
            title = 'Could not read layouts',
            description = 'The server did not answer. Try again.',
            type = 'error' })
        reset(true)
        return
    end

    W.plan.interiors = list

    if #list == 1 then
        -- Exactly one layout for this feature set. Nothing to ask.
        W.interiorTemplateId = list[1].id
        lib.notify({
            description = ('Using the "%s" layout.'):format(list[1].label),
            type = 'inform',
        })
        stepGarage()
        return
    end

    if #list == 0 then
        lib.notify({
            title = 'Interior template required',
            description = 'Create an interior template from cm-admin first, then restart this house setup.',
            type = 'error', duration = 8000,
        })
        reset(true)
        return
    end

    -- Several saved templates exist. Let the admin choose one.
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'wizardPickInterior',
        data = { templates = list, signature = W.plan.signature },
    })
end

RegisterNUICallback('wizard:pickInterior', function(d, cb)
    cb({})
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'wizardClose' })

    local id = tonumber(d.templateId)
    if not id then
        lib.notify({ description = 'Create templates from cm-admin; new layouts are disabled here.', type = 'error' })
        reset(true)
        return
    end
    W.interiorTemplateId = id
    stepGarage()
end)

--- Which physical room. A known list, plus "somewhere else" for anything
--- I have not catalogued.
function openRoomPicker()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'wizardRooms',
        data = { rooms = Config.Rooms },
    })
end

RegisterNUICallback('wizard:room', function(_, cb)
    cb({ ok = false, message = 'Interior templates are created only from cm-admin.' })
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'wizardClose' })
end)

local IN = {
    { key='entry', multi=false, title='SPAWN POINT',
      sub='Where players appear on walking in. Face the way they should face.',
      hint='~b~H~s~ place   ~r~ESC~s~ cancel' },
    -- ONE door. Standing here, E offers "Leave" and "Go to garage" -- there
    -- is no second point to place. A house without a garage simply gets one
    -- option instead of two.
    { key='exitPoint', multi=false, title='THE DOOR',
      sub='Where players press E. From here they can leave, or go to the garage.',
      hint='~b~H~s~ place   ~r~ESC~s~ cancel' },
    { key='weaponStorages', multi=true, title='WEAPON STORAGE',
      sub='Stand at each secure weapon locker and press H.',
      hint='~b~H~s~ add   ~y~BACKSPACE~s~ done   ~r~ESC~s~ cancel' },
    { key='stashes', multi=true, title='STORAGE',
      sub='Stand at each stash, safe or fridge and press H.',
      hint='~b~H~s~ add   ~y~BACKSPACE~s~ done   ~r~ESC~s~ cancel' },
}

function walkInterior(i)
    local s = IN[i]
    W.step = 'in' .. i

    CreateThread(function()
        while W and W.step == 'in' .. i do
            local pt = here()
            local sub = s.sub
            if s.multi then
                sub = ('%s      %d placed'):format(s.sub, #W.interior[s.key])
            end

            banner(('LAYOUT   %s'):format(s.title), sub,
                   ('%.1f, %.1f, %.1f'):format(pt.x, pt.y, pt.z))
            help(s.hint)
            drawInterior()

            DisableControlAction(0, 200, true)
            DisableControlAction(0, 199, true)

            if kPlace() then
                if s.multi then
                    W.interior[s.key][#W.interior[s.key] + 1] = pt
                    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                    lib.notify({
                        description = ('%s %d placed.'):format(s.title:lower(), #W.interior[s.key]),
                        type = 'success' })
                else
                    W.interior[s.key] = pt
                    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                    if i < #IN then walkInterior(i + 1) else nameInterior() end
                    return
                end
            end

            if kSkip() and (s.multi or s.opt) then
                PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                if i < #IN then walkInterior(i + 1) else nameInterior() end
                return
            end

            if kCancel() then
                lib.notify({ description = 'Cancelled. Back where you started.', type = 'inform' })
                reset(true)
                return
            end

            Wait(0)
        end
    end)
end

--- Name it, save it, and it is a template from now on.
function nameInterior()
    W.step = 'name_interior'
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'wizardNameLayout',
        data = {
            kind      = 'interior',
            signature = W.plan.signature,
            weaponStorages = #W.interior.weaponStorages,
            wardrobes = #W.interior.weaponStorages, -- compatibility
            stashes   = #W.interior.stashes,
            suggested = W.room.label,
        },
    })
end

RegisterNUICallback('wizard:nameInterior', function(_, cb)
    cb({ ok = false, message = 'Interior templates are created only from cm-admin.' })
end)

-- ============================================================
--  5 -- GARAGE  (same branching, keyed by capacity)
-- ============================================================
stepGarage = function()
    W.step = 'garage'
    local templateId = tonumber(W.features and W.features.garageTemplateId)
    if not templateId or (W.plan and W.plan.derived and W.plan.derived.garageCapacity or 0) <= 0 then
        W.garageTemplateId = nil
        stepPublish()
        return
    end

    local valid = false
    for _, row in ipairs((W.plan and W.plan.garages) or {}) do
        if tonumber(row.id) == templateId then valid = true break end
    end
    if not valid then
        lib.notify({
            title = 'Garage template unavailable',
            description = 'Select an existing garage template. Create or edit templates from cm-admin.',
            type = 'error', duration = 8000,
        })
        reset(true)
        return
    end

    W.garageTemplateId = templateId
    stepPublish()
end

RegisterNUICallback('wizard:pickGarage', function(_, cb)
    cb({ ok = false, message = 'Garage templates are selected in the property setup and created only from cm-admin.' })
end)

local GA = {
    { key='playerEntry', kind='single', title='THE DOOR',
      sub='Where players arrive from the house and return to it.',
      hint='~b~H~s~ place   ~r~ESC~s~ cancel' },
    { key='vehicleExits', kind='points', min=1, max=(Config.GarageTemplate and Config.GarageTemplate.maxVehicleExits) or 8,
      title='VEHICLE EXITS',
      sub='Add every place where a driver or player on foot can leave this garage.',
      hint='~b~H~s~ add exit   ~g~G~s~ finish exits   ~y~BACKSPACE~s~ undo   ~r~ESC~s~ cancel' },
    { key='slots', kind='slots', title='CAR SPACES',
      sub='Drive the real placement car into each space and press H.',
      hint='~b~H~s~ leave it here   ~y~BACKSPACE~s~ undo the last   ~r~ESC~s~ cancel' },
}

-- A mid-size saloon: if this fits in the space, most vehicles fit.
PLACER_MODEL_NAME = tostring((Config.PlacementVehicles and Config.PlacementVehicles.car) or 'sultan')
local placer      = nil
local placerPlate = nil
local parked      = {}
local parkedPlates = {}
placerLocal = false
local fallbackWarned = false

local function clearPlacer()
    if placerPlate then
        TriggerServerEvent('cm-house:server:deletePlacer', placerPlate)
        placerPlate = nil
    elseif placer and DoesEntityExist(placer) then
        DeleteEntity(placer)
    end
    placer = nil
end

local function clearParked()
    for i = 1, #parked do
        local plate = parkedPlates[i]
        if plate and plate ~= false then
            TriggerServerEvent('cm-house:server:deletePlacer', plate)
        else
            local entity = parked[i]
            if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
        end
    end
    parked, parkedPlates = {}, {}
end

function ClearGarageCars()
    clearPlacer()
    clearParked()
    fallbackWarned = false
end

local function spawnLocalPlacer(at)
    local model = GetHashKey(PLACER_MODEL_NAME)
    RequestModel(model)
    local started = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer() - started < 7000 do Wait(10) end
    if not HasModelLoaded(model) then
        lib.notify({ description = 'Could not load the placement car model.', type = 'error' })
        return false
    end

    local ped = PlayerPedId()
    local c = at or GetEntityCoords(ped)
    local h = at and (at.h or at.w or 0.0) or GetEntityHeading(ped)
    if not at then
        local rad = math.rad(h)
        c = vector3(c.x - math.sin(rad) * 3.5, c.y + math.cos(rad) * 3.5, c.z + 0.2)
    end

    placer = CreateVehicle(model, c.x, c.y, c.z, h, false, false)
    if placer == 0 or not DoesEntityExist(placer) then
        SetModelAsNoLongerNeeded(model)
        return false
    end
    SetEntityAsMissionEntity(placer, true, true)
    SetVehicleOnGroundProperly(placer)
    SetEntityInvincible(placer, true)
    SetVehicleDoorsLocked(placer, 2)
    SetEntityCollision(placer, false, false)
    SetVehicleCustomPrimaryColour(placer, 0, 220, 255)
    SetVehicleCustomSecondaryColour(placer, 0, 220, 255)
    SetEntityAlpha(placer, 200, false)
    FreezeEntityPosition(placer, true)
    SetModelAsNoLongerNeeded(model)

    placerLocal = true
    placerPlate = nil
    return true
end

local function spawnPlacer(at)
    clearPlacer()
    local ped = PlayerPedId()
    local c = at or GetEntityCoords(ped)
    local h = at and (at.h or at.w or 0.0) or GetEntityHeading(ped)

    local ok, res = lib.callback.await('cm-house:server:spawnPlacer', false, {
        coords = { x = c.x, y = c.y, z = c.z, h = h }, kind = 'car', exact = at ~= nil,
    })

    if not ok then
        lib.notify({
            title = 'Placement car fallback',
            description = tostring(res or 'The server could not create the network car. Nudge mode will be used.'),
            type = 'warning', duration = 7000,
        })
        return spawnLocalPlacer(at)
    end

    if res.fallback then return spawnLocalPlacer(at) end

    local started = GetGameTimer()
    local ent = 0
    while GetGameTimer() - started < 9000 do
        ent = NetworkGetEntityFromNetworkId(tonumber(res.netId) or 0)
        if ent ~= 0 and DoesEntityExist(ent) then break end
        Wait(25)
    end

    if ent == 0 or not DoesEntityExist(ent) then
        -- Delete the unreachable server entity before using a local fallback.
        if res.plate then TriggerServerEvent('cm-house:server:deletePlacer', res.plate) end
        lib.notify({
            title = 'Placement car fallback',
            description = 'The network car did not stream into this interior. Nudge mode is active.',
            type = 'warning', duration = 7000,
        })
        return spawnLocalPlacer(at)
    end

    placer = ent
    placerPlate = res.plate
    placerLocal = false
    SetVehicleOnGroundProperly(placer)
    SetVehicleEngineOn(placer, true, true, false)
    SetVehicleDoorsLocked(placer, 1)
    SetVehicleCustomPrimaryColour(placer, 0, 220, 255)
    SetVehicleCustomSecondaryColour(placer, 0, 220, 255)
    SetPedIntoVehicle(ped, placer, -1)
    return true
end

function NudgePlacer()
    if not placer or not DoesEntityExist(placer) then return end
    local c = GetEntityCoords(placer)
    local h = GetEntityHeading(placer)
    local step = IsControlPressed(0, 21) and 0.25 or 0.06
    local cam = GetGameplayCamRot(2)
    local rad = math.rad(cam.z)
    local fwd = vector3(-math.sin(rad), math.cos(rad), 0.0)
    local rgt = vector3(math.cos(rad), math.sin(rad), 0.0)
    local mv = vector3(0.0, 0.0, 0.0)
    if IsControlPressed(0, 172) then mv = mv + fwd end
    if IsControlPressed(0, 173) then mv = mv - fwd end
    if IsControlPressed(0, 174) then mv = mv - rgt end
    if IsControlPressed(0, 175) then mv = mv + rgt end
    if IsControlPressed(0, 10)  then mv = mv + vector3(0.0, 0.0, 1.0) end
    if IsControlPressed(0, 11)  then mv = mv - vector3(0.0, 0.0, 1.0) end
    if #mv > 0.0 then
        SetEntityCoordsNoOffset(placer, c.x + mv.x * step, c.y + mv.y * step, c.z + mv.z * step, false, false, false)
    end
    local turn = IsControlPressed(0, 21) and 2.5 or 0.7
    if IsControlPressed(0, 39) then SetEntityHeading(placer, h - turn) end
    if IsControlPressed(0, 40) then SetEntityHeading(placer, h + turn) end
    DisableControlAction(0, 172, true)
    DisableControlAction(0, 173, true)
    DisableControlAction(0, 174, true)
    DisableControlAction(0, 175, true)
end

local function freezePlaced()
    if not placer or not DoesEntityExist(placer) then return nil end
    local c = GetEntityCoords(placer)
    local h = GetEntityHeading(placer)
    if not placerLocal and GetVehiclePedIsIn(PlayerPedId(), false) == placer then
        TaskLeaveVehicle(PlayerPedId(), placer, 16)
        Wait(250)
    end
    FreezeEntityPosition(placer, true)
    SetEntityInvincible(placer, true)
    SetVehicleDoorsLocked(placer, 2)
    SetEntityAlpha(placer, 140, false)
    SetVehicleEngineOn(placer, false, true, false)
    local n = #parked + 1
    parked[n] = placer
    parkedPlates[n] = placerPlate or false
    placer, placerPlate = nil, nil
    return {
        x = tonumber(('%.3f'):format(c.x)), y = tonumber(('%.3f'):format(c.y)),
        z = tonumber(('%.3f'):format(c.z)), h = tonumber(('%.2f'):format(h)),
    }
end

local function undoPlacedCar()
    local entity = table.remove(parked)
    local plate = table.remove(parkedPlates)
    if plate and plate ~= false then
        TriggerServerEvent('cm-house:server:deletePlacer', plate)
    elseif entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

-- Reused by the standalone admin template editor loaded after this file.
CMHouseGaragePlacer = {
    Spawn = spawnPlacer,
    Freeze = freezePlaced,
    Clear = ClearGarageCars,
    DiscardCurrent = clearPlacer,
    Undo = undoPlacedCar,
    Exists = function() return placer ~= nil and DoesEntityExist(placer) end,
    Entity = function() return placer end,
    IsLocal = function() return placerLocal == true end,
    Nudge = NudgePlacer,
}

local function stepPointList(s)
    return W.garage[s.key]
end

function walkGarage(i)
    local s = GA[i]
    if not s then nameGarage() return end
    W.step = 'ga' .. i
    local cap = W.plan.derived.garageCapacity

    if s.kind == 'slots' and not CMHouseGaragePlacer.Exists() then
        if not CMHouseGaragePlacer.Spawn(nil) then reset(true) return end
        lib.notify({
            title = ('Space 1 of %d'):format(cap),
            description = CMHouseGaragePlacer.IsLocal()
                and 'Nudge the cyan car with arrow keys, then press H.'
                or 'Drive the cyan car into the first space, then press H.',
            type = 'inform', duration = 7000,
        })
    end

    CreateThread(function()
        while W and W.step == 'ga' .. i do
            local pt = here()
            local list = s.kind == 'points' and stepPointList(s) or nil
            local sub = s.sub
            if list then sub = ('%s      %d placed'):format(s.sub, #list) end
            if s.kind == 'slots' then sub = ('%s      %d of %d parked'):format(s.sub, #W.garage.slots, cap) end

            banner(('GARAGE   %s'):format(s.title), sub, ('%.1f, %.1f, %.1f'):format(pt.x, pt.y, pt.z))
            if s.kind == 'slots' and CMHouseGaragePlacer.IsLocal() and CMHouseGaragePlacer.Exists() then
                help('~b~H~s~ leave it here   ~y~BACKSPACE~s~ undo   ~r~ESC~s~ cancel\n~c~ARROWS~s~ move   ~c~[~s~ ~c~]~s~ rotate')
                CMHouseGaragePlacer.Nudge()
            else
                help(s.hint)
            end
            drawGarage()
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 199, true)

            if kPlace() then
                if s.kind == 'single' then
                    W.garage[s.key] = pt
                    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                    walkGarage(i + 1)
                    return
                elseif s.kind == 'points' then
                    if #list >= (tonumber(s.max) or 24) then
                        lib.notify({ description = 'Maximum points reached. Press G to continue.', type = 'error' })
                    else
                        list[#list + 1] = pt
                        PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                    end
                elseif s.kind == 'slots' then
                    if not CMHouseGaragePlacer.Exists() then
                        lib.notify({ description = 'The placement car is missing.', type = 'error' })
                        goto continue
                    end
                    if not CMHouseGaragePlacer.IsLocal() and GetVehiclePedIsIn(PlayerPedId(), false) ~= CMHouseGaragePlacer.Entity() then
                        lib.notify({ description = 'Sit in the placement car before saving this space.', type = 'error' })
                        goto continue
                    end
                    local pos = GetEntityCoords(CMHouseGaragePlacer.Entity())
                    local clash
                    for j, old in ipairs(W.garage.slots) do
                        if #(pos - vector3(old.x, old.y, old.z)) < 3.2 then clash = j break end
                    end
                    if clash then
                        lib.notify({ description = ('Too close to space %d.'):format(clash), type = 'error' })
                        goto continue
                    end
                    local coords = CMHouseGaragePlacer.Freeze()
                    if not coords then goto continue end
                    W.garage.slots[#W.garage.slots + 1] = coords
                    local n = #W.garage.slots
                    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                    if n >= cap then
                        lib.notify({ title = 'All spaces placed', description = ('%d real car spaces saved.'):format(cap), type = 'success' })
                        Wait(500)
                        nameGarage()
                        return
                    end
                    Wait(250)
                    if not CMHouseGaragePlacer.Spawn(nil) then reset(true) return end
                    lib.notify({ description = ('Park space %d of %d.'):format(n + 1, cap), type = 'inform' })
                end
            end

            if s.kind == 'points' and kFinish() then
                if #list < (tonumber(s.min) or 0) then
                    lib.notify({ description = ('Place at least %d point%s.'):format(s.min, s.min == 1 and '' or 's'), type = 'error' })
                else
                    walkGarage(i + 1)
                    return
                end
            end

            if kSkip() then
                if s.kind == 'points' and #list > 0 then
                    table.remove(list)
                    PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                elseif s.kind == 'slots' and #W.garage.slots > 0 then
                    CMHouseGaragePlacer.Undo()
                    table.remove(W.garage.slots)
                    clearPlacer()
                    if not CMHouseGaragePlacer.Spawn(nil) then reset(true) return end
                    lib.notify({ description = ('Park space %d again.'):format(#W.garage.slots + 1), type = 'inform' })
                end
            end

            if kCancel() then
                CMHouseGaragePlacer.Clear()
                reset(true)
                return
            end
            ::continue::
            Wait(0)
        end
    end)
end

function nameGarage()
    W.step = 'name_garage'
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'wizardNameLayout',
        data = {
            kind      = 'garage',
            capacity  = W.plan.derived.garageCapacity,
            suggested = W.garageRoom.label,
        },
    })
end

RegisterNUICallback('wizard:nameGarage', function(_, cb)
    cb({ ok = false, message = 'Garage templates are created only from cm-admin.' })
end)

-- ============================================================
--  6 -- PUBLISH
-- ============================================================
stepPublish = function()
    W.step = 'publish'

    -- Back to the front door, so the summary is framed by the actual house.
    if W.door then goTo(W.door, (W.door.h or 0.0) + 180.0) end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'wizardPublish',
        data = {
            features = W.features,
            derived  = W.plan.derived,
            hasGarage = W.plan.derived.garageCapacity > 0,
            hasHelipad = W.features.hasHelipad,
        },
    })
end

RegisterNUICallback('wizard:publish', function(form, cb)
    SetNuiFocus(false, false)

    local ok, msg = lib.callback.await('cm-house:server:createHouse', false, {
        houseNumber = form.houseNumber,
        label       = form.label,

        features    = W.features,
        door        = W.door,
        garageZone  = W.garageZone,
        vehicleExit = W.vehicleExit,
        helipad     = W.helipad,
        photoCam    = W.photoCam,
        imageUrl    = W.imageUrl,
        photoToken  = W.photoToken,

        interiorTemplateId = W.interiorTemplateId,
        garageTemplateId   = W.garageTemplateId,
    })

    cb({ ok = ok, message = msg })

    if not ok then
        lib.notify({ title = 'Not published', description = msg, type = 'error' })
        SetNuiFocus(true, true)
        return
    end

    lib.notify({ title = 'Published', description = msg, type = 'success' })
    reset()
end)

RegisterNUICallback('wizard:cancel', function(_, cb)
    cb({})
    lib.notify({ description = 'Cancelled.', type = 'inform' })
    reset(true)
end)

-- ============================================================
RegisterNetEvent('cm-house:client:startPlacement', function()
    if not lib or not lib.notify then
        print('[cm-house] ^1ox_lib is not loaded.^7')
        return
    end
    if W then
        lib.notify({ description = 'You are already building a property.', type = 'error' })
        return
    end
    W = blank()

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    W.origin = {
        x = c.x, y = c.y, z = c.z,
        h = GetEntityHeading(ped),
        bucket = 0,
    }

    stepFeatures()
end)

RegisterNetEvent('cm-house:client:notify', function(msg, kind)
    lib.notify({ description = msg, type = kind or 'inform' })
end)

-- Note: the authoritative 'cm-house:client:forceExit' handler lives in
-- cl_interior.lua (it leaves the garage state, closes the door prompt, clears
-- the busy lock, and fades in). A second handler here previously only faded the
-- screen and was removed to avoid double execution.

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ClearGarageCars()
    clearHelipadPlacer()
    if W then reset() end
end)

--- Live address check while the admin types, so a clash is caught before the
--- Publish button is ever pressed.
RegisterNUICallback('wizard:checkAddress', function(d, cb)
    local ok, msg = lib.callback.await('cm-house:server:checkAddress', false, d.number)
    cb({ ok = ok, message = msg })
end)
