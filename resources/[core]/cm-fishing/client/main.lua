local Config = CMFishing.Config
CMFishing.Client = CMFishing.Client or {}

-- ---------------------------------------------------------------------------
-- State. The client only ever RENDERS what the server decided: the cast
-- token, wait time, difficulty and outcome all come from the server, and every
-- result is sent back bound to that single-use token.
-- ---------------------------------------------------------------------------

local casting = false          -- line in the water (waiting for a bite)
local biting = false           -- minigame phase
local castToken = nil          -- token of the live cast
local awaitToken = nil         -- token whose result we sent and are waiting on
local awaitDeadline = 0
local pendingCast = false      -- cast requested, server has not answered yet
local pendingUntil = 0
local minigameActive = false
local menuOpen = false
local castGeneration = 0       -- invalidates async work from an earlier cast
local publicWorld = false      -- server-published: routing bucket 0 (Fishing content visible)

local INTERACT_OWNER_STORE = 'cm-fishing:store'
local INTERACT_OWNER_CAST = 'cm-fishing:cast'
local claims = {}

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

-- ---------------------------------------------------------------------------
-- Shared cm-ui interaction prompts (owner-aware: every Show has a matching
-- Hide for the SAME owner; there is no ownerless/global hide in this file).
-- ---------------------------------------------------------------------------

local function showInteract(owner, name, label, role)
    if GetResourceState('cm-ui') ~= 'started' then return end
    claims[owner] = true
    pcall(function()
        exports['cm-ui']:ShowInteract({
            owner = owner,
            priority = 20,
            key = Config.interactKeyLabel or 'E',
            label = label,
            name = name,
            role = role,
        })
    end)
end

local function hideInteract(owner)
    if not claims[owner] then return end
    claims[owner] = nil
    if GetResourceState('cm-ui') ~= 'started' then return end
    pcall(function() exports['cm-ui']:HideInteract(owner) end)
end

local function hideAllInteracts()
    hideInteract(INTERACT_OWNER_STORE)
    hideInteract(INTERACT_OWNER_CAST)
end

-- ---------------------------------------------------------------------------
-- NUI focus. One place that always releases both focus and keep-input.
-- ---------------------------------------------------------------------------

local function grabFocus()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
end

local function releaseFocus()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

RegisterNetEvent('cm-fishing:client:notify', function(message, kind)
    notify(message, kind)
end)

-- The store UI only reads status when it opens (requestStore -> openStore
-- payload); registering this just avoids an "event has no handler" warning.
RegisterNetEvent('cm-fishing:client:status', function() end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('cm-fishing:server:requestStatus')
    TriggerServerEvent('cm-fishing:server:requestWorldState')
end)

-- ---------------------------------------------------------------------------
-- Blips
-- ---------------------------------------------------------------------------

local blips = {}

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
    blips[#blips + 1] = blip
end

-- Created once when the public world becomes visible, removed when it stops
-- being (no duplicates: guarded by #blips).
local function createBlips()
    if #blips > 0 then return end
    for _, area in ipairs(Config.FishingAreas) do
        if area.blip and area.blip.enabled then
            createBlip(area.coords, area.blip)
        end
    end
    if Config.Store.blip and Config.Store.blip.enabled then
        createBlip(Config.Store.coords, Config.Store.blip)
    end
end

local function removeBlips()
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
    blips = {}
end

-- ---------------------------------------------------------------------------
-- Store NPC (spawned once, frozen, invincible, passive)
-- ---------------------------------------------------------------------------

local storePed = nil
local npcSpawning = false

local function despawnStoreNpc()
    if storePed and DoesEntityExist(storePed) then DeleteEntity(storePed) end
    storePed = nil
end

-- Spawns the NPC once. Guarded against duplicates/overlapping spawns, and
-- aborts if the public world went away while the model was streaming in.
local function spawnStoreNpc()
    if npcSpawning or (storePed and DoesEntityExist(storePed)) then return end
    npcSpawning = true

    local model = joaat(Config.Store.model)
    RequestModel(model)
    local attempts = 0
    while not HasModelLoaded(model) and attempts < 200 do
        Wait(10)
        attempts = attempts + 1
    end
    if not HasModelLoaded(model) then
        print('[CM-FISHING] failed to load Fishing Store NPC model: ' .. tostring(Config.Store.model))
        npcSpawning = false
        return
    end

    if not publicWorld then
        SetModelAsNoLongerNeeded(model)
        npcSpawning = false
        return
    end

    local coords = Config.Store.coords
    storePed = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetEntityHeading(storePed, coords.w)
    SetEntityInvincible(storePed, true)
    SetPedCanRagdoll(storePed, false)
    SetPedFleeAttributes(storePed, 0, false)
    SetPedDiesWhenInjured(storePed, false)
    SetBlockingOfNonTemporaryEvents(storePed, true)
    FreezeEntityPosition(storePed, true)
    SetModelAsNoLongerNeeded(model)
    npcSpawning = false
end

CreateThread(function()
    while true do
        local wait = 800
        local ped = PlayerPedId()
        if publicWorld and not menuOpen and not casting and not biting and not awaitToken and storePed and DoesEntityExist(storePed) then
            local coords = GetEntityCoords(ped)
            local storeCoords = Config.Store.coords
            local distance = #(coords - vector3(storeCoords.x, storeCoords.y, storeCoords.z))

            -- Seated in a vehicle (e.g. a rented boat) never shows the
            -- prompt -- only once the player actually gets out.
            if not IsPedInAnyVehicle(ped, false) and distance <= (Config.Store.interactDistance or 2.2) then
                wait = 0
                showInteract(INTERACT_OWNER_STORE, 'Fishing Store', 'INTERACTION', 'CM FISHING')
                if IsControlJustPressed(0, Config.interactKey) then
                    TriggerServerEvent('cm-fishing:server:requestStore')
                end
            else
                hideInteract(INTERACT_OWNER_STORE)
            end
        else
            hideInteract(INTERACT_OWNER_STORE)
        end
        Wait(wait)
    end
end)

-- ---------------------------------------------------------------------------
-- Fishing zone tracking + water probe
-- ---------------------------------------------------------------------------

local function findCurrentArea(coords)
    for _, area in ipairs(Config.FishingAreas) do
        if #(coords - area.coords) <= area.radius then
            return area
        end
    end
    return nil
end

-- Water gate for the cast prompt: a UX/immersion check only (the server has
-- no water probe and does not rely on this for the economy). Casts a probe
-- from the player toward wherever they face and checks it lands on water.
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
            dbg(('water probe: hit=%s waterCoords=%s'):format(tostring(hit), waterCoords and tostring(waterCoords) or 'nil'))
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

-- ---------------------------------------------------------------------------
-- Rod prop / animation / boat freeze
-- ---------------------------------------------------------------------------

local rodEntity = nil

local function detachRodProp()
    if rodEntity and DoesEntityExist(rodEntity) then DeleteEntity(rodEntity) end
    rodEntity = nil
end

local function attachRodProp(generation)
    local model = -1910604593 -- fishing rod prop hash
    RequestModel(model)
    local attempts = 0
    while not HasModelLoaded(model) and attempts < 100 do Wait(10); attempts = attempts + 1 end
    if not HasModelLoaded(model) then return end

    -- The cast may have ended while the model streamed in.
    if generation ~= castGeneration or not casting then
        SetModelAsNoLongerNeeded(model)
        return
    end

    local ped = PlayerPedId()
    detachRodProp() -- one rod prop, ever
    rodEntity = CreateObject(model, GetEntityCoords(ped), true, false, false)
    AttachEntityToEntity(rodEntity, ped, GetPedBoneIndex(ped, 18905), 0.1, 0.05, 0.0, 80.0, 120.0, 160.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
end

local function playFishingIdle(generation)
    local ped = PlayerPedId()
    RequestAnimDict('amb@world_human_stand_fishing@idle_a')
    local attempts = 0
    while not HasAnimDictLoaded('amb@world_human_stand_fishing@idle_a') and attempts < 100 do Wait(10); attempts = attempts + 1 end
    if generation ~= castGeneration or not casting then return end
    TaskPlayAnim(ped, 'amb@world_human_stand_fishing@idle_a', 'idle_a', 3.0, 3.0, -1, 1, 0, false, false, false)
end

-- The animation tasks hold the player fixed in place for the whole cast -- if
-- the boat they're standing on keeps bobbing underneath that fixed position
-- they desync from the deck and drop. Freezing the boat for the duration
-- removes that. (The server's boat-distance policy tolerates drift anyway.)
local VEHICLE_CLASS_BOAT = 14
local frozenBoat = nil

local function findBoatUnderPlayer(ped)
    local coords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 4.0, 0, 70)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    if GetVehicleClass(vehicle) ~= VEHICLE_CLASS_BOAT then return nil end
    -- Roughly at deck height, not just nearby.
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

-- Local-only visual shark (not networked: no client-directed entity spawn).
local sharkPed = nil
local sharkGeneration = 0

local function removeShark()
    sharkGeneration = sharkGeneration + 1
    if sharkPed and DoesEntityExist(sharkPed) then DeleteEntity(sharkPed) end
    sharkPed = nil
end

-- Visual/animation teardown only. Tokens and NUI are handled by the callers.
local function endCast()
    casting = false
    biting = false
    castGeneration = castGeneration + 1
    local ped = PlayerPedId()
    -- Clearing an active scenario task can play an exit transition with baked
    -- in root motion. Capturing the exact spot right before the clear and
    -- re-pinning it right after cancels that out.
    local coordsBefore = GetEntityCoords(ped)
    local headingBefore = GetEntityHeading(ped)
    ClearPedTasks(ped)
    SetEntityCoords(ped, coordsBefore.x, coordsBefore.y, coordsBefore.z, false, false, false, false)
    SetEntityHeading(ped, headingBefore)
    -- Kill leftover momentum so control hands back without a sudden shove.
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    unfreezeBoat()
    detachRodProp()
    hideInteract(INTERACT_OWNER_CAST)
end

local function abortUi()
    minigameActive = false
    SendNUIMessage({ action = 'abortMinigame' })
    if not menuOpen then releaseFocus() end
end

-- Full local reset after the server (or a local safety) ended the cast.
local function resetCastState()
    castToken, awaitToken = nil, nil
    awaitDeadline = 0
    pendingCast = false
    if casting or biting then endCast() end
    abortUi()
end

-- ---------------------------------------------------------------------------
-- Cast prompt + reel-in
-- ---------------------------------------------------------------------------

-- Standing on a boat to fish means the native "enter/exit vehicle" control is
-- under the player's thumb the whole time. Disabled only while a cast is in
-- progress.
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

-- Longest a cast should ever wait, as a last-resort safety net independent of
-- the server (which enforces its own deadlines).
local CAST_WATCHDOG_MS = 90000
local castStartedAt = 0

local function cancelLocal(reasonText)
    local token = castToken or awaitToken
    if token then TriggerServerEvent('cm-fishing:server:cancelCast', token) end
    resetCastState()
    if reasonText then notify(reasonText, 'info') end
end

CreateThread(function()
    while true do
        local wait = 700
        local now = GetGameTimer()

        if pendingCast and now > pendingUntil then pendingCast = false end

        if not publicWorld then
            hideInteract(INTERACT_OWNER_CAST)
        elseif casting and not biting then
            -- Line in the water: shared prompt to reel in.
            wait = 0
            showInteract(INTERACT_OWNER_CAST, 'Fishing', 'REEL IN', 'Waiting for a bite')
            if IsControlJustPressed(0, Config.interactKey) then
                cancelLocal(nil)
            elseif (now - castStartedAt) > CAST_WATCHDOG_MS then
                dbg('cast watchdog fired -- forcing cancel')
                cancelLocal('Your line was reeled in automatically.')
            end
        elseif publicWorld and not menuOpen and not casting and not biting and not awaitToken then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local area = findCurrentArea(coords)
            local zoneOk = area ~= nil or Config.OutsideFishing.enabled
            -- Seated in any vehicle (including a rented boat) never shows the
            -- prompt, and neither does treading water -- fishing needs solid
            -- footing (shore, dock, or a boat deck).
            local facingWater = zoneOk and not IsPedInAnyVehicle(ped, false) and not IsPedSwimming(ped) and isFacingWater(ped)

            if facingWater then refreshRodStatus() end

            if facingWater and hasRodCached then
                wait = 0
                showInteract(INTERACT_OWNER_CAST, 'Fishing', 'CAST LINE', area and area.label or 'Open water')
                if IsControlJustPressed(0, Config.interactKey) and not pendingCast then
                    pendingCast = true
                    pendingUntil = now + 2500
                    local boatNetId
                    local boat = findBoatUnderPlayer(ped)
                    if boat and NetworkGetEntityIsNetworked(boat) then
                        boatNetId = NetworkGetNetworkIdFromEntity(boat)
                    end
                    TriggerServerEvent('cm-fishing:server:cast', boatNetId)
                end
            else
                hideInteract(INTERACT_OWNER_CAST)
            end
        else
            hideInteract(INTERACT_OWNER_CAST)
        end

        Wait(wait)
    end
end)

-- Death while waiting/fighting cancels the cast (the server cancels too; this
-- just makes the local cleanup immediate). Focus, prop and animation go with it.
CreateThread(function()
    while true do
        Wait(250)
        if casting or biting or awaitToken then
            if IsEntityDead(PlayerPedId()) then
                cancelLocal(nil)
            end
            if awaitToken and GetGameTimer() > awaitDeadline then
                -- Server never answered our result: do not strand the cursor.
                awaitToken = nil
                abortUi()
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Server-driven cast events
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-fishing:client:beginCast', function(token, waitMs)
    pendingCast = false
    if type(token) ~= 'string' then return end
    if casting or biting then endCast() end

    castToken = token
    awaitToken = nil
    casting = true
    biting = false
    castStartedAt = GetGameTimer()
    castGeneration = castGeneration + 1
    local generation = castGeneration

    freezeBoatForFishing()
    CreateThread(function() attachRodProp(generation) end)
    CreateThread(function() playFishingIdle(generation) end)
end)

-- The server ended the cast (cancel, death, movement, timeout, bucket,
-- character switch, resource stop, ...). Tear everything down; token-checked
-- so a late message about an OLD cast cannot disturb a newer one.
RegisterNetEvent('cm-fishing:client:castEnded', function(token, reason)
    if token ~= nil and token ~= castToken and token ~= awaitToken then return end
    dbg('castEnded', tostring(reason))
    resetCastState()
end)

RegisterNetEvent('cm-fishing:client:bite', function(payload)
    if type(payload) ~= 'table' or not casting or payload.token ~= castToken then return end
    biting = true
    minigameActive = true
    hideInteract(INTERACT_OWNER_CAST)

    -- The boat frozen in beginCast (if any) stays frozen through this phase.
    local ped = PlayerPedId()
    local coordsBefore = GetEntityCoords(ped)
    local headingBefore = GetEntityHeading(ped)
    ClearPedTasks(ped)
    SetEntityCoords(ped, coordsBefore.x, coordsBefore.y, coordsBefore.z, false, false, false, false)
    SetEntityHeading(ped, headingBefore)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, false)

    grabFocus()
    SendNUIMessage({
        action = 'startMinigame',
        token = payload.token,
        difficulty = payload.difficulty,
        settings = payload.settings,
        heavy = payload.heavy,
    })
end)

-- Deep-water risk. The server decided this happened and how hard it hits; the
-- shark is a LOCAL visual (never networked) and is always removed afterwards.
RegisterNetEvent('cm-fishing:client:sharkEncounter', function(token, damage, models)
    if token ~= castToken then return end
    resetCastState()
    notify('Something big just hit your line!', 'error')

    removeShark()
    local generation = sharkGeneration

    CreateThread(function()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local forward = GetEntityForwardVector(ped)
        local modelList = type(models) == 'table' and models or { `a_c_sharktiger` }
        local sharkModel = modelList[math.random(1, #modelList)]

        RequestModel(sharkModel)
        local attempts = 0
        while not HasModelLoaded(sharkModel) and attempts < 100 do Wait(10); attempts = attempts + 1 end
        if not HasModelLoaded(sharkModel) or generation ~= sharkGeneration then return end

        local spawnPos = vector3(coords.x + forward.x * 15.0, coords.y + forward.y * 15.0, coords.z - 3.0)
        local shark = CreatePed(28, sharkModel, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, false, false)
        SetModelAsNoLongerNeeded(sharkModel)
        if not DoesEntityExist(shark) then return end
        sharkPed = shark

        SetEntityAsMissionEntity(shark, true, true)
        TaskGoToEntity(shark, ped, -1, 1.0, 8.0, 1073741824, 0)

        Wait(1800)
        if generation == sharkGeneration and DoesEntityExist(shark) and not IsEntityDead(ped) then
            if #(GetEntityCoords(ped) - GetEntityCoords(shark)) < 6.0 then
                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.6)
                SetEntityHealth(ped, math.max(GetEntityHealth(ped) - (tonumber(damage) or 25), 105))
                notify('The shark bit you!', 'error')
            end
        end

        -- Swims off instead of popping out of existence; deleted once far
        -- enough away, or after a generous timeout as a safety net.
        if generation == sharkGeneration and DoesEntityExist(shark) then
            TaskSmartFleePed(shark, ped, 250.0, -1, false, false)
        end
        local checks = 0
        while generation == sharkGeneration and DoesEntityExist(shark) and checks < 30 do
            Wait(1000)
            checks = checks + 1
            if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(shark)) > 80.0 then break end
        end

        if DoesEntityExist(shark) then DeleteEntity(shark) end
        if sharkPed == shark then sharkPed = nil end
    end)
end)

RegisterNUICallback('minigameResult', function(data, cb)
    cb({ ok = true })
    data = type(data) == 'table' and data or {}
    -- Only a live minigame for the CURRENT token may report; anything else is
    -- a stale/duplicate NUI callback and is dropped.
    if not minigameActive or not castToken or data.token ~= castToken then return end

    minigameActive = false
    local token = castToken
    castToken = nil
    awaitToken = token
    awaitDeadline = GetGameTimer() + 8000

    -- NUI focus stays on: the catch-result modal arrives after a server round
    -- trip and must remain clickable. Every exit path below releases it.
    TriggerServerEvent('cm-fishing:server:catchResult', token, data.success == true)
    endCast()
end)

RegisterNUICallback('closeCatch', function(_, cb)
    if not menuOpen then releaseFocus() end
    cb({ ok = true })
end)

RegisterNetEvent('cm-fishing:client:catchLanded', function(result)
    awaitToken = nil
    awaitDeadline = 0
    grabFocus()
    if result and result.success then
        SendNUIMessage({
            action = 'catchResult',
            success = true,
            label = result.label,
            rarity = result.rarity,
            xp = result.xp,
            xpText = result.xpText,
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
    hideAllInteracts()
    grabFocus()
    SendNUIMessage({ action = 'openStore', payload = payload })
end)

local function closeStore()
    if not menuOpen then return end
    menuOpen = false
    releaseFocus()
    SendNUIMessage({ action = 'closeStore' })
end

-- Server-published bucket-0 state. Event-driven only (no heartbeat/respawn
-- loop): leaving the public world hides every Fishing world element and
-- cancels local presentation; returning spawns the NPC and blips exactly once.
RegisterNetEvent('cm-fishing:client:publicWorld', function(state)
    state = state == true
    if state == publicWorld then return end
    publicWorld = state

    if not state then
        hideAllInteracts()
        closeStore()
        resetCastState()
        despawnStoreNpc()
        removeBlips()
    else
        createBlips()
        CreateThread(spawnStoreNpc)
    end
end)

-- Server-driven close (e.g. right after a successful boat rental).
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

-- Death also closes the store (nothing may keep the cursor while dead).
CreateThread(function()
    while true do
        Wait(500)
        if menuOpen and IsEntityDead(PlayerPedId()) then
            closeStore()
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    hideAllInteracts()
    releaseFocus()
    SendNUIMessage({ action = 'abortMinigame' })
    if casting or biting then
        ClearPedTasks(PlayerPedId())
    end
    detachRodProp()
    unfreezeBoat()
    removeShark()
    removeBlips()
    despawnStoreNpc()
end)
