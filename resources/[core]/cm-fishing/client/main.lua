local Config = CMFishing.Config
CMFishing.Client = CMFishing.Client or {}

local casting = false
local biting = false
local menuOpen = false

local promptVisible = false
local promptTitle, promptLabel, promptHint = nil, nil, nil
local lastPromptSentAt = 0

local function dbg(...)
    if Config.Debug then print('[CM-FISHING]', ...) end
end

local function notify(message, kind)
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'info')
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message or ''))
    EndTextCommandThefeedPostTicker(false, false)
end

local function sendInteraction(visible, title, label, hint, force)
    local sameState = promptVisible == visible
        and (not visible or (promptTitle == title and promptLabel == label and promptHint == hint))

    promptVisible, promptTitle, promptLabel, promptHint = visible, visible and title or nil, visible and label or nil, visible and hint or nil

    local now = GetGameTimer()
    if sameState and force ~= true and (now - lastPromptSentAt) < 800 then return end
    lastPromptSentAt = now

    SendNUIMessage({
        action = 'interaction',
        visible = visible == true,
        key = Config.interactKeyLabel or 'E',
        title = title or 'Fishing',
        label = label or '',
        hint = hint or '',
    })
end

RegisterNetEvent('cm-fishing:client:notify', function(message, kind)
    notify(message, kind)
end)

-- The server also fires this after every catch/level-up, but the store UI
-- only reads status when it opens (requestStore -> openStore payload), so
-- there is nothing to do with it client-side outside of that -- registering
-- it just avoids an "event has no handler" warning.
RegisterNetEvent('cm-fishing:client:status', function() end)

TriggerServerEvent('cm-fishing:server:requestStatus')

-- ---------------------------------------------------------------------------
-- Blips
-- ---------------------------------------------------------------------------

local function createBlip(coords, def)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, def.sprite or 317)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, def.scale or 0.6)
    SetBlipColour(blip, def.color or 29)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(def.name or 'Fishing')
    EndTextCommandSetBlipName(blip)
end

CreateThread(function()
    for _, area in ipairs(Config.FishingAreas) do
        if area.blip and area.blip.enabled then
            createBlip(area.coords, area.blip)
        end
    end
    if Config.Store.blip and Config.Store.blip.enabled then
        createBlip(Config.Store.coords, Config.Store.blip)
    end
end)

-- ---------------------------------------------------------------------------
-- Store NPC
-- ---------------------------------------------------------------------------

local storePed = nil

CreateThread(function()
    local model = joaat(Config.Store.model)
    RequestModel(model)
    local attempts = 0
    while not HasModelLoaded(model) and attempts < 200 do
        Wait(10)
        attempts = attempts + 1
    end
    if not HasModelLoaded(model) then return end

    local coords = Config.Store.coords
    storePed = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetEntityInvincible(storePed, true)
    SetBlockingOfNonTemporaryEvents(storePed, true)
    FreezeEntityPosition(storePed, true)
    SetModelAsNoLongerNeeded(model)
end)

CreateThread(function()
    while true do
        local wait = 800
        local ped = PlayerPedId()
        if not menuOpen and not casting and DoesEntityExist(storePed) then
            local coords = GetEntityCoords(ped)
            local storeCoords = Config.Store.coords
            local distance = #(coords - vector3(storeCoords.x, storeCoords.y, storeCoords.z))

            -- Seated in a vehicle (e.g. a rented boat) never shows the
            -- prompt, no matter the distance -- only shown again once the
            -- player actually gets out.
            if not IsPedInAnyVehicle(ped, false) and distance <= (Config.Store.interactDistance or 2.2) then
                wait = 0
                sendInteraction(true, 'Fishing Store', 'Open the fishing store', 'Buy rods, bait, and sell your catch')
                if IsControlJustPressed(0, Config.interactKey) then
                    TriggerServerEvent('cm-fishing:server:requestStore')
                end
            elseif promptTitle == 'Fishing Store' then
                sendInteraction(false)
            end
        end
        Wait(wait)
    end
end)

-- ---------------------------------------------------------------------------
-- Fishing zone tracking + cast prompt
-- ---------------------------------------------------------------------------

local function findCurrentArea(coords)
    for _, area in ipairs(Config.FishingAreas) do
        if #(coords - area.coords) <= area.radius then
            return area
        end
    end
    return nil
end

-- Water gate for the cast prompt: casts a probe from the player out toward
-- wherever they are currently facing and checks whether it lands on water.
-- Reach is generous (20 units forward, 30 down) so it still finds the
-- water below a real pier/dock (docks over the ocean commonly sit
-- 8-10+ units above sea level). Facing + reach is the whole gate -- no
-- extra height-above-water cap, since real dock heights vary too much on
-- this map for a fixed cutoff to be reliable.
local lastWaterDbgAt = 0

local function isFacingWater(ped)
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local startPos = coords + vector3(0.0, 0.0, 1.0)
    local endPos = vector3(coords.x + forward.x * 20.0, coords.y + forward.y * 20.0, coords.z - 30.0)
    local hit, waterCoords = TestProbeAgainstWater(startPos.x, startPos.y, startPos.z, endPos.x, endPos.y, endPos.z)
    local result = hit == true or hit == 1

    if Config.Debug then
        local now = GetGameTimer()
        if (now - lastWaterDbgAt) > 1000 then
            lastWaterDbgAt = now
            dbg(('water probe: hit=%s from (%.2f,%.2f,%.2f) to (%.2f,%.2f,%.2f) waterCoords=%s'):format(
                tostring(hit), startPos.x, startPos.y, startPos.z, endPos.x, endPos.y, endPos.z,
                waterCoords and ('(%.2f,%.2f,%.2f)'):format(waterCoords.x, waterCoords.y, waterCoords.z) or 'nil'))
        end
    end

    return result
end

-- Whether the player currently owns any fishing rod. Refreshed from the
-- server (client scripts cannot read inventory contents directly) and
-- throttled since it is only needed while already near/facing water.
local hasRodCached = false
local lastRodCheckAt = 0

RegisterNetEvent('cm-fishing:client:rodStatus', function(hasRod)
    hasRodCached = hasRod == true
end)

local function refreshRodStatus()
    local now = GetGameTimer()
    if (now - lastRodCheckAt) < 2000 then return end
    lastRodCheckAt = now
    TriggerServerEvent('cm-fishing:server:checkRod')
end

CreateThread(function()
    while true do
        local wait = 700

        if not menuOpen and not casting and not biting then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local area = findCurrentArea(coords)
            local zoneOk = area ~= nil or Config.OutsideFishing.enabled
            -- Seated in any vehicle (including a rented boat) never shows
            -- the prompt -- only once the player actually gets out. Actively
            -- swimming/floating in the water doesn't either -- fishing
            -- requires solid footing (shore, dock, or a boat deck), not
            -- treading water.
            local facingWater = zoneOk and not IsPedInAnyVehicle(ped, false) and not IsPedSwimming(ped) and isFacingWater(ped)

            if facingWater then refreshRodStatus() end
            local canFishHere = facingWater and hasRodCached

            if canFishHere then
                wait = 0
                sendInteraction(true, 'Fishing', 'Cast your line', area and area.label or 'Open water')
                if IsControlJustPressed(0, Config.interactKey) then
                    TriggerServerEvent('cm-fishing:server:cast')
                end
            elseif promptTitle == 'Fishing' then
                sendInteraction(false)
            end
        end

        Wait(wait)
    end
end)

-- ---------------------------------------------------------------------------
-- Cast / bite / minigame flow
-- ---------------------------------------------------------------------------

local rodEntity = nil

local function attachRodProp()
    local model = -1910604593 -- fishing rod prop hash
    RequestModel(model)
    local attempts = 0
    while not HasModelLoaded(model) and attempts < 100 do Wait(10); attempts = attempts + 1 end
    if not HasModelLoaded(model) then return end

    local ped = PlayerPedId()
    if DoesEntityExist(rodEntity) then DeleteEntity(rodEntity) end
    rodEntity = CreateObject(model, GetEntityCoords(ped), true, false, false)
    AttachEntityToEntity(rodEntity, ped, GetPedBoneIndex(ped, 18905), 0.1, 0.05, 0.0, 80.0, 120.0, 160.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
end

local function detachRodProp()
    if DoesEntityExist(rodEntity) then DeleteEntity(rodEntity) end
    rodEntity = nil
end

local function playFishingIdle()
    local ped = PlayerPedId()
    RequestAnimDict('amb@world_human_stand_fishing@idle_a')
    local attempts = 0
    while not HasAnimDictLoaded('amb@world_human_stand_fishing@idle_a') and attempts < 100 do Wait(10); attempts = attempts + 1 end
    TaskPlayAnim(ped, 'amb@world_human_stand_fishing@idle_a', 'idle_a', 3.0, 3.0, -1, 1, 0, false, false, false)
end

-- ---------------------------------------------------------------------------
-- Boat freeze while fishing. The animation tasks hold the player fixed in
-- place for the whole cast -- if the boat they're standing on keeps
-- bobbing/drifting with wave physics underneath that fixed position, they
-- desync from the deck and drop. Rather than dropping the animation,
-- freeze the boat itself for the duration so there's nothing for the
-- player to desync from.
-- ---------------------------------------------------------------------------

local VEHICLE_CLASS_BOAT = 14
local frozenBoat = nil

local function findBoatUnderPlayer(ped)
    local coords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 4.0, 0, 70)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    if GetVehicleClass(vehicle) ~= VEHICLE_CLASS_BOAT then return nil end
    -- Roughly at deck height, not just nearby (e.g. floating in the water
    -- next to a boat rather than standing on it).
    if math.abs(coords.z - GetEntityCoords(vehicle).z) > 5.0 then return nil end
    return vehicle
end

local function freezeBoatForFishing()
    local boat = findBoatUnderPlayer(PlayerPedId())
    if not boat then return end
    frozenBoat = boat
    FreezeEntityPosition(boat, true)
end

local function unfreezeBoat()
    if frozenBoat and DoesEntityExist(frozenBoat) then
        FreezeEntityPosition(frozenBoat, false)
    end
    frozenBoat = nil
end

local castStartedAt = 0

RegisterNetEvent('cm-fishing:client:beginCast', function(waitMs)
    casting = true
    castStartedAt = GetGameTimer()
    attachRodProp()
    freezeBoatForFishing()
    playFishingIdle()
    sendInteraction(true, 'Fishing', 'Waiting for a bite...', 'Press E to reel in and cancel', true)
end)

local function endCast()
    casting = false
    biting = false
    local ped = PlayerPedId()
    -- Clearing an active scenario task (WORLD_HUMAN_STAND_IMPATIENT, still
    -- running here if a bite/minigame happened) can play its own exit
    -- transition, and some of those have real baked-in root motion -- not
    -- just leftover momentum, an actual position snap. Capturing the exact
    -- spot right before the clear and re-pinning it right after cancels
    -- that out regardless of what specifically caused it.
    local coordsBefore = GetEntityCoords(ped)
    local headingBefore = GetEntityHeading(ped)
    ClearPedTasks(ped)
    SetEntityCoords(ped, coordsBefore.x, coordsBefore.y, coordsBefore.z, false, false, false, false)
    SetEntityHeading(ped, headingBefore)
    -- Standing at the water's edge (or on a boat) can build up buoyancy/wave
    -- push force that a task holds in check -- clearing the task without
    -- zeroing velocity lets that force release all at once as a sudden
    -- shove. This kills any leftover momentum at the exact moment control
    -- hands back to the player.
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    unfreezeBoat()
    detachRodProp()
    sendInteraction(false, nil, nil, nil, true)
end

-- Standing on a boat to fish means the native "enter/exit vehicle" control
-- (F by default) is right there under the player's thumb the whole time --
-- one accidental tap while actively fishing snaps them into/out of the
-- driver seat, which on water reads as getting flung/jumping overboard.
-- Disabling it only while a cast is in progress keeps normal boat
-- entry/exit working everywhere else.
CreateThread(function()
    while true do
        local wait = 500
        if casting or biting then
            wait = 0
            DisableControlAction(0, 75, true) -- INPUT_ENTER
        end
        Wait(wait)
    end
end)

-- Longest a cast should ever realistically wait for a bite, across every
-- configured zone/outside-fishing/gear combination, plus a wide margin.
-- Purely a safety net -- normal casts resolve in seconds, well under this.
local CAST_WATCHDOG_MS = 90000

CreateThread(function()
    while true do
        Wait(0)
        if casting and not biting then
            if IsControlJustPressed(0, Config.interactKey) then
                -- Not catchResult: no bite has happened yet, so the server
                -- session has no difficulty set and catchResult would just
                -- ignore this (leaving the session stuck and blocking every
                -- future cast). cancelCast always clears it.
                TriggerServerEvent('cm-fishing:server:cancelCast')
                endCast()
            elseif (GetGameTimer() - castStartedAt) > CAST_WATCHDOG_MS then
                -- Should never trigger in normal play -- a hard guarantee
                -- that a cast can never leave the player stuck, no matter
                -- what caused it (a missed server event, a client hiccup).
                dbg('cast watchdog fired -- forcing cancel')
                TriggerServerEvent('cm-fishing:server:cancelCast')
                endCast()
                notify('Your line was reeled in automatically.', 'info')
            end
        else
            Wait(300)
        end
    end
end)

-- Deep-water risk: instead of a normal bite, a shark hits the line. The
-- server already decided this happened and how much it hurts (damage is
-- server-rolled, not client-guessed); this just plays it out visually and
-- applies the damage if the shark actually reaches the player.
RegisterNetEvent('cm-fishing:client:sharkEncounter', function(damage, models)
    endCast()
    notify('Something big just hit your line!', 'error')

    CreateThread(function()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local forward = GetEntityForwardVector(ped)
        local modelList = type(models) == 'table' and models or { `a_c_sharktiger` }
        local sharkModel = modelList[math.random(1, #modelList)]

        RequestModel(sharkModel)
        local attempts = 0
        while not HasModelLoaded(sharkModel) and attempts < 100 do Wait(10); attempts = attempts + 1 end
        if not HasModelLoaded(sharkModel) then return end

        local spawnPos = vector3(coords.x + forward.x * 15.0, coords.y + forward.y * 15.0, coords.z - 3.0)
        local shark = CreatePed(28, sharkModel, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, true, true)
        SetModelAsNoLongerNeeded(sharkModel)
        if not DoesEntityExist(shark) then return end

        SetEntityAsMissionEntity(shark, true, true)
        TaskGoToEntity(shark, ped, -1, 1.0, 8.0, 1073741824, 0)

        Wait(1800)
        if DoesEntityExist(shark) and DoesEntityExist(ped) then
            local distance = #(GetEntityCoords(ped) - GetEntityCoords(shark))
            if distance < 6.0 then
                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.6)
                SetEntityHealth(ped, math.max(GetEntityHealth(ped) - (tonumber(damage) or 25), 105))
                notify('The shark bit you!', 'error')
            end
        end

        -- Swims off into the distance instead of just sitting there and
        -- popping out of existence. TaskSmartFleePed (flee AI relative to a
        -- target ped) is far more reliable out over open water than a
        -- fixed-coordinate goto task, which depends on nav-mesh coverage
        -- that mostly doesn't extend that far out to sea and would just
        -- silently fail to move the shark at all.
        if DoesEntityExist(shark) then
            TaskSmartFleePed(shark, ped, 250.0, -1, false, false)
        end

        -- Only despawns once it has actually swum far enough away to not be
        -- seen vanishing, or after a generous timeout as a safety net in
        -- case it gets stuck pathing.
        local checks = 0
        while DoesEntityExist(shark) and checks < 30 do
            Wait(1000)
            checks = checks + 1
            if DoesEntityExist(ped) and #(GetEntityCoords(ped) - GetEntityCoords(shark)) > 80.0 then
                break
            end
        end

        if DoesEntityExist(shark) then DeleteEntity(shark) end
    end)
end)

RegisterNetEvent('cm-fishing:client:bite', function(payload)
    if not casting then return end
    biting = true
    sendInteraction(false, nil, nil, nil, true)

    -- The boat frozen back in beginCast (if any) stays frozen through this
    -- phase too -- unfreezeBoat() only runs in endCast(), once the whole
    -- cast (bite included) is fully resolved.
    local ped = PlayerPedId()
    local coordsBefore = GetEntityCoords(ped)
    local headingBefore = GetEntityHeading(ped)
    ClearPedTasks(ped)
    SetEntityCoords(ped, coordsBefore.x, coordsBefore.y, coordsBefore.z, false, false, false, false)
    SetEntityHeading(ped, headingBefore)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, false)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'startMinigame',
        difficulty = payload.difficulty,
        settings = payload.settings,
        heavy = payload.heavy,
    })
end)

RegisterNUICallback('minigameResult', function(data, cb)
    -- NUI focus is intentionally left on here: the catch-result modal (shown
    -- via cm-fishing:client:catchLanded below) arrives after a server round
    -- trip, and turning focus off now would make that modal unclickable.
    TriggerServerEvent('cm-fishing:server:catchResult', data and data.success == true)
    endCast()
    cb({ ok = true })
end)

RegisterNUICallback('closeCatch', function(_, cb)
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNetEvent('cm-fishing:client:catchLanded', function(result)
    SetNuiFocus(true, true)
    if result and result.success then
        -- endCast() (called from the minigameResult NUI callback moments
        -- earlier) already cleared tasks and zeroed velocity once -- doing
        -- it again here on an already-idle ped was the one concrete
        -- difference between a successful and a failed catch, and lines up
        -- exactly with the push only happening on a landed fish.
        if result.rodBroke then
            notify('The fight was too much for your rod -- it snapped.', 'error')
        end

        SendNUIMessage({
            action = 'catchResult',
            success = true,
            label = result.label,
            rarity = result.rarity,
            xp = result.xp,
            heavy = result.heavy,
            rodBroke = result.rodBroke,
        })
    else
        SendNUIMessage({ action = 'catchResult', success = false })
    end
end)

-- ---------------------------------------------------------------------------
-- Store UI
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-fishing:client:openStore', function(payload)
    menuOpen = true
    sendInteraction(false, nil, nil, nil, true)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openStore', payload = payload })
end)

local function closeStore()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeStore' })
end

-- Server-driven close (e.g. right after a successful boat rental), as
-- opposed to the player clicking the close button/pressing escape.
RegisterNetEvent('cm-fishing:client:closeStoreForced', function()
    closeStore()
end)

RegisterNUICallback('closeStore', function(_, cb)
    closeStore()
    cb({ ok = true })
end)

RegisterNUICallback('escape', function(_, cb)
    if menuOpen then closeStore() end
    cb({ ok = true })
end)

RegisterNUICallback('buyItem', function(data, cb)
    if data and data.kind and data.name then
        TriggerServerEvent('cm-fishing:server:buyItem', data.kind, data.name, data.qty or 1)
    end
    cb({ ok = true })
end)

RegisterNUICallback('buyCart', function(data, cb)
    if data and type(data.items) == 'table' then
        TriggerServerEvent('cm-fishing:server:buyCart', data.items)
    end
    cb({ ok = true })
end)

RegisterNUICallback('sellFish', function(data, cb)
    if data and data.name then
        TriggerServerEvent('cm-fishing:server:sellFish', data.name, data.amount or 1)
    end
    cb({ ok = true })
end)

RegisterNUICallback('rentBoat', function(data, cb)
    if data and data.name then
        TriggerServerEvent('cm-fishing:server:requestBoat', true, data.name)
    end
    cb({ ok = true })
end)

RegisterNUICallback('returnBoat', function(_, cb)
    TriggerServerEvent('cm-fishing:server:requestBoat', false)
    cb({ ok = true })
end)

RegisterNUICallback('ready', function(_, cb)
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    detachRodProp()
    unfreezeBoat()
    if DoesEntityExist(storePed) then DeleteEntity(storePed) end
end)
