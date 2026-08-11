local U = CMVehicles.Utils
local Config = CMVehicles.Config


local function getMileageSpeedMultiplier(mileage)
    mileage = tonumber(mileage) or 0.0
    if mileage < 5000.0 then return 1.0 end
    if mileage < 10000.0 then return 0.98 end
    if mileage < 20000.0 then return 0.95 end
    if mileage < 50000.0 then return 0.90 end
    return 0.85
end

-- ════════════════════════════════════════════════════════════════════
--  UNIFIED PERFORMANCE
--
--  IMPORTANT: mileage wear and tuning BOTH want to set the engine power
--  multiplier. SetVehicleEnginePowerMultiplier is absolute, not additive, so if
--  they each called it independently whichever ran last would silently erase the
--  other. Everything therefore goes through this one function, which composes:
--
--      final = stock  x  mileageMultiplier  x  tuningMultiplier
--
--  Tuning is class-scaled because GTA's own engine mod is far too weak to feel
--  (~+15% at Level 4). A Super at Level 4 gets the full class gain (+60%).
-- ════════════════════════════════════════════════════════════════════

-- Engine level fitted on the car: GTA index -1 = stock, 0..3 = Level 1..4.
local function engineLevelOf(vehicle)
    local idx = GetVehicleMod(vehicle, 11)
    if idx == nil or idx < 0 then return 0 end
    return math.min(4, idx + 1)
end

-- How much faster this car gets at its current engine level.
function CMVehicles.Client.GetTuningMultiplier(vehicle)
    local cfg = Config.Tuning or {}
    if cfg.enabled == false then return 1.0 end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 1.0 end

    local level = engineLevelOf(vehicle)
    if level <= 0 then return 1.0 end

    local class = GetVehicleClass(vehicle)
    local gain = (cfg.ClassGain and cfg.ClassGain[class]) or cfg.defaultGain or 0.25

    local fractions = cfg.LevelFraction or { 0.25, 0.50, 0.75, 1.00 }
    local frac = fractions[level] or 1.0

    return 1.0 + (gain * frac)
end

-- Tyre level is not a GTA mod slot; we store it in the saved mods JSON.
function CMVehicles.Client.GetTyreLevel(vehicle)
    if not vehicle or vehicle == 0 then return 0 end
    local ok, lvl = pcall(function() return Entity(vehicle).state.cmTyreLevel end)
    return math.max(0, math.min(4, tonumber(ok and lvl or 0) or 0))
end

local function applyTyreLevel(vehicle, level)
    local tcfg = (Config.Tuning and Config.Tuning.Tyres) or {}
    if tcfg.enabled == false then return end
    level = math.max(0, math.min(tonumber(tcfg.maxLevel) or 4, tonumber(level) or 0))

    -- Grip. GTA has no direct "grip" native, so we use the traction-loss knob:
    -- 1.0 = normal, lower = MORE grip.
    local perLevel = tonumber(tcfg.gripPerLevel) or 0.05
    local reduce = 1.0 - (level * perLevel)
    pcall(function() SetVehicleReduceGrip(vehicle, false) end)
    pcall(function() SetVehicleGripLevel(vehicle, reduce) end)

    -- Bulletproof comes free at higher levels.
    local bpFrom = tonumber(tcfg.bulletproofFromLevel) or 3
    if level >= bpFrom then
        SetVehicleTyresCanBurst(vehicle, false)
    end

    pcall(function() Entity(vehicle).state:set('cmTyreLevel', level, true) end)
end
CMVehicles.Client.ApplyTyreLevel = applyTyreLevel

-- The ONE place engine power/torque is set.
function CMVehicles.Client.ApplyPerformance(vehicle, metadata)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    metadata = type(metadata) == 'table' and metadata or {}

    -- Mods must be live for GTA to even acknowledge the fitted parts.
    SetVehicleModKit(vehicle, 0)

    local mileageMul = getMileageSpeedMultiplier(metadata.mileage)  -- <= 1.0 (wear)
    local tuneMul    = CMVehicles.Client.GetTuningMultiplier(vehicle)  -- >= 1.0 (upgrade)
    local final      = mileageMul * tuneMul
    local catalogMaxSpeed = tonumber(metadata.catalogMaxSpeedKph or metadata.catalog_max_speed_kph)

    -- SetVehicleEnginePowerMultiplier takes a PERCENT delta (0 = stock).
    SetVehicleEnginePowerMultiplier(vehicle, (final - 1.0) * 100.0)
    SetVehicleEngineTorqueMultiplier(vehicle, 1.0 + ((final - 1.0) * ((Config.Tuning and Config.Tuning.torqueFactorOfGain) or 0.70)))

    -- Raise the actual top-speed ceiling. Without this the car accelerates
    -- harder but still bumps into its stock limiter, so the upgrade is invisible
    -- at the top end -- which is exactly why native mods feel pointless.
    local baseSpeed = GetVehicleEstimatedMaxSpeed(vehicle) or 0.0
    local target = catalogMaxSpeed and catalogMaxSpeed > 0 and (catalogMaxSpeed / 3.6) * final or baseSpeed * tuneMul
    if target > 0.0 and (catalogMaxSpeed or tuneMul > 1.0) then
        pcall(function() ModifyVehicleTopSpeed(vehicle, target - baseSpeed) end)
        pcall(function() SetVehicleMaxSpeed(vehicle, target) end)
    end
end

-- Kept for compatibility; now just delegates so nothing can bypass the compose.
local function applyMileagePerformance(vehicle, metadata)
    CMVehicles.Client.ApplyPerformance(vehicle, metadata)
end

-- Re-apply saved cosmetic mods (colors, extras, wheels, tuning) on spawn so
-- customization survives restarts. Safe: unknown/absent fields are skipped.
local function applyVehicleMods(vehicle, mods)
    if not vehicle or vehicle == 0 or type(mods) ~= 'table' then return end
    SetVehicleModKit(vehicle, 0)

    if mods.primaryColor ~= nil and mods.secondaryColor ~= nil then
        SetVehicleColours(vehicle, tonumber(mods.primaryColor) or 111, tonumber(mods.secondaryColor) or 111)
    end
    if mods.pearlColor ~= nil and mods.wheelColor ~= nil then
        SetVehicleExtraColours(vehicle, tonumber(mods.pearlColor) or 111, tonumber(mods.wheelColor) or 111)
    end
    if type(mods.customPrimary) == 'table' then
        SetVehicleCustomPrimaryColour(vehicle, tonumber(mods.customPrimary.r) or 0, tonumber(mods.customPrimary.g) or 0, tonumber(mods.customPrimary.b) or 0)
    end
    if type(mods.customSecondary) == 'table' then
        SetVehicleCustomSecondaryColour(vehicle, tonumber(mods.customSecondary.r) or 0, tonumber(mods.customSecondary.g) or 0, tonumber(mods.customSecondary.b) or 0)
    end
    if mods.wheelType ~= nil then SetVehicleWheelType(vehicle, tonumber(mods.wheelType) or 0) end
    if mods.windowTint ~= nil then SetVehicleWindowTint(vehicle, tonumber(mods.windowTint) or 0) end
    if mods.plateIndex ~= nil then SetVehicleNumberPlateTextIndex(vehicle, tonumber(mods.plateIndex) or 0) end
    if mods.livery ~= nil then SetVehicleLivery(vehicle, tonumber(mods.livery) or -1) end

    if type(mods.extras) == 'table' then
        for extraId, enabled in pairs(mods.extras) do
            local id = tonumber(extraId)
            if id and DoesExtraExist(vehicle, id) then
                SetVehicleExtra(vehicle, id, enabled == true and 0 or 1)
            end
        end
    end

    if type(mods.mods) == 'table' then
        for modType, modIndex in pairs(mods.mods) do
            local t, idx = tonumber(modType), tonumber(modIndex)
            if t and idx then
                if t == 18 or t == 22 then
                    ToggleVehicleMod(vehicle, t, idx == 1)
                else
                    SetVehicleMod(vehicle, t, idx, mods.customWheels == true)
                end
            end
        end
    end

    if type(mods.neons) == 'table' then
        for i = 0, 3 do SetVehicleNeonLightEnabled(vehicle, i, mods.neons[i + 1] == true) end
        if type(mods.neonColor) == 'table' then
            SetVehicleNeonLightsColour(vehicle, tonumber(mods.neonColor.r) or 255, tonumber(mods.neonColor.g) or 255, tonumber(mods.neonColor.b) or 255)
        end
    end
    if mods.turbo ~= nil then ToggleVehicleMod(vehicle, 18, mods.turbo == true) end
    if mods.xenon ~= nil then ToggleVehicleMod(vehicle, 22, mods.xenon == true) end

    -- Synthetic tyre level (not a GTA mod slot; we persist it ourselves).
    if mods.tyreLevel ~= nil then
        applyTyreLevel(vehicle, tonumber(mods.tyreLevel) or 0)
    end
    if mods.bulletproofTyres ~= nil then
        SetVehicleTyresCanBurst(vehicle, mods.bulletproofTyres ~= true)
    end
    local catalogMaxSpeed = tonumber(mods.catalogMaxSpeedKph or mods.catalog_max_speed_kph)
    if catalogMaxSpeed and catalogMaxSpeed > 0 then
        pcall(function() SetVehicleMaxSpeed(vehicle, catalogMaxSpeed / 3.6) end)
    end
end
CMVehicles.Client.ApplyVehicleMods = applyVehicleMods

local function waitForNetVehicle(netId)
    local timeout = GetGameTimer() + 7000
    while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < timeout do Wait(0) end
    local veh = NetworkGetEntityFromNetworkId(netId)
    while (not veh or veh == 0 or not DoesEntityExist(veh)) and GetGameTimer() < timeout do
        veh = NetworkGetEntityFromNetworkId(netId)
        Wait(0)
    end
    return veh
end

-- House-garage vehicles use client-assisted network creation. This is not a
-- public spawn API: the server sends a one-time token, then validates the model,
-- position, source and returned network entity before accepting it.
local pendingGarageCreates = {}
local activeConditionFinalizers = {}
local garageQuarantineSeen = {}
local startGarageProtection

local function normalizedHealth(value, defaultValue)
    if U.NormalizeSavedHealth then return U.NormalizeSavedHealth(value, defaultValue) end
    if U.NormalizeHealth then return U.NormalizeHealth(value, defaultValue) end
    local n = tonumber(value)
    if n == nil or n ~= n then n = tonumber(defaultValue) or 1000.0 end
    if n > 0.0 and n <= 1.0 then n = n * 1000.0 end
    return math.max(0.0, math.min(1000.0, n)) + 0.0
end

local function normalizedGarageHealth(value, defaultValue)
    return normalizedHealth(value, defaultValue)
end

local function normalizedBootstrapHealth(value, defaultValue)
    if U.NormalizeBootstrapHealth then return U.NormalizeBootstrapHealth(value, defaultValue) end
    local n = tonumber(value)
    if n == nil or n ~= n or n <= 1.0 then n = tonumber(defaultValue) or 1000.0 end
    return math.max(100.0, math.min(1000.0, n)) + 0.0
end

local function garageConditionTolerance()
    return math.max(0.5, tonumber(Config.Garage and Config.Garage.conditionTolerance) or 5.0)
end

local function savedGarageCondition(vehicle, fallback)
    fallback = type(fallback) == 'table' and fallback or {}
    local state = Entity(vehicle).state
    return {
        engineHealth = normalizedGarageHealth(state.cmEngineHealth ~= nil and state.cmEngineHealth or fallback.engineHealth, 1000.0),
        bodyHealth = normalizedGarageHealth(state.cmBodyHealth ~= nil and state.cmBodyHealth or fallback.bodyHealth, 1000.0),
        tankHealth = normalizedGarageHealth(state.cmTankHealth ~= nil and state.cmTankHealth or fallback.tankHealth, 1000.0),
        dirtLevel = tonumber(state.cmDirtLevel ~= nil and state.cmDirtLevel or fallback.dirtLevel) or 0.0,
        fuel = tonumber(state.cmFuel ~= nil and state.cmFuel or fallback.fuel) or 100.0,
    }
end

local function physicalConditionBelowSaved(vehicle, data)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    data = type(data) == 'table' and data or savedGarageCondition(vehicle)
    local tolerance = garageConditionTolerance()
    local currentEngine = tonumber(GetVehicleEngineHealth(vehicle)) or 0.0
    local currentBody = tonumber(GetVehicleBodyHealth(vehicle)) or 0.0
    local currentTank = tonumber(GetVehiclePetrolTankHealth(vehicle)) or 0.0
    return currentEngine < (normalizedGarageHealth(data.engineHealth, 1000.0) - tolerance)
        or currentBody < (normalizedGarageHealth(data.bodyHealth, 1000.0) - tolerance)
        or currentTank < (normalizedGarageHealth(data.tankHealth, 1000.0) - tolerance)
end

local function placeGarageVehicleAtSlot(vehicle, x, y, z, heading)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local offset = tonumber(Config.Garage and Config.Garage.spawnZOffset) or 0.45
    SetEntityCoordsNoOffset(vehicle, x + 0.0, y + 0.0, z + offset, false, false, false)
    SetEntityHeading(vehicle, heading + 0.0)
    RequestCollisionAtCoord(x + 0.0, y + 0.0, z + 0.0)
    local deadline = GetGameTimer() + 2500
    while not HasCollisionLoadedAroundEntity(vehicle) and GetGameTimer() < deadline do Wait(0) end
    if not (Config.Garage and Config.Garage.settleOnGround == false) then
        pcall(function() SetVehicleOnGroundProperly(vehicle) end)
        Wait(0)
        pcall(function() SetVehicleOnGroundProperly(vehicle) end)
    end
end

local function quarantineGarageVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleEngineOn(vehicle, false, true, true)
    SetVehicleUndriveable(vehicle, true)
    SetVehicleHandbrake(vehicle, true)
    FreezeEntityPosition(vehicle, true)
    SetEntityInvincible(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, false)
    pcall(function() SetEntityProofs(vehicle, true, true, true, true, true, true, true, true) end)
    -- CRITICAL: collision/physics must stay ENABLED. On this artifact a vehicle
    -- whose physics never activate does not accept SetVehicle*Health writes and
    -- reads engine/body/tank = 0, which is exactly the "condition initialization
    -- failed (engine 0, body 0, tank 0)" loop. Frozen + invincible + proofs is
    -- already a complete shield against adjacent-slot contact damage; disabling
    -- collision added nothing except a dead damage skeleton.
    SetEntityCollision(vehicle, true, true)
    SetEntityVisible(vehicle, false, false)
    SetEntityAlpha(vehicle, 0, false)
end

local function revealProtectedGarageVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    SetVehicleEngineOn(vehicle, false, true, true)
    SetVehicleUndriveable(vehicle, true)
    SetVehicleHandbrake(vehicle, true)
    FreezeEntityPosition(vehicle, true)
    SetEntityInvincible(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, false)
    pcall(function() SetEntityProofs(vehicle, true, true, true, true, true, true, true, true) end)
    SetEntityCollision(vehicle, true, true)
    local visible = false
    local alpha = 255
    pcall(function() visible = IsEntityVisible(vehicle) == true end)
    pcall(function() alpha = tonumber(GetEntityAlpha(vehicle)) or 255 end)
    if not visible or alpha < 250 then
        SetEntityVisible(vehicle, true, false)
        ResetEntityAlpha(vehicle)
        SetEntityAlpha(vehicle, 255, false)
    end
end

local WINDOW_BONES = {
    [0] = { 'window_lf', 'window_lf1', 'window_lf2', 'window_lf3' },
    [1] = { 'window_rf', 'window_rf1', 'window_rf2', 'window_rf3' },
    [2] = { 'window_lr', 'window_lr1', 'window_lr2', 'window_lr3' },
    [3] = { 'window_rr', 'window_rr1', 'window_rr2', 'window_rr3' },
    [4] = { 'window_lm' },
    [5] = { 'window_rm' },
    [6] = { 'windscreen' },
    [7] = { 'windscreen_r' },
}

local function vehicleHasWindowBone(vehicle, windowIndex)
    local names = WINDOW_BONES[windowIndex]
    if not names then return false end
    for _, boneName in ipairs(names) do
        local ok, boneIndex = pcall(GetEntityBoneIndexByName, vehicle, boneName)
        if ok and tonumber(boneIndex) and tonumber(boneIndex) ~= -1 then return true end
    end
    return false
end

local function repairLegacyGlassSnapshot(vehicle, snapshot)
    snapshot = type(snapshot) == 'table' and snapshot or {}
    local schema = tonumber(snapshot.windowSchema or snapshot.conditionVersion or snapshot.version) or 0
    if schema >= 2 or type(snapshot.windows) ~= 'table' then return false end

    -- v1.3.2.0-v1.3.2.5 window maps are not trustworthy because unsupported
    -- indexes were saved as false. Repair every glass bone that exists once;
    -- the server startup migration removes the legacy map from the database.
    for i = 0, 7 do
        if vehicleHasWindowBone(vehicle, i) then pcall(FixVehicleWindow, vehicle, i) end
    end
    return true
end

local function applyDamageSnapshot(vehicle, snapshot)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    snapshot = type(snapshot) == 'table' and snapshot or {}
    repairLegacyGlassSnapshot(vehicle, snapshot)

    -- Glass damage is trusted only from the model-aware schema-2 format.
    -- Legacy windows[index]=false maps are ignored because unsupported window
    -- indexes were falsely saved as broken on many vehicle models.
    local schema = tonumber(snapshot.windowSchema or snapshot.conditionVersion or snapshot.version) or 0
    local brokenWindows = schema >= 2 and type(snapshot.brokenWindows) == 'table'
        and snapshot.brokenWindows or {}
    for i = 0, 7 do
        local broken = brokenWindows[tostring(i)]
        if broken == nil then broken = brokenWindows[i] end
        if broken == true and vehicleHasWindowBone(vehicle, i) then
            pcall(SmashVehicleWindow, vehicle, i)
        end
    end

    local doors = type(snapshot.doors) == 'table' and snapshot.doors or {}
    for i = 0, 7 do
        local door = doors[i] or doors[tostring(i)]
        if type(door) == 'table' then
            if door.broken == true or door.damaged == true then
                pcall(SetVehicleDoorBroken, vehicle, i, false)
            elseif tonumber(door.angle) and tonumber(door.angle) > 0.05 then
                pcall(SetVehicleDoorOpen, vehicle, i, false, true)
            end
        elseif door == true then
            pcall(SetVehicleDoorBroken, vehicle, i, false)
        end
    end

    local tyres = type(snapshot.tyres) == 'table' and snapshot.tyres or {}
    for i = 0, 7 do
        local tyre = tyres[i] or tyres[tostring(i)]
        if type(tyre) == 'table' and tyre.burst == true then
            pcall(SetVehicleTyreBurst, vehicle, i, tyre.onRim == true, 1000.0)
        elseif tyre == true then
            pcall(SetVehicleTyreBurst, vehicle, i, false, 1000.0)
        end
    end
end

local function conditionMatches(vehicle, engine, body, tank)
    local tolerance = garageConditionTolerance()
    local gotEngine = tonumber(GetVehicleEngineHealth(vehicle)) or 0.0
    local gotBody = tonumber(GetVehicleBodyHealth(vehicle)) or 0.0
    local gotTank = tonumber(GetVehiclePetrolTankHealth(vehicle)) or 0.0
    local engineOk = engine <= tolerance and gotEngine <= tolerance
        or math.abs(gotEngine - engine) <= tolerance
    local bodyOk = body <= tolerance and gotBody <= tolerance
        or math.abs(gotBody - body) <= tolerance
    local tankOk = tank <= tolerance and gotTank <= tolerance
        or math.abs(gotTank - tank) <= tolerance
    return engineOk and bodyOk and tankOk, { engine = gotEngine, body = gotBody, tank = gotTank }
end

local function applyPhysicalCondition(vehicle, data, options)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false, nil, 'vanished'
    end
    data = type(data) == 'table' and data or {}
    options = type(options) == 'table' and options or {}
    local engine = normalizedGarageHealth(data.engineHealth, 1000.0)
    local body = normalizedGarageHealth(data.bodyHealth, 1000.0)
    local tank = normalizedGarageHealth(data.tankHealth, 1000.0)

    local coords = GetEntityCoords(vehicle)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local collisionDeadline = GetGameTimer() + 2500
    while not HasCollisionLoadedAroundEntity(vehicle) and GetGameTimer() < collisionDeadline do Wait(0) end
    if not DoesEntityExist(vehicle) then return false, nil, 'vanished' end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleModKit(vehicle, 0)
    if type(data.mods) == 'table' then applyVehicleMods(vehicle, data.mods) end
    SetVehicleDirtLevel(vehicle, (tonumber(data.dirtLevel) or 0.0) + 0.0)
    CMVehicles.Client.SetVehicleFuel(vehicle, tonumber(data.fuel) or 100.0)

    local deadline = GetGameTimer()
        + math.max(1000, tonumber(options.timeoutMs)
            or tonumber(Config.Garage and Config.Garage.conditionApplyMs) or 3000)
    local live = { engine = 0.0, body = 0.0, tank = 0.0 }

    while true do
        if not DoesEntityExist(vehicle) then return false, nil, 'vanished' end
        NetworkRequestControlOfEntity(vehicle)
        if NetworkHasControlOfEntity(vehicle) or options.requireControl == false then
            -- This repair is strictly an initialization baseline. It may run only
            -- before cmConditionReady becomes true, never as parked protection.
            if options.repairBaseline ~= false then
                pcall(function() SetEntityHealth(vehicle, math.max(1000, GetEntityMaxHealth(vehicle))) end)
                SetVehicleFixed(vehicle)
                SetVehicleDeformationFixed(vehicle)
            end
            -- Lua 5.4 integer/float subtype: these natives are float-typed and
            -- CitizenFX does not safely convert a Lua integer argument, it
            -- reinterprets the bits (e.g. integer 1000 becomes ~1.4e-42). Force
            -- a genuine float here even though engine/body/tank already went
            -- through U.ClampHealth, as defense-in-depth at the actual native
            -- call site -- the same pattern CMVehicles.Client.SetVehicleFuel
            -- already uses for the fuel native just above.
            SetVehicleEngineHealth(vehicle, engine + 0.0)
            SetVehicleBodyHealth(vehicle, body + 0.0)
            SetVehiclePetrolTankHealth(vehicle, tank + 0.0)
            applyDamageSnapshot(vehicle, data.conditionState)
        end

        Wait(0)
        local ok
        ok, live = conditionMatches(vehicle, engine, body, tank)
        if ok then return true, live end
        if GetGameTimer() >= deadline then break end
        Wait(100)
    end

    return false, live, 'unverified'
end

local function deletePendingGarageVehicle(token, netId)
    token = tostring(token or '')
    local vehicle = pendingGarageCreates[token]
    if (not vehicle or vehicle == 0) and tonumber(netId) and tonumber(netId) > 0 then
        vehicle = NetworkGetEntityFromNetworkId(tonumber(netId))
    end
    pendingGarageCreates[token] = nil
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    NetworkRequestControlOfEntity(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
    if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
    if not DoesEntityExist(vehicle) then return end

    -- One delete call is not enough when network ownership is migrating. Keep
    -- requesting control and deleting until the rejected quarantine entity is
    -- confirmed gone, preventing an unusable ghost beside the accepted car.
    CreateThread(function()
        local deadline = GetGameTimer() + 5000
        repeat
            if not DoesEntityExist(vehicle) then return end
            NetworkRequestControlOfEntity(vehicle)
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteVehicle(vehicle)
            if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
            if not DoesEntityExist(vehicle) then return end
            Wait(100)
        until GetGameTimer() >= deadline
        if DoesEntityExist(vehicle) then
            print(('[cm-vehicles] ^1rejected garage entity %s could not be deleted after 5 seconds^7')
                :format(tostring(netId or vehicle)))
        end
    end)
end

RegisterNetEvent('cm-vehicles:client:createGarageNetworkVehicle', function(token, data)
    token = tostring(token or '')
    data = type(data) == 'table' and data or {}
    local spawn = type(data.spawn) == 'table' and data.spawn or {}
    local modelHash = tonumber(data.modelHash) or joaat(tostring(data.model or ''))
    if token == '' or not modelHash or modelHash == 0 then
        TriggerServerEvent('cm-vehicles:server:garageVehicleCreated', token, 0, 'Garage vehicle request was invalid.')
        return
    end

    RequestModel(modelHash)
    local modelDeadline = GetGameTimer() + 10000
    while not HasModelLoaded(modelHash) and GetGameTimer() < modelDeadline do Wait(0) end
    if not HasModelLoaded(modelHash) then
        TriggerServerEvent('cm-vehicles:server:garageVehicleCreated', token, 0,
            ('Vehicle model %s could not be loaded.'):format(tostring(data.model or modelHash)))
        return
    end

    local x, y, z = tonumber(spawn.x), tonumber(spawn.y), tonumber(spawn.z)
    local heading = tonumber(spawn.h or spawn.w or spawn.heading) or 0.0
    if not x or not y or not z then
        SetModelAsNoLongerNeeded(modelHash)
        TriggerServerEvent('cm-vehicles:server:garageVehicleCreated', token, 0, 'Garage slot coordinates were invalid.')
        return
    end

    local spawnOffset = tonumber(Config.Garage and Config.Garage.spawnZOffset) or 0.45
    local vehicle = CreateVehicle(modelHash, x + 0.0, y + 0.0, z + spawnOffset, heading + 0.0, true, true)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        SetModelAsNoLongerNeeded(modelHash)
        TriggerServerEvent('cm-vehicles:server:garageVehicleCreated', token, 0, 'CreateVehicle failed on the garage client.')
        return
    end

    -- Mark the entity with immutable identity before any lengthy condition or
    -- network convergence. Server reconciliation can now find and remove this
    -- provisional copy even if the request times out before registration.
    local provisionalState = Entity(vehicle).state
    provisionalState:set('cmVehicleId', tonumber(data.id), true)
    provisionalState:set('cmPlate', tostring(data.plate or ''), true)
    provisionalState:set('cmGarageCreateToken', token, true)

    -- Never allow a newly-created garage car to enter the physics world before
    -- its saved condition has been applied. Previously the car remained visible,
    -- collidable and unfrozen while collision/model data loaded; nearby slots
    -- could hit it during those frames and permanently lower engine health.
    quarantineGarageVehicle(vehicle)
    placeGarageVehicleAtSlot(vehicle, x, y, z, heading)
    quarantineGarageVehicle(vehicle)

    -- Bootstrap with safe health only. The real saved condition (including a
    -- genuine zero/destroyed engine) is applied later by finalizeSpawn.
    local bootstrap = {
        engineHealth = normalizedBootstrapHealth(data.bootstrapEngineHealth, 1000.0),
        bodyHealth = normalizedBootstrapHealth(data.bootstrapBodyHealth, 1000.0),
        tankHealth = normalizedBootstrapHealth(data.bootstrapTankHealth, 1000.0),
        fuel = data.fuel, dirtLevel = 0.0, mods = data.mods,
    }
    local conditionOk, live, reason = applyPhysicalCondition(vehicle, bootstrap, { repairBaseline = true })
    SetModelAsNoLongerNeeded(modelHash)

    if not conditionOk and reason == 'vanished' then
        -- The entity was deleted out from under us mid-initialization (bucket
        -- change, lockdown, or an external cleanup). Only THIS is a real
        -- failure; report it as what it is instead of the old misleading
        -- "engine 0, body 0, tank 0".
        TriggerServerEvent('cm-vehicles:server:garageVehicleCreated', token, 0,
            'The garage vehicle entity was deleted during initialization (check routing bucket / entity lockdown).')
        return
    end

    if not conditionOk then
        -- The car exists but the health writes have not verified yet. Do NOT
        -- delete it -- that was the failure loop. Register it anyway: the
        -- finalizeSpawn owns the retry loop and keeps the entity quarantined
        -- until the saved condition verifies. Parked protection never writes health.
        print(('[cm-vehicles] garage condition not verified yet (engine %.0f, body %.0f, tank %.0f) - registering quarantined; the finalizer will retry it.')
            :format(tonumber(live and live.engine) or 0, tonumber(live and live.body) or 0,
                tonumber(live and live.tank) or 0))
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    NetworkRegisterEntityAsNetworked(vehicle)

    -- Ask for the id directly rather than waiting on NetworkGetEntityIsNetworked.
    -- Here the CLIENT created the entity so the native is trustworthy, but the
    -- id is the thing we actually need -- and asking for it straight away drops
    -- a seven-second worst case to a few frames.
    local netId = 0
    local networkDeadline = GetGameTimer() + 7000
    while GetGameTimer() < networkDeadline do
        local ok, value = pcall(NetworkGetNetworkIdFromEntity, vehicle)
        netId = ok and tonumber(value) or 0
        if netId > 0 then break end
        Wait(0)
    end

    if netId <= 0 then
        DeleteVehicle(vehicle)
        if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
        TriggerServerEvent('cm-vehicles:server:garageVehicleCreated', token, 0,
            'The garage client created a local vehicle instead of a network vehicle.')
        return
    end

    SetNetworkIdCanMigrate(netId, true)
    placeGarageVehicleAtSlot(vehicle, x, y, z, heading)
    SetVehicleDoorsLocked(vehicle, 0)
    SetVehicleDoorsLockedForAllPlayers(vehicle, false)

    -- Apply the REAL saved condition on the client that created/owns the entity
    -- before the server acceptance round-trip. The old build always reset the
    -- car to hidden + cmConditionReady=false here and depended on a later one-shot
    -- finalize event. If that event arrived before the entity streamed, the car
    -- stayed invisible forever. This local convergence closes that race.
    local savedCondition = {
        engineHealth = normalizedGarageHealth(data.engineHealth, 1000.0),
        bodyHealth = normalizedGarageHealth(data.bodyHealth, 1000.0),
        tankHealth = normalizedGarageHealth(data.tankHealth, 1000.0),
        dirtLevel = tonumber(data.dirtLevel) or 0.0,
        fuel = tonumber(data.fuel) or 100.0,
        mods = type(data.mods) == 'table' and data.mods or {},
        conditionState = type(data.conditionState) == 'table' and data.conditionState or {},
    }
    local state = Entity(vehicle).state
    state:set('cmConditionReady', false, true)
    state:set('cmEngineHealth', savedCondition.engineHealth, true)
    state:set('cmBodyHealth', savedCondition.bodyHealth, true)
    state:set('cmTankHealth', savedCondition.tankHealth, true)
    state:set('cmDirtLevel', savedCondition.dirtLevel, true)
    state:set('cmFuel', savedCondition.fuel, true)
    state:set('cmConditionState', savedCondition.conditionState, true)
    local destroyedThreshold = tonumber(Config.Damage and Config.Damage.destroyedEngineHealth) or 150.0
    local destroyed = savedCondition.engineHealth <= destroyedThreshold
    state:set('cmEngineDestroyed', destroyed, true)

    if type(data.mods) == 'table' then applyVehicleMods(vehicle, data.mods) end
    CMVehicles.Client.ApplyPerformance(vehicle, type(data.metadata) == 'table' and data.metadata or {})
    CMVehicles.Client.SetVehicleFuel(vehicle, savedCondition.fuel)
    local savedOk = applyPhysicalCondition(vehicle, savedCondition, {
        repairBaseline = true,
        timeoutMs = math.max(3000, tonumber(Config.Garage and Config.Garage.conditionApplyMs) or 3000),
    })
    if savedOk then
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleUndriveable(vehicle, true)
        state:set('cmConditionReady', true, true)
        revealProtectedGarageVehicle(vehicle)
        startGarageProtection(vehicle)
    else
        quarantineGarageVehicle(vehicle)
    end

    pendingGarageCreates[token] = vehicle
    TriggerServerEvent('cm-vehicles:server:garageVehicleCreated', token, netId, nil)
end)

RegisterNetEvent('cm-vehicles:client:garageVehicleCreateAccepted', function(token, netId)
    token = tostring(token or '')
    local vehicle = pendingGarageCreates[token]
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local actual = CMVehicles.Client.SafeNetId and CMVehicles.Client.SafeNetId(vehicle, 1000) or nil
        if tonumber(actual) ~= tonumber(netId) then
            deletePendingGarageVehicle(token, netId)
            return
        end
    end
    pendingGarageCreates[token] = nil
end)

RegisterNetEvent('cm-vehicles:client:garageVehicleCreateRejected', function(token, netId)
    deletePendingGarageVehicle(token, netId)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for token in pairs(pendingGarageCreates) do deletePendingGarageVehicle(token) end
end)

local function finalizeSpawnPayload(data)
    data = type(data) == 'table' and data or {}
    local netId = tonumber(data.netId) or 0
    if netId <= 0 then return end
    local veh = waitForNetVehicle(netId)
    if not veh or veh == 0 then return end

    local garageDisplay = data.garageDisplay == true
    local state = Entity(veh).state

    -- The client-assisted garage creator may already have safely applied the
    -- saved condition. Never hide/reset a ready vehicle because a delayed
    -- finalize event arrived afterward.
    if garageDisplay and state.cmConditionReady == true then
        revealProtectedGarageVehicle(veh)
        startGarageProtection(veh)
        return
    end
    if activeConditionFinalizers[netId] then return end
    activeConditionFinalizers[netId] = true

    if garageDisplay then quarantineGarageVehicle(veh) end
    state:set('cmConditionReady', false, true)

    local engine = normalizedHealth(data.engineHealth, 1000.0)
    local body = normalizedHealth(data.bodyHealth, 1000.0)
    local tank = normalizedHealth(data.tankHealth, 1000.0)
    local snapshot = type(data.conditionState) == 'table' and data.conditionState or {}
    local condition = {
        engineHealth = engine,
        bodyHealth = body,
        tankHealth = tank,
        dirtLevel = tonumber(data.dirtLevel) or 0.0,
        fuel = tonumber(data.fuel) or tonumber(Config.Fuel and Config.Fuel.defaultFuel) or 100.0,
        mods = type(data.mods) == 'table' and data.mods or {},
        conditionState = snapshot,
    }

    -- Fit the saved appearance before the one legal condition convergence loop.
    -- Once cmConditionReady becomes true no protection thread writes health again.
    -- Blank unless police have issued this vehicle a registration (cosmetic
    -- only -- vehicle identity is never read from this text, see docs/API.md).
    SetVehicleNumberPlateText(veh, data.licenseNumber or '        ')
    if type(data.mods) == 'table' then applyVehicleMods(veh, data.mods) end
    CMVehicles.Client.ApplyPerformance(veh, data.metadata)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    applyMileagePerformance(veh, data.metadata)
    pcall(function()
        local metadata = type(data.metadata) == 'table' and data.metadata or {}
        state:set('cmMileage', tonumber(metadata.mileage) or 0.0, true)
        state:set('cmRacingHarness', metadata.racingHarness == true or metadata.racing_harness == true, true)
    end)

    CMVehicles.Client.ApplyLock(veh, garageDisplay and false or data.locked == true)
    if data.metadata and type(data.metadata.neons) == 'table' then
        for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, data.metadata.neons[i + 1] == true) end
    end

    local destroyedThreshold = tonumber(Config.Damage and Config.Damage.destroyedEngineHealth) or 150.0
    local destroyed = engine <= destroyedThreshold
    local completed = false
    local warped = false

    local function completeInitialization()
        if completed or not DoesEntityExist(veh) then return end
        completed = true
        activeConditionFinalizers[netId] = nil
        garageQuarantineSeen[netId] = nil
        CMVehicles.Client.SetVehicleFuel(veh, condition.fuel)
        SetVehicleEngineOn(veh, false, true, true)
        SetVehicleUndriveable(veh, true)
        pcall(function()
            state:set('cmEngineHealth', engine, true)
            state:set('cmBodyHealth', body, true)
            state:set('cmTankHealth', tank, true)
            state:set('cmDirtLevel', condition.dirtLevel, true)
            state:set('cmFuel', condition.fuel, true)
            state:set('cmConditionState', snapshot, true)
            state:set('cmEngineDestroyed', destroyed, true)
            state:set('cmConditionReady', true, true)
            state:set('cmPendingFinalize', false, true)
        end)

        if garageDisplay then
            SetVehicleDoorsLocked(veh, 0)
            SetVehicleDoorsLockedForAllPlayers(veh, false)
            SetVehicleDoorsLockedForPlayer(veh, PlayerId(), false)
            revealProtectedGarageVehicle(veh)
            startGarageProtection(veh)
        elseif destroyed then
            CMVehicles.Client.Notify('Vehicle spawned, but its engine is destroyed and must be repaired.')
        else
            CMVehicles.Client.Notify('Vehicle ready. Press Left Ctrl to start the engine.')
        end

        if data.warp == true and not warped then
            warped = true
            Wait(50)
            if DoesEntityExist(veh) then TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1) end
        end
    end

    local applied, live, reason = applyPhysicalCondition(veh, condition, {
        repairBaseline = true,
        timeoutMs = garageDisplay and 5000 or 3500,
    })
    if applied then
        completeInitialization()
        return
    end

    -- Keep an unverified garage vehicle hidden and every other vehicle
    -- undriveable. Retry only while cmConditionReady is false; successful
    -- initialization permanently ends all saved-health writes.
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, true)
    if garageDisplay then quarantineGarageVehicle(veh) end
    if CMVehicles.Client.DebugCondition then
        print(('[cm-vehicles] ^3saved condition initial verification failed on netId %s (%s): engine %.0f body %.0f tank %.0f^7')
            :format(tostring(data.netId), tostring(reason), tonumber(live and live.engine) or 0,
                tonumber(live and live.body) or 0, tonumber(live and live.tank) or 0))
    end

    CreateThread(function()
        local deadline = GetGameTimer() + 10000
        while DoesEntityExist(veh) and Entity(veh).state.cmConditionReady ~= true
            and GetGameTimer() < deadline do
            Wait(350)
            local ok = applyPhysicalCondition(veh, condition, { repairBaseline = true, timeoutMs = 1200 })
            if ok then
                completeInitialization()
                return
            end
        end
        if DoesEntityExist(veh) and Entity(veh).state.cmConditionReady ~= true then
            SetVehicleEngineOn(veh, false, true, true)
            SetVehicleUndriveable(veh, true)
            if garageDisplay then
                -- Fail visible, not invisible. The vehicle remains frozen and
                -- undriveable, but admins/players can see which car failed and
                -- the server can retry finalization on the next garage sync.
                revealProtectedGarageVehicle(veh)
            end
            print(('[cm-vehicles] ^1vehicle %s condition could not be verified; kept protected/undriveable^7')
                :format(tostring(data.id or data.plate or data.netId)))
            if not garageDisplay then
                CMVehicles.Client.Notify('Vehicle condition failed to load safely. Store it and contact an administrator.')
            end
        end
        activeConditionFinalizers[netId] = nil
    end)
end

RegisterNetEvent('cm-vehicles:client:finalizeSpawn', function(data)
    finalizeSpawnPayload(data)
end)

local deferredFinalizeLastAttempt = {}

local function tryDeferredFinalize(entity, payload)
    if type(payload) ~= 'table' or not entity or entity == 0 or not DoesEntityExist(entity) then return end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId <= 0 then return end
    if Entity(entity).state.cmConditionReady == true then
        pcall(function() Entity(entity).state:set('cmPendingFinalize', false, true) end)
        return
    end
    local now = GetGameTimer()
    if deferredFinalizeLastAttempt[netId] and now - deferredFinalizeLastAttempt[netId] < 12000 then return end
    deferredFinalizeLastAttempt[netId] = now
    local data = {}
    for key, value in pairs(payload) do data[key] = value end
    data.netId = netId
    CreateThread(function()
        finalizeSpawnPayload(data)
        if DoesEntityExist(entity) and Entity(entity).state.cmConditionReady == true then
            deferredFinalizeLastAttempt[netId] = nil
            pcall(function() Entity(entity).state:set('cmPendingFinalize', false, true) end)
        end
    end)
end

AddStateBagChangeHandler('cmPendingFinalize', nil, function(bagName, _, value)
    if type(value) ~= 'table' then return end
    local entity = GetEntityFromStateBagName(bagName)
    if entity and entity ~= 0 and DoesEntityExist(entity) and IsEntityAVehicle(entity) then
        tryDeferredFinalize(entity, value)
    end
end)

local activeTrustedCondition = {}

-- Shared by the direct server-fired event (below) and the pooled vehicle scan
-- retry (see cmPendingServicePatch): a trusted service/repair may be requested
-- while nobody is near the vehicle to physically apply it (e.g. an EMS fleet
-- vehicle recalled to its garage from across the map). cmPendingServicePatch
-- keeps the patch replicated so whichever client's vehicle pool eventually
-- streams this entity in can finish the job instead of leaving it permanently
-- damaged/dirty/undriveable.
local function runTrustedConditionApply(netId, patch)
    netId = tonumber(netId)
    if not netId or netId <= 0 or activeTrustedCondition[netId] then return end
    activeTrustedCondition[netId] = true
    CreateThread(function()
        local veh = waitForNetVehicle(netId)
        if not veh or veh == 0 or not DoesEntityExist(veh) then
            activeTrustedCondition[netId] = nil
            return
        end

        patch = type(patch) == 'table' and patch or {}
        local state = Entity(veh).state
        local data = {
            engineHealth = patch.engineHealth ~= nil and patch.engineHealth or state.cmEngineHealth,
            bodyHealth = patch.bodyHealth ~= nil and patch.bodyHealth or state.cmBodyHealth,
            tankHealth = patch.tankHealth ~= nil and patch.tankHealth or state.cmTankHealth,
            dirtLevel = patch.dirtLevel ~= nil and patch.dirtLevel or state.cmDirtLevel,
            fuel = patch.fuel ~= nil and patch.fuel or state.cmFuel,
            conditionState = patch.conditionState ~= nil and patch.conditionState or state.cmConditionState,
        }

        local deadline = GetGameTimer() + 12000
        local applied = false
        while DoesEntityExist(veh) and GetGameTimer() < deadline do
            if CMVehicles.Client.HasControl(veh, 1200) then
                state:set('cmConditionReady', false, true)
                applied = applyPhysicalCondition(veh, data, {
                    repairBaseline = true,
                    timeoutMs = 2000,
                }) == true
                if applied then break end
            end
            Wait(350)
        end

        if applied and DoesEntityExist(veh) then
            local threshold = tonumber(Config.Damage and Config.Damage.destroyedEngineHealth) or 150.0
            state:set('cmEngineHealth', normalizedHealth(data.engineHealth, 1000.0), true)
            state:set('cmBodyHealth', normalizedHealth(data.bodyHealth, 1000.0), true)
            state:set('cmTankHealth', normalizedHealth(data.tankHealth, 1000.0), true)
            state:set('cmDirtLevel', tonumber(data.dirtLevel) or 0.0, true)
            state:set('cmFuel', tonumber(data.fuel) or 100.0, true)
            state:set('cmConditionState', type(data.conditionState) == 'table' and data.conditionState or {}, true)
            state:set('cmEngineDestroyed', normalizedHealth(data.engineHealth, 1000.0) <= threshold, true)
            state:set('cmConditionReady', true, true)
            state:set('cmPendingServicePatch', false, true)
            SetVehicleUndriveable(veh, false)
        end
        activeTrustedCondition[netId] = nil
    end)
end

RegisterNetEvent('cm-vehicles:client:applyTrustedCondition', function(netId, patch)
    runTrustedConditionApply(netId, patch)
end)

local releaseHandoffThreads = {}
local appliedGarageReleaseVersions = {}

local function revealReleasedGarageVehicle(entity, expectedToken)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local state = Entity(entity).state
    repairLegacyGlassSnapshot(entity, state.cmConditionState)
    local token = tostring(state.cmGarageReleaseVersion or state.cmGarageReleasePending or '')
    local pending = tostring(state.cmGarageReleasePending or '') ~= ''
    local released = state.cmGarageReleased == true
    if expectedToken and tostring(expectedToken) ~= '' and token ~= tostring(expectedToken) and not released then
        return false
    end
    if not released and token == '' and state.cmHouseGarageDisplay == true then return false end

    -- These flags are client-local on some OneSync ownership paths. Apply every
    -- one explicitly, including door locks, so an entity that exists only as an
    -- invisible raycast/G-menu target becomes a normal enterable world vehicle.
    pcall(function()
        if NetworkGetEntityIsNetworked(entity) and not NetworkHasControlOfEntity(entity) then
            NetworkRequestControlOfEntity(entity)
        end
    end)
    pcall(function() SetEntityHasGravity(entity, true) end)
    SetEntityInvincible(entity, false)
    SetVehicleCanBeVisiblyDamaged(entity, true)
    pcall(function() SetEntityProofs(entity, false, false, false, false, false, false, false, false) end)
    SetEntityCollision(entity, true, true)

    -- Visual state is client-local, but repeatedly resetting alpha or calling
    -- NetworkFadeInEntity makes the vehicle flash for the entire convergence
    -- window. Reveal it only when this client still has a hidden/transparent
    -- copy; subsequent passes repair physics without touching the rendered
    -- entity again.
    local visible = false
    local alpha = 255
    pcall(function() visible = IsEntityVisible(entity) == true end)
    pcall(function() alpha = tonumber(GetEntityAlpha(entity)) or 255 end)
    if not visible or alpha < 250 then
        SetEntityVisible(entity, true, false)
        ResetEntityAlpha(entity)
        SetEntityAlpha(entity, 255, false)
    end

    FreezeEntityPosition(entity, false)
    SetVehicleHandbrake(entity, false)
    if state.cmLocked ~= true then
        SetVehicleDoorsLocked(entity, 1)
        SetVehicleDoorsLockedForAllPlayers(entity, false)
        pcall(function() SetVehicleDoorsLockedForPlayer(entity, PlayerId(), false) end)
    end
    -- Only touch driveability while the release is actively converging. Once
    -- the one-shot pending marker is acknowledged, live engine damage and other
    -- vehicle systems remain authoritative.
    if pending then
        if state.cmEngineDestroyed == true then
            SetVehicleEngineOn(entity, false, true, true)
            SetVehicleUndriveable(entity, true)
        else
            SetVehicleUndriveable(entity, false)
        end
    end
    return IsEntityVisible(entity) and not IsEntityPositionFrozen(entity)
end

local function beginReleaseHandoff(bagName, token)
    token = tostring(token or '')
    if token == '' then return end
    local key = tostring(bagName) .. ':' .. token
    if releaseHandoffThreads[key] then return end
    releaseHandoffThreads[key] = true

    CreateThread(function()
        -- The caller can still be inside the private garage bucket when the car
        -- is promoted. Keep waiting until the world entity streams to this client.
        local startedAt = GetGameTimer()
        local deadline = startedAt + 180000
        while GetGameTimer() < deadline do
            local entity = GetEntityFromStateBagName(bagName)
            if entity and entity ~= 0 and DoesEntityExist(entity) and IsEntityAVehicle(entity) then
                local state = Entity(entity).state
                local liveToken = tostring(state.cmGarageReleaseVersion or state.cmGarageReleasePending or '')
                if liveToken ~= token and state.cmGarageReleased ~= true then break end
                if revealReleasedGarageVehicle(entity, token) then
                    -- Repeat only the idempotent state convergence. The reveal
                    -- helper no longer fades or resets alpha once the vehicle is
                    -- visible, so this cannot create a two-second blinking loop.
                    for _ = 1, 12 do
                        if not DoesEntityExist(entity) then break end
                        revealReleasedGarageVehicle(entity, token)
                        Wait(100)
                    end
                    local netId = NetworkGetNetworkIdFromEntity(entity)
                    if netId and netId > 0 then
                        appliedGarageReleaseVersions[netId] = token
                        TriggerServerEvent('cm-vehicles:server:garageReleaseApplied', netId, token)
                    end
                    break
                end
            end
            -- Poll every frame during the initial stream window so the owner
            -- never sees a one-second alpha-0 ghost before the pooled scan runs.
            if GetGameTimer() - startedAt < 5000 then Wait(0) else Wait(50) end
        end
        releaseHandoffThreads[key] = nil
    end)
end

AddStateBagChangeHandler('cmGarageReleasePending', nil, function(bagName, _, value)
    if value ~= nil and value ~= false and tostring(value) ~= '' then
        beginReleaseHandoff(bagName, value)
    end
end)

AddStateBagChangeHandler('cmGarageReleased', nil, function(bagName, _, value)
    if value ~= true then return end
    local entity = GetEntityFromStateBagName(bagName)
    if entity and entity ~= 0 and DoesEntityExist(entity) and IsEntityAVehicle(entity) then
        local state = Entity(entity).state
        local token = tostring(state.cmGarageReleaseVersion or state.cmGarageReleasePending or '')
        if token ~= '' then beginReleaseHandoff(bagName, token) end
    end
end)

AddStateBagChangeHandler('cmGarageReleaseVersion', nil, function(bagName, _, value)
    local token = tostring(value or '')
    if token ~= '' then beginReleaseHandoff(bagName, token) end
end)

-- Direct handoff for the player who called/recalled the vehicle. State-bag
-- replication remains the durable fallback, but this per-frame watcher removes
-- the brief invisible period before the general 1.5-second pool scan notices it.
RegisterNetEvent('cm-vehicles:client:forceGarageWorldReveal', function(netId, token)
    netId = tonumber(netId) or 0
    token = tostring(token or '')
    if netId <= 0 or token == '' then return end
    beginReleaseHandoff(('entity:%s'):format(netId), token)
end)

-- Catch entities that streamed after their state-bag change event or after a
-- client resource restart. One pooled scan repairs both world-release and
-- parked-garage visibility so we do not run competing full vehicle scans.
CreateThread(function()
    while true do
        Wait(1500)
        local now = GetGameTimer()
        for _, entity in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(entity) then
                local state = Entity(entity).state
                if type(state.cmPendingFinalize) == 'table' and state.cmConditionReady ~= true then
                    tryDeferredFinalize(entity, state.cmPendingFinalize)
                elseif type(state.cmPendingServicePatch) == 'table' and state.cmConditionReady ~= true then
                    local netId = NetworkGetNetworkIdFromEntity(entity)
                    if netId and netId > 0 then runTrustedConditionApply(netId, state.cmPendingServicePatch) end
                end
                local token = tostring(state.cmGarageReleaseVersion or state.cmGarageReleasePending or '')
                local netId = NetworkGetNetworkIdFromEntity(entity)
                if state.cmGarageReleased == true and token ~= '' then
                    if netId and netId > 0 and appliedGarageReleaseVersions[netId] ~= token then
                        beginReleaseHandoff(('entity:%s'):format(netId), token)
                    end
                elseif state.cmHouseGarageDisplay == true then
                    if state.cmConditionReady == true then
                        if state.cmGarageDriving == true then
                            revealReleasedGarageVehicle(entity)
                        else
                            revealProtectedGarageVehicle(entity)
                            startGarageProtection(entity)
                        end
                        if netId and netId > 0 then garageQuarantineSeen[netId] = nil end
                    elseif netId and netId > 0 then
                        garageQuarantineSeen[netId] = garageQuarantineSeen[netId] or now
                        if now - garageQuarantineSeen[netId] >= 8000 then
                            revealProtectedGarageVehicle(entity)
                            SetVehicleEngineOn(entity, false, true, true)
                            SetVehicleUndriveable(entity, true)
                        end
                    end
                end
            end
        end
    end
end)

-- Apply/remove parked-car protection whenever cm-house changes the state bag.
-- Protection controls physics only. It never re-applies saved health after
-- cmConditionReady, because legitimate new damage must remain authoritative.
AddStateBagChangeHandler('cmHouseGarageDisplay', nil, function(bagName, _, value)
    local entity = GetEntityFromStateBagName(bagName)
    if not entity or entity == 0 or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then return end
    local state = Entity(entity).state
    if value == true then
        if state.cmConditionReady == true then
            revealProtectedGarageVehicle(entity)
        else
            quarantineGarageVehicle(entity)
            local netId = NetworkGetNetworkIdFromEntity(entity)
            if netId and netId > 0 then garageQuarantineSeen[netId] = garageQuarantineSeen[netId] or GetGameTimer() end
        end
        startGarageProtection(entity)
    else
        revealReleasedGarageVehicle(entity)
    end
end)

-- Visibility/alpha are client-local. A client that streamed the parked vehicle
-- while cmConditionReady=false used to hide it, but no handler revealed it when
-- another client later changed cmConditionReady=true. This was the intermittent
-- invisible-inside-garage bug and why pressing G appeared to fix it.
AddStateBagChangeHandler('cmConditionReady', nil, function(bagName, _, value)
    local entity = GetEntityFromStateBagName(bagName)
    if not entity or entity == 0 or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then return end
    local state = Entity(entity).state
    if state.cmHouseGarageDisplay ~= true then return end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if value == true then
        if netId and netId > 0 then garageQuarantineSeen[netId] = nil end
        if state.cmGarageDriving == true then
            revealReleasedGarageVehicle(entity)
        else
            revealProtectedGarageVehicle(entity)
            startGarageProtection(entity)
        end
    elseif netId and netId > 0 then
        garageQuarantineSeen[netId] = garageQuarantineSeen[netId] or GetGameTimer()
    end
end)

-- Starting a parked garage vehicle is the explicit physics handoff. React to
-- the replicated flag immediately on every client instead of waiting for the
-- next protection interval.
AddStateBagChangeHandler('cmGarageDriving', nil, function(bagName, _, value)
    if value ~= true then return end
    local entity = GetEntityFromStateBagName(bagName)
    if not entity or entity == 0 or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then return end
    local state = Entity(entity).state
    if state.cmHouseGarageDisplay == true and state.cmConditionReady == true then
        revealReleasedGarageVehicle(entity)
    end
end)

local protectedGarageThreads = {}

startGarageProtection = function(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    local netId = CMVehicles.Client.SafeNetId and CMVehicles.Client.SafeNetId(entity, 500) or entity
    local key = tonumber(netId) or entity
    if protectedGarageThreads[key] then return end
    protectedGarageThreads[key] = true

    CreateThread(function()
        local interval = math.max(250, tonumber(Config.Garage and Config.Garage.protectionCheckMs) or 500)
        while DoesEntityExist(entity) do
            local state = Entity(entity).state
            if state.cmHouseGarageDisplay ~= true then break end

            local driver = GetPedInVehicleSeat(entity, -1)
            local running = false
            pcall(function() running = GetIsVehicleEngineRunning(entity) == true end)
            if state.cmGarageReleased == true
               or (state.cmGarageReleasePending ~= nil and state.cmGarageReleasePending ~= false
                   and tostring(state.cmGarageReleasePending) ~= '')
               or state.cmGarageDriving == true
               or (driver and driver ~= 0 and running and state.cmEngineDestroyed ~= true) then
                revealReleasedGarageVehicle(entity, state.cmGarageReleasePending)
                break
            end

            if state.cmConditionReady == true then
                -- Visibility and alpha are client-local, but resetting them on
                -- every protection tick makes a fully visible vehicle flash.
                -- Heal only a genuinely hidden/transparent copy; normal parked
                -- cars keep their rendered state untouched between checks.
                local visible = false
                local alpha = 255
                pcall(function() visible = IsEntityVisible(entity) == true end)
                pcall(function() alpha = tonumber(GetEntityAlpha(entity)) or 255 end)
                if not visible or alpha < 250 then
                    SetEntityVisible(entity, true, false)
                    ResetEntityAlpha(entity)
                    SetEntityAlpha(entity, 255, false)
                end
                SetEntityCollision(entity, true, true)
            end
            SetEntityInvincible(entity, true)
            SetVehicleCanBeVisiblyDamaged(entity, false)
            pcall(function() SetEntityProofs(entity, true, true, true, true, true, true, true, true) end)
            FreezeEntityPosition(entity, true)
            SetVehicleHandbrake(entity, true)
            pcall(function() SetEntityHasGravity(entity, false) end)
            if state.cmEngineDestroyed == true then
                SetVehicleEngineOn(entity, false, true, true)
                SetVehicleUndriveable(entity, true)
            end
            Wait(interval)
        end
        protectedGarageThreads[key] = nil
    end)
end

local function captureConditionSnapshot(vehicle)
    local out = { windowSchema = 2, brokenWindows = {}, doors = {}, tyres = {} }
    for i = 0, 7 do
        local key = tostring(i)
        if vehicleHasWindowBone(vehicle, i) then
            local okWindow, intact = pcall(IsVehicleWindowIntact, vehicle, i)
            if okWindow and intact == false then out.brokenWindows[key] = true end
        end
        local damaged, angle = false, 0.0
        pcall(function() damaged = IsVehicleDoorDamaged(vehicle, i) == true end)
        pcall(function() angle = tonumber(GetVehicleDoorAngleRatio(vehicle, i)) or 0.0 end)
        out.doors[key] = { damaged = damaged, broken = damaged, angle = angle }
        local burst, onRim = false, false
        pcall(function() burst = IsVehicleTyreBurst(vehicle, i, false) == true end)
        pcall(function() onRim = IsVehicleTyreBurst(vehicle, i, true) == true end)
        out.tyres[key] = { burst = burst or onRim, onRim = onRim }
    end
    pcall(function() out.engineRunning = GetIsVehicleEngineRunning(vehicle) == true end)
    pcall(function() out.undriveable = not IsVehicleDriveable(vehicle, false) end)
    return out
end

RegisterNetEvent('cm-vehicles:client:spawnPurchasedVehicle', function(data)
    -- Backward compatible event name. Actual spawn is now server-side.
    local vehicleId = type(data) == 'table' and (data.id or data.vehicleId) or data
    TriggerServerEvent('cm-vehicles:server:spawnPurchasedVehicle', vehicleId)
end)

if CMVehicles.Config.Persistence and CMVehicles.Config.Persistence.legacyPeriodic == true then
CreateThread(function()
    local lastCoords = nil
    while true do
        Wait(CMVehicles.Config.Persistence.saveIntervalMs)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local isGarageDisplay = false
            pcall(function() isGarageDisplay = Entity(veh).state.cmHouseGarageDisplay == true end)
            local vehicleId = CMVehicles.Client.VehicleId(veh)
            if vehicleId and not isGarageDisplay then
                local coords = GetEntityCoords(veh)
                local deltaKm = 0.0
                if lastCoords then deltaKm = #(coords - lastCoords) / 1000.0 end
                lastCoords = coords
                if deltaKm > 0.0 then
                    pcall(function()
                        local currentMileage = tonumber(Entity(veh).state.cmMileage) or 0.0
                        local newMileage = currentMileage + deltaKm
                        Entity(veh).state:set('cmMileage', newMileage, true)
                        applyMileagePerformance(veh, { mileage = newMileage })
                    end)
                end
                TriggerServerEvent('cm-vehicles:server:saveState', vehicleId, {
                    netId = CMVehicles.Client.SafeNetId(veh) or 0,
                    fuel = CMVehicles.Client.GetVehicleFuel(veh),
                    engineHealth = GetVehicleEngineHealth(veh),
                    bodyHealth = GetVehicleBodyHealth(veh),
                    tankHealth = GetVehiclePetrolTankHealth(veh),
                    dirtLevel = GetVehicleDirtLevel(veh),
                    conditionState = captureConditionSnapshot(veh),
                    mileage = deltaKm,
                    position = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(veh) }
                })
            end
        else
            lastCoords = nil
        end
    end
end)
end

-- Exposed so a tuning shop can revert a live preview back to the saved state
-- when the player cancels.
exports('ApplyVehicleMods', function(vehicle, mods)
    return applyVehicleMods(vehicle, mods)
end)

-- Exposed so cm-tuning can apply performance the moment a part is bought,
-- and so the shop UI can show "275 -> 450 km/h" before the player pays.
exports('ApplyPerformance', function(vehicle, metadata)
    return CMVehicles.Client.ApplyPerformance(vehicle, metadata)
end)
exports('GetTuningMultiplier', function(vehicle)
    return CMVehicles.Client.GetTuningMultiplier(vehicle)
end)
exports('ApplyTyreLevel', function(vehicle, level)
    return CMVehicles.Client.ApplyTyreLevel(vehicle, level)
end)
exports('GetTyreLevel', function(vehicle)
    return CMVehicles.Client.GetTyreLevel(vehicle)
end)

-- Estimated top speed in km/h at a given engine level, used by the shop UI.
exports('EstimateTopSpeed', function(vehicle, engineLevel)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end
    local cfg = Config.Tuning or {}

    -- Base = the car's stock ceiling with NO tuning applied.
    local base = GetVehicleEstimatedMaxSpeed(vehicle) or 0.0
    local current = CMVehicles.Client.GetTuningMultiplier(vehicle)
    if current > 0 then base = base / current end   -- strip any tuning already on it

    local level = math.max(0, math.min(4, tonumber(engineLevel) or 0))
    local mul = 1.0
    if level > 0 then
        local class = GetVehicleClass(vehicle)
        local gain = (cfg.ClassGain and cfg.ClassGain[class]) or cfg.defaultGain or 0.25
        local frac = (cfg.LevelFraction or { 0.25, 0.5, 0.75, 1.0 })[level] or 1.0
        mul = 1.0 + (gain * frac)
    end

    return math.floor((base * mul) * 3.6 + 0.5)   -- m/s -> km/h
end)
